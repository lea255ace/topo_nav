# TopoNav

An iPhone app for live, route-based navigation on a 3D terrain map. Instead of a flat top-down map, you see the mountains, ridges and river valleys around you — so it's obvious *why* the road curves the way it does.

Built with Swift, SwiftUI and the [Mapbox Maps SDK for iOS](https://github.com/mapbox/mapbox-maps-ios) (v11). Routes come from the Mapbox Directions API. You supply your own Mapbox access token.

> **Status:** version 0.1.0: a 3D terrain map with Satellite and Outdoors styles, location follow mode with a course-up camera, long-press routing and a Recenter button. Search, rerouting, spoken directions and CarPlay are not included yet.

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

For device builds, also set these in the same file (see `Secrets.example.xcconfig`), so your signing details stay out of the shared project:

```
TOPONAV_BUNDLE_ID_PREFIX_OVERRIDE = com.yourname
DEVELOPMENT_TEAM = ABCDE12345
```

Your team ID is listed in Xcode ▸ Settings ▸ Accounts; a free Personal Team works.

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

### On your iPhone

1. Set `TOPONAV_BUNDLE_ID_PREFIX_OVERRIDE` and `DEVELOPMENT_TEAM` in `Config/Secrets.xcconfig` (above), and make sure that Apple ID is signed in under Xcode ▸ Settings ▸ Accounts.
2. Connect the phone, unlock it and tap **Trust** when asked.
3. Turn on **Settings ▸ Privacy & Security ▸ Developer Mode** (the phone restarts).
4. Pick the phone as the run destination in Xcode and press ⌘R. Xcode creates the development certificate and profile automatically.
5. The first launch is blocked until you trust your profile: **Settings ▸ General ▸ VPN & Device Management ▸** your Apple ID **▸ Trust**.

With a free Personal Team, installs stop opening after 7 days; run from Xcode again to refresh.

## Using the app

- **Follow mode:** once location access is allowed, the camera follows close behind your position at an 80° tilt, with the puck lowered to show more road ahead, and turns to match your direction of travel, leaning toward the route ahead when one is shown. Drag or rotate the map to look around, then tap **Recenter** to resume following.
- **Route to a spot:** long-press anywhere on the map to drop a destination pin. TopoNav fetches a driving route (with live traffic) from your current position and draws it on the terrain. Long-press again to replace it. Each long press is one Directions API request.
- **Map style:** switch between **Satellite** and **Outdoors** at the top of the screen.

### Tuning the camera (debug builds)

Debug builds show a sliders button next to the map style picker. It opens a panel for tuning the follow view live while you drive or play a test route:

- **Pitch** (0–85°): how far the camera tilts toward the horizon.
- **Zoom:** how close the camera sits to the puck.
- **Puck lower by:** moves the puck down the screen to show more road ahead.
- **Exaggeration:** terrain height multiplier.
- **Haze strength / Haze starts / Haze ends / Horizon blend:** how strong the distance haze is (0 turns it off), where it fades far terrain into the sky, and how far up the sky the horizon glow extends. Distances are relative to the map's center point.
- **Far width / Full width at:** widens the route line with straight-line distance from you, reaching the far width at the set distance, so the route stays readable far off (along a river, around the next bend, or turning off up a side valley).
- **Smoothing:** how gently the camera turns to a new direction; higher is steadier but lags more.
- **Look ahead / Look-ahead weight:** while a route is shown and you're on it, turns the camera toward where the route goes that far ahead. A weight of 0 follows your direction of travel only.

Values are saved between launches. **Copy values** puts them on the clipboard so they can become the defaults in `CameraTuning` (`TopoNav/CameraSettings.swift`); release builds always use those defaults.

## Testing with simulated routes

The simulator has no GPS, so feed it a location track:

- **Built-in:** with the app running, choose **Features ▸ Location ▸ Freeway Drive** in the Simulator menu.
- **Test drives in `TestRoutes/`**, each traced from real road geometry with a point about every 10 m:

  | File | Drive | Length |
  |---|---|---|
  | `DonnerPass.gpx` | I-80 west over Donner Summit, Truckee to Kingvale, CA | 27 km |
  | `FeatherRiver.gpx` | CA-70 up the Feather River Canyon, Jarbo Gap to Belden, CA | 46 km |
  | `MountRose.gpx` | NV-431 switchbacks from Incline Village up Mount Rose | 15 km |
  | `EmeraldBay.gpx` | CA-89 cliffside curves above Emerald Bay, Lake Tahoe | 23 km |
  | `Susquehanna.gpx` | Harrisburg to Williamsport, PA along the Susquehanna: US-15, US-11/15, then I-180 | 159 km |

- **Playing a drive (recommended):** `TestRoutes/play_route.py` stops any running playback, moves the simulated location to the drive's start, relaunches the debug build with a route to the drive's end (through the same waypoints, so it follows the same roads), then plays the drive:
  ```bash
  python3 TestRoutes/play_route.py MountRose
  ```
  Options: `--from N` starts at sample N of the drive, `--speed` sets meters per second (default: the drive's speed), `--device` picks a simulator other than the booted one. Stop playback with `python3 TestRoutes/stop_route.py`.
- **Playing a drive by hand:** play its points into a booted simulator. `--speed` is in meters per second (25 ≈ 55 mph):
  ```bash
  grep -oE 'lat="[^"]+" lon="[^"]+"' TestRoutes/MountRose.gpx | sed -E 's/lat="([^"]+)" lon="([^"]+)"/\1,\2/' | xcrun simctl location booted start --speed=25 -
  ```
  To try look-ahead this way, long-press on the road ahead so a route is shown along the drive.
- **From Xcode:** open **Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Options**, tick *Allow Location Simulation* and pick a GPX file, or choose one while running from the location arrow in the debug bar. Xcode's playback pauses briefly at waypoints and sends no direction of travel, so the command-line playback gives smoother, more realistic motion.
- **Adding a drive:** add an entry with waypoints to `ROUTES` in `TestRoutes/make_route.py`, then run `python3 TestRoutes/make_route.py <name>`. It reads your token from `Config/Secrets.xcconfig`.
- **Permission states:** `xcrun simctl privacy booted grant location <bundle id>` pre-approves location; `revoke` tests the "location off" message; `reset` brings the prompt back.

On a real device, test on a twisty road with a passenger operating the phone, or with the phone mounted and hands-off.

## Project layout

```
TopoNav/            App sources, assets, Info.plist
Config/             xcconfig files (Secrets.xcconfig is git-ignored)
TestRoutes/         GPX files for simulated driving; play_route.py replays one, make_route.py adds more
Design/AppIcon/     App icon generator and SVG sources (python3 Design/AppIcon/make_icon.py)
```

## Versioning

- **Version** (`MARKETING_VERSION`, e.g. `0.1.0`) is the user-facing [semantic version](https://semver.org). iOS only allows numbers and dots here.
- **Build** (`CURRENT_PROJECT_VERSION`, e.g. `2`) increases for every build that leaves your machine and never goes down. It's independent of pre-release numbers.
- **Pre-releases** are marked only in git tags, e.g. `v0.1.0-beta.1`, `v0.1.0-beta.2`; the final release is tagged `v0.1.0`.

To bump:

```bash
agvtool next-version -all
```

```bash
agvtool new-marketing-version 0.2.0
```

(`next-version` may print a harmless note about `Info.plist`; the build number lives in the project's build settings.)

## License

MIT — see [LICENSE](LICENSE).
