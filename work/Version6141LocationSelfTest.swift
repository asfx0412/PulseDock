import Foundation

@main
enum Version6141LocationSelfTest {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() {
        let now = Date(timeIntervalSince1970: 2_000)
        require(WeatherLocationAcquisitionPolicy.sessionTimeout == 20, "location session must remain bounded to 20 seconds")
        require(WeatherLocationAcquisitionPolicy.reverseGeocodeTimeout == 5, "reverse geocoding must have a bounded fallback")
        require(
            WeatherLocationAcquisitionPolicy.accepts(
                timestamp: now.addingTimeInterval(-29), horizontalAccuracy: 1_000, now: now
            ),
            "a recent city-level fix must be accepted"
        )
        require(
            !WeatherLocationAcquisitionPolicy.accepts(
                timestamp: now.addingTimeInterval(-31), horizontalAccuracy: 1_000, now: now
            ),
            "a stale cached fix must not move the weather city"
        )
        require(
            !WeatherLocationAcquisitionPolicy.accepts(timestamp: now, horizontalAccuracy: 5_001, now: now),
            "an excessively coarse fix must not move the weather city"
        )
        require(
            !WeatherLocationAcquisitionPolicy.accepts(timestamp: now, horizontalAccuracy: -1, now: now),
            "an invalid accuracy must not move the weather city"
        )

        require(WeatherLocationRetryPolicy.delays == [30, 120, 600], "location retries must use 30/120/600 seconds")
        require(WeatherLocationRetryPolicy.delay(forFailureCount: 1) == 30, "first location retry must occur after 30 seconds")
        require(WeatherLocationRetryPolicy.delay(forFailureCount: 3) == 600, "third location retry must occur after 10 minutes")
        require(WeatherLocationRetryPolicy.delay(forFailureCount: 4) == nil, "location retries must stop after the bounded schedule")

        print("PulseDock 6.14.1 location policy self-test passed")
    }
}
