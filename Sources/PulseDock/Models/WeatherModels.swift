import Foundation

enum WeatherLocationMode: String, CaseIterable, Sendable {
    case fixed
    case automatic

    var label: String { self == .fixed ? "固定地点" : "自动跟随当前位置" }
}

/// Location acquisition is deliberately a short foreground session, never a
/// continuous tracker.  A Mac may have only Wi-Fi based positioning, so a
/// single `requestLocation()` callback is not a dependable freshness signal.
/// These values keep the location good enough for city-level weather without
/// silently accepting an old or extremely coarse fix.
enum WeatherLocationAcquisitionPolicy {
    static let sessionTimeout: TimeInterval = 20
    static let reverseGeocodeTimeout: TimeInterval = 5
    /// A fresh fix may move the weather city.  This remains deliberately
    /// conservative: a Mac is not a GPS tracker and an old Wi-Fi cache must
    /// not silently jump a user's weather location.
    static let maximumLocationAge: TimeInterval = 30
    static let maximumHorizontalAccuracyMeters: Double = 5_000
    /// Core Location can legitimately hand a foreground app its last known
    /// Wi-Fi position while it is resolving a new one.  It is useful evidence
    /// to *confirm* an existing city, but is never authority to replace it.
    static let reusableLocationAge: TimeInterval = 15 * 60
    static let reusableHorizontalAccuracyMeters: Double = 10_000

    static func accepts(timestamp: Date, horizontalAccuracy: Double, now: Date = Date()) -> Bool {
        now.timeIntervalSince(timestamp) <= maximumLocationAge
            && horizontalAccuracy >= 0
            && horizontalAccuracy <= maximumHorizontalAccuracyMeters
    }

    static func acceptsRecentReusable(timestamp: Date, horizontalAccuracy: Double, now: Date = Date()) -> Bool {
        now.timeIntervalSince(timestamp) <= reusableLocationAge
            && horizontalAccuracy >= 0
            && horizontalAccuracy <= reusableHorizontalAccuracyMeters
    }
}

/// The acquisition policy is intentionally explicit.  UI can say whether a
/// location was newly fixed or merely confirmed from the system's recent
/// cache, without persisting precise coordinate diagnostics.
enum WeatherLocationEvidence: String, Codable, Sendable, Equatable {
    case fresh
    case recentReusable
}

struct WeatherLocationCandidate: Sendable, Equatable {
    var location: WeatherLocation
    var evidence: WeatherLocationEvidence
    var horizontalAccuracy: Double
}

/// Privacy-safe result labels shown in settings diagnostics.  Raw Core
/// Location domains/codes, coordinates and Wi-Fi observations are never
/// persisted or rendered as the primary status.
enum WeatherLocationDiagnosticKind: String, Sendable, Equatable {
    case fresh
    case recentReusable
    case locationUnknown
    case timedOut
    case inadequateAccuracy
    case servicesDisabled
    case authorizationDenied
    case authorizationRestricted
    case reverseGeocodeFailed
    case cancelled
    case unexpected

    var label: String {
        switch self {
        case .fresh: "已获得新的当前位置"
        case .recentReusable: "沿用系统最近位置"
        case .locationUnknown: "系统暂时无法确定位置"
        case .timedOut: "定位会话超时"
        case .inadequateAccuracy: "定位精度不足"
        case .servicesDisabled: "系统定位服务已关闭"
        case .authorizationDenied: "PulseDock 未获位置权限"
        case .authorizationRestricted: "系统限制了位置服务"
        case .reverseGeocodeFailed: "地点名称暂时无法解析"
        case .cancelled: "定位请求已取消"
        case .unexpected: "定位服务暂时不可用"
        }
    }
}

/// Retries are intentionally separate from weather-network retries.  This
/// keeps a temporary Core Location `locationUnknown` from waiting for the next
/// 30-minute weather cycle, while avoiding any form of persistent tracking.
enum WeatherLocationRetryPolicy {
    static let delays: [TimeInterval] = [30, 120, 600]

    static func delay(forFailureCount count: Int) -> TimeInterval? {
        guard count > 0, count <= delays.count else { return nil }
        return delays[count - 1]
    }
}

/// Public, non-sensitive category for a failed weather read.  The full URL,
/// coordinates and raw networking error remain local diagnostic evidence and
/// are not rendered in the compact dashboard.
enum WeatherFailure: Sendable, Equatable {
    case invalidRequest
    case network
    case dns
    case tls
    case timeout
    case http(Int)
    case decoding

    var label: String {
        switch self {
        case .invalidRequest: "请求地址无效"
        case .network: "网络暂不可用"
        case .dns: "DNS 解析失败"
        case .tls: "TLS 连接失败"
        case .timeout: "请求超时"
        case let .http(status): "天气服务返回 HTTP \(status)"
        case .decoding: "天气数据格式无效"
        }
    }
}

struct WeatherLocation: Codable, Sendable, Equatable, Identifiable {
    var name: String
    var admin2: String? = nil
    var admin1: String?
    var country: String
    var latitude: Double
    var longitude: Double
    var timezone: String

    var id: String { "\(latitude),\(longitude)" }
    var displayName: String { [name, admin2, admin1, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") }

    var hasResolvedAdministrativeName: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && country != "定位坐标"
            && !name.hasPrefix("当前位置 ")
    }
}

enum WeatherLocationPolicy {
    static func shouldUpdate(current: WeatherLocation, candidate: WeatherLocation, minimumDistanceMeters: Double = 2_000) -> Bool {
        guard candidate.hasResolvedAdministrativeName else { return false }
        let regionChanged = current.name != candidate.name || current.admin2 != candidate.admin2 || current.admin1 != candidate.admin1
        guard regionChanged else { return false }

        // A city-only location left by an earlier manual search or an older
        // Core Location response must be allowed to gain its district/province
        // immediately.  This is an address-quality repair, not a movement, so
        // the normal 2 km anti-jitter threshold must not block it.  The shared
        // municipality requirement prevents a nearby but unrelated result
        // from being treated as an upgrade.
        if isAdministrativeEnrichment(current: current, candidate: candidate) { return true }

        // Conversely, a later coarse response such as "深圳市" must never
        // overwrite an existing "南山区 · 深圳市 · 广东省 · 中国", even after
        // real movement inside the same municipality.
        if isAdministrativeDowngrade(current: current, candidate: candidate) { return false }

        let radius = 6_371_000.0
        let lat1 = current.latitude * .pi / 180
        let lat2 = candidate.latitude * .pi / 180
        let deltaLat = (candidate.latitude - current.latitude) * .pi / 180
        let deltaLon = (candidate.longitude - current.longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let distance = radius * 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return distance >= minimumDistanceMeters
    }

    private static func isAdministrativeEnrichment(current: WeatherLocation, candidate: WeatherLocation) -> Bool {
        candidate.administrativeFieldCount > current.administrativeFieldCount
            && sharesMunicipality(current: current, candidate: candidate)
    }

    private static func isAdministrativeDowngrade(current: WeatherLocation, candidate: WeatherLocation) -> Bool {
        candidate.administrativeFieldCount < current.administrativeFieldCount
            && sharesMunicipality(current: current, candidate: candidate)
    }

    private static func sharesMunicipality(current: WeatherLocation, candidate: WeatherLocation) -> Bool {
        let currentNames = Set([current.name, current.admin2].compactMap(normalizedAdministrativeName))
        let candidateNames = Set([candidate.name, candidate.admin2].compactMap(normalizedAdministrativeName))
        guard !currentNames.isEmpty, !candidateNames.isEmpty,
              !currentNames.isDisjoint(with: candidateNames) else { return false }
        return normalizedAdministrativeName(current.country) == normalizedAdministrativeName(candidate.country)
    }

    private static func normalizedAdministrativeName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Cached fixes can validate an existing choice but cannot select a new
    /// city.  This prevents a stale macOS location from replacing a manually
    /// selected city after travel or a network transition.
    static func mayConfirmExisting(current: WeatherLocation, candidate: WeatherLocation, maximumDistanceMeters: Double = 12_000) -> Bool {
        guard candidate.hasResolvedAdministrativeName else { return false }
        let sameAdministrativeArea = current.name == candidate.name
            || (current.admin2 != nil && current.admin2 == candidate.admin2 && current.admin1 == candidate.admin1)
            || (current.admin1 != nil && current.admin1 == candidate.admin1 && current.country == candidate.country)
        guard sameAdministrativeArea else { return false }
        return distanceMeters(from: current, to: candidate) <= maximumDistanceMeters
    }

    static func distanceMeters(from current: WeatherLocation, to candidate: WeatherLocation) -> Double {
        let radius = 6_371_000.0
        let lat1 = current.latitude * .pi / 180
        let lat2 = candidate.latitude * .pi / 180
        let deltaLat = (candidate.latitude - current.latitude) * .pi / 180
        let deltaLon = (candidate.longitude - current.longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }
}

private extension WeatherLocation {
    /// `name` is always the most specific known level, then city, province and
    /// country.  Counting known levels is only used to prevent information
    /// loss or permit safe same-city enrichment; it never infers a district.
    var administrativeFieldCount: Int {
        [name, admin2, admin1, country]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }
}

struct WeatherSnapshot: Sendable, Equatable {
    enum State: Sendable { case loading, available, unavailable }

    var state: State
    var location: WeatherLocation?
    var temperature: Double?
    var apparentTemperature: Double?
    var windSpeed: Double?
    var precipitationProbability: Int?
    var weatherCode: Int?
    var isDay: Bool
    var sunrise: Date?
    var sunset: Date?
    var moonPhase: Double?
    var updatedAt: Date?
    var message: String
    var refresh = RefreshMetadata()
    var failure: WeatherFailure? = nil

    static let unconfigured = WeatherSnapshot(
        state: .unavailable, location: nil, temperature: nil, apparentTemperature: nil,
        windSpeed: nil, precipitationProbability: nil, weatherCode: nil, isDay: true,
        sunrise: nil, sunset: nil, moonPhase: nil, updatedAt: nil, message: "请在设置中选择城市",
        refresh: RefreshMetadata(status: .initialFailure)
    )

    var temperatureLabel: String { temperature.map { String(format: "%.0f°C", $0) } ?? "--" }
    var apparentLabel: String { apparentTemperature.map { String(format: "体感 %.0f°C", $0) } ?? "体感 --" }
    var conditionLabel: String { WeatherPresentation.condition(code: weatherCode) }
    var symbol: String { WeatherPresentation.symbol(code: weatherCode, isDay: isDay, moonPhase: moonPhase) }
    var moonPhaseLabel: String { WeatherPresentation.moonPhase(moonPhase) }
    var metricsLabel: String {
        var parts = [conditionLabel, apparentLabel]
        if let precipitationProbability { parts.append("降雨 \(precipitationProbability)%") }
        if let windSpeed { parts.append(String(format: "风 %.0f km/h", windSpeed)) }
        return parts.joined(separator: " · ")
    }
    var celestialLabel: String {
        var parts: [String] = []
        if let sunrise { parts.append("日出 \(sunrise.formatted(date: .omitted, time: .shortened))") }
        if let sunset { parts.append("日落 \(sunset.formatted(date: .omitted, time: .shortened))") }
        parts.append(moonPhaseLabel)
        return parts.joined(separator: " · ")
    }

    var hasDisplayPayload: Bool {
        temperature != nil || apparentTemperature != nil || weatherCode != nil
    }

    @discardableResult
    mutating func copyDisplayPayload(from previous: WeatherSnapshot) -> Bool {
        guard previous.hasDisplayPayload else { return false }
        location = previous.location
        temperature = previous.temperature
        apparentTemperature = previous.apparentTemperature
        windSpeed = previous.windSpeed
        precipitationProbability = previous.precipitationProbability
        weatherCode = previous.weatherCode
        isDay = previous.isDay
        sunrise = previous.sunrise
        sunset = previous.sunset
        moonPhase = previous.moonPhase
        updatedAt = previous.updatedAt
        return true
    }
}

enum WeatherPresentation {
    static func condition(code: Int?) -> String {
        switch code {
        case 0: "晴"
        case 1, 2: "少云"
        case 3: "阴"
        case 45, 48: "雾"
        case 51, 53, 55, 56, 57: "毛毛雨"
        case 61, 63, 65, 66, 67, 80, 81, 82: "雨"
        case 71, 73, 75, 77, 85, 86: "雪"
        case 95, 96, 99: "雷雨"
        default: "天气"
        }
    }

    static func symbol(code: Int?, isDay: Bool, moonPhase: Double?) -> String {
        if !isDay, code == 0 || code == 1 { return "moon.stars.fill" }
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return isDay ? "sun.max.fill" : "moon.stars.fill"
        }
    }

    static func moonPhase(_ phase: Double?) -> String {
        guard let phase else { return "月相未知" }
        let normalized = phase - floor(phase)
        switch normalized {
        case 0..<0.03, 0.97..<1: return "新月"
        case 0.03..<0.22: return "娥眉月"
        case 0.22..<0.28: return "上弦月"
        case 0.28..<0.47: return "盈凸月"
        case 0.47..<0.53: return "满月"
        case 0.53..<0.72: return "亏凸月"
        case 0.72..<0.78: return "下弦月"
        default: return "残月"
        }
    }
}
