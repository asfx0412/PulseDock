import Foundation
import SwiftUI

enum APIConnectorKind: String, Codable, CaseIterable, Sendable {
    /// The one built-in Codex source is a presentation adapter over the
    /// existing official local app-server reader. It is not an API-key
    /// connector and must never trigger a second read of that service.
    case codexLocalQuota
    case customRateLimit
    case glmCodingPlan
    case deepSeekBalance
    case cursorLocalUsage
    case githubCopilotUsage

    var label: String {
        switch self {
        case .codexLocalQuota: "Codex 本机官方额度"
        case .customRateLimit: "通用 Rate Limit"
        case .glmCodingPlan: "GLM Coding Plan 用量"
        case .deepSeekBalance: "DeepSeek 账户余额"
        case .cursorLocalUsage: "Cursor 本地额度（实验性）"
        case .githubCopilotUsage: "GitHub Copilot 个人用量"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .codexLocalQuota, .cursorLocalUsage: false
        case .customRateLimit, .glmCodingPlan, .deepSeekBalance, .githubCopilotUsage: true
        }
    }

    var isBuiltInSingleton: Bool { self == .codexLocalQuota }

    var defaultEndpoint: String {
        switch self {
        case .codexLocalQuota: "Codex 官方本机 app-server（只读）"
        case .customRateLimit: ""
        case .glmCodingPlan: "https://open.bigmodel.cn/api/monitor/usage/quota/limit"
        case .deepSeekBalance: "https://api.deepseek.com/user/balance"
        case .cursorLocalUsage: "本机 Cursor 登录会话（只读）"
        case .githubCopilotUsage: "https://api.github.com/users/{username}/settings/billing"
        }
    }
}

struct APIConnectorConfiguration: Identifiable, Codable, Sendable, Equatable {
    /// Stable across launches/configuration imports so the built-in source
    /// cannot multiply and never has a Keychain credential attached to it.
    static let codexLocalID = UUID(uuidString: "9E5A9B55-90D7-4C4B-BD4B-4C92D971D908")!

    var id = UUID()
    var name: String
    var kind: APIConnectorKind = .customRateLimit
    var endpoint: String
    /// A non-secret GitHub login for the fixed Copilot personal endpoints.
    /// It is intentionally not an arbitrary URL and supports multiple
    /// accounts without relying on browser sessions or local Copilot tokens.
    var accountID: String? = nil
    var enabled = true
    /// Multiple sources may be visible in the expanded Workbench.
    var showOnDashboard = false
    /// Exactly zero or one source may be pinned into the compact panel.
    var pinned = false
    var sortOrder = 0

    enum CodingKeys: String, CodingKey { case id, name, kind, endpoint, accountID, enabled, showOnDashboard, pinned, sortOrder }

    init(id: UUID = UUID(), name: String, kind: APIConnectorKind = .customRateLimit, endpoint: String, accountID: String? = nil, enabled: Bool = true, showOnDashboard: Bool = false, pinned: Bool = false, sortOrder: Int = 0) {
        self.id = id; self.name = name; self.kind = kind; self.endpoint = endpoint; self.accountID = accountID; self.enabled = enabled; self.showOnDashboard = showOnDashboard; self.pinned = pinned; self.sortOrder = sortOrder
    }

    static var codexLocalDefault: APIConnectorConfiguration {
        APIConnectorConfiguration(
            id: codexLocalID,
            name: "Codex",
            kind: .codexLocalQuota,
            endpoint: APIConnectorKind.codexLocalQuota.defaultEndpoint,
            enabled: true,
            showOnDashboard: true,
            pinned: true,
            sortOrder: 0
        )
    }

    /// Sanitizes imported/persisted connector lists while reserving the
    /// built-in Codex id. The result contains exactly one Codex source and no
    /// duplicate ids, even if an older build or an imported config assigned
    /// the reserved id to an ordinary connector.
    static func sanitizeForStorage(_ values: [APIConnectorConfiguration]) -> [APIConnectorConfiguration] {
        var seen: Set<UUID> = [codexLocalID]
        var codex: APIConnectorConfiguration?
        var sanitized: [APIConnectorConfiguration] = []
        for (offset, raw) in values.enumerated() {
            var value = raw
            if value.kind == .codexLocalQuota {
                if codex == nil {
                    value.id = codexLocalID
                    value.name = "Codex"
                    value.endpoint = APIConnectorKind.codexLocalQuota.defaultEndpoint
                    codex = value
                }
                continue
            }
            if !seen.insert(value.id).inserted {
                repeat { value.id = UUID() } while !seen.insert(value.id).inserted
            }
            if value.sortOrder < 0 { value.sortOrder = offset }
            value.name = String(value.name.prefix(120))
            value.endpoint = String(value.endpoint.prefix(2_048))
            value.accountID = value.accountID
                .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(39)) }
                .flatMap { $0.isEmpty ? nil : $0 }
            if value.kind == .githubCopilotUsage {
                value.endpoint = APIConnectorKind.githubCopilotUsage.defaultEndpoint
            }
            sanitized.append(value)
        }
        var builtIn = codex ?? codexLocalDefault
        builtIn.id = codexLocalID
        builtIn.kind = .codexLocalQuota
        builtIn.name = "Codex"
        builtIn.endpoint = APIConnectorKind.codexLocalQuota.defaultEndpoint
        if codex == nil { builtIn.sortOrder = 0 }
        sanitized.append(builtIn)
        // 6.13.0 used `pinned` for both the Workbench and compact panel. Keep
        // those sources visible on migration, but retain only the first user
        // ordered source as the one compact-panel pin.
        let compactPin = sanitized.enumerated()
            .filter { $0.element.pinned }
            .min { lhs, rhs in
                if lhs.element.sortOrder != rhs.element.sortOrder { return lhs.element.sortOrder < rhs.element.sortOrder }
                return lhs.offset < rhs.offset
            }?.element.id
        for index in sanitized.indices {
            if sanitized[index].pinned { sanitized[index].showOnDashboard = true }
            sanitized[index].pinned = sanitized[index].id == compactPin
        }
        return sanitized
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decodeIfPresent(APIConnectorKind.self, forKey: .kind) ?? .customRateLimit
        endpoint = try c.decode(String.self, forKey: .endpoint)
        accountID = try c.decodeIfPresent(String.self, forKey: .accountID)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        showOnDashboard = try c.decodeIfPresent(Bool.self, forKey: .showOnDashboard) ?? pinned
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

/// A provider-native usage measurement.  Unlike `APIUsageWindow`, this has no
/// implied total or remaining percentage.  It is used for GitHub Copilot's
/// official billing data, which can report amounts used without publishing a
/// user's plan allowance.
struct APIUsageMetric: Identifiable, Sendable, Equatable {
    var id: String
    var title: String
    var usedValue: String
    var detail: String
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
    var usageMetrics: [APIUsageMetric] = []
    /// Display-only source value where the provider has no reliable remaining
    /// percentage.  This keeps dashboard/pinned cards semantically honest.
    var primaryValue: String? = nil
    var refresh = RefreshMetadata()
    /// The provider's own aggregate remaining percentage, when it exposes
    /// one.  This is a presentation hint only; it is never combined with
    /// independent windows from other providers.
    var primaryRemainingPercent: Double? = nil

    /// Values that may safely remain visible while a refresh or credential
    /// transition is in progress. State/message are deliberately excluded:
    /// callers must always label retained data as stale or waiting.
    var hasDisplayPayload: Bool {
        !usageWindows.isEmpty || !usageMetrics.isEmpty || primaryValue != nil || remainingRequests != nil || remainingTokens != nil
    }

    @discardableResult
    mutating func copyDisplayPayload(from previous: APIConnectorSnapshot) -> Bool {
        guard previous.hasDisplayPayload else { return false }
        remainingRequests = previous.remainingRequests
        remainingTokens = previous.remainingTokens
        resetAt = previous.resetAt
        updatedAt = previous.updatedAt
        usageWindows = previous.usageWindows
        usageMetrics = previous.usageMetrics
        primaryValue = previous.primaryValue
        primaryRemainingPercent = previous.primaryRemainingPercent
        return true
    }

    var summary: String {
        primaryValue ?? (usageWindows.isEmpty ? (remainingTokens ?? remainingRequests ?? "--") : "\(usageWindows.count) 个额度周期")
    }
    var color: Color {
        switch state {
        case .available: .green
        case .loading, .waitingUnlock: .secondary
        case .unavailable, .error: .orange
        }
    }
}
