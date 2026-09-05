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
        identity.countryCode = "US"; identity.country = "United States"; identity.city = "Los Angeles"; identity.address = "2001:49f0:d0b3:ff00::3"
        require(!identity.isMainlandChina && identity.scopeLabel == "境外出口", "foreign IP scope")
        require(identity.locationHeadline == "美国 · Los Angeles" && identity.addressFamilyLabel == "IPv6", "exit location presentation")
        require(ActivityFormat.duration(59) == "59秒" && ActivityFormat.duration(3_900) == "1小时5分", "activity duration formatting")
        require(WeatherPresentation.condition(code: 95) == "雷雨" && WeatherPresentation.moonPhase(0.5) == "满月", "weather presentation")
        var appearance = AppearanceProfile(theme: .win97, expandedBackgroundAssetID: "A", compactBackgroundAssetID: nil, compactFollowsExpanded: true, placement: .fit, dimming: 0.35, frost: .light, cardOpacity: 0.08, borderStrength: 0.5, automaticTextContrast: true)
        let appearanceData = try! JSONEncoder().encode(appearance)
        appearance = try! JSONDecoder().decode(AppearanceProfile.self, from: appearanceData)
        require(appearance.theme == .win97 && appearance.compactFollowsExpanded && appearance.placement == .fit && appearance.frost == .light, "appearance profile must persist window-specific settings")
        require(FloatingTheme.win97.label == "Win98 经典" && !FloatingTheme.win97.isDark, "legacy theme preference must resolve to Win98")
        let clash = ClashQuotaSnapshot(
            state: .available, name: "test", usedBytes: 80_9 * 1024 * 1024 * 1024 / 10,
            totalBytes: 1024 * 1024 * 1024 * 1024, autoUpdateEnabled: false, message: "fixture"
        )
        require(clash.totalLabel == "1024 GiB" && clash.remainingLabel.hasSuffix("GiB"), "Clash quota must use explicit binary units")
        print("PulseDock 6.8 formatting self-test passed")
    }
}
