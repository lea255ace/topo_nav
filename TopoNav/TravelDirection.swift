import Combine
import CoreLocation
import MapboxMaps

/// Builds the map's location data from the device GPS, filling in the direction of travel
/// when Core Location doesn't report one.
///
/// The follow camera and puck turn to `Location.bearing`, which comes from `CLLocation.course`.
/// Course is invalid (-1) at very low speeds and in Xcode's GPX playback, which would leave
/// the map stuck facing north. In those cases this derives the bearing from successive
/// positions, and holds the last known bearing while stopped.
final class TravelDirection {
    let dataModel: LocationDataModel

    /// The provider's signals don't retain it, so this object owns it for the map's lifetime.
    private let provider = AppleLocationProvider()
    private let estimator = BearingEstimator()

    init() {
        let estimator = estimator
        let locations = provider.onLocationUpdate
            .map { batch in batch.map(estimator.withBearing) }
            .eraseToAnyPublisher()
        dataModel = LocationDataModel(location: locations, heading: provider.onHeadingUpdate.eraseToAnyPublisher())
    }
}

/// Fills in a missing bearing from movement between fixes.
final class BearingEstimator {
    /// Ignore smaller moves, which are dominated by GPS jitter.
    static let minimumDistance: CLLocationDistance = 5

    private var anchor: CLLocation?
    private var lastBearing: CLLocationDirection?

    func withBearing(_ location: Location) -> Location {
        let position = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)

        if let reported = location.bearing, reported >= 0 {
            anchor = position
            lastBearing = reported
            return location
        }

        guard let anchor else {
            self.anchor = position
            return location
        }

        if position.distance(from: anchor) >= Self.minimumDistance {
            lastBearing = Self.bearing(from: anchor.coordinate, to: position.coordinate)
            self.anchor = position
        }
        guard let lastBearing else { return location }

        return Location(
            coordinate: location.coordinate,
            timestamp: location.timestamp,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            speed: location.speed,
            speedAccuracy: location.speedAccuracy,
            bearing: lastBearing,
            bearingAccuracy: nil,
            floor: location.floor,
            extra: location.extra
        )
    }

    /// Initial great-circle bearing in degrees clockwise from true north.
    static func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLon = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}
