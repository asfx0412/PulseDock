import Foundation
import SwiftUI

/// A display-only adapter for quota sources.  It deliberately does not try to
/// add or average values from different providers/units: a Codex percentage,
/// an API rate limit, and an account balance are independent promises.
struct QuotaPresentation: Identifiable, Sendable, Equatable {
    enum Freshness: Sendable, Equatable {
        case loading
        case fresh
        case stale
        case waitingUnlock
        case unavailable
    }

    let id: UUID
    let title: String
    let sourceLabel: String
    let value: String
    let detail: String
    let remainingPercent: Double?
    let freshness: Freshness
    let isRefreshing: Bool
    let failureMessage: String?
    let failureCount: Int
    let nextRetryAt: Date?
    let lastSuccessAt: Date?

    var hasRecoverableFailure: Bool { freshness == .stale || freshness == .unavailable }

    var color: Color {
        switch freshness {
        case .fresh: return remainingPercent.map { $0 <= 15 ? .orange : .green } ?? .secondary
        case .loading: return .secondary
        case .stale: return .orange
        case .waitingUnlock: return .secondary
        case .unavailable: return .orange
        }
    }

    static func codex(id: UUID, snapshot: QuotaSnapshot, isRefreshing: Bool, now: Date) -> Self {
        let freshness = Self.freshness(for: snapshot.refresh, fallback: snapshot.state)
        return Self(
            id: id,
            title: "Codex",
            sourceLabel: "Codex 官方本机额度",
            value: snapshot.riskRemainingLabel,
            detail: "最低剩余额度周期 · \(DataFreshness.label(snapshot.updatedAt, now: now))",
            remainingPercent: snapshot.riskRemainingPercent,
            freshness: freshness,
            isRefreshing: isRefreshing,
            failureMessage: snapshot.refresh.failureMessage,
            failureCount: snapshot.refresh.failureCount,
            nextRetryAt: snapshot.refresh.nextRetryAt,
            lastSuccessAt: snapshot.refresh.lastSuccessAt
        )
    }

    static func connector(_ connector: APIConnectorConfiguration, snapshot: APIConnectorSnapshot, now: Date, isRefreshing: Bool = false) -> Self {
        let retained = snapshot.refresh.status == .stale || snapshot.message.contains("显示上次成功快照")
        let freshness = Self.freshness(for: snapshot.refresh, fallback: snapshot.state)
        let lowestRemaining = snapshot.usageWindows.map(\.remainingPercent).min()
        let summaryRemaining = snapshot.primaryRemainingPercent ?? lowestRemaining
        // Copilot and similar providers can publish an amount used without a
        // plan total.  Never turn that into a made-up remaining percentage.
        let value = snapshot.primaryValue ?? summaryRemaining.map { String(format: "%.0f%%", $0) } ?? snapshot.summary
        let detail: String
        if freshness == .waitingUnlock {
            detail = retained
                ? "等待解锁凭据保险库 · 上次成功 \(DataFreshness.label(snapshot.updatedAt, now: now))"
                : "等待解锁凭据保险库"
        } else if let summaryRemaining {
            let label = snapshot.primaryRemainingPercent == nil ? "最低剩余" : "综合剩余"
            detail = "\(label) \(Int(summaryRemaining.rounded()))% · \(DataFreshness.label(snapshot.updatedAt, now: now))"
        } else if !snapshot.usageMetrics.isEmpty {
            detail = "官方已用量 · \(DataFreshness.label(snapshot.updatedAt, now: now))"
        } else {
            detail = "\(snapshot.summary) · \(DataFreshness.label(snapshot.updatedAt, now: now))"
        }
        return Self(
            id: connector.id,
            title: connector.name,
            sourceLabel: connector.kind.label,
            value: value,
            detail: detail,
            remainingPercent: summaryRemaining,
            freshness: freshness,
            isRefreshing: isRefreshing,
            failureMessage: snapshot.refresh.failureMessage,
            failureCount: snapshot.refresh.failureCount,
            nextRetryAt: snapshot.refresh.nextRetryAt,
            lastSuccessAt: snapshot.refresh.lastSuccessAt
        )
    }

    private static func freshness(for refresh: RefreshMetadata, fallback state: QuotaSnapshot.State) -> Freshness {
        // Compatibility for persisted/test snapshots created before refresh
        // metadata existed.  A successful payload is still fresh unless it
        // explicitly records a failure.
        if refresh.status == .initialFailure, refresh.failureCount == 0, refresh.failureMessage == nil {
            switch state {
            case .available: return .fresh
            case .loading: return .loading
            case .waitingUnlock: return .waitingUnlock
            case .unavailable, .error: break
            }
        }
        switch refresh.status {
        case .fresh: return .fresh
        case .refreshing: return .loading
        case .stale: return .stale
        case .initialFailure: return .unavailable
        case .waitingUnlock: return .waitingUnlock
        }
    }
}
