import SwiftUI
import MapboxMaps

/// Root map screen: a tilted 3D terrain view that follows the user's position,
/// starting at Donner Pass, CA until location is available.
/// Routing is added in a later build step.
struct ContentView: View {
    static let donnerPass = CLLocationCoordinate2D(latitude: 39.3157, longitude: -120.3291)
    static let pitch: CGFloat = 60
    static let followZoom: CGFloat = 14.5
    static let terrainExaggeration: Double = 1.5

    /// Trails behind the puck and rotates to match the direction of travel.
    static let followViewport: Viewport = .followPuck(zoom: followZoom, bearing: .course, pitch: pitch)

    @State private var viewport: Viewport = .camera(center: donnerPass, zoom: 12.5, bearing: 0, pitch: pitch)
    @State private var baseStyle: BaseStyle = .satelliteStreets
    @State private var location = LocationAuthorization()

    /// The map sets `viewport` to idle as soon as the user drags or rotates it.
    private var isFollowing: Bool { viewport.followPuck != nil }

    var body: some View {
        Map(viewport: $viewport) {
            if location.isAuthorized {
                Puck2D(bearing: .course)
            }

            RasterDemSource(id: "mapbox-dem")
                .url("mapbox://mapbox.mapbox-terrain-dem-v1")
                .maxzoom(14)
            Terrain(sourceId: "mapbox-dem")
                .exaggeration(Self.terrainExaggeration)
            SkyLayer(id: "sky")
                .skyType(.atmosphere)
                .skyAtmosphereSunIntensity(15)
        }
        .mapStyle(baseStyle.mapStyle)
        // The compass's tap-to-north fights the course-up follow camera, and sticks
        // whenever there are no new course updates, so only offer it once the user
        // has taken manual control of the camera.
        .ornamentOptions(OrnamentOptions(
            compass: CompassViewOptions(visibility: isFollowing ? .hidden : .adaptive)
        ))
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            Picker("Map style", selection: $baseStyle) {
                ForEach(BaseStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            .padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            if location.isDenied {
                LocationDeniedBanner()
            }
        }
        .onAppear {
            if location.isAuthorized {
                viewport = Self.followViewport
            } else {
                location.requestIfNeeded()
            }
        }
        .onChange(of: location.isAuthorized) { _, isAuthorized in
            guard isAuthorized else { return }
            withViewportAnimation(.default(maxDuration: 2)) {
                viewport = Self.followViewport
            }
        }
    }
}

/// The base map styles the user can switch between.
enum BaseStyle: String, CaseIterable, Identifiable {
    case satelliteStreets
    case outdoors

    var id: Self { self }

    var title: String {
        switch self {
        case .satelliteStreets: "Satellite"
        case .outdoors: "Outdoors"
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .satelliteStreets: .satelliteStreets
        case .outdoors: .outdoors
        }
    }
}

#Preview {
    ContentView()
}
