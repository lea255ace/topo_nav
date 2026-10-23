#!/usr/bin/env python3
"""Replays a test drive in the iOS Simulator with its route shown in TopoNav.

    python3 TestRoutes/play_route.py MountRose
    python3 TestRoutes/play_route.py Susquehanna --from 1000 --speed 30

Steps:
1. Stops any running location playback.
2. Puts the simulated location at the drive's start (or at sample --from).
3. Relaunches TopoNav with launch arguments so the debug build drops a pin at the drive's end and
   requests a route to it, through the drive's waypoints from make_route.py so it follows the
   same roads.
4. Plays the drive's points with `xcrun simctl location start`.

Needs a booted simulator with a debug build of TopoNav installed and location access allowed.
"""
import argparse
import math
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from make_route import ROUTES  # noqa: E402


def gpx_points(name):
    path = os.path.join(HERE, f"{name}.gpx")
    if not os.path.exists(path):
        sys.exit(f"No {path}")
    with open(path) as f:
        return [(float(a), float(b)) for a, b in re.findall(r'lat="([^"]+)" lon="([^"]+)"', f.read())]


def nearest_index(points, target):
    lat0 = math.radians(target[0])
    return min(range(len(points)),
               key=lambda i: ((points[i][0] - target[0]) ** 2
                              + ((points[i][1] - target[1]) * math.cos(lat0)) ** 2))


def simctl(*args, stdin=None):
    result = subprocess.run(["xcrun", "simctl", *args], input=stdin, text=True, capture_output=True)
    if result.returncode != 0:
        sys.exit(f"simctl {' '.join(args[:2])} failed: {result.stderr.strip() or result.stdout.strip()}")
    return result.stdout.strip()


def find_bundle_id(device):
    """The installed app whose bundle ID ends in .TopoNav."""
    apps = simctl("listapps", device)
    ids = sorted(set(re.findall(r'"?([A-Za-z0-9.-]+\.TopoNav)"?\s*=', apps)))
    if not ids:
        sys.exit("TopoNav isn't installed on the simulator; build and run it from Xcode first.")
    if len(ids) > 1:
        sys.exit(f"Several TopoNav builds installed ({', '.join(ids)}); pass --bundle-id.")
    return ids[0]


def main():
    available = sorted(n[:-4] for n in os.listdir(HERE) if n.endswith(".gpx"))
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("route", help="one of: " + ", ".join(available))
    parser.add_argument("--from", dest="start", type=int, default=0, metavar="N",
                        help="start at sample N of the drive instead of the beginning")
    parser.add_argument("--speed", type=float, help="meters per second (default: the drive's speed, or 25)")
    parser.add_argument("--device", default="booted", help="simulator name or UDID (default: booted)")
    parser.add_argument("--bundle-id", help="TopoNav's bundle ID (default: found on the simulator)")
    args = parser.parse_args()

    name = {n.lower(): n for n in available}.get(args.route.lower())
    if not name:
        sys.exit(f"Unknown route {args.route!r}; choose from: {', '.join(available)}")
    points = gpx_points(name)
    if not 0 <= args.start < len(points) - 1:
        sys.exit(f"--from must be between 0 and {len(points) - 2}")
    drive = points[args.start:]

    config = ROUTES.get(name, {})
    speed = args.speed or (config["speed_mph"] * 0.44704 if "speed_mph" in config else 25)
    # Keep the drive's waypoints that are still ahead, so the route follows the same roads.
    via = [w for w in config.get("waypoints", [])[1:-1] if nearest_index(points, w) > args.start + 10]

    bundle_id = args.bundle_id or find_bundle_id(args.device)

    print(f"{name}: {len(drive)} points, about {len(drive) * 10 / speed / 60:.0f} min at {speed:.1f} m/s")
    simctl("location", args.device, "clear")
    simctl("location", args.device, "set", f"{drive[0][0]},{drive[0][1]}")

    end = drive[-1]
    launch = ["launch", "--terminate-running-process", args.device, bundle_id,
              "-TopoNavRouteTo", f"{end[0]:.6f},{end[1]:.6f}"]
    if via:
        launch += ["-TopoNavRouteVia", ";".join(f"{lat:.5f},{lon:.5f}" for lat, lon in via)]
    simctl(*launch)
    print(f"Relaunched {bundle_id} with a route to {end[0]:.5f},{end[1]:.5f}"
          + (f" via {len(via)} waypoints" if via else ""))
    time.sleep(6)  # let the app start, get a fix and fetch the route before driving starts

    stdin = "\n".join(f"{lat},{lon}" for lat, lon in drive) + "\n"
    simctl("location", args.device, "start", f"--speed={speed:.2f}", "-", stdin=stdin)
    print(f"Driving. Stop with: xcrun simctl location {args.device} clear")


if __name__ == "__main__":
    main()
