import Foundation

struct RateLimitResetCredit: Sendable, Equatable, Identifiable {
    var id: String
    var status: String
    var grantedAt: Date?
    var expiresAt: Date?
    var title: String?
    var detail: String?
}

/// One independent Codex quota window returned by the official local
/// `codex app-server`. A plan can expose more than one window (for example a
/// short rolling window and a weekly window); they must not be flattened into
/// an ambiguous `#1 / #2` string.
struct CodexQuotaWindow: Sendable, Equatable, Identifiable {
    var id: String
    var title: String
    var usedPercent: Double
    var windowMinutes: Int?
    var resetsAt: Date?

    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
    var usedLabel: String { String(format: "%.0f%%", usedPercent) }
    var remainingLabel: String { String(format: "%.0f%%", remainingPercent) }
    var resetLabel: String { resetsAt?.formatted(date: .numeric, time: .shortened) ?? "--" }
}

struct CodexTokenUsageSummary: Sendable, Equatable {
    var lifetimeTokens: Int64?
    var peakDailyTokens: Int64?
    var longestRunningTurnSeconds: Int64?
    var currentStreakDays: Int?
    var longestStreakDays: Int?
}

struct CodexDailyUsageBucket: Sendable, Equatable, Identifiable {
    var id: String { startDate }
    var startDate: String
    var tokens: Int64
}

struct QuotaSnapshot: Sendable, Equatable {
    enum State: String, Sendable {
        case loading, available, unavailable, error
    }

    var state: State
    var remainingPercent: Double?
    var resetsAt: Date?
    var windowMinutes: Int?
    var planType: String?
    var resetCreditCount: Int?
    var resetCredits: [RateLimitResetCredit]
    var message: String
    var updatedAt: Date?
    var windows: [CodexQuotaWindow] = []
    var tokenUsageSummary: CodexTokenUsageSummary? = nil
    var dailyUsageBuckets: [CodexDailyUsageBucket] = []
    var rateLimitReachedType: String? = nil

    static let loading = QuotaSnapshot(
        state: .loading,
        remainingPercent: nil,
        resetsAt: nil,
        windowMinutes: nil,
        planType: nil,
        resetCreditCount: nil,
        resetCredits: [],
        message: "正在读取 Codex 额度",
        updatedAt: nil
    )

    var remainingLabel: String {
        guard let remainingPercent else {
            return state == .loading ? "…" : "--"
        }
        return String(format: "%.0f%%", remainingPercent)
    }

    /// The most constrained official window drives compact risk indicators.
    /// Expanded UI still shows every window independently.
    var riskWindow: CodexQuotaWindow? {
        windows.min { lhs, rhs in lhs.remainingPercent < rhs.remainingPercent }
    }

    var riskRemainingPercent: Double? { riskWindow?.remainingPercent ?? remainingPercent }

    var riskRemainingLabel: String {
        guard let value = riskRemainingPercent else { return state == .loading ? "…" : "--" }
        return String(format: "%.0f%%", value)
    }

    var windowLabel: String? {
        guard let windowMinutes else { return nil }
        if windowMinutes >= 1_440, windowMinutes % 1_440 == 0 {
            return "\(windowMinutes / 1_440) 天窗口"
        }
        if windowMinutes >= 60, windowMinutes % 60 == 0 {
            return "\(windowMinutes / 60) 小时窗口"
        }
        return "\(windowMinutes) 分钟窗口"
    }

    var resetCreditLabel: String {
        guard let resetCreditCount else { return "重置券 --" }
        return "重置券 \(resetCreditCount) 张"
    }

    var resetDateTimeLabel: String {
        guard let resetsAt else { return "--" }
        return resetsAt.formatted(date: .numeric, time: .shortened)
    }
}
