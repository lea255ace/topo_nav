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
        terrainExaggeration: \(terrainExaggeration.formatted()), smoothing: \(smoothing.formatted()), \
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
           let saved = try? JSONDecoder().decode(CameraTuning.self, from: data) {
            tuning = saved
            return
        }
#endif
        tuning = .defaults
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
