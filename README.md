# TopoNav

An iPhone app for live, route-based navigation on a 3D terrain map. Instead of a flat top-down map, you see the mountains, ridges and river valleys around you — so it's obvious *why* the road curves the way it does.

Built with Swift, SwiftUI and the [Mapbox Maps SDK for iOS](https://github.com/mapbox/mapbox-maps-ios) (v11). Routes come from the Mapbox Directions API. You supply your own Mapbox access token.

> **Status:** early development. Version 1 covers a 3D terrain map, location follow mode, long-press routing and a recenter button. Search, rerouting and spoken directions are not included yet.

## Requirements

- A current Xcode (developed with Xcode 27.1) with the iOS simulator runtime installed (Xcode ▸ Settings ▸ Components)
- iOS 17.0+ (simulator or device)
- A free Mapbox account

## 1. Get a Mapbox access token

1. Sign up at [mapbox.com](https://account.mapbox.com/auth/signup/).
2. Open [Access tokens](https://account.mapbox.com/access-tokens/) and copy your **Default public token** (starts with `pk.`), or create a new public token. The default scopes are enough.

### Staying within the free tier

Mapbox's free tier is generous for personal use (at the time of writing, about 25,000 monthly active users for the mobile Maps SDK and 100,000 Directions API requests per month). TopoNav only calls the Directions API when you long-press to pick a destination, so normal personal use stays well inside it. Check [mapbox.com/pricing](https://www.mapbox.com/pricing) for current limits, and consider setting up billing alerts on your account.

## 2. Configure the token

The token is kept out of source control:

```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

Edit `Config/Secrets.xcconfig` and replace the placeholder:

```
MAPBOX_ACCESS_TOKEN = pk.your_token_here
```

`Config/Secrets.xcconfig` is listed in `.gitignore`. The build injects the value into `Info.plist` as `MBXAccessToken`, where the Mapbox SDK reads it. If the token is missing or still the placeholder, the app shows a setup screen instead of the map.

For device builds, also set `TOPONAV_BUNDLE_ID_PREFIX_OVERRIDE` (e.g. `com.yourname`) in the same file and choose your team under Signing & Capabilities.

## 3. (If needed) Mapbox SDK download token

Current Mapbox Maps v11 releases are fetched from public GitHub repositories, so Swift Package Manager usually needs no extra setup. If package resolution fails with a 401 from `api.mapbox.com` (older SDK versions, or if Mapbox changes this), create a **secret** token with the `DOWNLOADS:READ` scope on the Access tokens page and add it to `~/.netrc`:

```
machine api.mapbox.com
  login mapbox
  password sk.your_secret_token_here
```

Then restrict its permissions:

```bash
chmod 600 ~/.netrc
```

Never put the secret (`sk.`) token in the project.

## 4. Build and run

```bash
open TopoNav.xcodeproj
```

Xcode resolves the Mapbox package on first open. Pick an iPhone simulator and press ⌘R.

## Testing with simulated routes

The simulator has no GPS, so feed it a location track:

- **Built-in:** with the app running, choose **Features ▸ Location ▸ Freeway Drive** in the Simulator menu.
- **Mountain drive:** `TestRoutes/DonnerPass.gpx` is a westbound I-80 drive over Donner Summit (Truckee to Kingvale, about 27 km) at a steady 55 mph, traced from Mapbox Directions road geometry. In Xcode, open **Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Options**, tick *Allow Location Simulation* and pick `DonnerPass.gpx` as the default location — or choose it while running from the location arrow in the debug bar.
- **From the command line:** play the same waypoints into a booted simulator:
  ```bash
  grep -oE 'lat="[^"]+" lon="[^"]+"' TestRoutes/DonnerPass.gpx | sed -E 's/lat="([^"]+)" lon="([^"]+)"/\1,\2/' | xcrun simctl location booted start --speed=25 -
  ```
- **Permission states:** `xcrun simctl privacy booted grant location org.example.TopoNav` pre-approves location; `revoke` tests the "location off" message; `reset` brings the prompt back.

On a real device, test on a twisty road with a passenger operating the phone, or with the phone mounted and hands-off.

## Project layout

```
TopoNav/            App sources, assets, Info.plist
Config/             xcconfig files (Secrets.xcconfig is git-ignored)
TestRoutes/         GPX files for simulated driving
```

## License

MIT — see [LICENSE](LICENSE).
