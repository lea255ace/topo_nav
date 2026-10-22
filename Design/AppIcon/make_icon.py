#!/usr/bin/env python3
"""Generates the TopoNav app icon: a road winding up a mountain valley.

Writes one SVG per appearance next to this script, and, if `rsvg-convert` and ImageMagick
(`magick`) are installed, renders opaque 1024x1024 PNGs into the app's asset catalog:

    python3 Design/AppIcon/make_icon.py

Appearances: light (daylight palette), dark (dusk palette) and tinted (greyscale, which iOS
recolours from brightness, so the road is the brightest element).
"""
import math
import os
import shutil
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ICONSET = os.path.join(HERE, "..", "..", "TopoNav", "Assets.xcassets", "AppIcon.appiconset")


def bez(p0, p1, p2, p3, t):
    return tuple((1-t)**3*a + 3*(1-t)**2*t*b + 3*(1-t)*t*t*c + t**3*d for a, b, c, d in zip(p0, p1, p2, p3))


# Road centreline: starts in the foreground, sweeps right around the toe of the left ridge,
# cuts back left across the valley floor and passes out of sight behind the left ridge.
SEGS = [((380, 1110), (460, 930), (770, 900), (745, 770)),
        ((745, 770), (728, 690), (690, 640), (610, 612)),
        ((610, 612), (555, 594), (505, 588), (420, 578))]
# The near part (up to SPLIT of the length) is drawn in front of everything;
# the rest is drawn before the left ridge so the ridge hides its far end.
SPLIT = 0.34
NEAR_WIDTH, FAR_WIDTH, CASING = 132, 16, 26


def centreline(n=60):
    pts = []
    for s in SEGS:
        pts += [bez(*s, i / n) for i in range(n)]
    pts.append(SEGS[-1][3])
    return pts


CENTRE = centreline()


def ribbon(w0, w1, lo, hi):
    """Filled road polygon for the slice [lo, hi] of the centreline, narrowing with distance."""
    n = len(CENTRE) - 1
    left, right = [], []
    for i in range(int(lo * n), int(hi * n) + 1):
        i = min(i, n)
        a, b = CENTRE[max(i - 1, 0)], CENTRE[min(i + 1, n)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy) or 1
        nx, ny = -dy / length, dx / length
        w = (w0 + (w1 - w0) * ((i / n) ** 0.45)) / 2
        x, y = CENTRE[i]
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in left + right[::-1]) + " Z"


def road(p, near):
    lo, hi = (0, SPLIT + 0.02) if near else (SPLIT - 0.02, 1)
    return (f'<path d="{ribbon(NEAR_WIDTH + CASING, FAR_WIDTH + CASING * 0.3, lo, hi)}" fill="{p["casing"]}" opacity="0.85"/>'
            f'<path d="{ribbon(NEAR_WIDTH, FAR_WIDTH, lo, hi)}" fill="{p["road"]}"/>')


def puck(p, r=46):
    x, y = bez(*SEGS[0], 0.42)
    return (f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r + 12}" fill="{p["puck"]}" opacity="0.28"/>'
            f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r}" fill="{p["puck_ring"]}"/>'
            f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r - 15}" fill="{p["puck"]}"/>')


def gradient(gid, stops):
    return (f'<linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1">'
            + "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops) + "</linearGradient>")


def scene(p):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>{gradient("sky", p["sky"])}{gradient("right", p["right"])}{gradient("left", p["left"])}{gradient("floor", p["floor"])}{gradient("fg", p["fg"])}</defs>
<rect width="1024" height="1024" fill="url(#sky)"/>
<path d="M0,560 L130,505 L230,530 L380,455 L480,500 L560,470 L660,520 L1024,560 L1024,760 L0,760 Z" fill="{p["far"]}"/>
<path d="M330,610 L450,540 L560,495 L660,420 L790,300 L850,345 L905,325 L1024,395 L1024,760 L330,760 Z" fill="url(#right)"/>
<path d="M790,300 L838,362 L814,354 L793,382 L770,356 L742,366 Z" fill="{p["snow"]}"/>
<path d="M0,600 L430,556 L1024,580 L1024,1024 L0,1024 Z" fill="url(#floor)"/>
{road(p, near=False)}
<path d="M0,455 L110,420 L235,350 L300,392 L365,430 L425,488 L478,560 L528,640 L585,735 L540,775 L0,885 Z" fill="url(#left)"/>
<path d="M235,350 L284,402 L262,396 L240,422 L216,394 L190,402 Z" fill="{p["snow"]}"/>
<path d="M0,905 L300,836 L585,768 L760,800 L1024,782 L1024,1024 L0,1024 Z" fill="url(#fg)"/>
{road(p, near=True)}
{puck(p)}
</svg>'''


ROAD = dict(road="#FF2E9E", puck="#2F7BFF", puck_ring="#FFFFFF")
PALETTES = {
    "light": dict(ROAD, sky=[(0, "#4FB3F2"), (1, "#DDF2FF")], far="#A9BCCB",
                  right=[(0, "#8B9AAA"), (1, "#66798A")], left=[(0, "#5E7F52"), (1, "#3F6340")], snow="#FFFFFF",
                  floor=[(0, "#8DB06E"), (1, "#6E9656")], fg=[(0, "#4C7A41"), (1, "#355C31")], casing="#1A2A1A"),
    "dark": dict(ROAD, sky=[(0, "#1E2650"), (0.5, "#6A3F86"), (0.78, "#E0875A"), (1, "#F4A259")], far="#6C5A86",
                 right=[(0, "#47598A"), (1, "#2E3E66")], left=[(0, "#2B3A60"), (1, "#1B2744")], snow="#E9ECF7",
                 floor=[(0, "#3C4E73"), (1, "#24324F")], fg=[(0, "#18223A"), (1, "#0E1528")], casing="#0B0F1A"),
    # Greyscale for iOS tinting: dark terrain, mid-grey ridges, white road.
    "tinted": dict(road="#FFFFFF", puck="#3A3A3A", puck_ring="#FFFFFF",
                   sky=[(0, "#0A0A0A"), (1, "#262626")], far="#2E2E2E",
                   right=[(0, "#5A5A5A"), (1, "#404040")], left=[(0, "#4A4A4A"), (1, "#2E2E2E")], snow="#B5B5B5",
                   floor=[(0, "#363636"), (1, "#242424")], fg=[(0, "#1C1C1C"), (1, "#101010")], casing="#000000"),
}


def main():
    for name, palette in PALETTES.items():
        svg_path = os.path.join(HERE, f"AppIcon-{name}.svg")
        with open(svg_path, "w") as f:
            f.write(scene(palette))
        print("wrote", os.path.relpath(svg_path))

        if shutil.which("rsvg-convert") and shutil.which("magick"):
            png_path = os.path.join(ICONSET, f"AppIcon-{name}.png")
            rendered = subprocess.run(["rsvg-convert", "-w", "1024", "-h", "1024", svg_path],
                                      check=True, capture_output=True).stdout
            # App icons must be opaque.
            subprocess.run(["magick", "png:-", "-background", "black", "-alpha", "remove", "-alpha", "off", png_path],
                           input=rendered, check=True)
            print("rendered", os.path.relpath(png_path))


if __name__ == "__main__":
    main()
