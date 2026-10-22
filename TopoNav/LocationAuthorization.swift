import CoreLocation
import Observation

/// Tracks the app's location permission and requests it when needed.
/// Mapbox's location provider reads positions itself; this only handles authorization
/// so the UI can react when access is denied.
@Observable
final class LocationAuthorization: NSObject, CLLocationManagerDelegate {
    private(set) var status: CLAuthorizationStatus

    private let manager = CLLocationManager()

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var isAuthorized: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    var isDenied: Bool {
        status == .denied || status == .restricted
    }

    func requestIfNeeded() {
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
    }
}
