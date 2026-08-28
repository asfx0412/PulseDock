import Foundation

/// Experimental personal Cursor usage source. The access token is read only
/// for the request, kept in memory, and never written to PulseDock storage.
actor CursorUsageService {
    private var databasePath: String { NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb" }

    func readCurrentPeriodUsage(id: UUID) async -> APIConnectorSnapshot {
        guard FileManager.default.fileExists(atPath: databasePath) else {
            return APIConnectorSnapshot(id: id, state: .unavailable, updatedAt: Date(), message: "未发现 Cursor 登录数据库；请安装并登录 Cursor")
        }
        guard let token = readAccessToken(), !token.isEmpty else {
            return APIConnectorSnapshot(id: id, state: .unavailable, updatedAt: Date(), message: "Cursor 未登录或本机会话不可读")
        }
        return await requestUsage(id: id, token: token)
    }

    private func readAccessToken() -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", databasePath, "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1;"]
        process.standardOutput = output
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let value = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        // Cursor versions may store either the raw string or a JSON-encoded value.
        if let data = value.data(using: .utf8), let decoded = try? JSONDecoder().decode(String.self, from: data) { return decoded }
        return value
    }

    private func requestUsage(id: UUID, token: String) async -> APIConnectorSnapshot {
        guard let url = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage") else {
            return APIConnectorSnapshot(id: id, state: .error, updatedAt: Date(), message: "Cursor 用量地址无效")
        }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = Data("{}".utf8)
            request.timeoutInterval = 15
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard http.statusCode == 200 else {
                let message = http.statusCode == 401 ? "Cursor 会话已过期；请打开 Cursor 重新登录" : "Cursor 用量请求返回 HTTP \(http.statusCode)"
                return APIConnectorSnapshot(id: id, state: .unavailable, updatedAt: Date(), message: message)
            }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let usage = root["planUsage"] as? [String: Any] else {
                return APIConnectorSnapshot(id: id, state: .unavailable, updatedAt: Date(), message: "Cursor 返回了用量响应，但当前套餐未提供个人额度字段")
            }
            let percent = (usage["totalPercentUsed"] as? NSNumber)?.doubleValue
            let remaining = (usage["remaining"] as? NSNumber)?.doubleValue
            let limit = (usage["limit"] as? NSNumber)?.doubleValue
            let cycleEnd = Self.dateLabel(root["billingCycleEnd"])
            let amount: String?
            if let remaining, let limit { amount = String(format: "$%.2f / $%.2f", remaining / 100, limit / 100) } else { amount = nil }
            let auto = (usage["autoPercentUsed"] as? NSNumber)?.doubleValue
            let api = (usage["apiPercentUsed"] as? NSNumber)?.doubleValue
            let detail = [percent.map { String(format: "综合已用 %.0f%%", $0) }, auto.map { String(format: "Auto %.0f%%", $0) }, api.map { String(format: "指定模型 %.0f%%", $0) }].compactMap { $0 }.joined(separator: " · ")
            return APIConnectorSnapshot(id: id, state: .available, remainingRequests: amount, remainingTokens: detail.isEmpty ? nil : detail, resetAt: cycleEnd, updatedAt: Date(), message: "Cursor 本地会话 · 非官方实验性接口")
        } catch {
            return APIConnectorSnapshot(id: id, state: .error, updatedAt: Date(), message: "Cursor 用量请求失败：\(error.localizedDescription)")
        }
    }

    private static func dateLabel(_ raw: Any?) -> String? {
        let milliseconds: Double?
        if let value = raw as? String { milliseconds = Double(value) }
        else if let value = raw as? NSNumber { milliseconds = value.doubleValue }
        else { milliseconds = nil }
        guard let milliseconds else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1_000).formatted(date: .abbreviated, time: .shortened)
    }
}
