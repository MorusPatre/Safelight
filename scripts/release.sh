#!/bin/zsh
# Builds Safelight (Release) for Apple silicon and Intel, signed ad hoc so no Apple Developer
# account is needed, and puts it in a disk image for a GitHub release, with the update feed that tells
# copies already installed about it. Then it draws the README's screenshots again with
# scripts/screenshots.sh, so they show the version released.
#
#   scripts/release.sh        writes build/release/Safelight.app, Safelight-<version>.dmg and
#                             appcast.xml, and any screenshots in docs/ that have changed

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

# The update feed, appcast.xml, goes on the GitHub release beside the disk image. Each copy of
# Safelight reads the latest release's (SUFeedURL in Safelight/Info.plist) and installs the disk image
# it points to, but only if Sparkle's sign_update signed it with the private key that goes with
# SUPublicEDKey. generate_keys put that key in this Mac's login keychain; without it, a copy that's
# already installed can't be updated again, so keep a backup (generate_keys -x <file> writes one).
SPARKLE="$BUILD_DIR/SourcePackages/artifacts/sparkle/Sparkle/bin"
APPCAST="$OUT/appcast.xml"
rm -f "$APPCAST"
if SIGNATURE=$("$SPARKLE/sign_update" "$DMG"); then
    INFO="$OUT/Safelight.app/Contents/Info.plist"
    BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$INFO")
    MINIMUM_SYSTEM=$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$INFO")
    RELEASE="https://github.com/MorusPatre/Safelight/releases"
    cat >"$APPCAST" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Safelight</title>
        <link>$RELEASE</link>
        <item>
            <title>Safelight $VERSION</title>
            <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
            <sparkle:version>$BUILD_NUMBER</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$MINIMUM_SYSTEM</sparkle:minimumSystemVersion>
            <sparkle:fullReleaseNotesLink>$RELEASE/tag/v$VERSION</sparkle:fullReleaseNotesLink>
            <enclosure url="$RELEASE/download/v$VERSION/Safelight-$VERSION.dmg" $SIGNATURE type="application/octet-stream"/>
        </item>
    </channel>
</rss>
EOF
    # Signed as well (SURequireSignedFeed), so no one else can change what it says about the update
    "$SPARKLE/sign_update" "$APPCAST" >/dev/null
    echo "Update feed for $VERSION: $APPCAST (attach it to the v$VERSION release with the disk image)"
else
    echo "No update feed: sign_update couldn't sign the disk image (is Sparkle's private key in this Mac's keychain?)" >&2
fi

scripts/screenshots.sh || echo "The screenshots weren't drawn again; the disk image is ready all the same." >&2
