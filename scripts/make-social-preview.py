#!/usr/bin/env python3
# Writes docs/social-preview.png, the 1280×640 picture GitHub shows when a link to the repository is
# shared: the icon, the name and a line about Safelight beside the popover, from docs/icon.png and
# docs/popover-dark.png.
#
#   scripts/make-social-preview.py
#
# GitHub has no way to upload it from here: upload it in the repository's Settings › General › Social
# preview, and again when you run this after the popover changes. Needs Pillow (pip install pillow).
import io, os
from PIL import Image, ImageCms, ImageDraw, ImageFilter, ImageFont

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
docs = os.path.join(root, "docs")
W, H = 1280, 640
BACKGROUND, GLOW = (20, 19, 30), (150, 28, 16)  # the icon's night sky, and the red the dial ends in
FONT = "/System/Library/Fonts/SFNS.ttf"

def srgb(name):  # the screenshots are in Display P3; link previews are drawn as sRGB
    image = Image.open(os.path.join(docs, name)).convert("RGBA")
    p3 = ImageCms.ImageCmsProfile(io.BytesIO(image.info["icc_profile"]))
    return ImageCms.profileToProfile(image, p3, ImageCms.createProfile("sRGB"), outputMode="RGBA")

def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f

# A dark ground with the red glowing up from behind the popover
canvas = Image.new("RGB", (W, H), BACKGROUND)
glow = Image.new("L", (W, H), 0)
ImageDraw.Draw(glow).ellipse((620, 220, 1260, 900), fill=255)
canvas.paste(Image.new("RGB", (W, H), GLOW), mask=glow.filter(ImageFilter.GaussianBlur(170)).point(lambda a: a * 0.55))

# The popover, its shadow and all, sized to stand 40 points clear of the top and bottom. The menu bar
# above it ends with the clock at the screenshot's right edge, so that goes at the picture's, as on a
# screen.
popover = srgb("popover-dark.png")
scale = (H - 80) / 950  # its opaque part is 950 pixels high
popover = popover.resize((round(popover.width * scale), round(popover.height * scale)), Image.LANCZOS)
canvas.paste(popover, (W - 16 - popover.width, 40 - round(51 * scale)), popover)

icon = srgb("icon.png").resize((176, 176), Image.LANCZOS)
canvas.paste(icon, (64, 112), icon)

draw = ImageDraw.Draw(canvas)
draw.text((70, 316), "Safelight", font=font(92, "Bold"), fill=(255, 255, 255))
lines = ["Your Mac’s color filter, brightness and", "Light/Dark appearance on one schedule,", "from daylight to deep red."]
for i, line in enumerate(lines):
    draw.text((72, 438 + i * 42), line, font=font(31, "Regular"), fill=(206, 204, 216))

canvas.save(os.path.join(docs, "social-preview.png"), optimize=True)
