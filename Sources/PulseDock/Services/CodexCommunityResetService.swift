import Foundation

/// A deliberately small, public subset of a Codex Runway record. We do not
/// retain source-post text: it is not needed to present or deduplicate a
/// reset signal, and would make the local cache needlessly broad.
struct CodexCommunityResetRecord: Sendable, Equatable, Codable, Identifiable {
    struct Scope: Sendable, Equatable, Codable {
        var plans: [String]
        var windows: [String]

        var label: String? {
            let usefulPlans = plans.filter { $0 != "unknown" }
            guard !usefulPlans.isEmpty else { return nil }
            return usefulPlans.map { $0 == "all" ? "全部套餐" : $0 }.joined(separator: "、")
        }
    }

    var id: String
    var kind: String
    var announcedAt: Date?
    var effectiveAt: Date?
    var confidence: Double?
    var scope: Scope?
    var sourceURL: URL?
    var schedulePrecision: String?
    var scheduleBasis: String?
    var scheduleState: String?
    var completionRecordID: String?
    var relatedRecordIDs: [String]

    var isPendingSchedule: Bool { kind == "reset_scheduled" && scheduleState == "pending" }
    var isCompletion: Bool { kind == "reset_completed" || scheduleState == "fulfilled" }
    var isExactExplicitSchedule: Bool { schedulePrecision == "datetime" && scheduleBasis == "explicit" }
    var scopeLabel: String? { scope?.label }
}

struct CodexCommunityResetSnapshot: Sendable, Equatable {
    enum State: Sendable { case loading, available, unavailable }

    var state: State
    var resetToday: Bool
    var confidence: Double?
    var lastResetAt: Date?
    var nextScheduledAt: Date?
    var sourceURL: URL?
    var checkedAt: Date?
    var sourceGeneratedAt: Date?
    var upstreamLastSuccessfulCheckAt: Date?
    var isStale: Bool
    var records: [CodexCommunityResetRecord]
    var message: String

    static let loading = CodexCommunityResetSnapshot(
        state: .loading, resetToday: false, confidence: nil, lastResetAt: nil,
        nextScheduledAt: nil, sourceURL: nil, checkedAt: nil, sourceGeneratedAt: nil,
        upstreamLastSuccessfulCheckAt: nil, isStale: false, records: [],
        message: "正在读取社区重置信号"
    )

    var verdictLabel: String {
        if state != .available { return "社区信号 --" }
        return resetToday ? "今日已全局重置" : (nextScheduledAt == nil ? "暂无重置计划" : "已有重置计划")
    }

    var confidenceLabel: String? {
        guard (resetToday || nextScheduledAt != nil), let confidence else { return nil }
        return "当前信号确认度 \(Int((confidence * 100).rounded()))%"
    }

    var historicalConfidenceLabel: String? {
        guard !resetToday, nextScheduledAt == nil, let confidence, lastResetAt != nil else { return nil }
        return "最近历史事件确认度 \(Int((confidence * 100).rounded()))%"
    }

    var activeSchedule: CodexCommunityResetRecord? {
        records.filter(\.isPendingSchedule).sorted { ($0.effectiveAt ?? .distantFuture) < ($1.effectiveAt ?? .distantFuture) }.first
    }
}

struct CodexCommunityResetReadResult: Sendable {
    var snapshot: CodexCommunityResetSnapshot
    /// A server-mandated delay (429). Nil means the normal cadence may resume.
    var retryAfter: TimeInterval?
    var wasSuccessful: Bool
}

actor CodexCommunityResetService {
    // The public API caps pageSize at 10. We intentionally request only page
    // one (newest effective records) rather than chase mutable pagination:
    // corrected records may move between pages, while alerts only need the
    // latest current plan and linked completion state.
    private let endpoint = URL(string: "https://www.codexrunway.com/openapi/v1/records?page=1&pageSize=10")!
    private let cacheKey = "PulseDock.codexCommunityResetRecordsCache"
    private let maximumResponseBytes = 256 * 1_024
    private var inFlight: Task<CodexCommunityResetReadResult, Never>?

    private struct CachedRecords: Codable {
        var records: [CodexCommunityResetRecord]
        var sourceGeneratedAt: Date?
        var upstreamLastSuccessfulCheckAt: Date?
    }

    func readRecords() async -> CodexCommunityResetReadResult {
        if let inFlight { return await inFlight.value }
        let task = Task { await self.performRead() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    private func performRead() async -> CodexCommunityResetReadResult {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            var data = Data()
            for try await byte in bytes {
                guard data.count < maximumResponseBytes else { throw URLError(.dataLengthExceedsMaximum) }
                data.append(byte)
            }
            let http = response as? HTTPURLResponse
            if http?.statusCode == 429 {
                return cachedResult(message: "社区源请求过快；正在遵守上游重试时间", retryAfter: retryAfter(http: http, data: data))
            }
            guard http?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let snapshot = Self.decode(data: data, now: Date(), stale: false)
            guard snapshot.state == .available else { throw URLError(.cannotParseResponse) }
            cache(snapshot)
            return CodexCommunityResetReadResult(snapshot: snapshot, retryAfter: nil, wasSuccessful: true)
        } catch {
            return cachedResult(message: "社区数据暂时不可用，正在显示缓存", retryAfter: nil)
        }
    }

    /// Kept for the existing manual-refresh call sites and small offline tests.
    func read() async -> CodexCommunityResetSnapshot { await readRecords().snapshot }

    private func cachedResult(message: String, retryAfter: TimeInterval?) -> CodexCommunityResetReadResult {
        if let cached = UserDefaults.standard.data(forKey: cacheKey) {
            if let payload = try? JSONDecoder().decode(CachedRecords.self, from: cached) {
                var snapshot = Self.snapshot(records: payload.records, now: Date(), stale: true, generatedAt: payload.sourceGeneratedAt, upstreamLastSuccessfulCheckAt: payload.upstreamLastSuccessfulCheckAt)
                snapshot.message = message
                return CodexCommunityResetReadResult(snapshot: snapshot, retryAfter: retryAfter, wasSuccessful: false)
            }
            // Read, but never write back, a short-lived cache from an older
            // release. A successful new request replaces it with the bounded
            // record-only payload above.
            var legacy = Self.decode(data: cached, now: Date(), stale: true)
            if legacy.state == .available {
                legacy.message = message
                return CodexCommunityResetReadResult(snapshot: legacy, retryAfter: retryAfter, wasSuccessful: false)
            }
        }
        return CodexCommunityResetReadResult(
            snapshot: CodexCommunityResetSnapshot(
                state: .unavailable, resetToday: false, confidence: nil, lastResetAt: nil,
                nextScheduledAt: nil, sourceURL: nil, checkedAt: Date(), sourceGeneratedAt: nil,
                upstreamLastSuccessfulCheckAt: nil, isStale: false, records: [], message: "社区重置信号不可用"
            ), retryAfter: retryAfter, wasSuccessful: false
        )
    }

    private func cache(_ snapshot: CodexCommunityResetSnapshot) {
        let payload = CachedRecords(records: snapshot.records, sourceGeneratedAt: snapshot.sourceGeneratedAt, upstreamLastSuccessfulCheckAt: snapshot.upstreamLastSuccessfulCheckAt)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    private func retryAfter(http: HTTPURLResponse?, data: Data) -> TimeInterval {
        if let text = http?.value(forHTTPHeaderField: "Retry-After"), let seconds = TimeInterval(text), seconds > 0 { return seconds }
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let seconds = (root["retryAfter"] as? NSNumber)?.doubleValue, seconds > 0 { return seconds }
        return 300
    }

    nonisolated static func decode(data: Data, now: Date, stale: Bool) -> CodexCommunityResetSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return unavailable(now: now, stale: stale) }
        if let apiData = root["data"] as? [String: Any], let items = apiData["items"] as? [[String: Any]] {
            let meta = root["meta"] as? [String: Any]
            let records = items.compactMap(parseRecord)
            // An empty page is valid. A non-empty page where every record is
            // malformed is not: treat it as a failed read so callers preserve
            // their earlier valid snapshot and never cache hostile data.
            guard items.isEmpty || !records.isEmpty else { return unavailable(now: now, stale: stale) }
            return snapshot(records: records, now: now, stale: stale,
                            generatedAt: parseDate(meta?["generatedAt"] as? String),
                            upstreamLastSuccessfulCheckAt: parseDate(meta?["lastSuccessfulCheckAt"] as? String))
        }
        if let apiRecord = root["data"] as? [String: Any], let record = parseRecord(apiRecord) {
            let meta = root["meta"] as? [String: Any]
            return snapshot(records: [record], now: now, stale: stale,
                            generatedAt: parseDate(meta?["generatedAt"] as? String),
                            upstreamLastSuccessfulCheckAt: parseDate(meta?["lastSuccessfulCheckAt"] as? String))
        }
        // Compatibility for a pre-OpenAPI cache from older PulseDock builds.
        if let rawEvents = root["events"] as? [[String: Any]] {
            let records = rawEvents.enumerated().compactMap { index, raw -> CodexCommunityResetRecord? in
                guard let kind = raw["kind"] as? String else { return nil }
                let announced = parseDate(raw["announcedAt"] as? String)
                let effective = parseDate(raw["effectiveAt"] as? String)
                guard announced != nil || effective != nil else { return nil }
                let source = (raw["source"] as? [String: Any])?["url"] as? String
                return CodexCommunityResetRecord(
                    id: "legacy-\(index)-\(announced?.timeIntervalSince1970 ?? effective?.timeIntervalSince1970 ?? 0)",
                    kind: kind, announcedAt: announced, effectiveAt: effective,
                    confidence: (raw["confidence"] as? NSNumber)?.doubleValue,
                    scope: nil, sourceURL: source.flatMap(validSourceURL),
                    schedulePrecision: nil, scheduleBasis: nil,
                    scheduleState: kind == "reset_scheduled" ? "pending" : nil,
                    completionRecordID: nil, relatedRecordIDs: []
                )
            }
            return snapshot(records: records, now: now, stale: stale,
                            generatedAt: parseDate(root["generatedAt"] as? String), upstreamLastSuccessfulCheckAt: nil)
        }
        return unavailable(now: now, stale: stale)
    }

    private nonisolated static func snapshot(records: [CodexCommunityResetRecord], now: Date, stale: Bool, generatedAt: Date?, upstreamLastSuccessfulCheckAt: Date?) -> CodexCommunityResetSnapshot {
        let completed = records.filter { $0.kind == "reset_completed" }.sorted { ($0.effectiveAt ?? $0.announcedAt ?? .distantPast) > ($1.effectiveAt ?? $1.announcedAt ?? .distantPast) }
        let scheduled = records.filter(\.isPendingSchedule).filter { ($0.effectiveAt ?? .distantPast) > now }.sorted { ($0.effectiveAt ?? .distantFuture) < ($1.effectiveAt ?? .distantFuture) }
        let calendar = Calendar.current
        let todayEvents = completed.filter { event in
            guard let date = event.effectiveAt ?? event.announcedAt else { return false }
            return calendar.isDate(date, inSameDayAs: now)
        }
        let source = todayEvents.max { ($0.confidence ?? 0) < ($1.confidence ?? 0) } ?? scheduled.first ?? completed.first
        return CodexCommunityResetSnapshot(
            state: .available, resetToday: !todayEvents.isEmpty, confidence: source?.confidence,
            lastResetAt: completed.first?.effectiveAt ?? completed.first?.announcedAt,
            nextScheduledAt: scheduled.first?.effectiveAt, sourceURL: source?.sourceURL,
            checkedAt: now, sourceGeneratedAt: generatedAt,
            upstreamLastSuccessfulCheckAt: upstreamLastSuccessfulCheckAt, isStale: stale, records: records,
            message: "第三方社区信号，仅供参考"
        )
    }

    private nonisolated static func unavailable(now: Date, stale: Bool) -> CodexCommunityResetSnapshot {
        CodexCommunityResetSnapshot(
            state: .unavailable, resetToday: false, confidence: nil, lastResetAt: nil,
            nextScheduledAt: nil, sourceURL: nil, checkedAt: now, sourceGeneratedAt: nil,
            upstreamLastSuccessfulCheckAt: nil, isStale: stale, records: [], message: "社区数据格式无法识别"
        )
    }

    private nonisolated static func parseRecord(_ raw: [String: Any]) -> CodexCommunityResetRecord? {
        guard let id = raw["id"] as? String, let kind = raw["kind"] as? String else { return nil }
        let scopePayload = raw["scope"] as? [String: Any]
        let scope = scopePayload.map { CodexCommunityResetRecord.Scope(plans: $0["plans"] as? [String] ?? [], windows: $0["windows"] as? [String] ?? []) }
        let sourceURL = ((raw["source"] as? [String: Any])?["url"] as? String).flatMap(validSourceURL)
        return CodexCommunityResetRecord(
            id: id, kind: kind, announcedAt: parseDate(raw["announcedAt"] as? String), effectiveAt: parseDate(raw["effectiveAt"] as? String),
            confidence: (raw["confidence"] as? NSNumber)?.doubleValue, scope: scope, sourceURL: sourceURL,
            schedulePrecision: raw["schedulePrecision"] as? String, scheduleBasis: raw["scheduleBasis"] as? String,
            scheduleState: raw["scheduleState"] as? String, completionRecordID: raw["completionRecordId"] as? String,
            relatedRecordIDs: raw["relatedRecordIds"] as? [String] ?? []
        )
    }

    private nonisolated static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private nonisolated static func validSourceURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host?.lowercased() else { return nil }
        let approvedHosts = ["x.com", "twitter.com", "codexrunway.com"]
        guard approvedHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) else { return nil }
        return url
    }
}
