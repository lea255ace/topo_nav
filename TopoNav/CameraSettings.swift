import Foundation
import Observation

/// Camera, terrain and direction-of-travel parameters for the follow view.
///
/// The defaults below are the shipped values. In debug builds they can be tuned live from the
/// camera tuning panel, and the tuned values are saved between launches.
struct CameraTuning: Codable, Equatable {
    /// Camera tilt in degrees: 0 looks straight down, 85 (Mapbox's maximum) is near the horizon.
    var pitch: Double = 60
    /// Follow-mode zoom level; higher sits closer to the puck.
    var followZoom: Double = 14.5
    /// Moves the puck down the screen by this many points, showing more of the road ahead.
    var puckOffset: Double = 0
    var terrainExaggeration: Double = 1.5
    /// Distance haze: fades terrain from clear (`fogStart`) to fully hazy (`fogEnd`). Measured
    /// from the map's center point, so negative values are nearer the camera.
    var fogStart: Double = 1
    var fogEnd: Double = 12
    /// How far up the sky the horizon haze extends (0 = a sharp horizon line).
    var horizonBlend: Double = 0.1
    /// Haze opacity: 1 is full strength, 0 turns the haze off. (Mapbox has no separate fog
    /// intensity; this is the fog color's alpha. Below 1, Mapbox loads and draws more tiles.)
    var hazeStrength: Double = 1
    /// How much wider the route line gets far from you, to offset perspective thinning it.
    var routeFarWidth: Double = 2.5
    /// Straight-line distance from you, in meters, at which the route reaches `routeFarWidth`.
    var routeFarDistance: Double = 4000
    /// Scales how long the camera takes to turn to a new direction: higher is steadier but lags more.
    var smoothing: Double = 1
    /// How far along the active route the camera looks ahead, in meters.
    var lookAheadDistance: Double = 250
    /// How far the camera turns toward the route ahead: 0 follows the current direction of
    /// travel only, 1 points at the look-ahead point on the route.
    var lookAheadWeight: Double = 0

    static let defaults = CameraTuning()

    /// The values as Swift, for pasting back into the defaults above.
    var summary: String {
        """
        pitch: \(pitch.formatted()), followZoom: \(followZoom.formatted()), puckOffset: \(puckOffset.formatted()), \
        terrainExaggeration: \(terrainExaggeration.formatted()), fogStart: \(fogStart.formatted()), \
        fogEnd: \(fogEnd.formatted()), horizonBlend: \(horizonBlend.formatted()), hazeStrength: \(hazeStrength.formatted()), \
        routeFarWidth: \(routeFarWidth.formatted()), routeFarDistance: \(routeFarDistance.formatted()), smoothing: \(smoothing.formatted()), \
        lookAheadDistance: \(lookAheadDistance.formatted()), lookAheadWeight: \(lookAheadWeight.formatted())
        """
    }
}

/// Holds the current `CameraTuning`, persisting changes in debug builds.
@Observable
final class CameraSettings {
    private static let storageKey = "CameraTuning"

    var tuning: CameraTuning {
        didSet { save() }
    }

    init() {
#if DEBUG
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = (try? JSONDecoder().decode(CameraTuning.self, from: data)) ?? Self.migrate(data) {
            tuning = saved
            return
        }
#endif
        tuning = .defaults
    }

    /// Keeps tuning saved by an older build, filling settings it didn't have with defaults.
    private static func migrate(_ data: Data) -> CameraTuning? {
        guard let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var merged = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(CameraTuning.defaults))) as? [String: Any]
        else { return nil }
        merged.merge(saved) { _, savedValue in savedValue }
        guard let json = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(CameraTuning.self, from: json)
    }

    func reset() {
        tuning = .defaults
    }

    private func save() {
#if DEBUG
        if let data = try? JSONEncoder().encode(tuning) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
#endif
    }
}
