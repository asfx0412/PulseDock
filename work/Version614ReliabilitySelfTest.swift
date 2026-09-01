import Foundation

@main
enum Version614ReliabilitySelfTest {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() {
        require(RetryPolicy.delays == [30, 120, 600], "retry policy must retain the documented 30/120/600 schedule")
        require(RetryPolicy.delay(forFailureCount: 1) == 30 && RetryPolicy.delay(forFailureCount: 4) == 600, "retry policy must bound later attempts")

        let now = Date(timeIntervalSince1970: 1_000)
        let successfulQuota = QuotaSnapshot(state: .available, remainingPercent: 64, resetsAt: now, windowMinutes: 300, planType: nil, resetCreditCount: 1, resetCredits: [], message: "fixture", updatedAt: now, refresh: .fresh(at: now))
        var failedQuota = QuotaSnapshot(state: .unavailable, remainingPercent: nil, resetsAt: nil, windowMinutes: nil, planType: nil, resetCreditCount: nil, resetCredits: [], message: "timeout", updatedAt: Date())
        require(failedQuota.copyDisplayPayload(from: successfulQuota), "failed Codex refresh must retain the last successful payload")
        require(failedQuota.remainingPercent == 64 && failedQuota.updatedAt == now, "retained Codex snapshot must keep the old timestamp")

        let location = WeatherLocation(name: "深圳", admin1: "广东", country: "中国", latitude: 22.5, longitude: 113.9, timezone: "Asia/Shanghai")
        let successfulWeather = WeatherSnapshot(state: .available, location: location, temperature: 26, apparentTemperature: 28, windSpeed: 4, precipitationProbability: 20, weatherCode: 1, isDay: true, sunrise: nil, sunset: nil, moonPhase: nil, updatedAt: now, message: "fixture", refresh: .fresh(at: now))
        var failedWeather = WeatherSnapshot.unconfigured
        require(failedWeather.copyDisplayPayload(from: successfulWeather), "failed weather refresh must retain last successful weather")
        require(failedWeather.temperature == 26 && failedWeather.updatedAt == now, "weather failure must not replace freshness with failure time")

        let id = UUID()
        let cursor = APIConnectorSnapshot(id: id, state: .available, remainingTokens: "fixture", updatedAt: now, message: "fixture", usageWindows: [APIUsageWindow(id: "auto", title: "Auto", windowNumber: nil, usedPercent: 11, resetAt: nil), APIUsageWindow(id: "specified", title: "指定模型", windowNumber: nil, usedPercent: 21, resetAt: nil)], refresh: .fresh(at: now), primaryRemainingPercent: 89)
        let cursorSource = APIConnectorConfiguration(name: "Cursor", kind: .cursorLocalUsage, endpoint: APIConnectorKind.cursorLocalUsage.defaultEndpoint)
        let presentation = QuotaPresentation.connector(cursorSource, snapshot: cursor, now: now)
        require(presentation.value == "89%" && presentation.detail.contains("综合剩余"), "Workbench must use Cursor's own aggregate remaining value")
        require(cursor.usageWindows.count == 2, "Settings must retain Cursor Auto and specified-model detail")
        print("PulseDock 6.14 reliability self-test passed")
    }
}
