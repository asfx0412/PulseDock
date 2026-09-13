import Foundation

/// Pure scheduling policy for SSH probes. The store owns execution; this type
/// only makes the admission and ordering decisions testable and deterministic.
struct RemoteProbeScheduler {
    struct Candidate: Sendable {
        var id: UUID
        var enabled: Bool
        var intervalSeconds: Int
        var pinned: Bool
        var health: RemoteHealth
        var lastProbeAt: Date?
        var failureStreak: Int
        var observing: Bool
        var manual: Bool
    }

    static func select(_ candidates: [Candidate], activeIDs: Set<UUID>, now: Date, limit: Int = 3) -> [UUID] {
        candidates.filter { candidate in
            guard candidate.enabled, !activeIDs.contains(candidate.id) else { return false }
            return candidate.manual || candidate.observing || Self.nextDueAt(for: candidate) <= now
        }
        .sorted { lhs, rhs in
            let lhsPriority = priority(of: lhs)
            let rhsPriority = priority(of: rhs)
            if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
            if Self.nextDueAt(for: lhs) != Self.nextDueAt(for: rhs) { return Self.nextDueAt(for: lhs) < Self.nextDueAt(for: rhs) }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        .prefix(max(0, limit)).map(\.id)
    }

    static func nextDueAt(for candidate: Candidate) -> Date {
        guard let lastProbeAt = candidate.lastProbeAt else { return .distantPast }
        if candidate.observing { return lastProbeAt.addingTimeInterval(5) }
        let base = max(15, candidate.intervalSeconds)
        let multiplier = 1 << min(3, max(0, candidate.failureStreak))
        // A stable 0–9s offset avoids a herd of devices becoming due together.
        let jitter = Double(stableJitter(candidate.id))
        return lastProbeAt.addingTimeInterval(Double(base * multiplier) + jitter)
    }

    private static func priority(of candidate: Candidate) -> Int {
        if candidate.manual { return 5 }
        if candidate.observing { return 4 }
        if candidate.health == .offline || candidate.health == .degraded { return 3 }
        if candidate.pinned { return 2 }
        return 1
    }

    private static func stableJitter(_ id: UUID) -> Int {
        let value = id.uuid
        return (Int(value.0) + Int(value.5) + Int(value.10) + Int(value.15)) % 10
    }
}
