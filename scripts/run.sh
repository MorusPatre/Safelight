#!/bin/zsh
# Builds SlowBurn (Debug) and relaunches it, replacing any running copy.
#
#   scripts/run.sh            build and relaunch
#   scripts/run.sh --if-changed
#                             only rebuild when sources changed since the last launch
#                             (used by the Claude Code Stop hook in .claude/settings.json)

set -u
cd "${0:A:h}/.."

BUILD_DIR="build"
APP="$BUILD_DIR/Build/Products/Debug/SlowBurn.app"
STAMP="$BUILD_DIR/.last-launch"
LOG="$BUILD_DIR/last-build.log"

if [[ "${1:-}" == "--if-changed" && -f "$STAMP" ]]; then
    if [[ -z "$(find SlowBurn SlowBurn.xcodeproj -type f -newer "$STAMP" \
                  -not -path '*/xcuserdata/*' -not -name '.DS_Store' -print -quit)" ]]; then
        exit 0
    fi
fi

mkdir -p "$BUILD_DIR"
if ! xcodebuild -project SlowBurn.xcodeproj -scheme SlowBurn -configuration Debug \
        -derivedDataPath "$BUILD_DIR" build >"$LOG" 2>&1; then
    echo "SlowBurn build failed (full log: $LOG):" >&2
    grep -E 'error:' "$LOG" | sort -u | head -20 >&2
    exit 2
fi

# Quit the running copy, whether it came from Xcode or from here.
if pgrep -xq SlowBurn; then
    killall SlowBurn 2>/dev/null
    for _ in {1..50}; do pgrep -xq SlowBurn || break; sleep 0.1; done
    pgrep -xq SlowBurn && killall -9 SlowBurn 2>/dev/null
fi

# LaunchServices can briefly still see the old copy as running (error -600), so retry.
for attempt in {1..10}; do
    open "$APP" 2>/dev/null && break
    (( attempt == 10 )) && { echo "SlowBurn built but failed to launch: $APP" >&2; exit 2; }
    sleep 0.5
done
touch "$STAMP"
echo "SlowBurn rebuilt and relaunched."
