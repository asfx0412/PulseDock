import Foundation

@main
enum Version615FeatureSelfTest {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func location(_ name: String, _ city: String?, _ province: String?, _ country: String, _ lat: Double, _ lon: Double) -> WeatherLocation {
        WeatherLocation(name: name, admin2: city, admin1: province, country: country, latitude: lat, longitude: lon, timezone: "Asia/Shanghai")
    }

    static func main() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        require(WeatherLocationAcquisitionPolicy.accepts(timestamp: now.addingTimeInterval(-29), horizontalAccuracy: 1_000, now: now), "fresh city fix must be accepted")
        require(!WeatherLocationAcquisitionPolicy.accepts(timestamp: now.addingTimeInterval(-31), horizontalAccuracy: 1_000, now: now), "stale fix must not update city")
        require(WeatherLocationAcquisitionPolicy.acceptsRecentReusable(timestamp: now.addingTimeInterval(-600), horizontalAccuracy: 8_000, now: now), "recent cache should remain available for confirmation")
        require(!WeatherLocationAcquisitionPolicy.acceptsRecentReusable(timestamp: now.addingTimeInterval(-901), horizontalAccuracy: 1_000, now: now), "old cache must expire")

        let nanshan = location("南山区", "深圳市", "广东省", "中国", 22.54, 113.94)
        let nearbyNanshan = location("南山区", "深圳市", "广东省", "中国", 22.56, 113.93)
        let baoan = location("宝安区", "深圳市", "广东省", "中国", 22.65, 113.83)
        let shenzhenOnly = location("深圳市", nil, nil, "中国", 22.54, 113.94)
        let sameCityFullAddress = location("南山区", "深圳市", "广东省", "中国", 22.54, 113.94)
        require(WeatherLocationPolicy.mayConfirmExisting(current: nanshan, candidate: nearbyNanshan), "recent cache may confirm same administrative area")
        require(!WeatherLocationPolicy.mayConfirmExisting(current: nanshan, candidate: baoan), "recent cache must not move to another district")
        require(WeatherLocationPolicy.shouldUpdate(current: shenzhenOnly, candidate: sameCityFullAddress), "same-city district/province enrichment must bypass movement debounce")
        require(!WeatherLocationPolicy.shouldUpdate(current: sameCityFullAddress, candidate: shenzhenOnly), "coarse city response must not erase a confirmed district")
        require(!WeatherLocation(name: "当前位置 22.54, 113.94", country: "定位坐标", latitude: 0, longitude: 0, timezone: "UTC").hasResolvedAdministrativeName, "coordinates must never be presented as city")

        let copilot = APIConnectorConfiguration(name: "Copilot", kind: .githubCopilotUsage, endpoint: "https://example.invalid", accountID: "octo-cat")
        let sanitized = APIConnectorConfiguration.sanitizeForStorage([copilot])
        let stored = sanitized.first { $0.kind == .githubCopilotUsage }
        require(stored?.endpoint == APIConnectorKind.githubCopilotUsage.defaultEndpoint, "Copilot endpoint must be fixed to GitHub official host")
        require(APIConnectorService.isValidGitHubUsername("octo-cat"), "valid GitHub username rejected")
        require(!APIConnectorService.isValidGitHubUsername("-bad-"), "invalid GitHub username accepted")
        let credits = Data("{\"used_amount\":3,\"unit\":\"credits\",\"usage_items\":[{\"sku\":\"premium\",\"used_amount\":2}]}".utf8)
        let requests = Data("{\"used\":8,\"unit\":\"requests\",\"items\":[{\"model\":\"gpt-5\",\"used\":8}]}".utf8)
        let metrics = APIConnectorService.decodeGitHubCopilotMetrics(creditData: credits, premiumData: requests)
        require(metrics.count == 2 && metrics.allSatisfy { $0.usedValue.contains("已用") }, "Copilot must display official used amounts without percentages")
        print("PulseDock 6.15 feature self-test passed")
    }
}
