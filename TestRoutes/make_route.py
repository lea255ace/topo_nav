#!/usr/bin/env python3
"""Generates simulated-drive GPX files from real road geometry.

Each route is fetched from the Mapbox Directions API (driving profile) through its waypoints,
smoothed with a centripetal Catmull-Rom spline through every road vertex, and resampled about
every 10 m, so curves play back as curves. Timestamps assume a steady speed.

Reads MAPBOX_ACCESS_TOKEN from Config/Secrets.xcconfig.

    python3 TestRoutes/make_route.py                 # all routes below
    python3 TestRoutes/make_route.py susquehanna     # just one

To add a route, add an entry to ROUTES with waypoints in driving order (lat, lon). Put a waypoint
on each stretch of road you care about, since the Directions API picks the fastest road otherwise.
"""
import datetime
import json
import math
import os
import re
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SECRETS = os.path.join(HERE, "..", "Config", "Secrets.xcconfig")

ROUTES = {
    "FeatherRiver": dict(
        description="Eastbound up the Feather River Canyon on CA-70, Jarbo Gap to Belden, CA: "
                    "the highway follows the river's bends between steep canyon walls",
        waypoints=[(39.7357, -121.4892), (39.8350, -121.4129), (40.0063, -121.2478)],
        speed_mph=45),
    "MountRose": dict(
        description="Up the Mount Rose Highway (NV-431) from Incline Village to the summit: "
                    "hairpin switchbacks climbing above Lake Tahoe",
        waypoints=[(39.2513, -119.9563), (39.3127, -119.8880)],
        speed_mph=35),
    "EmeraldBay": dict(
        description="North on CA-89 from Camp Richardson to Meeks Bay, CA: tight curves on a "
                    "cliffside road above Emerald Bay and Lake Tahoe",
        waypoints=[(38.9350, -120.0390), (38.9545, -120.1100), (39.0367, -120.1240)],
        speed_mph=30),
    "Susquehanna": dict(
        description="North from Harrisburg to Williamsport, PA along the Susquehanna River: "
                    "US-15 from Camp Hill, US-11/15 up the west bank, US-15 through Lewisburg, "
                    "then I-180 along the West Branch",
        # Points taken from the road geometry itself, so none snap onto side streets.
        waypoints=[(40.25036, -76.91962), (40.35487, -76.97803), (40.46751, -76.95062),
                   (40.98766, -76.87801), (41.13839, -76.79993), (41.25437, -76.88795),
                   (41.2412, -77.0011)],
        speed_mph=55),
}


def token():
    with open(SECRETS) as f:
        m = re.search(r"^\s*MAPBOX_ACCESS_TOKEN\s*=\s*(\S+)", f.read(), re.M)
    if not m or not m.group(1).startswith("pk."):
        sys.exit("Set MAPBOX_ACCESS_TOKEN in Config/Secrets.xcconfig first.")
    return m.group(1)


def fetch(waypoints):
    coords = ";".join(f"{lon},{lat}" for lat, lon in waypoints)
    url = (f"https://api.mapbox.com/directions/v5/mapbox/driving/{coords}"
           f"?geometries=geojson&overview=full&access_token={token()}")
    with urllib.request.urlopen(url, timeout=30) as response:
        body = json.load(response)
    if body.get("code") != "Ok":
        sys.exit(f"Directions error: {body.get('code')} {body.get('message', '')}")
    route = body["routes"][0]
    summary = "; ".join(leg.get("summary", "") for leg in route["legs"])
    return route["geometry"]["coordinates"], route["distance"], summary


def smooth(coords, spacing=10.0):
    """Centripetal Catmull-Rom through every vertex, sampled about every `spacing` meters."""
    lat0 = math.radians(sum(c[1] for c in coords) / len(coords))
    radius = 6371000.0

    def to_xy(c):
        return (math.radians(c[0]) * math.cos(lat0) * radius, math.radians(c[1]) * radius)

    pts = [to_xy(coords[0])]
    for c in coords[1:]:
        p = to_xy(c)
        if math.dist(p, pts[-1]) > 0.5:
            pts.append(p)

    def segment(p0, p1, p2, p3, n):
        def knot(t, a, b):
            return t + max(math.dist(a, b), 1e-6) ** 0.5
        t0 = 0.0
        t1 = knot(t0, p0, p1)
        t2 = knot(t1, p1, p2)
        t3 = knot(t2, p2, p3)

        def lerp(a, b, ta, tb, t):
            return tuple(((tb - t) * a[k] + (t - ta) * b[k]) / (tb - ta) for k in range(2))
        out = []
        for i in range(n):
            t = t1 + (t2 - t1) * i / n
            a1, a2, a3 = lerp(p0, p1, t0, t1, t), lerp(p1, p2, t1, t2, t), lerp(p2, p3, t2, t3, t)
            out.append(lerp(lerp(a1, a2, t0, t2, t), lerp(a2, a3, t1, t3, t), t1, t2, t))
        return out

    ext = [pts[0]] + pts + [pts[-1]]
    dense = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        if p0 == p1:
            p0 = (2 * p1[0] - p2[0], 2 * p1[1] - p2[1])
        if p3 == p2:
            p3 = (2 * p2[0] - p1[0], 2 * p2[1] - p1[1])
        dense += segment(p0, p1, p2, p3, max(1, math.ceil(math.dist(p1, p2) / spacing)))
    dense.append(pts[-1])
    return [(math.degrees(y / radius), math.degrees(x / (radius * math.cos(lat0)))) for x, y in dense], dense


def write_gpx(name, route):
    coords, distance, summary = fetch(route["waypoints"])
    latlon, xy = smooth(coords)
    speed = route["speed_mph"] * 0.44704
    start = datetime.datetime(2026, 1, 1, 12, 0, 0)
    elapsed = 0.0
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             f'<!-- {route["description"]}, at a steady ~{route["speed_mph"]} mph.',
             '     Generated by TestRoutes/make_route.py from Mapbox Directions road geometry. -->',
             '<gpx version="1.1" creator="TopoNav" xmlns="http://www.topografix.com/GPX/1/1">']
    for i, (lat, lon) in enumerate(latlon):
        if i:
            elapsed += math.dist(xy[i - 1], xy[i]) / speed
        ts = (start + datetime.timedelta(seconds=elapsed)).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-4] + "Z"
        lines.append(f'  <wpt lat="{lat:.6f}" lon="{lon:.6f}"><time>{ts}</time></wpt>')
    lines.append("</gpx>")
    path = os.path.join(HERE, f"{name}.gpx")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"{name}.gpx: {distance / 1000:.1f} km, {len(latlon)} points, {elapsed / 60:.0f} min — via {summary}")


def main():
    names = sys.argv[1:] or list(ROUTES)
    lookup = {n.lower(): n for n in ROUTES}
    for arg in names:
        name = lookup.get(arg.lower())
        if not name:
            sys.exit(f"Unknown route {arg!r}; choose from: {', '.join(ROUTES)}")
        write_gpx(name, ROUTES[name])


if __name__ == "__main__":
    main()
