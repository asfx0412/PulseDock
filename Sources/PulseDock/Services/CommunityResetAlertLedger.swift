import Foundation

/// Local-only delivery state. It contains public record IDs and timestamps,
/// never account data, source text, webhook URLs, or notification bodies.
@MainActor
final class CommunityResetAlertLedger {
    enum Stage: String, Codable, CaseIterable { case firstSeen, changed, before60Minutes, before30Minutes, completed }
    enum Channel: String, Codable { case local, feishu }

    private struct Entry: Codable {
        var firstSeenAt: Date
        var lastSeenAt: Date
        var announcedAt: Date?
        var effectiveAt: Date?
        var confidence: Double?
        var scopeLabel: String?
        var scopePlans: [String]
        var wasEligibleSchedule: Bool
        var deliveries: [String: Date]
        /// A durable hand-off marker for an in-flight external delivery.
        /// If the process dies after HTTP submission, favour not duplicating a
        /// user-visible Feishu message over uncertain automatic retry.
        var claims: [String: Date]
        var retryNotBefore: [String: Date]
        var retryCounts: [String: Int]

        private enum CodingKeys: String, CodingKey { case firstSeenAt, lastSeenAt, announcedAt, effectiveAt, confidence, scopeLabel, scopePlans, wasEligibleSchedule, deliveries, claims, retryNotBefore, retryCounts }

        init(firstSeenAt: Date, lastSeenAt: Date, announcedAt: Date?, effectiveAt: Date?, confidence: Double?, scopeLabel: String?, scopePlans: [String], wasEligibleSchedule: Bool, deliveries: [String: Date], claims: [String: Date], retryNotBefore: [String: Date] = [:], retryCounts: [String: Int] = [:]) {
            self.firstSeenAt = firstSeenAt; self.lastSeenAt = lastSeenAt; self.announcedAt = announcedAt; self.effectiveAt = effectiveAt
            self.confidence = confidence; self.scopeLabel = scopeLabel; self.wasEligibleSchedule = wasEligibleSchedule
            self.scopePlans = scopePlans; self.deliveries = deliveries; self.claims = claims; self.retryNotBefore = retryNotBefore; self.retryCounts = retryCounts
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            firstSeenAt = try values.decode(Date.self, forKey: .firstSeenAt)
            lastSeenAt = try values.decode(Date.self, forKey: .lastSeenAt)
            announcedAt = try values.decodeIfPresent(Date.self, forKey: .announcedAt)
            effectiveAt = try values.decodeIfPresent(Date.self, forKey: .effectiveAt)
            confidence = try values.decodeIfPresent(Double.self, forKey: .confidence)
            scopeLabel = try values.decodeIfPresent(String.self, forKey: .scopeLabel)
            scopePlans = try values.decodeIfPresent([String].self, forKey: .scopePlans) ?? []
            wasEligibleSchedule = try values.decode(Bool.self, forKey: .wasEligibleSchedule)
            deliveries = try values.decodeIfPresent([String: Date].self, forKey: .deliveries) ?? [:]
            claims = try values.decodeIfPresent([String: Date].self, forKey: .claims) ?? [:]
            retryNotBefore = try values.decodeIfPresent([String: Date].self, forKey: .retryNotBefore) ?? [:]
            retryCounts = try values.decodeIfPresent([String: Int].self, forKey: .retryCounts) ?? [:]
        }
    }
    private struct Payload: Codable { var version = 1; var entries: [String: Entry] }

    private let key = "PulseDock.communityResetAlertLedger.v1"
    private let defaults: UserDefaults
    private var entries: [String: Entry]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Payload.self, from: $0).entries } ?? [:]
    }

    func observe(_ record: CodexCommunityResetRecord, now: Date, eligibleSchedule: Bool) -> Date {
        var entry = entries[record.id] ?? Entry(
            firstSeenAt: now, lastSeenAt: now, announcedAt: record.announcedAt,
            effectiveAt: record.effectiveAt, confidence: record.confidence,
            scopeLabel: record.scopeLabel, scopePlans: record.scope?.plans ?? [], wasEligibleSchedule: eligibleSchedule, deliveries: [:], claims: [:]
        )
        entry.lastSeenAt = now
        entry.announcedAt = record.announcedAt ?? entry.announcedAt
        entry.effectiveAt = record.effectiveAt ?? entry.effectiveAt
        entry.confidence = record.confidence ?? entry.confidence
        entry.scopeLabel = record.scopeLabel ?? entry.scopeLabel
        if let plans = record.scope?.plans { entry.scopePlans = plans }
        entry.wasEligibleSchedule = entry.wasEligibleSchedule || eligibleSchedule
        entries[record.id] = entry
        save()
        return entry.firstSeenAt
    }

    func firstSeenAt(for recordID: String) -> Date? { entries[recordID]?.firstSeenAt }

    func hasObserved(_ recordID: String) -> Bool { entries[recordID] != nil }

    func hasMeaningfulChange(_ record: CodexCommunityResetRecord, minimumConfidence: Double) -> Bool {
        guard let entry = entries[record.id] else { return false }
        let timeChanged = entry.effectiveAt != nil && record.effectiveAt != nil && entry.effectiveAt != record.effectiveAt
        let crossedConfidence = (entry.confidence ?? 0) < minimumConfidence && (record.confidence ?? 0) >= minimumConfidence
        let oldPlans = Set(entry.scopePlans.filter { $0 != "unknown" })
        let newPlans = Set((record.scope?.plans ?? []).filter { $0 != "unknown" })
        let scopeExpanded = !oldPlans.isEmpty && (newPlans.contains("all") || (oldPlans.isSubset(of: newPlans) && newPlans.count > oldPlans.count))
        return timeChanged || crossedConfidence || scopeExpanded
    }

    func hasObservedEligibleSchedule(_ recordID: String) -> Bool { entries[recordID]?.wasEligibleSchedule == true }

    func wasDelivered(recordID: String, stage: Stage, channel: Channel) -> Bool {
        entries[recordID]?.deliveries[deliveryKey(stage, channel)] != nil
    }

    func markDelivered(recordID: String, stage: Stage, channel: Channel, at date: Date = Date()) {
        guard var entry = entries[recordID] else { return }
        let key = deliveryKey(stage, channel)
        entry.deliveries[key] = date
        entry.claims.removeValue(forKey: key)
        entry.retryNotBefore.removeValue(forKey: key); entry.retryCounts.removeValue(forKey: key)
        entries[recordID] = entry
        save()
    }

    /// Atomically reserve an external delivery before it is sent. Claims do
    /// not expire automatically: the remote outcome may be unknowable after a
    /// timeout, and repeating a quota-reset alert is worse than requiring the
    /// user to press the explicit reset control.
    func claim(recordID: String, stage: Stage, channel: Channel, at date: Date = Date()) -> Bool {
        guard var entry = entries[recordID] else { return false }
        let key = deliveryKey(stage, channel)
        guard entry.deliveries[key] == nil, entry.claims[key] == nil, (entry.retryNotBefore[key] ?? .distantPast) <= date else { return false }
        entry.claims[key] = date
        entries[recordID] = entry
        save()
        return true
    }

    func hasClaim(recordID: String, stage: Stage, channel: Channel) -> Bool {
        entries[recordID]?.claims[deliveryKey(stage, channel)] != nil
    }

    func releaseForRetry(recordID: String, stage: Stage, channel: Channel, at date: Date = Date()) {
        guard var entry = entries[recordID] else { return }
        let key = deliveryKey(stage, channel)
        entry.claims.removeValue(forKey: key)
        let count = min(3, entry.retryCounts[key, default: 0] + 1)
        entry.retryCounts[key] = count
        entry.retryNotBefore[key] = date.addingTimeInterval([300, 900, 1_800][count - 1])
        entries[recordID] = entry; save()
    }

    func reset() { entries.removeAll(); defaults.removeObject(forKey: key) }

    private func deliveryKey(_ stage: Stage, _ channel: Channel) -> String { "\(stage.rawValue).\(channel.rawValue)" }

    private func save() {
        guard let data = try? JSONEncoder().encode(Payload(entries: entries)) else { return }
        defaults.set(data, forKey: key)
    }
}
