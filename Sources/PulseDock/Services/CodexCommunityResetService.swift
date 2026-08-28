import Foundation

struct CodexCommunityResetSnapshot: Sendable, Equatable {
    enum State: Sendable { case loading, available, unavailable }

    var state: State
    var resetToday: Bool
    var confidence: Double?
    var lastResetAt: Date?
    var nextScheduledAt: Date?
    var sourceURL: URL?
    var checkedAt: Date?
    var sourceGeneratedAt: Date?
    var isStale: Bool
    var message: String

    static let loading = CodexCommunityResetSnapshot(
        state: .loading, resetToday: false, confidence: nil, lastResetAt: nil,
        nextScheduledAt: nil, sourceURL: nil, checkedAt: nil, sourceGeneratedAt: nil, isStale: false,
        message: "正在读取社区重置信号"
    )

    var verdictLabel: String {
        if state != .available { return "社区信号 --" }
        return resetToday ? "今日已全局重置" : (nextScheduledAt == nil ? "暂无重置计划" : "已有重置计划")
    }

    var confidenceLabel: String? {
        guard (resetToday || nextScheduledAt != nil), let confidence else { return nil }
        return "当前信号确认度 \(Int((confidence * 100).rounded()))%"
    }

    var historicalConfidenceLabel: String? {
        guard !resetToday, nextScheduledAt == nil, let confidence, lastResetAt != nil else { return nil }
        return "最近历史事件确认度 \(Int((confidence * 100).rounded()))%"
    }
}

actor CodexCommunityResetService {
    private let endpoint = URL(string: "https://www.codexrunway.com/api/status.json")!
    private let cacheKey = "PulseDock.codexCommunityResetCache"

    func read() async -> CodexCommunityResetSnapshot {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadRevalidatingCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let snapshot = Self.decode(data: data, now: Date(), stale: false)
            if snapshot.state == .available { UserDefaults.standard.set(data, forKey: cacheKey) }
            return snapshot
        } catch {
            if let cached = UserDefaults.standard.data(forKey: cacheKey) {
                var snapshot = Self.decode(data: cached, now: Date(), stale: true)
                snapshot.message = "社区数据暂时不可用，正在显示缓存"
                return snapshot
            }
            return CodexCommunityResetSnapshot(
                state: .unavailable, resetToday: false, confidence: nil, lastResetAt: nil,
                nextScheduledAt: nil, sourceURL: nil, checkedAt: Date(), sourceGeneratedAt: nil, isStale: false,
                message: "社区重置信号不可用"
            )
        }
    }

    nonisolated static func decode(data: Data, now: Date, stale: Bool) -> CodexCommunityResetSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawEvents = root["events"] as? [[String: Any]] else {
            return CodexCommunityResetSnapshot(
                state: .unavailable, resetToday: false, confidence: nil, lastResetAt: nil,
                nextScheduledAt: nil, sourceURL: nil, checkedAt: now, sourceGeneratedAt: nil, isStale: stale,
                message: "社区数据格式无法识别"
            )
        }
        let generated = parseDate(root["generatedAt"] as? String) ?? now
        let events = rawEvents.compactMap { raw -> (String, Date, Double, URL?)? in
            guard let kind = raw["kind"] as? String else { return nil }
            let announced = parseDate(raw["announcedAt"] as? String)
            let effective = parseDate(raw["effectiveAt"] as? String)
            guard let eventDate = effective ?? announced else { return nil }
            let confidence = (raw["confidence"] as? NSNumber)?.doubleValue ?? 0
            let source = (raw["source"] as? [String: Any])?["url"] as? String
            return (kind, eventDate, confidence, source.flatMap(URL.init(string:)))
        }
        // A banked reset is a saved/earned signal, not proof that limits were reset at that moment.
        let completed = events.filter { $0.0 == "reset_completed" }.sorted { $0.1 > $1.1 }
        let scheduled = events.filter { ($0.0 == "reset_scheduled" || $0.0 == "scheduled") && $0.1 > now }.sorted { $0.1 < $1.1 }
        let calendar = Calendar.current
        let todayEvents = completed.filter { calendar.isDate($0.1, inSameDayAs: now) }
        let source = todayEvents.max(by: { $0.2 < $1.2 }) ?? scheduled.first ?? completed.first
        return CodexCommunityResetSnapshot(
            state: .available,
            resetToday: !todayEvents.isEmpty,
            confidence: source?.2,
            lastResetAt: completed.first?.1,
            nextScheduledAt: scheduled.first?.1,
            sourceURL: source?.3,
            checkedAt: now,
            sourceGeneratedAt: generated,
            isStale: stale,
            message: "第三方社区信号，仅供参考"
        )
    }

    private nonisolated static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
