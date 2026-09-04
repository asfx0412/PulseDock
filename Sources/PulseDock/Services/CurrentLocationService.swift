@preconcurrency import CoreLocation
import Foundation

enum CurrentLocationError: LocalizedError {
    case servicesDisabled
    case authorizationDenied
    case authorizationRestricted
    case temporarilyUnavailable
    case inadequateAccuracy
    case timedOut
    case reverseGeocodeFailed
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
        case .reverseGeocodeFailed:
            "已取得位置，但暂时无法确认城市名称"
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
        case .servicesDisabled: WeatherLocationDiagnosticKind.servicesDisabled.label
        case .authorizationDenied: WeatherLocationDiagnosticKind.authorizationDenied.label
        case .authorizationRestricted: WeatherLocationDiagnosticKind.authorizationRestricted.label
        case .temporarilyUnavailable: WeatherLocationDiagnosticKind.locationUnknown.label
        case .inadequateAccuracy: WeatherLocationDiagnosticKind.inadequateAccuracy.label
        case .timedOut: WeatherLocationDiagnosticKind.timedOut.label
        case .reverseGeocodeFailed: WeatherLocationDiagnosticKind.reverseGeocodeFailed.label
        case .cancelled: WeatherLocationDiagnosticKind.cancelled.label
        case .unexpected: WeatherLocationDiagnosticKind.unexpected.label
        }
    }

    var supportsAutomaticRetry: Bool {
        switch self {
        case .temporarilyUnavailable, .inadequateAccuracy, .timedOut, .reverseGeocodeFailed, .unexpected:
            true
        case .servicesDisabled, .authorizationDenied, .authorizationRestricted, .cancelled:
            false
        }
    }

    var diagnosticKind: WeatherLocationDiagnosticKind {
        switch self {
        case .servicesDisabled: .servicesDisabled
        case .authorizationDenied: .authorizationDenied
        case .authorizationRestricted: .authorizationRestricted
        case .temporarilyUnavailable: .locationUnknown
        case .inadequateAccuracy: .inadequateAccuracy
        case .timedOut: .timedOut
        case .reverseGeocodeFailed: .reverseGeocodeFailed
        case .cancelled: .cancelled
        case .unexpected: .unexpected
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
    private var completion: ((Result<WeatherLocationCandidate, CurrentLocationError>) -> Void)?
    private var timeoutTask: Task<Void, Never>?
    private var reverseGeocodeTask: Task<Void, Never>?
    private var sawLocationUnknown = false
    private var sawInadequateFix = false
    private var bestRecentReusableLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestCurrentCity(completion: @escaping (Result<WeatherLocationCandidate, CurrentLocationError>) -> Void) {
        guard activeRequestID == nil else {
            completion(.failure(.unexpected("a location request is already active")))
            return
        }
        let requestID = UUID()
        activeRequestID = requestID
        self.completion = completion
        sawLocationUnknown = false
        sawInadequateFix = false
        bestRecentReusableLocation = nil
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(WeatherLocationAcquisitionPolicy.sessionTimeout))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            if let reusable = self.bestRecentReusableLocation {
                self.reverseGeocode(reusable, evidence: .recentReusable, requestID: requestID)
                return
            }
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

    private func finish(_ requestID: UUID, _ result: Result<WeatherLocationCandidate, CurrentLocationError>) {
        guard activeRequestID == requestID else { return }
        manager.stopUpdatingLocation()
        timeoutTask?.cancel(); timeoutTask = nil
        reverseGeocodeTask?.cancel(); reverseGeocodeTask = nil
        activeRequestID = nil
        sawLocationUnknown = false
        sawInadequateFix = false
        bestRecentReusableLocation = nil
        let callback = completion
        completion = nil
        callback?(result)
    }

    private func resolvedWeatherLocation(for location: CLLocation, placemark: CLPlacemark) -> WeatherLocation? {
        func clean(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        // `subLocality` is district/county; `locality` is city;
        // `administrativeArea` is province/state.  We do not map a generic
        // region label to country, which caused the 6.14.1 name regression.
        let district = clean(placemark.subLocality)
        let city = clean(placemark.locality) ?? clean(placemark.subAdministrativeArea)
        let province = clean(placemark.administrativeArea)
        guard let country = clean(placemark.country), let name = district ?? city ?? province else { return nil }
        return WeatherLocation(
            name: name,
            admin2: district == nil ? nil : city,
            admin1: province,
            country: country,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timezone: TimeZone.current.identifier
        )
    }

    private func reverseGeocode(_ location: CLLocation, evidence: WeatherLocationEvidence, requestID: UUID) {
        manager.stopUpdatingLocation()
        timeoutTask?.cancel(); timeoutTask = nil
        // Never represent coordinates as a city.  The location/weather pair
        // is committed only after a complete administrative name resolves.
        reverseGeocodeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let placemarks = try await Self.reverseGeocode(location)
                guard !Task.isCancelled,
                      let placemark = placemarks.first,
                      let resolved = self.resolvedWeatherLocation(for: location, placemark: placemark) else {
                    self.finish(requestID, .failure(.reverseGeocodeFailed))
                    return
                }
                self.finish(requestID, .success(WeatherLocationCandidate(
                    location: resolved, evidence: evidence, horizontalAccuracy: location.horizontalAccuracy
                )))
            } catch is CancellationError {
                // A newer selection or explicit cancellation owns completion.
            } catch {
                guard !Task.isCancelled else { return }
                self.finish(requestID, .failure(.reverseGeocodeFailed))
            }
        }
    }

    private static func reverseGeocode(_ location: CLLocation) async throws -> [CLPlacemark] {
        let geocoder = CLGeocoder()
        return try await withThrowingTaskGroup(of: [CLPlacemark].self) { group in
            group.addTask { try await geocoder.reverseGeocodeLocation(location) }
            group.addTask {
                try await Task.sleep(for: .seconds(WeatherLocationAcquisitionPolicy.reverseGeocodeTimeout))
                throw CurrentLocationError.reverseGeocodeFailed
            }
            guard let result = try await group.next() else { throw CurrentLocationError.reverseGeocodeFailed }
            group.cancelAll()
            return result
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
        if let location = locations.reversed().first(where: {
            WeatherLocationAcquisitionPolicy.accepts(timestamp: $0.timestamp, horizontalAccuracy: $0.horizontalAccuracy)
        }) {
            reverseGeocode(location, evidence: .fresh, requestID: requestID)
            return
        }
        if let reusable = locations.reversed().first(where: {
            WeatherLocationAcquisitionPolicy.acceptsRecentReusable(timestamp: $0.timestamp, horizontalAccuracy: $0.horizontalAccuracy)
        }) {
            // Continue waiting for a fresh fix.  If none arrives, this result
            // may only confirm the existing administrative area downstream.
            if bestRecentReusableLocation == nil || reusable.timestamp > bestRecentReusableLocation!.timestamp {
                bestRecentReusableLocation = reusable
            }
            return
        }
        sawInadequateFix = true
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
