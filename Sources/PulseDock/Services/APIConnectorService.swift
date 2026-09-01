import Foundation

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
        }
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
