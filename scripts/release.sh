#!/bin/zsh
# Builds Safelight (Release) for Apple silicon and Intel, signed ad hoc so no Apple Developer
# account is needed, and zips it for a GitHub release.
#
#   scripts/release.sh        writes build/release/Safelight.app and Safelight-<version>.zip

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
rm -rf "$OUT/Safelight.app" "$OUT/Safelight-$VERSION.zip"
ditto "$APP" "$OUT/Safelight.app"
# ditto keeps the signature and extended attributes intact, which a plain zip can break.
ditto -c -k --keepParent "$OUT/Safelight.app" "$OUT/Safelight-$VERSION.zip"
echo "Safelight $VERSION ($(lipo -archs "$OUT/Safelight.app/Contents/MacOS/Safelight")): $OUT/Safelight-$VERSION.zip"
