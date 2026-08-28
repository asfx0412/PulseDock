import Foundation

@main
enum Version65QuotaMediaSelfTest {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() {
        let rateJSON = Data(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":41,"windowDurationMins":300,"resetsAt":1787400000},"secondary":{"usedPercent":12,"windowDurationMins":10080,"resetsAt":1787900000}},"rateLimitResetCredits":{"availableCount":2,"credits":[]}}}"#.utf8)
        let usageJSON = Data(#"{"id":3,"result":{"summary":{"lifetimeTokens":1234567,"peakDailyTokens":90000,"currentStreakDays":3},"dailyUsageBuckets":[{"startDate":"2026-08-22","tokens":1200},{"startDate":"2026-08-23","tokens":2400}]}}"#.utf8)
        let quota = CodexQuotaService.decode(rateJSON, usageData: usageJSON)
        require(quota.state == .available, "official quota response should decode")
        require(quota.windows.map(\.title) == ["5 小时额度", "每周额度"], "quota windows need semantic labels")
        require(quota.windows[0].remainingPercent == 59, "remaining quota should be derived safely")
        require(quota.resetCreditCount == 2, "reset credits should remain visible")
        require(quota.dailyUsageBuckets.count == 2 && quota.tokenUsageSummary?.lifetimeTokens == 1_234_567, "official token usage should decode independently")

        let multiLimitJSON = Data(#"{"id":2,"result":{"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":99}},"codex":{"primary":{"usedPercent":8,"windowDurationMins":300,"resetsAt":1787400000}}}}}"#.utf8)
        let selected = CodexQuotaService.decode(multiLimitJSON)
        require(selected.remainingPercent == 92, "codex limit must win over unrelated limit IDs")

        let clampedJSON = Data(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":-5,"windowDurationMins":300},"secondary":{"usedPercent":150,"windowDurationMins":10080}}}}"#.utf8)
        let clamped = CodexQuotaService.decode(clampedJSON)
        require(clamped.windows.map(\.usedPercent) == [0, 100], "quota percentages must be clamped")
        require(clamped.riskWindow?.title == "每周额度" && clamped.riskRemainingPercent == 0, "the most constrained window must drive compact risk")

        let serverError = CodexQuotaService.decode(Data(#"{"id":2,"error":{"message":"session expired"}}"#.utf8))
        require(serverError.message.contains("session expired"), "server error envelopes must keep a bounded useful reason")

        let collector = QuotaOutputCollector()
        collector.append(Data(#"{"id":999,"result":{"noise":true}}"#.utf8))
        collector.append(Data("\n".utf8))
        let split = Data(#"{"id":2,"result":{"rateLimits":{}}}"#.utf8)
        collector.append(split.prefix(9))
        collector.append(split.dropFirst(9))
        collector.finish()
        require(collector.response(id: 999) == nil, "collector must ignore unrelated response IDs")
        require(collector.response(id: 2) == split, "collector must flush a split final response without newline")

        let radioJSON = Data(#"""
        [
          {"stationuuid":"one","name":"Focus One","url_resolved":"https://example.com/live.mp3","homepage":"https://example.com","country":"CN","countrycode":"CN","language":"zh","tags":"music,study","codec":"MP3","bitrate":128,"lastcheckok":1},
          {"stationuuid":"one","name":"Duplicate","url_resolved":"https://example.com/other.mp3","codec":"MP3","lastcheckok":1},
          {"stationuuid":"http","name":"Unsafe","url_resolved":"http://example.com/live.mp3","codec":"MP3","lastcheckok":1},
          {"stationuuid":"ogg","name":"Unsupported","url_resolved":"https://example.com/live.ogg","codec":"OGG","lastcheckok":1},
          {"stationuuid":"unchecked","name":"Unchecked","url_resolved":"https://example.com/missing.mp3","codec":"MP3"},
          {"stationuuid":"private","name":"Private","url_resolved":"https://127.0.0.1/live.mp3","codec":"MP3","lastcheckok":1},
          {"stationuuid":"userinfo","name":"Credentials","url_resolved":"https://user:pass@example.com/live.mp3","codec":"MP3","lastcheckok":1}
        ]
        """#.utf8)
        let stations = try! InternetRadioDirectoryService.decode(radioJSON, kind: .music)
        require(stations.count == 1, "directory must deduplicate and reject HTTP/unsupported streams")
        require(stations[0].kind == .music && stations[0].isLive, "music directory stream policy should be explicit")
        let emptyStations = try! InternetRadioDirectoryService.decode(Data("[]".utf8), kind: .radio)
        require(emptyStations.isEmpty, "a valid empty directory response must remain an empty result")
        let filteredFullPage = InternetRadioDirectoryPage(items: [], rawCount: 30, requestedLimit: 30)
        require(filteredFullPage.hasMoreCandidates, "a raw full page must keep pagination alive even when every candidate was filtered")
        let finalPartialPage = InternetRadioDirectoryPage(items: stations, rawCount: 7, requestedLimit: 30)
        require(!finalPartialPage.hasMoreCandidates, "a partial raw page must terminate the remote cursor")
        require(MediaScene.workMusic.count >= 10, "work-music discovery must expose materially more than four categories")
        require(MediaScene.radio.count >= 10, "radio discovery must expose materially more than four categories")
        let mainland = MediaScene.radio.first(where: { $0.id == "mainland-chinese" })
        require(mainland?.countryCodes == ["CN"], "大陆中文 must use a strict Mainland country filter")
        require(MediaScene.radio.contains(where: { $0.id == "greater-china" && Set($0.countryCodes) == ["HK", "MO", "TW"] }), "港澳台中文 must remain a separate category")
        require(MediaPlaybackMode.allCases.allSatisfy { !$0.symbol.isEmpty }, "every playback mode needs a visible icon")

        print("PulseDock 6.7.1 quota/media self-test passed")
    }
}
