#!/bin/zsh
# Makes a 15-second vertical video of Safelight for YouTube Shorts, TikTok, Reels and the like, from
# the README's screenshots: the popover as the screen turns red, the Schedule through an evening as
# the Mac goes red and Dark, then the icon and where to get it. It has no sound, so music can be added
# where it's posted.
#
#   scripts/make-short.sh           writes build/short/safelight-short.mp4
#   scripts/make-short.sh 1 6.5     writes build/short/still-1.0.png and still-6.5.png instead, the
#                                   frames at those seconds, to check a change quickly
#
# The captions and timings are at the top of scripts/short/render.py. The video shows the screenshots
# in docs/, so run scripts/screenshots.sh first if the popover or the Schedule has changed. Needs
# Pillow and NumPy (pip install pillow numpy) and ffmpeg (brew install ffmpeg).
#
# It builds scripts/short/Assets.swift into "Safelight Short.app", with Safelight's icon, to write the
# rest of the pictures the video is made from: the wallpaper, and the icon drawn as large as macOS draws
# it. Nothing on screen or in your settings changes.

set -eu
cd "${0:A:h}/.."

BUILD_DIR="build/short"
NAME="Safelight Short"
APP="$BUILD_DIR/$NAME.app"

rm -rf "$APP" "$BUILD_DIR/assets"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD_DIR/assets"
cp scripts/short/Info.plist "$APP/Contents/Info.plist"
if ! xcrun actool Safelight/AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 15.5 \
        --app-icon AppIcon --output-partial-info-plist "$BUILD_DIR/icon.plist" >"$BUILD_DIR/actool.log" 2>&1; then
    echo "Couldn't compile the app icon (full log: $BUILD_DIR/actool.log)" >&2
    exit 2
fi
if ! xcrun swiftc -swift-version 5 -O -o "$APP/Contents/MacOS/$NAME" scripts/short/Assets.swift >"$BUILD_DIR/build.log" 2>&1; then
    echo "Short app build failed (full log: $BUILD_DIR/build.log):" >&2
    grep -E 'error:' "$BUILD_DIR/build.log" | sort -u | head -20 >&2
    exit 2
fi
codesign --force --sign - "$APP" 2>/dev/null

"$APP/Contents/MacOS/$NAME" "$PWD/$BUILD_DIR/assets"
python3 scripts/short/render.py "$@"
