#!/usr/bin/env python3
# Writes scripts/dmg/DS_Store, the Finder layout of the window Safelight's disk image opens in:
# no toolbar or sidebar, large icons, Safelight on the left and Applications on the right.
# scripts/release.sh copies it into the disk image, so releases need only Xcode's tools.
#
#   python3 -m pip install ds_store     (once)
#   scripts/make-dmg-layout.py
#
# There's no background picture: Finder colours the labels for the window's appearance, not the
# picture's, so they become hard to read on a light picture in Dark mode (or a dark one in Light).
import os
from ds_store import DSStore

WINDOW = (240, 380, 540, 380)  # x, y from the bottom of the screen, width, height
ICON_SIZE = 128
ICONS = {"Safelight.app": (140, 150), "Applications": (400, 150)}  # icon centres in the window

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dmg", "DS_Store")
if os.path.exists(out):
    os.remove(out)
with DSStore.open(out, "w+") as store:
    store["."]["vSrn"] = ("long", 1)
    store["."]["bwsp"] = {
        "WindowBounds": "{{%d, %d}, {%d, %d}}" % WINDOW,
        "ShowToolbar": False, "ShowSidebar": False, "ContainerShowSidebar": False,
        "ShowStatusBar": False, "ShowPathbar": False, "ShowTabView": False,
        "PreviewPaneVisibility": False, "SidebarWidth": 180,
    }
    store["."]["icvp"] = {
        "viewOptionsVersion": 1, "arrangeBy": "none", "iconSize": float(ICON_SIZE), "textSize": 13.0,
        "labelOnBottom": True, "showIconPreview": True, "showItemInfo": False,
        "gridSpacing": 100.0, "gridOffsetX": 0.0, "gridOffsetY": 0.0,
        "scrollPositionX": 0.0, "scrollPositionY": 0.0,
        "backgroundType": 0, "backgroundColorRed": 1.0, "backgroundColorGreen": 1.0, "backgroundColorBlue": 1.0,
    }
    for name, point in ICONS.items():
        store[name]["Iloc"] = point
