import Foundation

@main
struct Version616CommunityResetSelfTest {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("community reset self-test failed: \(message)") }
    }

    @MainActor static func main() {
        let now = ISO8601DateFormatter().date(from: "2026-09-13T08:00:00Z")!
        let json = #"""
        {
          "ok": true,
          "data": { "items": [
            {"id":"schedule-1","kind":"reset_scheduled","announcedAt":"2026-09-13T07:00:00.000Z","effectiveAt":"2026-09-13T10:00:00.000Z","confidence":0.92,"scope":{"plans":["all"],"windows":["five_hour"]},"source":{"url":"https://x.com/example/1"},"schedulePrecision":"datetime","scheduleBasis":"explicit","scheduleState":"pending","completionRecordId":null,"relatedRecordIds":[]},
            {"id":"completed-1","kind":"reset_completed","announcedAt":null,"effectiveAt":"2026-09-12T08:00:00.000Z","confidence":null,"scope":null,"source":{"url":null},"schedulePrecision":null,"scheduleBasis":null,"scheduleState":null,"completionRecordId":null,"relatedRecordIds":["old-schedule"]},
            {"id":"date-only","kind":"reset_scheduled","announcedAt":"2026-09-13T07:00:00.000Z","effectiveAt":"2026-09-13T12:00:00.000Z","confidence":0.99,"scope":{"plans":["unknown"],"windows":["unknown"]},"source":{"url":null},"schedulePrecision":"date","scheduleBasis":"contextual_inference","scheduleState":"pending","completionRecordId":null,"relatedRecordIds":[]}
          ] },
          "meta": {"generatedAt":"2026-09-13T07:59:00.000Z","lastSuccessfulCheckAt":"2026-09-13T07:58:00.000Z"}
        }
        """#
        let snapshot = CodexCommunityResetService.decode(data: Data(json.utf8), now: now, stale: false)
        require(snapshot.state == .available, "OpenAPI records payload parses")
        require(snapshot.records.count == 3, "unknown fields and nulls do not discard valid records")
        require(snapshot.activeSchedule?.id == "schedule-1", "nearest future pending plan is selected")
        require(snapshot.activeSchedule?.isExactExplicitSchedule == true, "explicit datetime remains distinguishable")
        require(snapshot.activeSchedule?.scopeLabel == "全部套餐", "scope is safely summarized")
        require(snapshot.upstreamLastSuccessfulCheckAt != nil, "upstream freshness is retained separately")
        require(snapshot.checkedAt == now, "local checked time never impersonates upstream generated time")

        let malformed = CodexCommunityResetService.decode(data: Data("{\"data\":{\"items\":[{\"id\":\"missing-kind\"}]}}".utf8), now: now, stale: false)
        require(malformed.state == .unavailable, "all incomplete records fail closed so an old snapshot is retained")

        let unsafeURL = CodexCommunityResetService.decode(data: Data(#"{"data":{"id":"unsafe","kind":"reset_scheduled","announcedAt":"2026-09-13T07:00:00Z","effectiveAt":"2026-09-13T10:00:00Z","confidence":0.9,"scope":{"plans":["all"]},"source":{"url":"file:///private/secret"},"schedulePrecision":"datetime","scheduleBasis":"explicit","scheduleState":"pending","relatedRecordIds":[]}}"#.utf8), now: now, stale: false)
        require(unsafeURL.records.first?.sourceURL == nil, "non-HTTPS source URLs are rejected")

        let suite = "PulseDock.community-reset-self-test"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let record = snapshot.records[0]
        let ledger = CommunityResetAlertLedger(defaults: defaults)
        _ = ledger.observe(record, now: now, eligibleSchedule: true)
        require(ledger.claim(recordID: record.id, stage: .firstSeen, channel: .feishu, at: now), "first Feishu claim succeeds")
        require(!ledger.claim(recordID: record.id, stage: .firstSeen, channel: .feishu, at: now), "in-flight Feishu claim prevents duplicate send")
        let reloaded = CommunityResetAlertLedger(defaults: defaults)
        require(reloaded.hasClaim(recordID: record.id, stage: .firstSeen, channel: .feishu), "claim persists across polling/reload")
        reloaded.reset()
        require(defaults.data(forKey: "PulseDock.communityResetAlertLedger.v1") == nil, "reset uses injected defaults suite")
        print("PulseDock 6.16 community reset self-test passed")
    }
}
