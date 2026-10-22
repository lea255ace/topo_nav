# 3D Topo Navigation — First Version Plan

## Concept

An iPhone app for live, route-based navigation shown on a 3D terrain view, so the driver can see why the road curves the way it does — through mountain passes, along rivers — instead of reading a flat top-down map. It's a personal project, and could later be released as open source for technically minded users to build themselves, using their own Mapbox access token.

## Tech Stack

- **Language/UI:** Swift, SwiftUI
- **Map and 3D terrain:** Mapbox Maps SDK for iOS (added via Swift Package Manager)
- **Routing:** Mapbox Directions API
- **Position:** Core Location (device GPS), plus Mapbox's location marker and follow mode
- **Later:** Mapbox Navigation SDK for spoken turn-by-turn directions and rerouting

Why not Google Maps: Google's terms generally don't allow showing its route data on a map that isn't Google's, and live navigation is supposed to go through Google's Navigation SDK.

## Build Steps

1. **Project setup.** Create a SwiftUI app. Add the Mapbox Maps SDK through Swift Package Manager, and put the Mapbox access token in Info.plist.
2. **Terrain view.** Show a map using the satellite or outdoors style. Turn on the terrain layer with some exaggeration (start around 1.5), and tilt the camera to roughly 60°.
3. **Location.** Request location permission and turn on the position marker. Use the map's follow mode so the camera trails behind you and points in the direction you're driving.
4. **Route.** Let yourself pick a destination by long-pressing the map. Fetch the route from the Directions API and draw it as a thick, high-contrast line on the terrain.
5. **Test.** Use Xcode's simulated GPS routes first, then try it on a real twisty mountain road (with a passenger, or mounted and hands-off).

## Next Ideas

- Destination search
- Rerouting when you go off course
- A zoomed-out view showing the whole valley or pass
- Spoken turn-by-turn directions with the Navigation SDK
- Adjustable terrain exaggeration and camera angle

## Open-Source Notes

- Keep the access token out of source control and document how users should add their own.
- Explain in the README how to get a Mapbox token and stay within the free tier.

## Claude Code Handoff Spec

Build Version 1 exactly as specified below. Stop when every acceptance check passes, and don't start the Next Ideas items.

### Fixed decisions

- **Xcode project / app name:** TopoNav
- **Minimum iOS version:** iOS 17.0
- **Language/UI:** Swift 5.9+, SwiftUI app lifecycle
- **Map SDK:** Mapbox Maps SDK for iOS v11.x, added via Swift Package Manager (`mapbox-maps-ios`)
- **Routing:** Mapbox Directions API v5, `driving-traffic` profile, `geometries=geojson`, called directly with URLSession (not the Navigation SDK in v1)
- **Map style:** Mapbox Satellite Streets by default, with a toggle for Outdoors
- **Terrain:** `mapbox-dem` raster-dem source, exaggeration 1.5, plus a sky layer
- **Camera:** pitch 60°, follows the user and turns to match their heading while driving
- **No third-party dependencies** other than Mapbox

### Token handling

- The token lives in `Config/Secrets.xcconfig` as `MAPBOX_ACCESS_TOKEN`. That file is listed in `.gitignore`.
- Commit `Config/Secrets.example.xcconfig` with a placeholder value.
- Info.plist reads the token as `MBXAccessToken = $(MAPBOX_ACCESS_TOKEN)`.
- If the token is missing, the app shows a clear error screen instead of crashing.
- For Mapbox SPM downloads, the README explains how to set up a secret downloads token in `~/.netrc`.

### Acceptance checks

1. **Setup:** a clean clone, with `Secrets.xcconfig` filled in, builds and runs in the iOS 17 simulator with no warnings about the token.
2. **Terrain:** starting at a known pass (Donner Pass, CA: 39.3157, -120.3291), the map shows 3D terrain tilted to 60°, and the ridges and valleys are clearly visible.
3. **Location:** after permission is granted, a puck shows the user's position, and the camera follows it with heading. Denying permission shows a message explaining why location is needed.
4. **Route:** long-pressing places a destination pin, fetches a route from the current location, and draws it as a 6-pt high-contrast line on the terrain. A new long press replaces the old route. A failed request shows an error.
5. **Driving simulation:** with Xcode's "Freeway Drive" simulated location or a custom GPX file, the puck moves along the route and the camera follows smoothly.
6. **Recenter:** after the user pans away, a Recenter button brings the camera back to follow mode.

### Out of scope for v1

Search, rerouting, spoken or turn-by-turn directions, offline maps, CarPlay, settings screens, analytics, and any server or backend.

### Repo deliverables

- A README covering what the app is, how to get Mapbox tokens, setup steps, and testing with simulated routes
- `.gitignore` for Xcode, including `Secrets.xcconfig`
- An MIT license (this can be changed before public release)
- A sample GPX file of a mountain drive in `TestRoutes/` (for example, Donner Pass on I-80)
