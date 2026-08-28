import Foundation

@main
enum Version612FeatureSelfTest {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() {
        require(GlobalShortcut.optionSpace.label == "⌥Space", "visibility shortcut default must stay discoverable")
        require(GlobalShortcut.optionSpace != .optionShiftSpace, "two global actions require distinct defaults")
        require(GlobalShortcut(rawValue: GlobalShortcut.optionShiftSpace.rawValue) == .optionShiftSpace, "custom shortcut persistence must round-trip")
        require(GlobalShortcut(rawValue: "optionSpace") == .optionSpace, "legacy shortcut choices must migrate")

        let nanshan = WeatherLocation(name: "南山区", admin2: "深圳市", admin1: "广东省", country: "中国", latitude: 22.533, longitude: 113.930, timezone: "Asia/Shanghai")
        let drift = WeatherLocation(name: "福田区", admin2: "深圳市", admin1: "广东省", country: "中国", latitude: 22.534, longitude: 113.931, timezone: "Asia/Shanghai")
        let longgang = WeatherLocation(name: "龙岗区", admin2: "深圳市", admin1: "广东省", country: "中国", latitude: 22.720, longitude: 114.247, timezone: "Asia/Shanghai")
        require(!WeatherLocationPolicy.shouldUpdate(current: nanshan, candidate: drift), "GPS drift below 2 km must not replace the district")
        require(WeatherLocationPolicy.shouldUpdate(current: nanshan, candidate: longgang), "a real district move must update automatic weather location")
        require(!WeatherLocationPolicy.shouldUpdate(current: nanshan, candidate: nanshan), "same administrative location must remain stable")

        require(AudioStreamPreflightService.classify(URLError(.timedOut)) == .timeout, "audio timeout must remain a separate failure category")
        require(AudioStreamPreflightService.classify(URLError(.secureConnectionFailed)) == .tls, "audio TLS failures must remain visible")
        require(AudioStreamPreflightService.classify(URLError(.networkConnectionLost)) == .interrupted, "stream interruption must not be mislabeled as TLS")
        print("PulseDock 6.12 feature policy self-test passed")
    }
}
