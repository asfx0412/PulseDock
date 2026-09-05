import Foundation

@main
struct ActivityTest {
    @MainActor static func main() {
        let tracker = AppActivityTracker(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let date = Date()
        let a = ActiveApplicationSnapshot(name: "A", bundleIdentifier: "test.a", isTrackable: true, isEngaged: true)
        let b = ActiveApplicationSnapshot(name: "B", bundleIdentifier: "test.b", isTrackable: true, isEngaged: true)
        tracker.sample(a, at: date, excluded: [])
        tracker.sample(b, at: date.addingTimeInterval(1), excluded: [])
        var ranks = tracker.rankings(days: 1, endingAt: date, excluded: [])
        precondition(ranks.first?.name == "A" && ranks.first?.engagedSeconds == 1, "switch must settle previous owner")
        for i in 1...10 {
            tracker.sample(b, at: date.addingTimeInterval(1 + Double(i) / 10), excluded: [])
        }
        ranks = tracker.rankings(days: 1, endingAt: date, excluded: [])
        precondition(ranks.first(where: { $0.name == "B" })?.engagedSeconds == 1, "ten short events must not count as ten seconds")
        tracker.resetSampling()
        tracker.sample(a, at: date.addingTimeInterval(4), excluded: [])
        precondition(tracker.rankings(days: 1, endingAt: date, excluded: []).reduce(0) { $0 + $1.engagedSeconds } == 2, "wake must not backfill paused interval")
        tracker.sample(b, at: date.addingTimeInterval(20), excluded: [])
        precondition(tracker.rankings(days: 1, endingAt: date, excluded: []).reduce(0) { $0 + $1.engagedSeconds } == 2, "long gaps must not be counted")
        print("6.15.2 foreground accounting passed")
    }
}
