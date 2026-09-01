import Darwin
import Foundation

/// Collects newline-delimited JSON responses from `codex app-server` without
/// assuming that stdout arrives one complete line at a time.
final class QuotaOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var responses: [Int: Data] = [:]
    private var acceptedBytes = 0
    let updated = DispatchSemaphore(value: 0)
    private let maximumTotalBytes = 1_048_576
    private let maximumLineBytes = 262_144
    private let acceptedIDs: Set<Int> = [1, 2, 3]

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard acceptedBytes < maximumTotalBytes else { return }
        let accepted = data.prefix(maximumTotalBytes - acceptedBytes)
        acceptedBytes += accepted.count
        buffer.append(accepted)
        consumeCompleteLines()
    }

    private func consumeCompleteLines() {
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            consume(line)
        }
        if buffer.count > maximumLineBytes {
            buffer.removeAll(keepingCapacity: false)
        }
    }

    private func consume(_ line: Data) {
        guard !line.isEmpty, line.count <= maximumLineBytes,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let id = (object["id"] as? NSNumber)?.intValue,
              acceptedIDs.contains(id) else { return }
            responses[id] = line
            updated.signal()
    }

    /// Flushes a valid final JSON response even when app-server closes stdout
    /// without a trailing newline.
    func finish() {
        lock.lock()
        defer { lock.unlock() }
        consume(buffer)
        buffer.removeAll(keepingCapacity: false)
    }

    func response(id: Int) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return responses[id]
    }
}

actor CodexQuotaService {
    private var inFlight: Task<QuotaSnapshot, Never>?

    func read() async -> QuotaSnapshot {
        if let inFlight { return await inFlight.value }
        let task = Task.detached(priority: .utility) { Self.performRead() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    private nonisolated static func performRead() -> QuotaSnapshot {
        guard let executable = findCodexExecutable() else {
            return unavailable("未找到 Codex 本地组件")
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        let collector = QuotaOutputCollector()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        output.fileHandleForReading.readabilityHandler = { collector.append($0.availableData) }
        // Drain stderr while app-server is alive. Its contents can contain
        // local paths, therefore PulseDock never persists them.
        errors.fileHandleForReading.readabilityHandler = { _ = $0.availableData }
        process.terminationHandler = { _ in collector.updated.signal() }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            return unavailable("Codex 额度服务无法启动")
        }

        do {
            let initialize = "{\"method\":\"initialize\",\"id\":1,\"params\":{\"clientInfo\":{\"name\":\"pulsedock\",\"title\":\"PulseDock\",\"version\":\"6.14.0\"}}}\n"
            try input.fileHandleForWriting.write(contentsOf: Data(initialize.utf8))
            // Newer app-server builds may be busy loading account state on a
            // cold start.  Do not send `initialized` or a rate-limit request
            // before an actual successful initialize response: such early
            // messages are silently discarded by some builds.
            let initializeDeadline = Date().addingTimeInterval(12)
            while collector.response(id: 1) == nil, process.isRunning, Date() < initializeDeadline {
                _ = collector.updated.wait(timeout: .now() + 0.1)
            }
            guard let initializeResponse = collector.response(id: 1), responseSucceeded(initializeResponse) else {
                stop(process, output: output, errors: errors, collector: collector)
                return unavailable("Codex 初始化超时或未完成；将自动重试")
            }
            let requests = [
                "{\"method\":\"initialized\",\"params\":{}}",
                "{\"method\":\"account/rateLimits/read\",\"id\":2,\"params\":{}}",
                "{\"method\":\"account/usage/read\",\"id\":3,\"params\":{}}"
            ].joined(separator: "\n") + "\n"
            try input.fileHandleForWriting.write(contentsOf: Data(requests.utf8))
        } catch {
            stop(process, output: output, errors: errors, collector: collector)
            return unavailable("无法向 Codex 查询额度")
        }

        let deadline = Date().addingTimeInterval(12)
        while collector.response(id: 2) == nil, Date() < deadline {
            _ = collector.updated.wait(timeout: .now() + 0.25)
        }
        // Usage is additive. Older app-server builds might not implement it,
        // so it gets only a short grace period and never invalidates quota.
        let usageDeadline = min(deadline, Date().addingTimeInterval(1.2))
        while collector.response(id: 3) == nil, Date() < usageDeadline {
            _ = collector.updated.wait(timeout: .now() + 0.15)
        }
        stop(process, output: output, errors: errors, collector: collector)

        guard let rateData = collector.response(id: 2) else {
            return unavailable("Codex 额度查询超时；将自动重试")
        }
        return decode(rateData, usageData: collector.response(id: 3))
    }

    private nonisolated static func responseSucceeded(_ data: Data) -> Bool {
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return envelope["error"] == nil && envelope["result"] != nil
    }

    private nonisolated static func stop(_ process: Process, output: Pipe, errors: Pipe, collector: QuotaOutputCollector) {
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(0.6)
            while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        collector.append(output.fileHandleForReading.readDataToEndOfFile())
        collector.finish()
    }

    nonisolated static func decode(_ data: Data, usageData: Data? = nil) -> QuotaSnapshot {
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return unavailable("Codex 未返回有效额度数据")
        }
        if let error = envelope["error"] as? [String: Any] {
            let raw = (error["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let safe = raw.map { String($0.prefix(180)) }
            return unavailable(safe?.isEmpty == false ? "Codex：\(safe!)" : "Codex 额度服务返回错误")
        }
        guard let result = envelope["result"] as? [String: Any] else {
            return unavailable("Codex 未返回有效额度数据")
        }

        let selected = selectedRateLimit(in: result)
        let windows = decodeWindows(from: selected.payload)
        guard let primaryWindow = windows.min(by: {
            ($0.windowMinutes ?? Int.max) < ($1.windowMinutes ?? Int.max)
        }) else {
            return unavailable("Codex 未返回可用额度窗口")
        }

        let resetCreditPayload = result["rateLimitResetCredits"] as? [String: Any]
        let resetCreditCount = (resetCreditPayload?["availableCount"] as? NSNumber)?.intValue
        let resetCredits = (resetCreditPayload?["credits"] as? [[String: Any]] ?? []).compactMap { value -> RateLimitResetCredit? in
            guard let id = value["id"] as? String else { return nil }
            return RateLimitResetCredit(
                id: id,
                status: value["status"] as? String ?? "unknown",
                grantedAt: epochDate(value["grantedAt"]),
                expiresAt: epochDate(value["expiresAt"]),
                title: value["title"] as? String,
                detail: value["description"] as? String
            )
        }

        let usage = usageData.flatMap(decodeUsage)
        return QuotaSnapshot(
            state: .available,
            remainingPercent: primaryWindow.remainingPercent,
            resetsAt: primaryWindow.resetsAt,
            windowMinutes: primaryWindow.windowMinutes,
            planType: selected.payload["planType"] as? String ?? result["planType"] as? String,
            resetCreditCount: resetCreditCount,
            resetCredits: resetCredits,
            message: usage == nil ? "额度来自 Codex 本地官方接口；当前组件未返回 Token 用量" : "额度与 Token 用量来自 Codex 本地官方接口",
            updatedAt: Date(),
            windows: windows,
            tokenUsageSummary: usage?.summary,
            dailyUsageBuckets: usage?.buckets ?? [],
            rateLimitReachedType: selected.payload["limitReachedType"] as? String ?? result["rateLimitReachedType"] as? String
        )
    }

    private nonisolated static func selectedRateLimit(in result: [String: Any]) -> (id: String, payload: [String: Any]) {
        if let byID = result["rateLimitsByLimitId"] as? [String: Any] {
            if let codex = byID["codex"] as? [String: Any] { return ("codex", codex) }
            for (key, value) in byID.sorted(by: { $0.key < $1.key }) {
                guard let payload = value as? [String: Any] else { continue }
                let limitID = (payload["limitId"] as? String ?? key).lowercased()
                if limitID.contains("codex") { return (key, payload) }
            }
        }
        return ("codex", result["rateLimits"] as? [String: Any] ?? [:])
    }

    private nonisolated static func decodeWindows(from limits: [String: Any]) -> [CodexQuotaWindow] {
        ["primary", "secondary"].compactMap { slot in
            guard let value = limits[slot] as? [String: Any],
                  let used = (value["usedPercent"] as? NSNumber)?.doubleValue,
                  used.isFinite else { return nil }
            let minutes = (value["windowDurationMins"] as? NSNumber)?.intValue
            return CodexQuotaWindow(
                id: slot,
                title: windowTitle(minutes: minutes, fallback: slot == "primary" ? "主要窗口" : "次级窗口"),
                usedPercent: max(0, min(100, used)),
                windowMinutes: minutes,
                resetsAt: epochDate(value["resetsAt"])
            )
        }.sorted {
            ($0.windowMinutes ?? Int.max) < ($1.windowMinutes ?? Int.max)
        }
    }

    private nonisolated static func windowTitle(minutes: Int?, fallback: String) -> String {
        guard let minutes, minutes > 0 else { return fallback }
        if minutes == 300 { return "5 小时额度" }
        if minutes == 10_080 { return "每周额度" }
        if minutes >= 40_000 && minutes <= 45_000 { return "月度额度" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440) 天额度" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时额度" }
        return "\(minutes) 分钟额度"
    }

    private nonisolated static func epochDate(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber else { return nil }
        let raw = number.doubleValue
        guard raw.isFinite, raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
    }

    private nonisolated static func decodeUsage(_ data: Data) -> (summary: CodexTokenUsageSummary?, buckets: [CodexDailyUsageBucket])? {
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = envelope["result"] as? [String: Any] else { return nil }
        let rawSummary = result["summary"] as? [String: Any]
        func nonnegativeInt64(_ value: Any?) -> Int64? {
            guard let number = value as? NSNumber else { return nil }
            let result = number.int64Value
            return result >= 0 ? result : nil
        }
        func nonnegativeInt(_ value: Any?) -> Int? {
            guard let number = value as? NSNumber else { return nil }
            let result = number.intValue
            return result >= 0 ? result : nil
        }
        let summary = rawSummary.map {
            CodexTokenUsageSummary(
                lifetimeTokens: nonnegativeInt64($0["lifetimeTokens"]),
                peakDailyTokens: nonnegativeInt64($0["peakDailyTokens"]),
                longestRunningTurnSeconds: nonnegativeInt64($0["longestRunningTurnSec"]),
                currentStreakDays: nonnegativeInt($0["currentStreakDays"]),
                longestStreakDays: nonnegativeInt($0["longestStreakDays"])
            )
        }
        var bucketsByDate: [String: CodexDailyUsageBucket] = [:]
        for value in result["dailyUsageBuckets"] as? [[String: Any]] ?? [] {
            guard let date = value["startDate"] as? String,
                  let tokens = (value["tokens"] as? NSNumber)?.int64Value,
                  tokens >= 0 else { continue }
            bucketsByDate[date] = CodexDailyUsageBucket(startDate: date, tokens: tokens)
        }
        let buckets = bucketsByDate.values.sorted { $0.startDate < $1.startDate }
        return (summary, buckets)
    }

    private nonisolated static func findCodexExecutable() -> String? {
        let fixed = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex"
        ]
        for path in fixed where FileManager.default.isExecutableFile(atPath: path) { return path }
        for folder in ProcessInfo.processInfo.environment["PATH", default: ""].split(separator: ":") {
            let path = String(folder) + "/codex"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    private nonisolated static func unavailable(_ message: String) -> QuotaSnapshot {
        QuotaSnapshot(
            state: .unavailable,
            remainingPercent: nil,
            resetsAt: nil,
            windowMinutes: nil,
            planType: nil,
            resetCreditCount: nil,
            resetCredits: [],
            message: message,
            updatedAt: Date()
        )
    }
}
