#!/usr/bin/env python3
# Writes Safelight/AppIcon.icon, the Icon Composer document the app icon is built from.
#
#   scripts/make-icon.py
#
# The icon is a 24-hour dial, white through the day and red through the night, with a knob at 20:30.
# Noon is at the top and midnight at the bottom; time runs clockwise. Change the dial below and run
# this again; the icon can also be opened in Icon Composer (in Xcode).
import json, math, os, sys
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Safelight", "AppIcon.icon")
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
