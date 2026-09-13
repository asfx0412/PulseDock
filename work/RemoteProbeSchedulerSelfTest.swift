import Foundation

@main
struct RemoteProbeSchedulerSelfTest {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("remote scheduler self-test failed: \(message)") }
    }

    static func main() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let ids = (0..<6).map { _ in UUID() }
        func candidate(_ index: Int, manual: Bool = false, observing: Bool = false, health: RemoteHealth = .healthy, pinned: Bool = false, failures: Int = 0) -> RemoteProbeScheduler.Candidate {
            .init(id: ids[index], enabled: true, intervalSeconds: 60, pinned: pinned, health: health, lastProbeAt: now.addingTimeInterval(-600), failureStreak: failures, observing: observing, manual: manual)
        }
        let selected = RemoteProbeScheduler.select([
            candidate(0), candidate(1, pinned: true), candidate(2, health: .offline),
            candidate(3, observing: true), candidate(4, manual: true), candidate(5)
        ], activeIDs: [], now: now)
        require(selected.count == 3, "admission is capped at three")
        require(selected == [ids[4], ids[3], ids[2]], "manual > observing > unhealthy priority")
        let active = RemoteProbeScheduler.select([candidate(4, manual: true), candidate(3, observing: true)], activeIDs: [ids[4]], now: now)
        require(active == [ids[3]], "manual click cannot bypass an active SSH slot")
        let newManual = RemoteProbeScheduler.select([
            candidate(0), candidate(1), candidate(2), candidate(3, manual: true)
        ], activeIDs: [ids[0], ids[1], ids[2]], now: now, limit: 1)
        require(newManual == [ids[3]], "a manual request arriving during three active probes wins the next slot")
        let normal = candidate(0)
        let failing = candidate(0, failures: 3)
        require(RemoteProbeScheduler.nextDueAt(for: failing) > RemoteProbeScheduler.nextDueAt(for: normal), "failure backoff lengthens the next due time")
        print("PulseDock remote scheduler self-test passed")
    }
}
