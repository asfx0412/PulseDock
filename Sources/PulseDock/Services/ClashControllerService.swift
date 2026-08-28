import Foundation

struct ClashControllerDiscovery: Sendable {
    var address: String?
    var inspection: ClashControllerInspection?
    var candidates: [String]
    var evidence: String
}

struct ClashControllerInspection: Sendable {
    var reachable: Bool
    var providerCount: Int?
    var version: String?
    var evidence: String
    var checkedAt: Date
}

struct ClashSyncResult: Sendable {
    var success: Bool
    var updatedProviders: Int
    var evidence: String
    var checkedAt: Date
}

actor ClashControllerService {
    private let vergeSocketAddress = "unix:///tmp/verge/verge-mihomo.sock"

    nonisolated static func isAllowedLocalAddress(_ value: String) -> Bool {
        if value == "unix:///tmp/verge/verge-mihomo.sock" { return true }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: text), let host = url.host else { return false }
        return ["127.0.0.1", "localhost", "::1"].contains(host)
    }

    func discover(preferred: String, secret: String) async -> ClashControllerDiscovery {
        let candidates = candidateAddresses(preferred: preferred)
        guard !candidates.isEmpty else {
            return ClashControllerDiscovery(address: nil, inspection: nil, candidates: [], evidence: "未发现 Clash/Mihomo 的本机回环监听端口；请启动 Clash Verge 后重试")
        }
        var last: ClashControllerInspection?
        var reports: [String] = []
        for candidate in candidates {
            let inspection = await inspect(baseURL: candidate, secret: secret)
            last = inspection
            reports.append("\(displayAddress(candidate))：\(inspection.evidence)")
            if inspection.reachable || inspection.evidence.contains("Secret 缺失或不匹配") {
                return ClashControllerDiscovery(address: candidate, inspection: inspection, candidates: candidates, evidence: "已验证 \(displayAddress(candidate))：\(inspection.evidence)")
            }
        }
        return ClashControllerDiscovery(address: nil, inspection: last, candidates: candidates, evidence: "没有找到可用控制器。" + reports.joined(separator: "；"))
    }

    func providerUsage(baseURL: String, secret: String) async -> [ClashQuotaSnapshot] {
        guard validAddress(baseURL) else { return [] }
        do {
            let response = try await request(baseURL: baseURL, endpoint: "providers/proxies", secret: secret)
            guard response.status == 200,
                  let root = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
                  let providers = root["providers"] as? [String: Any] else { return [] }
            return providers.compactMap { name, raw in
                guard let provider = raw as? [String: Any],
                      let info = (provider["subscriptionInfo"] ?? provider["subscription-info"]) as? [String: Any],
                      let total = uint(info, "Total", "total"), total > 0 else { return nil }
                let upload = uint(info, "Upload", "upload") ?? 0
                let download = uint(info, "Download", "download") ?? 0
                let expire = uint(info, "Expire", "expire").map { Date(timeIntervalSince1970: TimeInterval($0)) }
                return ClashQuotaSnapshot(
                    state: .available,
                    identifier: "Mihomo|\(name)",
                    sourceApp: "Mihomo 控制器",
                    name: name,
                    usedBytes: upload &+ download,
                    totalBytes: total,
                    expiresAt: expire,
                    updatedAt: Date(),
                    autoUpdateEnabled: false,
                    updateIntervalMinutes: nil,
                    message: "数据来自运行中的 Mihomo 代理提供者"
                )
            }
        } catch { return [] }
    }
    func inspect(baseURL: String, secret: String) async -> ClashControllerInspection {
        guard validAddress(baseURL) else {
            return ClashControllerInspection(reachable: false, providerCount: nil, version: nil, evidence: "控制器地址无效；只允许本机回环地址或 Clash Verge 本机套接字", checkedAt: Date())
        }
        do {
            let response = try await request(baseURL: baseURL, endpoint: "version", secret: secret)
            guard response.status == 200 else {
                return ClashControllerInspection(reachable: false, providerCount: nil, version: nil, evidence: httpEvidence(response.status), checkedAt: Date())
            }
            let root = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any]
            let version = root?["version"] as? String
            let providers = try await request(baseURL: baseURL, endpoint: "providers/proxies", secret: secret)
            if providers.status == 200 {
                let providerRoot = try? JSONSerialization.jsonObject(with: providers.data) as? [String: Any]
                let count = (providerRoot?["providers"] as? [String: Any])?.count ?? 0
                let detail = count == 0 ? "控制器可用，但当前运行配置没有可刷新的代理提供者" : "控制器可用；发现 \(count) 个可刷新代理提供者"
                return ClashControllerInspection(reachable: true, providerCount: count, version: version, evidence: version.map { "\(detail)（Mihomo \($0)）" } ?? detail, checkedAt: Date())
            }
            return ClashControllerInspection(reachable: true, providerCount: nil, version: version, evidence: "控制器 /version 可用，但代理提供者查询失败：\(httpEvidence(providers.status))", checkedAt: Date())
        } catch {
            return ClashControllerInspection(reachable: false, providerCount: nil, version: nil, evidence: connectionEvidence(error), checkedAt: Date())
        }
    }

    func synchronize(baseURL: String, secret: String) async -> ClashSyncResult {
        guard validAddress(baseURL) else { return ClashSyncResult(success: false, updatedProviders: 0, evidence: "控制器地址无效；只允许本机回环地址或 Clash Verge 本机套接字", checkedAt: Date()) }
        let inspection = await inspect(baseURL: baseURL, secret: secret)
        guard inspection.reachable else { return ClashSyncResult(success: false, updatedProviders: 0, evidence: inspection.evidence, checkedAt: inspection.checkedAt) }
        guard let count = inspection.providerCount else { return ClashSyncResult(success: false, updatedProviders: 0, evidence: inspection.evidence, checkedAt: inspection.checkedAt) }
        guard count > 0 else { return ClashSyncResult(success: true, updatedProviders: 0, evidence: inspection.evidence, checkedAt: inspection.checkedAt) }
        do {
            let response = try await request(baseURL: baseURL, endpoint: "providers/proxies", secret: secret)
            guard response.status == 200 else { return ClashSyncResult(success: false, updatedProviders: 0, evidence: httpEvidence(response.status), checkedAt: Date()) }
            let root = try JSONSerialization.jsonObject(with: response.data) as? [String: Any]
            let providers = (root?["providers"] as? [String: Any])?.keys.sorted() ?? []
            var updated = 0
            for name in providers {
                let escaped = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
                let response = try await request(baseURL: baseURL, endpoint: "providers/proxies/\(escaped)", method: "PUT", secret: secret, timeout: 12)
                if response.status == 204 { updated += 1 }
            }
            let evidence = "已请求更新 \(updated)/\(providers.count) 个代理提供者"
            return ClashSyncResult(success: updated == providers.count, updatedProviders: updated, evidence: evidence, checkedAt: Date())
        } catch { return ClashSyncResult(success: false, updatedProviders: 0, evidence: connectionEvidence(error), checkedAt: Date()) }
    }

    private func request(baseURL: String, endpoint: String, method: String = "GET", secret: String, timeout: TimeInterval = 5) async throws -> (data: Data, status: Int) {
        if socketPath(baseURL) != nil { return try requestUnixSocket(baseURL: baseURL, endpoint: endpoint, method: method, timeout: timeout) }
        guard let base = normalizedURL(baseURL) else { throw URLError(.badURL) }
        let url = base.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        if !secret.isEmpty { request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http.statusCode)
    }

    private func requestUnixSocket(baseURL: String, endpoint: String, method: String, timeout: TimeInterval) throws -> (data: Data, status: Int) {
        guard let socket = socketPath(baseURL), FileManager.default.fileExists(atPath: socket) else { throw URLError(.cannotConnectToHost) }
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "--silent", "--show-error", "--max-time", String(max(1, Int(timeout))),
            "--max-filesize", "2000000", "--unix-socket", socket,
            "--request", method, "--write-out", "\n%{http_code}",
            "http://localhost/\(endpoint)"
        ]
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: errorData.prefix(240), as: UTF8.self)
            throw NSError(domain: "PulseDock.MihomoUnixSocket", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: detail.isEmpty ? "Unix 控制套接字请求失败" : detail])
        }
        guard let split = data.lastIndex(of: 0x0A), let status = Int(String(decoding: data[data.index(after: split)...], as: UTF8.self)) else { throw URLError(.badServerResponse) }
        let body = Data(data[..<split])
        return (body, status)
    }

    private func httpEvidence(_ status: Int) -> String {
        switch status {
        case 401, 403: return "控制器已监听，但 Secret 缺失或不匹配（HTTP \(status)）"
        case 400: return "控制器返回 HTTP 400；请重启当前 Mihomo 内核并确认实际运行配置启用了 external-controller"
        case 404: return "控制器端点不存在（HTTP 404）；当前内核可能不是兼容的 Mihomo 控制器"
        default: return "控制器返回 HTTP \(status)"
        }
    }

    private func connectionEvidence(_ error: Error) -> String {
        let code = (error as? URLError)?.code
        switch code {
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
            return "本机控制器端口没有进程监听；保存配置后需重载/重启正在运行的 Mihomo 内核"
        case .timedOut: return "本机控制器连接超时；请检查端口、内核状态和本机安全软件"
        default: return "控制器连接失败：\(error.localizedDescription)"
        }
    }

    private func normalizedURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: text), let host = url.host, ["127.0.0.1", "localhost", "::1"].contains(host) else { return nil }
        return url
    }

    private func socketPath(_ value: String) -> String? {
        guard value == vergeSocketAddress else { return nil }
        return String(value.dropFirst("unix://".count))
    }

    private func validAddress(_ value: String) -> Bool { Self.isAllowedLocalAddress(value) && (socketPath(value) != nil || normalizedURL(value) != nil) }

    private func displayAddress(_ value: String) -> String {
        if socketPath(value) != nil { return "Clash Verge 本机套接字" }
        return normalizedURL(value)?.host.map { host in
            let port = normalizedURL(value)?.port.map(String.init) ?? "80"
            return "\(host):\(port)"
        } ?? value
    }

    private func candidateAddresses(preferred: String) -> [String] {
        var candidates: [String] = [preferred]
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/io.github.clash-verge-rev.clash-verge-rev")
        for name in ["config.yaml", "clash-verge.yaml", "clash-verge-check.yaml"] {
            let url = support.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("external-controller-unix:"), trimmed.contains("/tmp/verge/verge-mihomo.sock") {
                    candidates.append(vergeSocketAddress)
                }
                guard trimmed.hasPrefix("external-controller:"), let colon = trimmed.firstIndex(of: ":") else { continue }
                let raw = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if normalizedURL(raw) != nil { candidates.append(raw) }
            }
        }
        if FileManager.default.fileExists(atPath: "/tmp/verge/verge-mihomo.sock") { candidates.append(vergeSocketAddress) }
        candidates.append(contentsOf: listeningClashPorts().map { "127.0.0.1:\($0)" })
        var seen = Set<String>()
        return candidates.filter { candidate in
            if socketPath(candidate) != nil { return seen.insert(candidate).inserted }
            guard let url = normalizedURL(candidate) else { return false }
            return seen.insert(url.absoluteString).inserted
        }
    }

    private func listeningClashPorts() -> [Int] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN"]
        process.standardOutput = output
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = String(raw).lowercased()
            guard (line.contains("clash") || line.contains("mihomo") || line.contains("verge")),
                  let match = line.range(of: #"127\.0\.0\.1:([0-9]+)"#, options: .regularExpression) else { return nil }
            let portText = line[match].split(separator: ":").last.map(String.init) ?? ""
            return Int(portText)
        }
    }

    private func uint(_ values: [String: Any], _ keys: String...) -> UInt64? {
        for key in keys {
            if let value = values[key] as? NSNumber { return value.uint64Value }
            if let value = values[key] as? String, let number = UInt64(value) { return number }
        }
        return nil
    }
}
