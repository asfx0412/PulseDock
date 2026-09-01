import Foundation

actor WeatherService {
    func searchCities(_ query: String) async -> [WeatherLocation] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "6"),
            URLQueryItem(name: "language", value: "zh"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { raw in
            guard let name = raw["name"] as? String,
                  let country = raw["country"] as? String,
                  let latitude = (raw["latitude"] as? NSNumber)?.doubleValue,
                  let longitude = (raw["longitude"] as? NSNumber)?.doubleValue else { return nil }
            return WeatherLocation(
                name: name, admin2: raw["admin2"] as? String, admin1: raw["admin1"] as? String, country: country,
                latitude: latitude, longitude: longitude,
                timezone: raw["timezone"] as? String ?? "auto"
            )
        }
    }

    func read(location: WeatherLocation) async -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m"),
            URLQueryItem(name: "daily", value: "sunrise,sunset,moon_phase,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: location.timezone),
            URLQueryItem(name: "forecast_days", value: "2")
        ]
        guard let url = components.url else { return unavailable(location, "天气请求无法创建", failure: .invalidRequest) }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                return unavailable(location, "天气服务响应无效", failure: .network)
            }
            guard http.statusCode == 200 else {
                return unavailable(location, "天气服务暂时不可用", failure: .http(http.statusCode))
            }
            guard var snapshot = Self.decode(data: data, location: location, now: Date()) else {
                return unavailable(location, "天气数据格式无效", failure: .decoding)
            }
            snapshot.refresh = .fresh(at: snapshot.updatedAt ?? Date())
            return snapshot
        } catch {
            let urlError = error as? URLError
            let failure: WeatherFailure
            switch urlError?.code {
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: failure = .dns
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot: failure = .tls
            case .timedOut: failure = .timeout
            default: failure = .network
            }
            return unavailable(location, failure.label, failure: failure)
        }
    }

    nonisolated static func decode(data: Data, location: WeatherLocation, now: Date) -> WeatherSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = root["current"] as? [String: Any] else { return nil }
        let daily = root["daily"] as? [String: Any]
        let timezone = TimeZone(identifier: root["timezone"] as? String ?? location.timezone) ?? .current
        return WeatherSnapshot(
            state: .available,
            location: location,
            temperature: (current["temperature_2m"] as? NSNumber)?.doubleValue,
            apparentTemperature: (current["apparent_temperature"] as? NSNumber)?.doubleValue,
            windSpeed: (current["wind_speed_10m"] as? NSNumber)?.doubleValue,
            precipitationProbability: (daily?["precipitation_probability_max"] as? [NSNumber])?.first?.intValue,
            weatherCode: (current["weather_code"] as? NSNumber)?.intValue,
            isDay: (current["is_day"] as? NSNumber)?.intValue == 1,
            sunrise: localDate((daily?["sunrise"] as? [String])?.first, timezone: timezone),
            sunset: localDate((daily?["sunset"] as? [String])?.first, timezone: timezone),
            moonPhase: (daily?["moon_phase"] as? [NSNumber])?.first?.doubleValue,
            updatedAt: now,
            message: "天气位置由你手动设定"
        )
    }

    private nonisolated static func localDate(_ value: String?, timezone: TimeZone) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.date(from: value)
    }

    private func unavailable(_ location: WeatherLocation, _ message: String, failure: WeatherFailure) -> WeatherSnapshot {
        var snapshot = WeatherSnapshot.unconfigured
        snapshot.location = location
        snapshot.message = message
        snapshot.failure = failure
        return snapshot
    }
}
