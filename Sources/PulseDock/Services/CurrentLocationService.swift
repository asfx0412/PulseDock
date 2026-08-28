@preconcurrency import CoreLocation
import Foundation

enum CurrentLocationError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { if case .unavailable(let message) = self { return message }; return nil }
}

/// A one-request-at-a-time Core Location bridge. Core Location is allowed to
/// delay or omit a one-shot callback in several real-world states, therefore
/// every request owns an ID and a timeout. Late callbacks are ignored.
@MainActor
final class CurrentLocationService: NSObject {
    private let manager = CLLocationManager()
    private var activeRequestID: UUID?
    private var completion: ((Result<WeatherLocation, CurrentLocationError>) -> Void)?
    private var timeoutTask: Task<Void, Never>?
    private var reverseGeocodeTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestCurrentCity(completion: @escaping (Result<WeatherLocation, CurrentLocationError>) -> Void) {
        guard activeRequestID == nil else {
            completion(.failure(.unavailable("已有定位请求正在进行；请等待完成或取消后重试")))
            return
        }
        let requestID = UUID()
        activeRequestID = requestID
        self.completion = completion
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            self?.finish(requestID, .failure(.unavailable("定位超时（15 秒）；请检查 macOS 定位服务后重试")))
        }
        startLocationIfAuthorized(requestID)
    }

    func cancelCurrentRequest() {
        guard let requestID = activeRequestID else { return }
        finish(requestID, .failure(.unavailable("已取消当前位置请求")))
    }

    private func startLocationIfAuthorized(_ requestID: UUID) {
        guard activeRequestID == requestID else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(requestID, .failure(.unavailable("定位权限未授予；可在系统设置中允许 PulseDock 使用位置")))
        @unknown default:
            finish(requestID, .failure(.unavailable("当前位置授权状态未知")))
        }
    }

    private func finish(_ requestID: UUID, _ result: Result<WeatherLocation, CurrentLocationError>) {
        guard activeRequestID == requestID else { return }
        manager.stopUpdatingLocation()
        timeoutTask?.cancel(); timeoutTask = nil
        reverseGeocodeTask?.cancel(); reverseGeocodeTask = nil
        activeRequestID = nil
        let callback = completion
        completion = nil
        callback?(result)
    }
}

extension CurrentLocationService: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let requestID = activeRequestID else { return }
        startLocationIfAuthorized(requestID)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let requestID = activeRequestID, let location = locations.last else {
            if let requestID = activeRequestID { finish(requestID, .failure(.unavailable("未获得当前位置"))) }
            return
        }
        manager.stopUpdatingLocation()
        reverseGeocodeTask?.cancel()
        let coordinate = location.coordinate
        reverseGeocodeTask = Task { [weak self] in
            do {
                guard !Task.isCancelled else { return }
                let placemark = try await CLGeocoder().reverseGeocodeLocation(location).first
                let district = placemark?.subLocality?.trimmingCharacters(in: .whitespacesAndNewlines)
                let city = placemark?.locality?.trimmingCharacters(in: .whitespacesAndNewlines)
                let region = placemark?.administrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines)
                let countryName = placemark?.country?.trimmingCharacters(in: .whitespacesAndNewlines)
                let coordinateName = String(format: "当前位置 %.2f, %.2f", coordinate.latitude, coordinate.longitude)
                let name = (district?.isEmpty == false ? district! : (city?.isEmpty == false ? city! : coordinateName))
                let country = (countryName?.isEmpty == false ? countryName! : "定位坐标")
                self?.finish(requestID, .success(WeatherLocation(name: name, admin2: city, admin1: region, country: country, latitude: coordinate.latitude, longitude: coordinate.longitude, timezone: TimeZone.current.identifier)))
            } catch is CancellationError {
                // A newer request or explicit cancel owns completion.
            } catch {
                guard !Task.isCancelled else { return }
                let coordinateName = String(format: "当前位置 %.2f, %.2f", coordinate.latitude, coordinate.longitude)
                self?.finish(requestID, .success(WeatherLocation(name: coordinateName, admin2: nil, admin1: nil, country: "定位坐标", latitude: coordinate.latitude, longitude: coordinate.longitude, timezone: TimeZone.current.identifier)))
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let requestID = activeRequestID else { return }
        finish(requestID, .failure(.unavailable("当前位置获取失败：\(error.localizedDescription)")))
    }
}
