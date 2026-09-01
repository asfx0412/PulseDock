import Foundation

/// A data value and the attempt that refreshed it are intentionally separate.
/// A transient failed request must never turn a previously valid value into an
/// ambiguous `--` value just because the failed request happened "just now".
enum RefreshStatus: Sendable, Equatable {
    case fresh
    case refreshing
    case stale
    case initialFailure
    case waitingUnlock
}

struct RefreshMetadata: Sendable, Equatable {
    var status: RefreshStatus = .initialFailure
    var lastSuccessAt: Date? = nil
    var lastFailureAt: Date? = nil
    var failureMessage: String? = nil
    var failureCount = 0
    var nextRetryAt: Date? = nil

    static func fresh(at date: Date) -> Self {
        Self(status: .fresh, lastSuccessAt: date)
    }

    static var waitingUnlock: Self { Self(status: .waitingUnlock) }
}

/// Bounded retry schedule for read-only sources.  The same policy is used by
/// Codex, weather, and API connectors so one source does not silently wait for
/// its normal long polling interval after a temporary failure.
enum RetryPolicy {
    static let delays: [TimeInterval] = [30, 120, 600]

    static func delay(forFailureCount count: Int) -> TimeInterval {
        delays[min(max(count - 1, 0), delays.count - 1)]
    }
}
