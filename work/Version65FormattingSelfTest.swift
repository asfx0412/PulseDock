import Foundation

@main
enum Version65FormattingSelfTest {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)); exit(1) }
    }

    static func main() {
        require(DisplayFormat.speed(0) == "0 KB/s", "zero speed formatting")
        require(DisplayFormat.speed(1_500) == "2 KB/s", "KB speed formatting")
        require(DisplayFormat.speed(1_500_000) == "1.5 MB/s", "MB speed formatting")
        require(DisplayFormat.speed(1_500_000_000) == "1.5 GB/s", "GB speed formatting")
        var identity = IPIdentity(); identity.countryCode = "CN"
        require(identity.isMainlandChina && identity.scopeLabel == "中国大陆", "mainland IP scope")
        identity.countryCode = "US"
        require(!identity.isMainlandChina && identity.scopeLabel == "境外出口", "foreign IP scope")
        require(ActivityFormat.duration(59) == "59秒" && ActivityFormat.duration(3_900) == "1小时5分", "activity duration formatting")
        require(WeatherPresentation.condition(code: 95) == "雷雨" && WeatherPresentation.moonPhase(0.5) == "满月", "weather presentation")
        let clash = ClashQuotaSnapshot(
            state: .available, name: "test", usedBytes: 80_9 * 1024 * 1024 * 1024 / 10,
            totalBytes: 1024 * 1024 * 1024 * 1024, autoUpdateEnabled: false, message: "fixture"
        )
        require(clash.totalLabel == "1024 GiB" && clash.remainingLabel.hasSuffix("GiB"), "Clash quota must use explicit binary units")
        print("PulseDock 6.8 formatting self-test passed")
    }
}
