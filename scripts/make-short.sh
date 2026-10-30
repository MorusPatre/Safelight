#!/bin/zsh
# Makes a vertical video of Safelight for YouTube Shorts, TikTok, Reels and the like, from the README's
# screenshots: the popover as the screen turns red, the Schedule through an evening as the Mac goes red
# and Dark, then the icon and where to get it. It has no sound, so music can be added where it's posted.
# It comes in two versions:
#   fade     the first, 15 seconds: the red fades in, the end card is a picture of its own
#            (scripts/short/render.py, build/short/safelight-short.mp4)
#   reveal   12.4 seconds, made to keep people from scrolling past: the red spreads out from the menu
#            bar icon from the first second, close in on the popover, then pulls back to the whole
#            screen (scripts/short/reveal.py, build/short/safelight-short-reveal.mp4)
#
#   scripts/make-short.sh                writes both
#   scripts/make-short.sh reveal         writes only the one named
#   scripts/make-short.sh reveal 1 6.5   writes build/short/still-reveal-1.0.png and still-reveal-6.5.png
#                                        instead, the frames at those seconds, to check a change quickly
#                                        (still-1.0.png and so on for fade, and for both if none is named)
#
# The captions and timings are at the top of each version's script. The video shows the screenshots
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
typeset -A SCRIPTS=(fade render.py reveal reveal.py)

VERSIONS=(fade reveal)
if (( $# )) && (( ${+SCRIPTS[$1]} )); then
    VERSIONS=($1)
    shift
fi

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
# Without this macOS sometimes hasn't looked at the new app yet when it runs, and draws its icon with a
# no-entry sign over it (two runs in three, 2026-10-30)
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

"$APP/Contents/MacOS/$NAME" "$PWD/$BUILD_DIR/assets"
for version in $VERSIONS; do
    python3 "scripts/short/$SCRIPTS[$version]" "$@"
done
