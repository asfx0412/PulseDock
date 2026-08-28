import Foundation

@main
@MainActor
struct Version5SelfTest {
    static func main() async {
        var failures: [String] = []
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }

        check(ActivityFormat.duration(3_900) == "1小时5分", "活跃时间格式")
        check(WeatherPresentation.condition(code: 0) == "晴", "晴天代码")
        check(WeatherPresentation.condition(code: 95) == "雷雨", "雷雨代码")
        check(WeatherPresentation.moonPhase(0.5) == "满月", "满月判断")
        let location = WeatherLocation(name: "上海", admin1: "上海", country: "中国", latitude: 31.23, longitude: 121.47, timezone: "Asia/Shanghai")
        let weatherJSON = """
        {"timezone":"Asia/Shanghai","current":{"temperature_2m":31.2,"apparent_temperature":35.6,"weather_code":0,"is_day":1,"wind_speed_10m":8.0},"daily":{"sunrise":["2026-08-09T05:15"],"sunset":["2026-08-09T18:45"],"moon_phase":[0.5],"precipitation_probability_max":[20]}}
        """
        let weather = WeatherService.decode(data: Data(weatherJSON.utf8), location: location, now: Date())
        check(weather?.temperatureLabel == "31°C", "天气解析")
        check(weather?.moonPhaseLabel == "满月", "天气月相解析")
        check(weather?.metricsLabel.contains("降雨 20%") == true, "天气降雨展示")
        check(weather?.celestialLabel.contains("日出") == true, "日出日落展示")

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("PulseDock-v5-selftest-\(UUID().uuidString).json")
        let tracker = AppActivityTracker(fileURL: temp)
        let start = Date(timeIntervalSince1970: 1_786_224_600)
        check(CompactDensity.minimal.label == "极简", "紧凑浮窗极简密度")
        check(CompactDensity.balanced.label == "平衡", "紧凑浮窗平衡密度")
        check(FloatingTheme.midnight.label == "午夜蓝", "浮窗主题标签")
        check(FloatingTheme.custom.description == "使用你选择的背景色。", "自定义主题说明")
        check(DataFreshness.label(nil, now: start) == "尚未更新", "数据新鲜度空状态")
        check(DataFreshness.label(start.addingTimeInterval(-120), now: start) == "2 分钟前更新", "数据新鲜度分钟状态")
        let cursor = ActiveApplicationSnapshot(name: "Cursor", bundleIdentifier: "com.cursor", idleSeconds: 2, isTrackable: true, isEngaged: true)
        let wechat = ActiveApplicationSnapshot(name: "微信", bundleIdentifier: "com.wechat", idleSeconds: 3, isTrackable: true, isEngaged: true)
        tracker.sample(cursor, at: start, excluded: [])
        tracker.sample(cursor, at: start.addingTimeInterval(1), excluded: [])
        tracker.sample(cursor, at: start.addingTimeInterval(2), excluded: [])
        tracker.sample(wechat, at: start.addingTimeInterval(3), excluded: [])
        let ranks = tracker.rankings(days: 1, endingAt: start.addingTimeInterval(3), excluded: [])
        check(ranks.first?.name == "Cursor", "排行榜第一名")
        check(ranks.first?.engagedSeconds == 2, "有效时长累计")
        let excluded = tracker.rankings(days: 1, endingAt: start.addingTimeInterval(3), excluded: ["com.cursor"])
        check(excluded.first?.name == "微信", "排除名单")
        tracker.sample(cursor, at: start.addingTimeInterval(300), excluded: [])
        check(tracker.rankings(days: 1, endingAt: start.addingTimeInterval(300), excluded: []).first?.engagedSeconds == 2, "睡眠间隔不补记")

        let communityJSON = """
        {"generatedAt":"2026-08-09T02:00:00.000Z","events":[
          {"kind":"reset_completed","announcedAt":"2026-08-09T01:00:00.000Z","effectiveAt":null,"confidence":0.95,"source":{"url":"https://x.com/example/1"}},
          {"kind":"reset_scheduled","announcedAt":"2026-08-09T01:30:00.000Z","effectiveAt":"2026-08-10T07:00:00.000Z","confidence":0.8,"source":{"url":"https://x.com/example/2"}}
        ]}
        """
        let now = ISO8601DateFormatter().date(from: "2026-08-09T02:30:00Z")!
        let community = CodexCommunityResetService.decode(data: Data(communityJSON.utf8), now: now, stale: false)
        check(community.state == .available, "社区数据解析")
        check(community.resetToday, "今日重置信号")
        check(community.nextScheduledAt != nil, "下次计划")
        check(community.confidence == 0.95, "今日信号置信度优先")

        let quotaJSON = """
        {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1786258800},"planType":"plus"},"rateLimitResetCredits":{"availableCount":2,"credits":[{"id":"credit-1","status":"available","grantedAt":1786086000,"expiresAt":1786690800,"title":"Rate-limit reset","description":"Reset an eligible window"}]}}}
        """
        let quota = CodexQuotaService.decode(Data(quotaJSON.utf8))
        check(quota.remainingPercent == 75, "Codex 剩余额度解析")
        check(quota.resetCreditCount == 2, "Codex 重置券数量")
        check(quota.resetCredits.first?.status == "available", "Codex 重置券详情")
        check(quota.resetDateTimeLabel.contains("2026"), "Codex 刷新日期与时间展示")

        try? FileManager.default.removeItem(at: temp)
        if failures.isEmpty {
            print("VERSION5_SELF_TEST_PASS")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }
}
