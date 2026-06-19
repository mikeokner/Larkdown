#!/bin/sh
set -eu
APP=${1:?Usage: scripts/check-distribution.sh APP}
PLIST="$APP/Contents/Info.plist"
BINARY="$APP/Contents/MacOS/Larkdown"
test -f "$PLIST"
test -x "$BINARY"
test -f "$APP/Contents/Resources/ThirdPartyNotices.txt"
if codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q 'com.apple.security.app-sandbox'; then
    echo 'Release unexpectedly contains App Sandbox entitlements.' >&2
    exit 1
fi
SIGNATURE=$(codesign -dv --verbose=4 "$APP" 2>&1)
if printf '%s\n' "$SIGNATURE" | grep -q 'Authority=Developer ID Application'; then
    printf '%s\n' "$SIGNATURE" | grep -Eq 'flags=.*runtime' || { echo 'Developer ID build lacks hardened runtime.' >&2; exit 1; }
fi
test -d "$APP/Contents/Frameworks/Sparkle.framework"
otool -L "$BINARY" | grep -q Sparkle
/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$PLIST" | grep -q '^https://'

# Signing problems such as library validation only show up at launch.
"$BINARY" >/dev/null 2>&1 &
PID=$!
sleep 3
if ! kill -0 "$PID" 2>/dev/null; then
    echo 'The app exited during launch.' >&2
    exit 1
fi
kill "$PID"
echo "Verified bundle: $APP"
