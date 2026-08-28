import CryptoKit
import Foundation

struct AlertDeliveryResult: Sendable {
    var success: Bool
    var evidence: String
}

actor FeishuAlertService {
    func send(webhook: String, signingSecret: String, title: String, body: String) async -> AlertDeliveryResult {
        guard let url = URL(string: webhook), url.scheme == "https", url.host == "open.feishu.cn", url.path.contains("/open-apis/bot/") else {
            return AlertDeliveryResult(success: false, evidence: "Webhook 必须是飞书 open.feishu.cn 的机器人地址")
        }
        var payload: [String: Any] = ["msg_type": "text", "content": ["text": "PulseDock · \(title)\n\(body)"]]
        if !signingSecret.isEmpty {
            let timestamp = String(Int(Date().timeIntervalSince1970))
            let key = SymmetricKey(data: Data("\(timestamp)\n\(signingSecret)".utf8))
            let signature = HMAC<SHA256>.authenticationCode(for: Data(), using: key)
            payload["timestamp"] = timestamp
            payload["sign"] = Data(signature).base64EncodedString()
        }
        do {
            var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return AlertDeliveryResult(success: false, evidence: "飞书返回 HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)") }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let code = (json?["code"] as? NSNumber)?.intValue ?? 0
            return AlertDeliveryResult(success: code == 0, evidence: code == 0 ? "飞书消息已发送" : "飞书返回错误码 \(code)")
        } catch { return AlertDeliveryResult(success: false, evidence: error.localizedDescription) }
    }
}
