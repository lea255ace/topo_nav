import SwiftUI
import MapboxMaps

/// Root map screen. Starts at Donner Pass, CA; terrain, location and routing
/// are added in the following build steps.
struct ContentView: View {
    static let donnerPass = CLLocationCoordinate2D(latitude: 39.3157, longitude: -120.3291)

    @State private var viewport: Viewport = .camera(center: donnerPass, zoom: 12.5, bearing: 0, pitch: 0)

    var body: some View {
        Map(viewport: $viewport)
            .mapStyle(.satelliteStreets)
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
