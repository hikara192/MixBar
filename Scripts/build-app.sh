#!/bin/bash
# Assembles MixBar.app from the SPM binary (walking-skeleton build path).
# Real signing: export MIXBAR_SIGN_IDENTITY="Developer ID Application: ..."
# TCC is tied to the code signature — ad-hoc signing ("-") causes permission
# churn between builds (ADR-007).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN=".build/$CONFIG/MixBarApp"
APP="build/MixBar.app"

if [ ! -f AppResources/AppIcon.icns ]; then
    echo "error: AppResources/AppIcon.icns is missing; run Scripts/make-icon.sh" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MixBarApp"
cp AppResources/Info.plist "$APP/Contents/Info.plist"
cp AppResources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="${MIXBAR_SIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
    codesign --force --options runtime --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi

echo "Built $APP"
echo "Run with: open $APP   (MIXBAR_ENGINE=fake|core)"
