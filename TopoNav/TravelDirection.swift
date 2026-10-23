import Combine
import CoreLocation
import MapboxMaps

/// Builds the map's location data from the device GPS, with a steadier direction of travel and
/// an optional look-ahead along the active route.
///
/// The map gets two bearings per fix:
/// - `Location.bearing` drives the follow camera (`FollowPuckViewportStateBearing.course`). It's
///   the smoothed direction of travel, blended toward the route ahead when look-ahead is on.
/// - The heading stream drives the puck's arrow (`PuckBearing.heading`), and is always the
///   smoothed direction of travel, so the arrow shows where you're actually going.
///
/// Raw course is jittery in mountain terrain, invalid (-1) at very low speeds, and missing
/// entirely in Xcode's GPX playback. See `BearingEstimator` for how it's cleaned up.
final class TravelDirection {
    /// Created on first use, once `self` can be captured by the location pipeline.
    lazy var dataModel: LocationDataModel = {
        let locations = provider.onLocationUpdate
            .map { [weak self] batch in batch.map { self?.process($0) ?? $0 } }
            .eraseToAnyPublisher()
        return LocationDataModel(location: locations, heading: headings.eraseToAnyPublisher())
    }()

    /// Current tuning, updated by the view when the settings change.
    var tuning = CameraTuning.defaults
    /// The active route's geometry, or nil when no route is shown.
    var route: [CLLocationCoordinate2D]? {
        didSet { lookAhead = route.flatMap(RouteLookAhead.init) }
    }

    /// The provider's signals don't retain it, so this object owns it for the map's lifetime.
    private let provider = AppleLocationProvider()
    private let estimator = BearingEstimator()
    private let headings = PassthroughSubject<Heading, Never>()
    private var lookAhead: RouteLookAhead?

    private func process(_ location: Location) -> Location {
        let lookAhead = lookAhead
        let distance = tuning.lookAheadDistance
        guard let bearings = estimator.update(
            location,
            tuning: tuning,
            routeBearing: { lookAhead?.bearing(from: $0, lookingAhead: distance) }
        ) else { return location }

        headings.send(Heading(direction: bearings.travel, accuracy: 5, timestamp: location.timestamp))
        return Location(
            coordinate: location.coordinate,
            timestamp: location.timestamp,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            speed: location.speed,
            speedAccuracy: location.speedAccuracy,
            bearing: bearings.camera,
            bearingAccuracy: nil,
            floor: location.floor,
            extra: location.extra
        )
    }
}

/// Produces steady bearings for each fix:
///
/// 1. Uses the reported course when it's valid, reasonably accurate, and the device is moving.
/// 2. Otherwise derives it from movement since the last fix at least `minimumDistance` away.
/// 3. Holds the current bearings below walking speed, so the map doesn't spin while stopped.
/// 4. For the camera, blends the direction of travel toward the route ahead by the tuned weight.
/// 5. Eases toward each new measurement instead of jumping to it. The lag shrinks with speed
///    so the camera keeps up through switchbacks on fast roads.
final class BearingEstimator {
    /// Ignore smaller moves, which are dominated by GPS jitter.
    static let minimumDistance: CLLocationDistance = 5
    /// Below this speed (m/s, about 3 mph) course is unreliable, so the bearing is held.
    static let minimumSpeed: CLLocationSpeed = 1.5
    /// Reported courses less accurate than this (degrees) are treated as missing.
    static let maximumCourseError: CLLocationDirectionAccuracy = 30
    /// Easing time constants (seconds) at low and high speed, before `CameraTuning.smoothing`.
    static let slowTimeConstant: TimeInterval = 1.2
    static let fastTimeConstant: TimeInterval = 0.5
    /// Speeds (m/s) between which the time constant shrinks from slow to fast.
    static let slowSpeed: CLLocationSpeed = 5
    static let fastSpeed: CLLocationSpeed = 30

    struct Bearings {
        /// Smoothed direction of travel.
        var travel: CLLocationDirection
        /// Smoothed camera bearing: travel blended toward the route ahead.
        var camera: CLLocationDirection
    }

    private var anchor: CLLocation?
    private var travel: CLLocationDirection?
    private var camera: CLLocationDirection?
    private var lastTimestamp: Date?

    /// Updates the bearings for a new fix. `routeBearing` returns the direction from a position
    /// to the look-ahead point on the route, or nil when there's no route or you're off it.
    func update(_ location: Location, tuning: CameraTuning,
                routeBearing: (CLLocationCoordinate2D) -> CLLocationDirection?) -> Bearings? {
        let position = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let speed = location.speed.flatMap { $0 >= 0 ? $0 : nil }

        let elapsed = lastTimestamp.map { location.timestamp.timeIntervalSince($0) } ?? 1
        lastTimestamp = location.timestamp

        if let measured = measuredBearing(for: location, at: position, speed: speed) {
            var target = measured
            if tuning.lookAheadWeight > 0, let ahead = routeBearing(location.coordinate) {
                target = Self.blend(measured, toward: ahead, weight: tuning.lookAheadWeight)
            }
            let timeConstant = Self.timeConstant(for: speed) * tuning.smoothing
            travel = travel.map { Self.ease($0, toward: measured, elapsed: elapsed, timeConstant: timeConstant) } ?? measured
            camera = camera.map { Self.ease($0, toward: target, elapsed: elapsed, timeConstant: timeConstant) } ?? target
        }
        guard let travel, let camera else { return nil }
        return Bearings(travel: travel, camera: camera)
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
        let step = 1 - exp(-min(max(elapsed, 0), 5) / max(timeConstant, 0.01))
        return blend(current, toward: target, weight: step)
    }

    /// The bearing `weight` of the way from `start` to `end`, turning the shorter way.
    static func blend(_ start: CLLocationDirection, toward end: CLLocationDirection, weight: Double) -> CLLocationDirection {
        var delta = (end - start).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
        return (start + delta * weight + 360).truncatingRemainder(dividingBy: 360)
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

/// Finds where the route goes a set distance ahead of the current position.
struct RouteLookAhead {
    /// Farther than this from the route (meters) counts as off it, so look-ahead is skipped.
    static let maximumOffRoute: CLLocationDistance = 60
    /// Look-ahead points closer than this (meters), as at the end of the route, are ignored.
    static let minimumLookAhead: CLLocationDistance = 20

    private let points: [CLLocationCoordinate2D]
    /// Distance along the route to each point, in meters.
    private let cumulative: [CLLocationDistance]

    init?(_ points: [CLLocationCoordinate2D]) {
        guard points.count >= 2 else { return nil }
        self.points = points
        var total: CLLocationDistance = 0
        var cumulative = [total]
        for (a, b) in zip(points, points.dropFirst()) {
            total += CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            cumulative.append(total)
        }
        self.cumulative = cumulative
    }

    /// The bearing from `position` to the point `distance` meters further along the route,
    /// or nil when `position` is off the route.
    func bearing(from position: CLLocationCoordinate2D, lookingAhead distance: CLLocationDistance) -> CLLocationDirection? {
        guard let along = distanceAlongRoute(nearest: position) else { return nil }
        let ahead = point(at: along + distance)
        let separation = CLLocation(latitude: position.latitude, longitude: position.longitude)
            .distance(from: CLLocation(latitude: ahead.latitude, longitude: ahead.longitude))
        guard separation >= Self.minimumLookAhead else { return nil }
        return BearingEstimator.bearing(from: position, to: ahead)
    }

    /// Distance along the route of the point nearest `position`, if it's within `maximumOffRoute`.
    private func distanceAlongRoute(nearest position: CLLocationCoordinate2D) -> CLLocationDistance? {
        // Project into local meters around `position`; accurate enough over a route's length.
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = metersPerDegreeLat * cos(position.latitude * .pi / 180)
        func local(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            ((c.longitude - position.longitude) * metersPerDegreeLon, (c.latitude - position.latitude) * metersPerDegreeLat)
        }

        var best: (distance: Double, along: Double)?
        var a = local(points[0])
        for i in 1..<points.count {
            let b = local(points[i])
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared > 0 ? min(max(-(a.x * dx + a.y * dy) / lengthSquared, 0), 1) : 0
            let px = a.x + t * dx, py = a.y + t * dy
            let offset = (px * px + py * py).squareRoot()
            if offset < (best?.distance ?? .infinity) {
                best = (offset, cumulative[i - 1] + t * (cumulative[i] - cumulative[i - 1]))
            }
            a = b
        }
        guard let best, best.distance <= Self.maximumOffRoute else { return nil }
        return best.along
    }

    /// The point `along` meters from the start of the route, clamped to its end.
    private func point(at along: CLLocationDistance) -> CLLocationCoordinate2D {
        guard along < cumulative[cumulative.count - 1] else { return points[points.count - 1] }
        var low = 0, high = cumulative.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if cumulative[mid] <= along { low = mid } else { high = mid }
        }
        let span = cumulative[high] - cumulative[low]
        let t = span > 0 ? (along - cumulative[low]) / span : 0
        let a = points[low], b = points[high]
        return CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                      longitude: a.longitude + (b.longitude - a.longitude) * t)
    }
}
