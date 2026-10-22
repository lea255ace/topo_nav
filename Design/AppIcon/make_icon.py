#!/usr/bin/env python3
"""Generates the TopoNav app icon: a road winding up a mountain valley.

Writes one SVG per appearance next to this script, and, if `rsvg-convert` and ImageMagick
(`magick`) are installed, renders opaque 1024x1024 PNGs into the app's asset catalog:

    python3 Design/AppIcon/make_icon.py

Appearances: light (daylight palette), dark (dusk palette) and tinted (greyscale, which iOS
recolours from brightness, so the road is the brightest element).

Scene, back to front: sky, hazy far hills, the valley floor, the far part of the road, a
snow-capped mountain on the right, a rough ridgeline on the left, the foreground, and the
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


# Road centreline. It sweeps right with room to spare around the toe of the left ridge, turns
# left and passes behind the ridge (hidden), reappears above the ridge's crest further away,
# and disappears again behind the left flank of the mountain.
SEGS = [((360, 1110), (440, 940), (850, 950), (840, 790)),    # near: sweep right
        ((840, 790), (835, 735), (790, 705), (700, 698)),     # turn left, behind the ridge's toe
        ((700, 698), (560, 690), (420, 560), (400, 425)),     # hidden behind the ridge
        ((400, 425), (430, 405), (470, 398), (520, 398)),     # reappears beyond the crest
        ((520, 398), (560, 398), (600, 404), (650, 414))]     # behind the mountain
# The near part (up to SPLIT of the length) is drawn in front of everything; the rest is
# drawn before the left ridge so the ridge hides the middle of it.
SPLIT = 0.2
NEAR_WIDTH, FAR_WIDTH, CASING = 140, 5, 26
# Road width shrinks in proportion to height above this horizon line, as in a real perspective view.
HORIZON_Y = 365


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
        x, y = CENTRE[i]
        depth = max(y - HORIZON_Y, 0) / (CENTRE[0][1] - HORIZON_Y)
        w = max(w0 * depth, w1) / 2
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

# Mountain on the right: smaller and nearer than the far hills, standing on the valley floor,
# with a main peak and a lower shoulder peak. Its left flank hides the end of the road.
MOUNTAIN = ("M520,470 L600,410 L660,350 L720,290 L790,230 L846,282 L900,268 L960,300 L1024,330 "
            "L1024,500 L520,500 Z")
MOUNTAIN_LIT = [  # sunlit faces, left of each peak's spine
    "M790,230 L768,310 L738,400 L722,500 L520,500 L520,470 L600,410 L660,350 L720,290 Z",
    "M900,268 L884,330 L874,500 L820,500 L842,340 L846,282 Z",
]
MOUNTAIN_GULLIES = [  # thin shadowed creases on the lit face
    "M660,350 L648,400 L632,460 L642,404 Z",
    "M720,290 L706,350 L684,440 L696,356 Z",
    "M846,282 L838,340 L826,420 L832,344 Z",
]
SNOW = "M790,230 L824,272 L809,269 L799,290 L787,276 L771,288 L757,258 L766,252 Z"
SNOW_LIT = "M790,230 L787,276 L771,288 L757,258 L766,252 Z"
SNOW_SHOULDER = "M900,268 L924,290 L912,289 L904,304 L894,292 L882,299 L875,284 Z"
SNOW_SHOULDER_LIT = "M900,268 L894,292 L882,299 L875,284 Z"

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
MOUNTAIN_TREES = tree_line(476, 492, x0=500, x1=1024, bump=14, depth=30)

# Rough ridgeline on the left: it runs in from beyond the left edge and descends to a toe
# in the middle of the frame. Its crest is jagged, lit from the upper left.
RIDGE_CREST = [(-20, 404), (30, 392), (62, 402), (96, 386), (128, 398), (160, 380), (196, 396),
               (228, 388), (262, 404), (296, 398), (330, 424), (362, 418), (396, 440), (430, 452),
               (466, 476), (498, 486), (532, 512), (566, 530), (598, 560), (630, 584), (658, 618),
               (686, 648), (706, 682), (722, 712), (730, 738)]


def _pts(points):
    return " L".join(f"{x},{y}" for x, y in points)


RIDGE = f"M{_pts(RIDGE_CREST)} L712,762 L660,780 L-20,880 Z"


def _lit_band():
    """The sunlit upper face: a band below the crest, thinning toward the toe."""
    n = len(RIDGE_CREST) - 1
    lower = []
    for i, (x, y) in enumerate(RIDGE_CREST):
        band = 70 - 52 * i / n + (12 if i % 3 == 0 else 0)   # uneven lower edge reads as rock
        lower.append((x - 14 * i / n, y + band))
    return f"M{_pts(RIDGE_CREST)} L{_pts(lower[::-1])} Z"


RIDGE_CREST_LIT = _lit_band()
RIDGE_CREASES = [  # shadowed gullies running down the ridge's front face
    "M96,440 C110,520 96,610 60,700 C86,610 96,520 82,444 Z",
    "M228,446 C246,530 232,640 196,760 C222,640 232,530 214,450 Z",
    "M362,476 C378,560 364,660 330,770 C354,660 364,560 348,480 Z",
    "M498,536 C510,600 500,670 474,740 C492,670 498,600 486,540 Z",
    "M630,624 C638,660 630,700 612,740 C626,700 630,660 620,628 Z",
]

FOREGROUND = "M0,884 L280,818 L640,772 L760,802 L1024,782 L1024,1024 L0,1024 Z"


def scene(p):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>{gradient("sky", p["sky"])}{gradient("floor", p["floor"])}{gradient("fg", p["fg"])}</defs>
<rect width="1024" height="1024" fill="url(#sky)"/>
{shape(FAR_HILLS, p["far"])}
{shape(VALLEY_FLOOR, "url(#floor)")}
{shape(TREE_LINE, p["trees"], 0.85)}
{road(p, near=False)}
{shape(MOUNTAIN, p["mtn_shadow"])}
{"".join(shape(d, p["mtn_lit"]) for d in MOUNTAIN_LIT)}
{"".join(shape(d, p["mtn_shadow"], 0.55) for d in MOUNTAIN_GULLIES)}
{shape(SNOW, p["snow_shadow"])}{shape(SNOW_LIT, p["snow_lit"])}
{shape(SNOW_SHOULDER, p["snow_shadow"])}{shape(SNOW_SHOULDER_LIT, p["snow_lit"])}
{shape(MOUNTAIN_TREES, p["trees"])}
{shape(RIDGE, p["ridge_shadow"])}
{shape(RIDGE_CREST_LIT, p["ridge_lit"])}
{"".join(shape(d, p["casing"], 0.25) for d in RIDGE_CREASES)}
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
