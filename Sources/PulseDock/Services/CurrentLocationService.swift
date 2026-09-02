@preconcurrency import CoreLocation
import Foundation
import MapKit

enum CurrentLocationError: LocalizedError {
    case servicesDisabled
    case authorizationDenied
    case authorizationRestricted
    case temporarilyUnavailable
    case inadequateAccuracy
    case timedOut
    case cancelled
    case unexpected(String)

    /// This message is suitable for normal UI.  Do not expose Core Location's
    /// raw domain/code here: `locationUnknown` is expected on Macs while Wi-Fi
    /// positioning is being resolved and is not an actionable user error.
    var errorDescription: String? {
        switch self {
        case .servicesDisabled:
            "系统定位服务已关闭"
        case .authorizationDenied:
            "定位权限未授予；可在系统设置中允许 PulseDock 使用位置"
        case .authorizationRestricted:
            "系统限制了定位服务"
        case .temporarilyUnavailable:
            "暂时无法确定当前位置"
        case .inadequateAccuracy:
            "当前位置精度暂时不足"
        case .timedOut:
            "暂时未能确定当前位置"
        case .cancelled:
            "已取消当前位置请求"
        case .unexpected:
            "当前位置暂时不可用"
        }
    }

    /// Kept only for diagnostics/help text; it never becomes the settings
    /// card's primary status line.
    var diagnosticDescription: String {
        switch self {
        case .servicesDisabled:
            "Core Location: location services disabled"
        case .authorizationDenied:
            "Core Location: authorization denied"
        case .authorizationRestricted:
            "Core Location: authorization restricted"
        case .temporarilyUnavailable:
            "Core Location: locationUnknown (kCLErrorDomain 0)"
        case .inadequateAccuracy:
            "Core Location: only stale or > \(Int(WeatherLocationAcquisitionPolicy.maximumHorizontalAccuracyMeters)) m accuracy fixes arrived"
        case .timedOut:
            "Core Location: no acceptable fix within \(Int(WeatherLocationAcquisitionPolicy.sessionTimeout)) seconds"
        case .cancelled:
            "Core Location: request cancelled by user or a newer selection"
        case let .unexpected(detail):
            "Core Location: \(detail)"
        }
    }

    var supportsAutomaticRetry: Bool {
        switch self {
        case .temporarilyUnavailable, .inadequateAccuracy, .timedOut, .unexpected:
            true
        case .servicesDisabled, .authorizationDenied, .authorizationRestricted, .cancelled:
            false
        }
    }
}

/// A one-request-at-a-time Core Location bridge.  Each request creates a
/// bounded, short `startUpdatingLocation()` session instead of treating a
/// single `requestLocation()` / `locationUnknown` callback as the final answer.
/// It stops immediately after an acceptable fix, timeout, cancellation, or a
/// non-recoverable authorization error; PulseDock never continuously tracks.
@MainActor
final class CurrentLocationService: NSObject {
    private let manager = CLLocationManager()
    private var activeRequestID: UUID?
    private var completion: ((Result<WeatherLocation, CurrentLocationError>) -> Void)?
    private var timeoutTask: Task<Void, Never>?
    private var reverseGeocodeTask: Task<Void, Never>?
    private var reverseGeocodeTimeoutTask: Task<Void, Never>?
    private var reverseGeocodeRequest: MKReverseGeocodingRequest?
    private var sawLocationUnknown = false
    private var sawInadequateFix = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestCurrentCity(completion: @escaping (Result<WeatherLocation, CurrentLocationError>) -> Void) {
        guard activeRequestID == nil else {
            completion(.failure(.unexpected("a location request is already active")))
            return
        }
        let requestID = UUID()
        activeRequestID = requestID
        self.completion = completion
        sawLocationUnknown = false
        sawInadequateFix = false
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(WeatherLocationAcquisitionPolicy.sessionTimeout))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let error: CurrentLocationError
            if self.sawLocationUnknown {
                error = .temporarilyUnavailable
            } else if self.sawInadequateFix {
                error = .inadequateAccuracy
            } else {
                error = .timedOut
            }
            self.finish(requestID, .failure(error))
        }
        startLocationIfAuthorized(requestID)
    }

    func cancelCurrentRequest() {
        guard let requestID = activeRequestID else { return }
        finish(requestID, .failure(.cancelled))
    }

    private func startLocationIfAuthorized(_ requestID: UUID) {
        guard activeRequestID == requestID else { return }
        guard CLLocationManager.locationServicesEnabled() else {
            finish(requestID, .failure(.servicesDisabled))
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied:
            finish(requestID, .failure(.authorizationDenied))
        case .restricted:
            finish(requestID, .failure(.authorizationRestricted))
        @unknown default:
            finish(requestID, .failure(.unexpected("unknown authorization state")))
        }
    }

    private func finish(_ requestID: UUID, _ result: Result<WeatherLocation, CurrentLocationError>) {
        guard activeRequestID == requestID else { return }
        manager.stopUpdatingLocation()
        timeoutTask?.cancel(); timeoutTask = nil
        reverseGeocodeTask?.cancel(); reverseGeocodeTask = nil
        reverseGeocodeTimeoutTask?.cancel(); reverseGeocodeTimeoutTask = nil
        reverseGeocodeRequest?.cancel(); reverseGeocodeRequest = nil
        activeRequestID = nil
        sawLocationUnknown = false
        sawInadequateFix = false
        let callback = completion
        completion = nil
        callback?(result)
    }

    private func weatherLocation(for location: CLLocation, mapItem: MKMapItem? = nil) -> WeatherLocation {
        let coordinate = location.coordinate
        let city = mapItem?.addressRepresentations?.cityName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let countryName = mapItem?.addressRepresentations?.regionName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let coordinateName = String(format: "当前位置 %.2f, %.2f", coordinate.latitude, coordinate.longitude)
        let name = city?.isEmpty == false ? city! : coordinateName
        let country = (countryName?.isEmpty == false ? countryName! : "定位坐标")
        return WeatherLocation(
            name: name, admin2: nil, admin1: nil, country: country,
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            timezone: TimeZone.current.identifier
        )
    }

    private func reverseGeocode(_ location: CLLocation, requestID: UUID) {
        manager.stopUpdatingLocation()
        timeoutTask?.cancel(); timeoutTask = nil
        let fallback = weatherLocation(for: location)
        guard let request = MKReverseGeocodingRequest(location: location) else {
            finish(requestID, .success(fallback))
            return
        }
        reverseGeocodeRequest = request
        reverseGeocodeTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(WeatherLocationAcquisitionPolicy.reverseGeocodeTimeout))
            guard !Task.isCancelled, let self else { return }
            self.reverseGeocodeTask?.cancel()
            self.finish(requestID, .success(fallback))
        }
        reverseGeocodeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let mapItems = try await request.mapItems
                guard !Task.isCancelled else { return }
                self.finish(requestID, .success(self.weatherLocation(for: location, mapItem: mapItems.first)))
            } catch is CancellationError {
                // The bounded fallback or a newer request owns completion.
            } catch {
                guard !Task.isCancelled else { return }
                self.finish(requestID, .success(fallback))
            }
        }
    }
}

extension CurrentLocationService: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let requestID = activeRequestID else { return }
        startLocationIfAuthorized(requestID)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let requestID = activeRequestID else { return }
        guard let location = locations.reversed().first(where: {
            WeatherLocationAcquisitionPolicy.accepts(timestamp: $0.timestamp, horizontalAccuracy: $0.horizontalAccuracy)
        }) else {
            // Keep the short session alive.  A low-quality cached location is
            // worse than no update because weather would jump to the wrong city.
            sawInadequateFix = true
            return
        }
        reverseGeocode(location, requestID: requestID)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let requestID = activeRequestID else { return }
        if let locationError = error as? CLError {
            switch locationError.code {
            case .locationUnknown:
                // This is explicitly transient.  Continue the bounded session
                // rather than making Wi-Fi positioning look like a network or
                // permission failure.
                sawLocationUnknown = true
                return
            case .denied:
                finish(requestID, .failure(.authorizationDenied))
                return
            default:
                break
            }
        }
        finish(requestID, .failure(.unexpected(error.localizedDescription)))
    }
}
