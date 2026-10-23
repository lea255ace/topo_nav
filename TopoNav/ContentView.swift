import SwiftUI
import MapboxMaps

/// Root map screen: a tilted 3D terrain view that follows the user's position,
/// starting at Donner Pass, CA until location is available.
/// Long-press the map to drop a destination and draw a driving route to it.
struct ContentView: View {
    static let donnerPass = CLLocationCoordinate2D(latitude: 39.3157, longitude: -120.3291)

    @State private var settings: CameraSettings
    @State private var viewport: Viewport
    @State private var baseStyle: BaseStyle = .satelliteStreets
    @State private var location = LocationAuthorization()
    @State private var travelDirection = TravelDirection()
#if DEBUG
    @State private var showsTuning = false
#endif

    @State private var destination: CLLocationCoordinate2D?
    @State private var route: Route?
    @State private var routeTask: Task<Void, Never>?
    @State private var isRouting = false
    @State private var routeError: String?

    private let directions = DirectionsClient()

    init() {
        let settings = CameraSettings()
        _settings = State(initialValue: settings)
        _viewport = State(initialValue: .camera(center: Self.donnerPass, zoom: 12.5, bearing: 0,
                                                pitch: settings.tuning.pitch))
    }

    /// The map sets `viewport` to idle as soon as the user drags or rotates it.
    private var isFollowing: Bool { viewport.followPuck != nil }

    /// Trails behind the puck and turns with the camera bearing (see `TravelDirection`).
    private var followViewport: Viewport {
        let tuning = settings.tuning
        return Viewport.followPuck(zoom: tuning.followZoom, bearing: .course, pitch: tuning.pitch)
            .padding(.top, tuning.puckOffset)
    }

    var body: some View {
        MapReader { proxy in
            map(proxy: proxy)
        }
    }

    private func map(proxy: MapProxy) -> some View {
        Map(viewport: $viewport) {
            if location.isAuthorized {
                Puck2D(bearing: .heading)
            }

            RasterDemSource(id: "mapbox-dem")
                .url("mapbox://mapbox.mapbox-terrain-dem-v1")
                .maxzoom(14)
            Terrain(sourceId: "mapbox-dem")
                .exaggeration(settings.tuning.terrainExaggeration)
            SkyLayer(id: "sky")
                .skyType(.atmosphere)
                .skyAtmosphereSunIntensity(15)

            if let route {
                RouteLine(route: route)
            }
            if let destination {
                MapViewAnnotation(coordinate: destination) {
                    DestinationPin()
                }
                .variableAnchors([ViewAnnotationAnchorConfig(anchor: .bottom)])
                .allowOverlap(true)
            }

            LongPressInteraction { context in
                requestRoute(to: context.coordinate, from: proxy.location?.latestLocation?.coordinate)
                return true
            }
        }
        .mapStyle(baseStyle.mapStyle)
        .locationDataModel(travelDirection.dataModel)
        // The compass's tap-to-north fights the course-up follow camera, and sticks
        // whenever there are no new course updates, so only offer it once the user
        // has taken manual control of the camera.
        .ornamentOptions(OrnamentOptions(
            compass: CompassViewOptions(visibility: isFollowing ? .hidden : .adaptive)
        ))
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Picker("Map style", selection: $baseStyle) {
                        ForEach(BaseStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                    .padding(6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
#if DEBUG
                    Button {
                        showsTuning.toggle()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .accessibilityLabel("Camera tuning")
#endif
                }

                if isRouting {
                    Label {
                        Text("Finding route…")
                    } icon: {
                        ProgressView()
                    }
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                }
                if let routeError {
                    RouteErrorBanner(message: routeError)
                }
            }
            .padding(.top, 8)
            .animation(.default, value: isRouting)
            .animation(.default, value: routeError)
        }
        .task(id: routeError) {
            // Hide the error after a few seconds.
            guard routeError != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            routeError = nil
        }
        .overlay(alignment: .bottom) {
            if location.isDenied {
                LocationDeniedBanner()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if location.isAuthorized && !isFollowing {
                RecenterButton(action: startFollowing)
            }
        }
        .onAppear {
            if location.isAuthorized {
                viewport = followViewport
            } else {
                location.requestIfNeeded()
            }
        }
        .onChange(of: location.isAuthorized) { _, isAuthorized in
            guard isAuthorized else { return }
            startFollowing()
        }
        .onChange(of: settings.tuning, initial: true) { _, tuning in
            travelDirection.tuning = tuning
            // Apply camera changes straight away while following.
            if isFollowing {
                withViewportAnimation(.default(maxDuration: 0.4)) {
                    viewport = followViewport
                }
            }
        }
        .onChange(of: route, initial: true) { _, route in
            travelDirection.route = route?.coordinates
        }
#if DEBUG
        .sheet(isPresented: $showsTuning) {
            CameraTuningPanel(settings: settings)
        }
#endif
    }

    private func startFollowing() {
        withViewportAnimation(.default(maxDuration: 2)) {
            viewport = followViewport
        }
    }

    /// Drops a destination pin and replaces any existing route with a new one from `origin`.
    private func requestRoute(to target: CLLocationCoordinate2D, from origin: CLLocationCoordinate2D?) {
        routeTask?.cancel()
        destination = target
        route = nil
        routeError = nil
        isRouting = false

        guard let origin else {
            routeError = location.isAuthorized
                ? "Waiting for your location. Try again in a moment."
                : "Turn on location access to plan a route from where you are."
            return
        }

        isRouting = true
        routeTask = Task {
            do {
                let newRoute = try await directions.route(from: origin, to: target)
                guard !Task.isCancelled else { return }
                route = newRoute
            } catch {
                // A newer long press cancelled this request; it owns the UI now.
                guard !Task.isCancelled else { return }
                routeError = error.localizedDescription
            }
            isRouting = false
        }
    }
}

/// The route drawn as a thick, high-contrast line draped over the terrain:
/// a bright core on a dark casing so it reads on both satellite and Outdoors.
struct RouteLine: MapStyleContent {
    static let sourceId = "route"
    /// Draw under the base style's labels so place and road names stay readable.
    /// Both Satellite Streets and Outdoors have this layer.
    static let labelLayerId = "road-label"
    /// Declarative layers can only be positioned through a slot, so anchor one below the labels.
    static let slot: Slot = "below-labels"

    let route: Route

    var body: some MapStyleContent {
        SlotLayer(id: Self.slot.rawValue)
            .position(.below(Self.labelLayerId))
        GeoJSONSource(id: Self.sourceId)
            .data(.geometry(.lineString(LineString(route.coordinates))))
        LineLayer(id: "route-casing", source: Self.sourceId)
            .lineColor(UIColor(white: 0.05, alpha: 0.85))
            .lineWidth(10)
            .lineJoin(.round)
            .lineCap(.round)
            .slot(Self.slot)
        LineLayer(id: "route-line", source: Self.sourceId)
            .lineColor(UIColor(red: 1.0, green: 0.18, blue: 0.62, alpha: 1))
            .lineWidth(6)
            .lineJoin(.round)
            .lineCap(.round)
            .slot(Self.slot)
    }
}

/// The destination marker, anchored at its bottom point.
struct DestinationPin: View {
    var body: some View {
        Image(systemName: "mappin")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Circle().fill(.red))
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .padding(.bottom, 4)
            .shadow(radius: 3)
            .accessibilityLabel("Destination")
    }
}

/// A short error message shown under the style picker when a route request fails.
struct RouteErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Returns the camera to follow mode after the user has panned or rotated the map.
struct RecenterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Recenter", systemImage: "location.north.line.fill")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(.blue, in: Capsule())
        .shadow(radius: 4)
        .padding(.trailing, 16)
        // Sit above the Mapbox attribution button, which must stay visible.
        .padding(.bottom, 52)
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
