#!/usr/bin/env python3
# Writes Safelight/AppIcon.icon, the Icon Composer document the app icon is built from, and the menu
# bar's symbol, Safelight/Assets.xcassets/safelight.dial.symbolset.
#
#   scripts/make-icon.py
#
# The icon is a 24-hour dial, white through the day and red through the night, with a knob at 20:30.
# Noon is at the top and midnight at the bottom; time runs clockwise. Change the dial below and run
# this again; the icon can also be opened in Icon Composer (in Xcode), and the symbol in SF Symbols.
import json, math, os, sys
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Safelight")
out = os.path.join(root, "AppIcon.icon")
os.makedirs(os.path.join(out, "Assets"), exist_ok=True)

C, R, WIDTH, KNOB_R, KNOB_HOUR = 512, 296, 116, 70, 20.5
STOPS = [(0, (255, 248, 236)), (0.42, (255, 217, 158)), (0.6, (255, 128, 64)), (0.78, (240, 54, 38)), (1, (176, 20, 12))]

def colour(t):  # t: 0 at noon, 1 at midnight
    for (a, ca), (b, cb) in zip(STOPS, STOPS[1:]):
        if t <= b:
            k = (t - a) / (b - a)
            return "#%02X%02X%02X" % tuple(round(ca[i] + (cb[i] - ca[i]) * k) for i in range(3))

def point(angle, r=R):
    return C + r * math.sin(angle), C - r * math.cos(angle)

def svg(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">{body}</svg>\n'

n = 360
paths = []
for i in range(n):
    (x0, y0), (x1, y1) = point(2 * math.pi * i / n), point(2 * math.pi * (i + 1.5) / n)  # overlap, so no seams
    t = min(i + 0.5, n - i - 0.5) / (n / 2)
    paths.append(f'<path d="M{x0:.2f},{y0:.2f}A{R},{R} 0 0 1 {x1:.2f},{y1:.2f}" stroke="{colour(t)}" stroke-width="{WIDTH}" fill="none"/>')
kx, ky = point(2 * math.pi * (KNOB_HOUR - 12) / 24)

with open(os.path.join(out, "Assets", "Dial.svg"), "w") as f:
    f.write(svg("".join(paths)))
with open(os.path.join(out, "Assets", "Knob.svg"), "w") as f:
    f.write(svg(f'<circle cx="{kx:.2f}" cy="{ky:.2f}" r="{KNOB_R}" fill="#FFFFFF"/>'))

def srgb(r, g, b): return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"
icon = {
    "fill": {"linear-gradient": [srgb(0.11, 0.11, 0.18), srgb(0.03, 0.03, 0.06)]},
    # Front to back: Icon Composer draws the first layer frontmost
    "groups": [{
        "layers": [
            {"image-name": "Knob.svg", "name": "Knob", "glass": True},
            {"image-name": "Dial.svg", "name": "Dial", "glass": True},
        ],
        "shadow": {"kind": "neutral", "opacity": 0.5},
        "translucency": {"enabled": True, "value": 0.4},
    }],
    "supported-platforms": {"squares": ["macOS"]},
}
with open(os.path.join(out, "icon.json"), "w") as f:
    json.dump(icon, f, indent=2)
    f.write("\n")

# The menu bar's symbol: the same dial in one colour, as an SF Symbols template. Its ring is the size
# of Apple's `circle` symbol at each weight and, at Regular, as thick for its size as the icon's. The
# knob is bigger than the icon's, so it still shows at 16 pt, and the ring is cut round it. The
# template has Ultralight, Regular and Black, and SF Symbols blends them into the weights between, so
# all three are drawn with the same pieces.
SYMBOL = {  # weight: the ring's outer radius and width, how far the knob stands out of it, the gap round the knob
    "Ultralight": (37.5, 3.94, 4, 3.6),
    "Regular": (39.375, 39.375 * WIDTH / (R + WIDTH / 2), 5, 4.5),
    "Black": (42, 17.96, 6, 5.4),
}
SIDE_MARGIN, BASELINE, CAP_MIDDLE = 7, 696, -35.2297  # as Apple's circle; the middle of the cap height

def beziers(c, r, angles):
    """Cubic Béziers along a circle, one from each angle to the next. y points down, so a growing
    angle runs clockwise on screen."""
    out = []
    for a0, a1 in zip(angles, angles[1:]):
        k = 4 / 3 * math.tan((a1 - a0) / 4) * r
        p0, p3 = (c[0] + r * math.cos(a0), c[1] + r * math.sin(a0)), (c[0] + r * math.cos(a1), c[1] + r * math.sin(a1))
        out.append(((p0[0] - k * math.sin(a0), p0[1] + k * math.cos(a0)), (p3[0] + k * math.sin(a1), p3[1] - k * math.cos(a1)), p3))
    return out

def steps(a0, a1, n): return [a0 + (a1 - a0) * i / n for i in range(n + 1)]

def dial(weight):
    """The symbol at `weight`, centred on (0, 0): the ring, clockwise from the knob round to it, and
    the knob."""
    ro, width, stands_out, gap = SYMBOL[weight]
    ri, rm, rk = ro - width, ro - width / 2, width / 2 + stands_out
    a = 2 * math.pi * (KNOB_HOUR - 12) / 24 - math.pi / 2
    knob = (rm * math.cos(a), rm * math.sin(a))
    cut = rk + gap
    # how far round from the knob the cut meets each edge of the ring
    to_outer = math.acos((ro * ro + rm * rm - cut * cut) / (2 * ro * rm))
    to_inner = math.acos((ri * ri + rm * rm - cut * cut) / (2 * ri * rm))
    def from_knob(r, b): return math.atan2(r * math.sin(b) - knob[1], r * math.cos(b) - knob[0])
    def back(b0, b1): return b0 - (b0 - b1) % (2 * math.pi)  # b1, reached counterclockwise from b0
    # The outer edge breaks at the top, bottom and sides, like Apple's circles, so no control point
    # lies outside the bounds; the inner edge breaks evenly, as the cut can pass its sides.
    o0, o1, q = a + to_outer, a + 2 * math.pi - to_outer, math.pi / 2
    outer = [o0] + [i * q for i in range(math.floor(o0 / q) + 1, math.ceil(o1 / q))] + [o1]
    i0, i1 = a - to_inner, a + to_inner
    c0 = from_knob(ro, o1)
    c1 = from_knob(ri, i1)
    ring = [("M", (ro * math.cos(o0), ro * math.sin(o0)))] + beziers((0, 0), ro, outer) \
        + beziers(knob, cut, [c0, back(c0, from_knob(ri, i0))]) \
        + beziers((0, 0), ri, steps(i0 + 2 * math.pi, i1, 4)) \
        + beziers(knob, cut, [c1, back(c1, from_knob(ro, o0))])
    return [ring, [("M", (knob[0] + rk, knob[1]))] + beziers(knob, rk, steps(0, 2 * math.pi, 4))]

def fmt(v):
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s

def d(path, dx, dy):
    return "".join(p[0] + " ".join(f"{fmt(x + dx)} {fmt(y + dy)}" for x, y in p[1:]) if p[0] == "M" else
                   "C" + " ".join(f"{fmt(x + dx)} {fmt(y + dy)}" for x, y in p) for p in path) + "Z"

guides = "".join(f'  <line id="{name}-{scale}" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="{fmt(y)}" y2="{fmt(y)}"/>\n'
                 for scale, baseline in (("S", 696), ("M", 1126), ("L", 1556)) for name, y in (("Baseline", baseline), ("Capline", baseline - 70.459)))
symbols = ""
for weight, x in (("Ultralight", 518), ("Regular", 1406), ("Black", 2886)):
    ro, shapes = SYMBOL[weight][0], dial(weight)
    assert len(shapes[0]) == len(dial("Regular")[0]), weight
    for side, mx in (("left", x), ("right", x + 2 * (ro + SIDE_MARGIN))):
        guides += f'  <line id="{side}-margin-{weight}-S" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="{fmt(mx)}" x2="{fmt(mx)}" y1="600.785" y2="720.121"/>\n'
    symbols += f'  <g id="{weight}-S" transform="matrix(1 0 0 1 {x} {BASELINE})">\n'
    symbols += "".join(f'   <path d="{d(shape, SIDE_MARGIN + ro, CAP_MIDDLE)}"/>\n' for shape in shapes)
    symbols += "  </g>\n"

name = "safelight.dial"
symbolset = os.path.join(root, "Assets.xcassets", name + ".symbolset")
os.makedirs(symbolset, exist_ok=True)
with open(os.path.join(symbolset, name + ".svg"), "w") as f:
    f.write(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 3300 2200">
 <g id="Notes">
  <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0"/>
  <text id="template-version" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1933)">Template v.3.0</text>
  <text id="descriptive-name" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1969)">{name}</text>
 </g>
 <g id="Guides">
{guides} </g>
 <g id="Symbols">
{symbols} </g>
</svg>
''')
with open(os.path.join(symbolset, "Contents.json"), "w") as f:
    f.write('{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  },\n  "symbols" : [\n    {\n'
            f'      "filename" : "{name}.svg",\n      "idiom" : "universal"\n    }}\n  ]\n}}\n')
