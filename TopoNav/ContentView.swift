import SwiftUI
import MapboxMaps

/// Root map screen: a tilted 3D terrain view, starting at Donner Pass, CA.
/// Location following and routing are added in later build steps.
struct ContentView: View {
    static let donnerPass = CLLocationCoordinate2D(latitude: 39.3157, longitude: -120.3291)
    static let pitch: CGFloat = 60
    static let terrainExaggeration: Double = 1.5

    @State private var viewport: Viewport = .camera(center: donnerPass, zoom: 12.5, bearing: 0, pitch: pitch)
    @State private var baseStyle: BaseStyle = .satelliteStreets

    var body: some View {
        Map(viewport: $viewport) {
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
