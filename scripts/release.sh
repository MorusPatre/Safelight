#!/bin/zsh
# Builds Safelight (Release) for Apple silicon and Intel, signed ad hoc so no Apple Developer
# account is needed, and puts it in a disk image for a GitHub release. Then it draws the README's
# screenshots again with scripts/screenshots.sh, so they show the version released.
#
#   scripts/release.sh        writes build/release/Safelight.app and Safelight-<version>.dmg, and any
#                             screenshots in docs/ that have changed

set -eu
cd "${0:A:h}/.."

BUILD_DIR="build"
OUT="$BUILD_DIR/release"
LOG="$BUILD_DIR/release-build.log"
APP="$BUILD_DIR/Build/Products/Release/Safelight.app"

mkdir -p "$OUT"
# The generic destination builds every architecture; without it, xcodebuild builds only this Mac's.
if ! xcodebuild -project Safelight.xcodeproj -scheme Safelight -configuration Release \
        -destination 'generic/platform=macOS' -derivedDataPath "$BUILD_DIR" \
        CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build >"$LOG" 2>&1; then
    echo "Safelight build failed (full log: $LOG):" >&2
    grep -E 'error:' "$LOG" | sort -u | head -20 >&2
    exit 2
fi
codesign --verify --deep --strict "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="$OUT/Safelight-$VERSION.dmg"
STAGE="$OUT/disk-image"
rm -rf "$OUT/Safelight.app" "$STAGE" "$DMG"
ditto "$APP" "$OUT/Safelight.app"

# The disk image's window: Safelight beside a link to Applications, laid out by
# scripts/dmg/DS_Store (which scripts/make-dmg-layout.py writes).
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Safelight.app"
ln -s /Applications "$STAGE/Applications"
cp scripts/dmg/DS_Store "$STAGE/.DS_Store"
hdiutil create -quiet -volname Safelight -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
rm -rf "$STAGE"
echo "Safelight $VERSION ($(lipo -archs "$OUT/Safelight.app/Contents/MacOS/Safelight")): $DMG"

scripts/screenshots.sh || echo "The screenshots weren't drawn again; the disk image is ready all the same." >&2
