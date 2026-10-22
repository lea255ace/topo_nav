import Combine
import CoreLocation
import MapboxMaps

/// Builds the map's location data from the device GPS, with a steadier direction of travel.
///
/// The follow camera and puck turn to `Location.bearing`, which comes from `CLLocation.course`.
/// Raw course is jittery in mountain terrain, invalid (-1) at very low speeds, and missing
/// entirely in Xcode's GPX playback. See `BearingEstimator` for how it's cleaned up.
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

/// Produces a steady bearing for each fix:
///
/// 1. Uses the reported course when it's valid, reasonably accurate, and the device is moving.
/// 2. Otherwise derives it from movement since the last fix at least `minimumDistance` away.
/// 3. Holds the current bearing below walking speed, so the map doesn't spin while stopped.
/// 4. Eases toward each new measurement instead of jumping to it. The lag shrinks with speed
///    so the camera keeps up through switchbacks on fast roads.
final class BearingEstimator {
    /// Ignore smaller moves, which are dominated by GPS jitter.
    static let minimumDistance: CLLocationDistance = 5
    /// Below this speed (m/s, about 3 mph) course is unreliable, so the bearing is held.
    static let minimumSpeed: CLLocationSpeed = 1.5
    /// Reported courses less accurate than this (degrees) are treated as missing.
    static let maximumCourseError: CLLocationDirectionAccuracy = 30
    /// Easing time constants (seconds) at low and high speed.
    static let slowTimeConstant: TimeInterval = 1.2
    static let fastTimeConstant: TimeInterval = 0.5
    /// Speeds (m/s) between which the time constant shrinks from slow to fast.
    static let slowSpeed: CLLocationSpeed = 5
    static let fastSpeed: CLLocationSpeed = 30

    private var anchor: CLLocation?
    private var smoothedBearing: CLLocationDirection?
    private var lastTimestamp: Date?

    func withBearing(_ location: Location) -> Location {
        let position = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let speed = location.speed.flatMap { $0 >= 0 ? $0 : nil }

        let elapsed = lastTimestamp.map { location.timestamp.timeIntervalSince($0) } ?? 1
        lastTimestamp = location.timestamp

        if let measured = measuredBearing(for: location, at: position, speed: speed) {
            smoothedBearing = smoothedBearing.map {
                Self.ease($0, toward: measured, elapsed: elapsed, timeConstant: Self.timeConstant(for: speed))
            } ?? measured
        }
        guard let smoothedBearing else { return location }

        return Location(
            coordinate: location.coordinate,
            timestamp: location.timestamp,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            speed: location.speed,
            speedAccuracy: location.speedAccuracy,
            bearing: smoothedBearing,
            bearingAccuracy: nil,
            floor: location.floor,
            extra: location.extra
        )
    }

    /// The direction of travel measured at this fix, or nil to keep the current bearing.
    private func measuredBearing(for location: Location, at position: CLLocation, speed: CLLocationSpeed?) -> CLLocationDirection? {
        if let speed, speed < Self.minimumSpeed {
            return nil
        }

        if let reported = location.bearing, reported >= 0,
           (location.bearingAccuracy ?? 0) <= Self.maximumCourseError {
            anchor = position
            return reported
        }

        guard let anchor else {
            self.anchor = position
            return nil
        }
        guard position.distance(from: anchor) >= Self.minimumDistance else { return nil }
        self.anchor = position
        return Self.bearing(from: anchor.coordinate, to: position.coordinate)
    }

    /// Easing time constant for the current speed; unknown speed uses the midpoint.
    static func timeConstant(for speed: CLLocationSpeed?) -> TimeInterval {
        guard let speed else { return (slowTimeConstant + fastTimeConstant) / 2 }
        let fraction = min(max((speed - slowSpeed) / (fastSpeed - slowSpeed), 0), 1)
        return slowTimeConstant + (fastTimeConstant - slowTimeConstant) * fraction
    }

    /// Moves `current` toward `target` along the shorter way around the compass.
    static func ease(_ current: CLLocationDirection, toward target: CLLocationDirection,
                     elapsed: TimeInterval, timeConstant: TimeInterval) -> CLLocationDirection {
        let step = 1 - exp(-min(max(elapsed, 0), 5) / timeConstant)
        var delta = (target - current).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
        let eased = current + delta * step
        return (eased + 360).truncatingRemainder(dividingBy: 360)
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
