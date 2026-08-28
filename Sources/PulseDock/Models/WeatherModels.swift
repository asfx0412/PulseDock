import Foundation

enum WeatherLocationMode: String, CaseIterable, Sendable {
    case fixed
    case automatic

    var label: String { self == .fixed ? "固定地点" : "自动跟随当前位置" }
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
}

enum WeatherLocationPolicy {
    static func shouldUpdate(current: WeatherLocation, candidate: WeatherLocation, minimumDistanceMeters: Double = 2_000) -> Bool {
        let regionChanged = current.name != candidate.name || current.admin2 != candidate.admin2 || current.admin1 != candidate.admin1
        guard regionChanged else { return false }
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

    static let unconfigured = WeatherSnapshot(
        state: .unavailable, location: nil, temperature: nil, apparentTemperature: nil,
        windSpeed: nil, precipitationProbability: nil, weatherCode: nil, isDay: true,
        sunrise: nil, sunset: nil, moonPhase: nil, updatedAt: nil, message: "请在设置中选择城市"
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
