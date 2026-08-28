import Foundation

final class EventLedger: @unchecked Sendable {
    private struct Payload: Codable { var version = 1; var events: [TimelineEvent] }
    private let fileURL: URL
    private(set) var events: [TimelineEvent]
    private(set) var lastWriteError: String?
    var storageDescription: String { fileURL.path }

    init(fileURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PulseDock", isDirectory: true)
        self.fileURL = fileURL ?? support.appendingPathComponent("events-v1.json")
        if let data = try? Data(contentsOf: self.fileURL), let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            events = payload.events
        } else { events = [] }
        lastWriteError = nil
        prune()
    }

    @discardableResult
    func beginOrUpdate(key: String, category: TimelineCategory, severity: TimelineSeverity, title: String, evidence: String, source: String, at date: Date = Date()) -> TimelineEvent {
        if let index = events.firstIndex(where: { $0.key == key && $0.recoveredAt == nil }) {
            events[index].severity = severity
            events[index].title = title
            events[index].evidence = evidence
            events[index].source = source
            save()
            return events[index]
        }
        let item = TimelineEvent(id: UUID(), key: key, category: category, severity: severity, title: title, evidence: evidence, source: source, startedAt: date, recoveredAt: nil)
        events.insert(item, at: 0); prune(); save(); return item
    }

    func recover(key: String, evidence: String, at date: Date = Date()) {
        guard let index = events.firstIndex(where: { $0.key == key && $0.recoveredAt == nil }) else { return }
        events[index].recoveredAt = date
        if !evidence.isEmpty { events[index].evidence += "；恢复：\(evidence)" }
        save()
    }

    func append(category: TimelineCategory, severity: TimelineSeverity, title: String, evidence: String, source: String, at date: Date = Date()) {
        events.insert(TimelineEvent(id: UUID(), key: UUID().uuidString, category: category, severity: severity, title: title, evidence: evidence, source: source, startedAt: date, recoveredAt: date), at: 0)
        prune(); save()
    }

    func clearResolved() { events.removeAll { !$0.isActive }; save() }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        events = Array(events.filter { $0.startedAt >= cutoff }.prefix(500))
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Payload(events: events))
            try data.write(to: fileURL, options: .atomic)
            lastWriteError = nil
        } catch {
            lastWriteError = error.localizedDescription
        }
    }
}
