#!/usr/bin/env python3
"""Generates the TopoNav app icon: a road winding up a mountain valley.

Writes one SVG per appearance next to this script, and, if `rsvg-convert` and ImageMagick
(`magick`) are installed, renders opaque 1024x1024 PNGs into the app's asset catalog:

    python3 Design/AppIcon/make_icon.py

Appearances: light (daylight palette), dark (dusk palette) and tinted (greyscale, which iOS
recolours from brightness, so the road is the brightest element).

Scene, back to front: sky, hazy far hills, a snow-capped mountain on the right, the valley
floor, the far part of the road, a low wooded ridge on the left, the foreground, and the
near part of the road. Landforms are lit from the upper left, with a lit and a shadowed face.
"""
import math
import os
import shutil
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ICONSET = os.path.join(HERE, "..", "..", "TopoNav", "Assets.xcassets", "AppIcon.appiconset")


def bez(p0, p1, p2, p3, t):
    return tuple((1-t)**3*a + 3*(1-t)**2*t*b + 3*(1-t)*t*t*c + t**3*d for a, b, c, d in zip(p0, p1, p2, p3))


# Road centreline. It sweeps right around the toe of the left ridge, turns left and passes
# behind the ridge (hidden), reappears above the ridge's crest further away, and winds right
# toward the foot of the mountain.
SEGS = [((360, 1110), (430, 940), (800, 930), (790, 790)),    # near: sweep right
        ((790, 790), (782, 740), (745, 712), (650, 700)),     # turn left, into the ridge
        ((650, 700), (520, 690), (330, 600), (300, 470)),     # hidden behind the ridge
        ((300, 470), (290, 430), (330, 408), (420, 398)),     # reappears beyond the crest
        ((420, 398), (490, 392), (550, 398), (612, 392))]     # into the distance
# The near part (up to SPLIT of the length) is drawn in front of everything; the rest is
# drawn before the left ridge so the ridge hides the middle of it.
SPLIT = 0.2
NEAR_WIDTH, FAR_WIDTH, CASING = 140, 6, 26


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
        w = (w0 + (w1 - w0) * ((i / n) ** 0.4)) / 2
        x, y = CENTRE[i]
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in left + right[::-1]) + " Z"


def road(p, near):
    lo, hi = (0, SPLIT + 0.02) if near else (SPLIT - 0.02, 1)
    return (f'<path d="{ribbon(NEAR_WIDTH + CASING, FAR_WIDTH + CASING * 0.2, lo, hi)}" fill="{p["casing"]}" opacity="0.85"/>'
            f'<path d="{ribbon(NEAR_WIDTH, FAR_WIDTH, lo, hi)}" fill="{p["road"]}"/>')


def puck(p, r=46):
    x, y = bez(*SEGS[0], 0.42)
    return (f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r + 12}" fill="{p["puck"]}" opacity="0.28"/>'
            f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r}" fill="{p["puck_ring"]}"/>'
            f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r - 15}" fill="{p["puck"]}"/>')


def gradient(gid, stops):
    return (f'<linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1">'
            + "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops) + "</linearGradient>")


def shape(d, fill, opacity=None):
    op = f' opacity="{opacity}"' if opacity is not None else ""
    return f'<path d="{d}" fill="{fill}"{op}/>'


# --- Landforms -------------------------------------------------------------------------------

FAR_HILLS = "M0,330 L90,300 L200,318 L310,285 L420,312 L520,300 L600,330 L1024,340 L1024,440 L0,440 Z"

# Background mountain on the right: main peak and a lower shoulder peak.
MOUNTAIN = ("M420,384 L560,300 L640,252 L720,192 L790,140 L850,198 L902,172 L960,214 L1024,250 "
            "L1024,460 L420,460 Z")
MOUNTAIN_LIT = [  # sunlit faces, left of each peak's spine
    "M790,140 L772,236 L726,330 L700,460 L420,460 L420,384 L560,300 L640,252 L720,192 Z",
    "M902,172 L884,262 L872,460 L800,460 L826,310 L850,198 Z",
]
MOUNTAIN_GULLIES = [  # thin shadowed creases on the lit face
    "M640,252 L622,320 L598,410 L612,330 Z",
    "M720,192 L702,280 L668,400 L688,284 Z",
    "M850,198 L838,270 L818,380 L830,276 Z",
]
SNOW = "M790,140 L830,190 L812,186 L800,212 L786,194 L768,208 L752,174 L762,166 Z"
SNOW_LIT = "M790,140 L786,194 L768,208 L752,174 L762,166 Z"
SNOW_SHOULDER = "M902,172 L930,198 L916,196 L906,214 L894,198 L880,206 L872,188 Z"
SNOW_SHOULDER_LIT = "M902,172 L894,198 L880,206 L872,188 Z"

VALLEY_FLOOR = "M0,404 L300,372 L470,386 L640,394 L1024,430 L1024,1024 L0,1024 Z"


def tree_line(y_left, y_right, x0=0, x1=1024, bump=18, depth=26):
    """A band of rounded tree crowns along the far edge of the valley floor."""
    def base(x):
        return y_left + (y_right - y_left) * (x - x0) / (x1 - x0)

    step = 22
    d = f"M{x0},{base(x0):.0f}"
    for i, x in enumerate(range(x0, x1, step)):
        height = bump if i % 3 else bump * 0.6
        d += f" Q{x + step / 2:.0f},{base(x + step / 2) - height * 2:.0f} {x + step:.0f},{base(x + step):.0f}"
    return d + f" L{x1},{y_right + depth} L{x0},{y_left + depth} Z"


TREE_LINE = tree_line(398, 446)

# Low, wide wooded ridge on the left, its toe reaching toward the middle of the frame.
RIDGE = ("M0,470 L80,452 L180,440 L270,448 L360,470 L450,505 L540,560 L620,630 L690,700 L725,740 "
         "L640,770 L0,860 Z")
RIDGE_CREST_LIT = ("M0,470 L80,452 L180,440 L270,448 L360,470 L450,505 L540,560 L620,630 L690,700 "
                   "L640,692 L560,624 L470,566 L380,526 L270,504 L160,508 L60,522 L0,534 Z")
RIDGE_CREASES = [  # shadowed folds running down the ridge's front face
    "M150,512 C170,570 150,640 110,700 C140,640 150,580 132,516 Z",
    "M330,520 C350,590 330,680 290,770 C320,690 330,600 312,522 Z",
    "M500,580 C512,640 500,700 470,760 C492,700 498,640 484,586 Z",
]

FOREGROUND = "M0,884 L280,818 L640,772 L760,802 L1024,782 L1024,1024 L0,1024 Z"


def scene(p):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>{gradient("sky", p["sky"])}{gradient("floor", p["floor"])}{gradient("fg", p["fg"])}</defs>
<rect width="1024" height="1024" fill="url(#sky)"/>
{shape(FAR_HILLS, p["far"])}
{shape(MOUNTAIN, p["mtn_shadow"])}
{"".join(shape(d, p["mtn_lit"]) for d in MOUNTAIN_LIT)}
{"".join(shape(d, p["mtn_shadow"], 0.55) for d in MOUNTAIN_GULLIES)}
{shape(SNOW, p["snow_shadow"])}{shape(SNOW_LIT, p["snow_lit"])}
{shape(SNOW_SHOULDER, p["snow_shadow"])}{shape(SNOW_SHOULDER_LIT, p["snow_lit"])}
{shape(VALLEY_FLOOR, "url(#floor)")}
{shape(TREE_LINE, p["trees"], 0.85)}
{road(p, near=False)}
{shape(RIDGE, p["ridge_shadow"])}
{shape(RIDGE_CREST_LIT, p["ridge_lit"])}
{"".join(shape(d, p["casing"], 0.22) for d in RIDGE_CREASES)}
{shape(FOREGROUND, "url(#fg)")}
{road(p, near=True)}
{puck(p)}
</svg>'''


ROAD = dict(road="#FF2E9E", puck="#2F7BFF", puck_ring="#FFFFFF")
PALETTES = {
    "light": dict(ROAD, sky=[(0, "#3FA6EE"), (0.22, "#8CCBF6"), (0.34, "#DDF1FD")], far="#B7C9D8",
                  mtn_shadow="#6B7E92", mtn_lit="#9AABBC", snow_lit="#FFFFFF", snow_shadow="#CFDAE7",
                  floor=[(0, "#B4CC97"), (0.5, "#8FB473"), (1, "#6F9A55")],
                  trees="#6A8F57", ridge_shadow="#44703F", ridge_lit="#6E9A5C",
                  fg=[(0, "#4E7D43"), (1, "#335A30")], casing="#1A2A1A"),
    "dark": dict(ROAD, sky=[(0, "#1A2150"), (0.16, "#4A3478"), (0.27, "#B2627A"), (0.34, "#EE9A5E")], far="#7A6593",
                 mtn_shadow="#2E3D66", mtn_lit="#4F6396", snow_lit="#EEF0FA", snow_shadow="#A6AFCC",
                 floor=[(0, "#56638A"), (0.5, "#36456A"), (1, "#222E4C")],
                 trees="#2C395C", ridge_shadow="#1B2745", ridge_lit="#2F4069",
                 fg=[(0, "#17213A"), (1, "#0D1427")], casing="#0B0F1A"),
    # Greyscale for iOS tinting: dark terrain, mid-grey landforms, white road.
    "tinted": dict(road="#FFFFFF", puck="#3A3A3A", puck_ring="#FFFFFF",
                   sky=[(0, "#0A0A0A"), (1, "#2A2A2A")], far="#353535",
                   mtn_shadow="#3E3E3E", mtn_lit="#5E5E5E", snow_lit="#BDBDBD", snow_shadow="#8A8A8A",
                   floor=[(0, "#404040"), (1, "#222222")],
                   trees="#2E2E2E", ridge_shadow="#262626", ridge_lit="#3C3C3C",
                   fg=[(0, "#1A1A1A"), (1, "#0F0F0F")], casing="#000000"),
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
