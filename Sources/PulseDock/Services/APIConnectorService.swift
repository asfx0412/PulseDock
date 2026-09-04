import Foundation

private final class GitHubCopilotRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // Authorization must never follow a redirect to an arbitrary host.
        guard request.url?.scheme == "https", request.url?.host?.lowercased() == "api.github.com" else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

actor APIConnectorService {
    private let cursorUsage = CursorUsageService()
    private var glmInFlight: [UUID: Task<APIConnectorSnapshot, Never>] = [:]

    func probe(_ connector: APIConnectorConfiguration, apiKey: String) async -> APIConnectorSnapshot {
        switch connector.kind {
        case .codexLocalQuota:
            // MonitorStore adapts the already-read CodexQuotaService snapshot.
            // Keeping this branch inert prevents a duplicate app-server query.
            return APIConnectorSnapshot(id: connector.id, state: .unavailable, updatedAt: Date(), message: "Codex 由本机官方额度读取器提供")
        case .cursorLocalUsage:
            return await cursorUsage.readCurrentPeriodUsage(id: connector.id)
        case .glmCodingPlan:
            if let task = glmInFlight[connector.id] { return await task.value }
            let task = Task { await self.probeGLMCodingPlan(connector, apiKey: apiKey) }
            glmInFlight[connector.id] = task
            let snapshot = await task.value
            glmInFlight[connector.id] = nil
            return snapshot
        case .deepSeekBalance:
            return await probeDeepSeekBalance(connector, apiKey: apiKey)
        case .customRateLimit:
            return await probeRateLimit(connector, apiKey: apiKey)
        case .githubCopilotUsage:
            return await probeGitHubCopilotUsage(connector, apiKey: apiKey)
        }
    }

    private func probeGitHubCopilotUsage(_ connector: APIConnectorConfiguration, apiKey: String) async -> APIConnectorSnapshot {
        guard let username = Self.validGitHubUsername(connector.accountID) else {
            return APIConnectorSnapshot(id: connector.id, state: .unavailable, updatedAt: Date(), message: "请填写有效的 GitHub 用户名（1–39 位，字母、数字、连字符）")
        }
        guard !apiKey.isEmpty else {
            return APIConnectorSnapshot(id: connector.id, state: .unavailable, updatedAt: Date(), message: "请填写 GitHub Fine-grained PAT（仅 Plan: read）")
        }
        let base = "https://api.github.com/users/\(username)/settings/billing"
        guard let credits = URL(string: base + "/ai_credit/usage"),
              let premium = URL(string: base + "/premium_request/usage") else {
            return APIConnectorSnapshot(id: connector.id, state: .error, updatedAt: Date(), message: "GitHub Copilot 官方端点无效")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: GitHubCopilotRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            async let creditResult = Self.githubJSON(session: session, url: credits, token: apiKey)
            async let premiumResult = Self.githubJSON(session: session, url: premium, token: apiKey)
            let (creditData, premiumData) = try await (creditResult, premiumResult)
            let metrics = Self.decodeGitHubCopilotMetrics(creditData: creditData, premiumData: premiumData)
            guard !metrics.isEmpty else {
                return APIConnectorSnapshot(id: connector.id, state: .unavailable, updatedAt: Date(), message: "GitHub 返回成功，但未提供可显示的 Copilot 个人用量")
            }
            let primary = metrics.first?.usedValue
            return APIConnectorSnapshot(
                id: connector.id, state: .available, updatedAt: Date(),
                message: "GitHub 官方个人 Billing API · 仅显示已用量，不推测套餐总额",
                usageMetrics: metrics, primaryValue: primary
            )
        } catch let error as GitHubCopilotRequestError {
            return APIConnectorSnapshot(id: connector.id, state: .unavailable, updatedAt: Date(), message: error.message)
        } catch {
            return APIConnectorSnapshot(id: connector.id, state: .error, updatedAt: Date(), message: "GitHub Copilot 用量请求失败：\(error.localizedDescription)")
        }
    }

    private enum GitHubCopilotRequestError: Error {
        case status(Int, retryAfter: String?)
        case oversized
        case nonJSON

        var message: String {
            switch self {
            case let .status(code, retryAfter):
                switch code {
                case 401: "GitHub 凭据无效或已过期（401）"
                case 403: "GitHub 拒绝访问；请确认 Fine-grained PAT 仅授予 Plan: read（403）"
                case 404: "GitHub 未找到该个人 Billing 端点；组织账户不在此模式支持范围内（404）"
                case 429: "GitHub 请求频率受限（429）\(retryAfter.map { "；请在 \($0) 后重试" } ?? "")"
                case 500...599: "GitHub 服务暂时异常（HTTP \(code)），将自动重试"
                default: "GitHub Copilot Billing API 返回 HTTP \(code)"
                }
            case .oversized: "GitHub 返回数据超过 1 MB 安全上限"
            case .nonJSON: "GitHub 返回非 JSON 数据，可能被网络网关替换"
            }
        }
    }

    private nonisolated static func githubJSON(session: URLSession, url: URL, token: String) async throws -> Data {
        guard url.scheme == "https", url.host?.lowercased() == "api.github.com" else { throw GitHubCopilotRequestError.nonJSON }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else { throw GitHubCopilotRequestError.status(http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After")) }
        guard data.count <= 1_000_000 else { throw GitHubCopilotRequestError.oversized }
        let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        guard type.contains("json"), (try? JSONSerialization.jsonObject(with: data)) != nil else { throw GitHubCopilotRequestError.nonJSON }
        return data
    }

    nonisolated static func isValidGitHubUsername(_ raw: String?) -> Bool {
        validGitHubUsername(raw) != nil
    }

    private nonisolated static func validGitHubUsername(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.count <= 39, value.range(of: "^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$", options: .regularExpression) != nil else { return nil }
        return value
    }

    nonisolated static func decodeGitHubCopilotMetrics(creditData: Data, premiumData: Data) -> [APIUsageMetric] {
        let creditObject = (try? JSONSerialization.jsonObject(with: creditData)) as? [String: Any] ?? [:]
        let premiumObject = (try? JSONSerialization.jsonObject(with: premiumData)) as? [String: Any] ?? [:]
        var metrics: [APIUsageMetric] = []
        if let credit = usageMetric(from: creditObject, title: "AI Credits") {
            metrics.append(credit)
        }
        if let premium = usageMetric(from: premiumObject, title: "Premium Requests") {
            metrics.append(premium)
        }
        return metrics
    }

    private nonisolated static func usageMetric(from object: [String: Any], title: String) -> APIUsageMetric? {
        let used = firstNumber(in: object, keys: ["used", "used_amount", "total_used", "usage", "consumed", "amount_used"])
            ?? firstNumberRecursively(in: object, keys: ["used", "used_amount", "total_used", "usage", "consumed", "amount_used"])
        guard let used else { return nil }
        let unit = firstString(in: object, keys: ["unit", "currency", "measurement"]) ?? ""
        let details = usageBreakdown(in: object).prefix(4).joined(separator: " · ")
        let compact = used.rounded() == used ? String(Int(used)) : String(format: "%.2f", used)
        return APIUsageMetric(id: title, title: title, usedValue: "已用 \(compact)\(unit.isEmpty ? "" : " \(unit)")", detail: details.isEmpty ? "本计费周期官方已用量" : details)
    }

    private nonisolated static func firstNumber(in object: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = object[key] as? NSNumber { return value.doubleValue }
            if let value = object[key] as? String, let number = Double(value) { return number }
        }
        return nil
    }

    private nonisolated static func firstString(in object: [String: Any], keys: [String]) -> String? {
        for key in keys { if let value = object[key] as? String, !value.isEmpty { return String(value.prefix(40)) } }
        return nil
    }

    private nonisolated static func firstNumberRecursively(in value: Any, keys: [String], depth: Int = 0) -> Double? {
        guard depth < 4 else { return nil }
        if let object = value as? [String: Any] {
            if let direct = firstNumber(in: object, keys: keys) { return direct }
            for child in object.values { if let found = firstNumberRecursively(in: child, keys: keys, depth: depth + 1) { return found } }
        } else if let array = value as? [Any] {
            for child in array { if let found = firstNumberRecursively(in: child, keys: keys, depth: depth + 1) { return found } }
        }
        return nil
    }

    private nonisolated static func usageBreakdown(in value: Any, depth: Int = 0) -> [String] {
        guard depth < 3 else { return [] }
        if let array = value as? [[String: Any]] {
            return array.compactMap { item in
                guard let used = firstNumber(in: item, keys: ["used", "used_amount", "usage", "consumed"]) else { return nil }
                let label = firstString(in: item, keys: ["sku", "model", "name", "product"]) ?? "项目"
                return "\(label) \(used.rounded() == used ? String(Int(used)) : String(format: "%.2f", used))"
            }
        }
        if let object = value as? [String: Any] {
            for key in ["items", "usage_items", "breakdown", "sku_usage", "data"] {
                if let child = object[key] { let found = usageBreakdown(in: child, depth: depth + 1); if !found.isEmpty { return found } }
            }
            for child in object.values { let found = usageBreakdown(in: child, depth: depth + 1); if !found.isEmpty { return found } }
        }
        return []
    }

    private func probeRateLimit(_ connector: APIConnectorConfiguration, apiKey: String) async -> APIConnectorSnapshot {
        guard let url = URL(string: connector.endpoint), url.scheme == "https" else {
            return APIConnectorSnapshot(id: connector.id, state: .error, updatedAt: Date(), message: "仅允许 HTTPS 官方端点")
        }
        do {
            var request = URLRequest(url: url); request.timeoutInterval = 10; request.httpMethod = "HEAD"
            if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                // HTTP field names are case-insensitive and some servers emit
                // duplicate spellings. Deterministically keep the last value;
                // never feed untrusted response keys to a uniqueness precondition.
                headers[String(describing: key).lowercased()] = String(describing: value)
            }
            let requests = headers["x-ratelimit-remaining-requests"] ?? headers["ratelimit-remaining"]
            let tokens = headers["x-ratelimit-remaining-tokens"]
            let reset = headers["x-ratelimit-reset-requests"] ?? headers["ratelimit-reset"]
            if requests == nil && tokens == nil {
                return APIConnectorSnapshot(id: connector.id, state: .unavailable, updatedAt: Date(), message: "端点可达，但响应未公开剩余额度/速率限制")
            }
            return APIConnectorSnapshot(id: connector.id, state: .available, remainingRequests: requests, remainingTokens: tokens, resetAt: reset, updatedAt: Date(), message: "来自官方 API 响应头")
        } catch { return APIConnectorSnapshot(id: connector.id, state: .error, updatedAt: Date(), message: error.localizedDescription) }
    }

    private func probeGLMCodingPlan(_ connector: APIConnectorConfiguration, apiKey: String) async -> APIConnectorSnapshot {
        guard !apiKey.isEmpty else { return APIConnectorSnapshot(id: connector.id, state: .unavailable, updatedAt: Date(), message: "请填写 GLM Coding Plan API Key") }
        guard let url = URL(string: connector.endpoint), url.scheme == "https", url.host == "open.bigmodel.cn" else {
            return APIConnectorSnapshot(id: connector.id, state: .error, updatedAt: Date(), message: "GLM 仅允许 open.bigmodel.cn 官方用量端点")
        }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 12
            // Matches Z.ai's official glm-plan-usage plugin: this endpoint is
            // queried directly and does not send a model completion request.
            request.setValue(apiKey, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("zh-CN,zh;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard http.statusCode == 200 else {
                let retry = http.value(forHTTPHeaderField: "Retry-After").map { "；请在 \($0) 后重试" } ?? ""
                return APIConnectorSnapshot(id: connector.id, state: .unavailable, updatedAt: Date(), message: "GLM 用量接口返回 HTTP \(http.statusCode)\(retry)；未发送模型请求")
            }
            guard data.count <= 1_000_000 else {
                return APIConnectorSnapshot(id: connector.id, state: .unavailable, updatedAt: Date(), message: "GLM 返回数据超过 1 MB 安全上限")
            }
            let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            if !contentType.isEmpty, !contentType.contains("json"), data.first.map({ $0 != 0x7B && $0 != 0x5B }) == true {
                return APIConnectorSnapshot(id: connector.id, state: .unavailable, updatedAt: Date(), message: "GLM 上游返回非 JSON（\(String(contentType.prefix(64)))），可能被代理或网关替换")
            }
            return Self.decodeGLMCodingPlan(id: connector.id, data: data)
        } catch {
            return APIConnectorSnapshot(id: connector.id, state: .error, updatedAt: Date(), message: "GLM 用量请求失败：\(error.localizedDescription)")
        }
    }

    nonisolated static func decodeGLMCodingPlan(id: UUID, data: Data) -> APIConnectorSnapshot {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            let prefix = String(decoding: data.prefix(32), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let hint = prefix.hasPrefix("<") ? "；响应看起来是 HTML，可能被代理或网关替换" : ""
            return APIConnectorSnapshot(id: id, state: .unavailable, updatedAt: Date(), message: "GLM 返回数据格式无法识别\(hint)")
        }
        let root = object as? [String: Any] ?? [:]
        if let success = root["success"] as? Bool, !success {
            let reason = [root["msg"], root["message"], root["error"]].compactMap { $0 }.map { String(describing: $0) }.first ?? "上游业务错误"
            return APIConnectorSnapshot(id: id, state: .unavailable, updatedAt: Date(), message: "GLM：\(String(reason.prefix(160)))")
        }
        if let code = Self.integer(root["code"]), code != 0, code != 200 {
            let reason = [root["msg"], root["message"]].compactMap { $0 }.map { String(describing: $0) }.first ?? "业务状态码 \(code)"
            return APIConnectorSnapshot(id: id, state: .unavailable, updatedAt: Date(), message: "GLM：\(String(reason.prefix(160)))")
        }
        let limits = Self.findLimits(in: object)
        var totals: [String: Int] = [:]
        for item in limits {
            let type = Self.string(item, keys: ["type", "limit_type", "resource_type", "quotaType"]) ?? "UNKNOWN"
            totals[type, default: 0] += 1
        }
        var typeCounts: [String: Int] = [:]
        let windows = limits.compactMap { item -> APIUsageWindow? in
            let rawType = Self.string(item, keys: ["type", "limit_type", "resource_type", "quotaType"]) ?? "UNKNOWN"
            let type = String(rawType.prefix(64))
            let explicitUsed = Self.number(item, keys: ["percentage", "used_percentage", "usedPercent", "usagePercentage", "percent"])
            let explicitRemaining = Self.number(item, keys: ["remaining_percentage", "remainingPercent"])
            let used = Self.number(item, keys: ["usage", "used", "currentValue", "current_value", "consumed"])
            let limit = Self.number(item, keys: ["limit", "total", "maxValue", "max_value", "capacity"])
            let computed = (used != nil && limit != nil && limit! > 0) ? used! / limit! * 100 : nil
            guard let percentage = explicitUsed ?? explicitRemaining.map({ 100 - $0 }) ?? computed,
                  percentage.isFinite else { return nil }
            typeCounts[type, default: 0] += 1
            let itemName = ["name", "label", "display_name", "resource_name"]
                .compactMap { item[$0] as? String }
                .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)) }
                .first(where: { !$0.isEmpty })
            let fallback: String
            switch type {
            case "TOKENS_LIMIT": fallback = "短周期额度"
            case "TIME_LIMIT": fallback = "月度 / MCP"
            default: fallback = type
            }
            let number = (totals[rawType] ?? 0) > 1 ? typeCounts[type] : nil
            let reset = ["reset_at", "resetAt", "next_reset_time", "nextResetTime", "refreshTime", "refresh_time"]
                .compactMap { item[$0] }
                .first.map { String(String(describing: $0).prefix(80)) }
            return APIUsageWindow(
                id: "\(type)-\(typeCounts[type] ?? 1)", title: itemName ?? fallback,
                windowNumber: number, usedPercent: max(0, min(100, percentage)), resetAt: reset
            )
        }
        return APIConnectorSnapshot(
            id: id, state: windows.isEmpty ? .unavailable : .available, updatedAt: Date(),
            message: windows.isEmpty ? "GLM 返回成功，但未识别到额度字段" : "GLM Coding Plan 官方用量查询 · 未发送模型请求",
            usageWindows: windows
        )
    }

    private nonisolated static func findLimits(in value: Any, depth: Int = 0) -> [[String: Any]] {
        guard depth < 5 else { return [] }
        if let array = value as? [[String: Any]], !array.isEmpty,
           array.contains(where: { $0["percentage"] != nil || $0["usage"] != nil || $0["currentValue"] != nil || $0["remaining"] != nil }) {
            return array
        }
        if let dictionary = value as? [String: Any] {
            for key in ["limits", "quotas", "quotaLimits", "usageLimits", "items", "list"] {
                if let nested = dictionary[key] {
                    let found = findLimits(in: nested, depth: depth + 1)
                    if !found.isEmpty { return found }
                }
            }
            for key in ["data", "result", "payload"] {
                if let nested = dictionary[key] {
                    let found = findLimits(in: nested, depth: depth + 1)
                    if !found.isEmpty { return found }
                }
            }
        }
        return []
    }

    private nonisolated static func number(_ values: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = values[key] as? NSNumber { return value.doubleValue }
            if let value = values[key] as? String, let number = Double(value) { return number }
        }
        return nil
    }

    private nonisolated static func integer(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private nonisolated static func string(_ values: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = values[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
        }
        return nil
    }

    private func probeDeepSeekBalance(_ connector: APIConnectorConfiguration, apiKey: String) async -> APIConnectorSnapshot {
        guard !apiKey.isEmpty else { return APIConnectorSnapshot(id: connector.id, state: .unavailable, updatedAt: Date(), message: "请填写 DeepSeek API Key") }
        guard let url = URL(string: connector.endpoint), url.scheme == "https", url.host == "api.deepseek.com", url.path == "/user/balance" else {
            return APIConnectorSnapshot(id: connector.id, state: .error, updatedAt: Date(), message: "DeepSeek 仅允许 api.deepseek.com/user/balance 官方余额端点")
        }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"; request.timeoutInterval = 12
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard http.statusCode == 200 else { return APIConnectorSnapshot(id: connector.id, state: .unavailable, updatedAt: Date(), message: "DeepSeek 余额接口返回 HTTP \(http.statusCode)；未发送模型请求") }
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let available = root?["is_available"] as? Bool ?? false
            let infos = root?["balance_infos"] as? [[String: Any]] ?? []
            let entries = infos.compactMap { info -> String? in
                guard let total = info["total_balance"] else { return nil }
                let currency = (info["currency"] as? String) ?? ""
                return "\(currency) \(total)"
            }
            let grants = infos.compactMap { info -> String? in
                let granted = info["granted_balance"].map { String(describing: $0) }
                let toppedUp = info["topped_up_balance"].map { String(describing: $0) }
                guard granted != nil || toppedUp != nil else { return nil }
                return "赠送 \(granted ?? "--") · 充值 \(toppedUp ?? "--")"
            }
            let summary = entries.joined(separator: " · ")
            let message = available ? (grants.isEmpty ? "DeepSeek 官方账户余额查询 · 未发送模型请求" : "DeepSeek 官方账户余额查询 · \(grants.joined(separator: "；"))") : "DeepSeek 账户当前不可用"
            return APIConnectorSnapshot(id: connector.id, state: available && !summary.isEmpty ? .available : .unavailable, remainingTokens: summary.isEmpty ? nil : summary, updatedAt: Date(), message: message)
        } catch { return APIConnectorSnapshot(id: connector.id, state: .error, updatedAt: Date(), message: "DeepSeek 余额查询失败：\(error.localizedDescription)") }
    }
}
