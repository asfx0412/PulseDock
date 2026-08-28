import Foundation
import SwiftUI

enum APIConnectorKind: String, Codable, CaseIterable, Sendable {
    case customRateLimit
    case glmCodingPlan
    case deepSeekBalance
    case cursorLocalUsage

    var label: String {
        switch self {
        case .customRateLimit: "通用 Rate Limit"
        case .glmCodingPlan: "GLM Coding Plan 用量"
        case .deepSeekBalance: "DeepSeek 账户余额"
        case .cursorLocalUsage: "Cursor 本地额度（实验性）"
        }
    }

    var requiresAPIKey: Bool { self != .cursorLocalUsage }
    var defaultEndpoint: String {
        switch self {
        case .customRateLimit: ""
        case .glmCodingPlan: "https://open.bigmodel.cn/api/monitor/usage/quota/limit"
        case .deepSeekBalance: "https://api.deepseek.com/user/balance"
        case .cursorLocalUsage: "本机 Cursor 登录会话（只读）"
        }
    }
}

struct APIConnectorConfiguration: Identifiable, Codable, Sendable, Equatable {
    var id = UUID()
    var name: String
    var kind: APIConnectorKind = .customRateLimit
    var endpoint: String
    var enabled = true
    var pinned = false
    var sortOrder = 0

    enum CodingKeys: String, CodingKey { case id, name, kind, endpoint, enabled, pinned, sortOrder }

    init(id: UUID = UUID(), name: String, kind: APIConnectorKind = .customRateLimit, endpoint: String, enabled: Bool = true, pinned: Bool = false, sortOrder: Int = 0) {
        self.id = id; self.name = name; self.kind = kind; self.endpoint = endpoint; self.enabled = enabled; self.pinned = pinned; self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decodeIfPresent(APIConnectorKind.self, forKey: .kind) ?? .customRateLimit
        endpoint = try c.decode(String.self, forKey: .endpoint)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }
}

struct APIUsageWindow: Identifiable, Sendable, Equatable {
    var id: String
    var title: String
    var windowNumber: Int?
    var usedPercent: Double
    var resetAt: String?

    var usedLabel: String { String(format: "%.0f%%", max(0, min(100, usedPercent))) }
    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
}

struct APIConnectorSnapshot: Identifiable, Sendable, Equatable {
    var id: UUID
    var state: QuotaSnapshot.State = .loading
    var remainingRequests: String?
    var remainingTokens: String?
    var resetAt: String?
    var updatedAt: Date?
    var message = "等待检测"
    var usageWindows: [APIUsageWindow] = []

    var summary: String { usageWindows.isEmpty ? (remainingTokens ?? remainingRequests ?? "--") : "\(usageWindows.count) 个额度周期" }
    var color: Color { state == .available ? .green : state == .loading ? .secondary : .orange }
}
