import Foundation

struct PulseDockConfigurationBundle: Codable, Sendable {
    var schemaVersion = 1
    var exportedAt = Date()
    var focusMinutes: Int
    var breakMinutes: Int
    var longBreakMinutes: Int
    var sessionsBeforeLongBreak: Int
    var workStartMinutes: Int
    var workEndMinutes: Int
    var lunchStartMinutes: Int
    var lunchEndMinutes: Int
    var workWeekdays: [Int]
    var idleThresholdSeconds: Int
    var remoteDevices: [RemoteDeviceConfiguration]
    var apiConnectors: [APIConnectorConfiguration]
    var clashControllerEnabled: Bool
    var clashControllerURL: String
    var alertCooldownMinutes: Int
    var note = "安全信息未导出：SSH 私钥/密码、Clash Secret、飞书 Webhook/签名密钥、API Key。"
}
