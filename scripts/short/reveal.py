#!/usr/bin/env python3
# Makes the short's second version from the same pictures as render.py's, and with its parts. It's
# made to hold on to people scrolling past, who decide within the first second:
#   - the first caption is there from the first frame, and the red starts to move at once
#   - the red spreads out from Safelight's menu bar icon instead of fading in everywhere, so for a
#     moment the screen is white and red at once
#   - it starts close in on the popover, big enough to read on a phone, and pulls back to the whole
#     red desktop
#   - the captions all sit at the same height
#   - the evening goes quicker, and the end card comes up over the last shot (12.4 seconds in all)
# Run it with scripts/make-short.sh, which writes the pictures first.
#
#   reveal.py            writes build/short/safelight-short-reveal.mp4
#   reveal.py 1 6.5      writes build/short/still-reveal-1.0.png and still-reveal-6.5.png, the frames at
#                        those seconds
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from render import (ASSETS, FPS, H, REPO, W, arr, clock, color_filter, font, over, pill, scaled, screen_b,
                    settings, smooth, srgb, write)

# Timeline, in seconds
A_END, B_END, END = 4.0, 9.6, 12.4
SPREAD = (0.1, 1.5)       # shot A: the red spreading out from the menu bar icon
PULL_BACK = (1.4, 4.0)    # and the camera pulling back from the popover to the whole screen
XFADE = 0.3
# Shot B's clock, (second, minute): as render.py's, but quicker
CLOCK = [(A_END, 16 * 60), (5.3, 17 * 60 + 55), (7.1, 18 * 60 + 32), (B_END, 21 * 60 + 30)]

# Captions: from, to (seconds), lines. All at one height, clear of the bottom fifth, where Shorts and
# TikTok put the title and channel; the first is there from the first frame.
CAPTION_Y = 1450
CAPTIONS = [
    (0.0, 1.9, ["Night Shift can’t do this"]),
    (1.9, A_END, ["Safelight goes full red"]),
    (A_END + 0.1, 5.3, ["White by day…"]),
    (5.3, 7.0, ["…red by night"]),
    (7.0, B_END, ["Dark Mode and wallpaper", "switch with it"]),
]

# The popover's own intensity and brightness, which the red comes on at
RED = (0.90, 0.68)


def minute_at(t):
    return float(np.interp(t, *zip(*CLOCK)))


def rgb8(rgb):
    return (np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)


# --- Shot A -------------------------------------------------------------------------------------

# The same screen as render.py's shot A, made K times as large so it stays sharp close in. Positions
# are in the frame's pixels when the whole screen is in it.
K = 1.5
POPOVER_SCALE = 1.1
POPOVER_AT = (W - 18 - 836 * POPOVER_SCALE, 14)
ICON = (POPOVER_AT[0] + 364 * POPOVER_SCALE, POPOVER_AT[1] + 23 * POPOVER_SCALE)  # in the screenshot at 364, 23
ZOOM = 1.45  # at the start: the popover across the frame


def screen_a():
    size = round(H * K)
    wall = srgb(os.path.join(ASSETS, "wallpaper-light.png"), (size, size)).convert("RGB")
    left = (size - round(W * K)) // 2
    rgb = arr(wall.crop((left, 0, left + round(W * K), size)))
    popover = scaled(srgb(os.path.join(REPO, "docs/popover-light.png")), POPOVER_SCALE * K)
    over(rgb, arr(popover), round(POPOVER_AT[0] * K), round(POPOVER_AT[1] * K))
    return Image.fromarray(rgb8(rgb))


SCREEN_A = screen_a()
V, U = np.mgrid[0:H, 0:W].astype(np.float32)
FEATHER = 90
REACH = float(np.hypot(max(ICON[0], W - ICON[0]), H - ICON[1])) + FEATHER


def view(t):
    """The part of the screen in frame: its left, top and how far it's zoomed in. The camera pulls
    back from above the icon, so the menu bar stays along the top."""
    z = ZOOM ** (1 - smooth((t - PULL_BACK[0]) / (PULL_BACK[1] - PULL_BACK[0])))
    return ICON[0] * (1 - 1 / z), 0.0, z


def shot_a(t):
    x0, y0, z = view(t)
    box = (x0 * K, y0 * K, (x0 + W / z) * K, (y0 + H / z) * K)
    rgb = arr(SCREEN_A.resize((W, H), Image.LANCZOS, box=box))
    red = color_filter(rgb, *RED)
    k = smooth((t - SPREAD[0]) / (SPREAD[1] - SPREAD[0]))
    if k >= 1:
        return red
    if k <= 0:
        return rgb
    # Red inside a circle round the icon, with a soft edge
    d = np.hypot(x0 + U / z - ICON[0], y0 + V / z - ICON[1])
    m = np.clip((REACH * k - d) / FEATHER, 0, 1)[..., None]
    m = m * m * (3 - 2 * m)
    return rgb * (1 - m) + red * m


# --- Shot B -------------------------------------------------------------------------------------

B_SWITCH = next(n / FPS for n in range(int(A_END * FPS), int(B_END * FPS)) if settings(minute_at(n / FPS))[2])


def shot_b(t):
    minute = minute_at(t)
    intensity, brightness, _ = settings(minute)
    rgb = color_filter(screen_b(minute, B_SWITCH if t >= B_SWITCH else None, t), intensity, brightness)
    art = clock(minute)
    over(rgb, art, (W - art.shape[1]) // 2, 300)
    return rgb


# --- Text ---------------------------------------------------------------------------------------

CAPTION_ART = [pill(lines) for _, _, lines in CAPTIONS]


def captions(rgb, t):
    for (start, end, _), art in zip(CAPTIONS, CAPTION_ART):
        if start <= t < end:
            appear = smooth((t - start) / 0.18) if start > 0 else 1
            leave = smooth((end - t) / 0.12)
            rise = round((1 - appear) * 18)
            over(rgb, art, (W - art.shape[1]) // 2, CAPTION_Y - art.shape[0] // 2 + rise, appear * leave)


# --- End card -----------------------------------------------------------------------------------

# Over the last of shot B, blurred and darkened
LAST_B = shot_b(B_END - 1 / FPS)
END_BACKGROUND = arr(Image.fromarray(rgb8(LAST_B)).filter(ImageFilter.GaussianBlur(72))) * 0.4
ICON_IMAGE = srgb(os.path.join(ASSETS, "icon.png"))
ICON_SIZE, ICON_TOP = 400, 500


def label(text, size, weight, fill):
    f = font(size, weight)
    box = f.getbbox(text)
    image = Image.new("RGBA", (box[2] - box[0] + 4, box[3] - box[1] + 4), (0, 0, 0, 0))
    ImageDraw.Draw(image).text((2 - box[0], 2 - box[1]), text, font=f, fill=fill)
    return arr(image)


# What comes up after the icon: art, top, delay after the end card starts
END_TEXT = [
    (label("Safelight", 132, "Bold", (255, 255, 255)), 960, 0.30),
    (label("White by day, red by night.", 52, "Medium", (236, 228, 230)), 1135, 0.42),
    (label("Free and open source, for Mac", 42, "Regular", (200, 186, 190)), 1290, 0.56),
    (label("github.com/mopfaff/Safelight", 44, "Semibold", (255, 246, 246)), 1350, 0.56),
]


def back_out(x):
    """Eases out, going a little past the end and coming back to it."""
    x = min(max(x, 0.0), 1.0) - 1
    return 1 + 2.7 * x ** 3 + 1.7 * x ** 2


def end_card(t):
    rgb = END_BACKGROUND.copy()
    s = t - B_END
    k = smooth((s - 0.12) / 0.25)
    if k > 0:
        size = round(ICON_SIZE * (0.8 + 0.2 * back_out((s - 0.12) / 0.45)))
        icon = arr(scaled(ICON_IMAGE, size / ICON_IMAGE.width))
        over(rgb, icon, (W - size) // 2, ICON_TOP + (ICON_SIZE - size) // 2, k)
    for art, top, delay in END_TEXT:
        k = smooth((s - delay) / 0.3)
        if k > 0:
            over(rgb, art, (W - art.shape[1]) // 2, top + round((1 - k) * 24), k)
    return rgb


# --- Frames -------------------------------------------------------------------------------------

def frame(t):
    if t < A_END:
        rgb = shot_a(t)
        captions(rgb, t)
    elif t < B_END:
        rgb = shot_b(t)
        captions(rgb, t)
        if t < A_END + XFADE:  # from the last of shot A
            k = smooth((t - A_END) / XFADE)
            last = shot_a(A_END - 1 / FPS)
            captions(last, A_END - 1 / FPS)
            rgb = last * (1 - k) + rgb * k
    else:
        rgb = end_card(t)
        if t < B_END + XFADE:  # the last of shot B blurring into it
            k = smooth((t - B_END) / XFADE)
            last = LAST_B.copy()
            captions(last, B_END - 1 / FPS)
            rgb = last * (1 - k) + rgb * k
    return rgb8(rgb)


if __name__ == "__main__":
    write(frame, END, "safelight-short-reveal", "still-reveal")
