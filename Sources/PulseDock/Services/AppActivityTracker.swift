import Foundation

@MainActor
final class AppActivityTracker {
    private struct Ledger: Codable {
        var days: [String: [String: AppActivityEntry]] = [:]
    }

    private var ledger = Ledger()
    private var lastSampleAt: Date?
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.fileURL = base.appendingPathComponent("PulseDock/activity-v1.json")
        }
        load()
    }

    func sample(_ snapshot: ActiveApplicationSnapshot, at now: Date = Date(), excluded: Set<String>) {
        defer { lastSampleAt = now }
        guard let previous = lastSampleAt else { return }
        let elapsed = now.timeIntervalSince(previous)
        // Do not count sleep, clock jumps, debugger pauses, or time while PulseDock was stopped.
        guard elapsed > 0, elapsed <= 5, snapshot.isTrackable,
              !snapshot.bundleIdentifier.isEmpty, !excluded.contains(snapshot.bundleIdentifier) else { return }

        let seconds = max(1, Int(elapsed.rounded()))
        let day = ChinaHolidayCalendar.dateKey(now)
        var entries = ledger.days[day] ?? [:]
        var entry = entries[snapshot.bundleIdentifier] ?? AppActivityEntry(
            bundleIdentifier: snapshot.bundleIdentifier,
            name: snapshot.name,
            foregroundSeconds: 0,
            engagedSeconds: 0
        )
        entry.name = snapshot.name
        entry.foregroundSeconds += seconds
        if snapshot.isEngaged { entry.engagedSeconds += seconds }
        entries[snapshot.bundleIdentifier] = entry
        ledger.days[day] = entries
        prune(relativeTo: now)
    }

    func rankings(days: Int, endingAt date: Date = Date(), excluded: Set<String>) -> [AppActivityRanking] {
        let calendar = Calendar.current
        var totals: [String: AppActivityEntry] = [:]
        for offset in 0..<max(1, days) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { continue }
            for entry in ledger.days[ChinaHolidayCalendar.dateKey(day)]?.values ?? Dictionary<String, AppActivityEntry>().values {
                guard !excluded.contains(entry.bundleIdentifier) else { continue }
                var total = totals[entry.bundleIdentifier] ?? AppActivityEntry(
                    bundleIdentifier: entry.bundleIdentifier,
                    name: entry.name,
                    foregroundSeconds: 0,
                    engagedSeconds: 0
                )
                total.name = entry.name
                total.foregroundSeconds += entry.foregroundSeconds
                total.engagedSeconds += entry.engagedSeconds
                totals[entry.bundleIdentifier] = total
            }
        }
        let engagedTotal = totals.values.reduce(0) { $0 + $1.engagedSeconds }
        return totals.values.map { entry in
            AppActivityRanking(
                bundleIdentifier: entry.bundleIdentifier,
                name: entry.name,
                foregroundSeconds: entry.foregroundSeconds,
                engagedSeconds: entry.engagedSeconds,
                share: engagedTotal > 0 ? Double(entry.engagedSeconds) / Double(engagedTotal) : 0
            )
        }.sorted {
            if $0.engagedSeconds == $1.engagedSeconds { return $0.foregroundSeconds > $1.foregroundSeconds }
            return $0.engagedSeconds > $1.engagedSeconds
        }
    }

    func knownName(for bundleIdentifier: String) -> String {
        for entries in ledger.days.values {
            if let name = entries[bundleIdentifier]?.name { return name }
        }
        return bundleIdentifier
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(ledger)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Activity tracking is best-effort and must never interrupt the floating window.
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL), let value = try? JSONDecoder().decode(Ledger.self, from: data) else { return }
        ledger = value
        prune(relativeTo: Date())
    }

    private func prune(relativeTo date: Date) {
        let calendar = Calendar.current
        let retained = Set((0..<31).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: date).map { ChinaHolidayCalendar.dateKey($0) }
        })
        ledger.days = ledger.days.filter { retained.contains($0.key) }
    }
}
