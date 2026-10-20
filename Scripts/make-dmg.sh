#!/bin/bash
# Builds a drag-to-Applications DMG for GitHub Releases.
# The app is ad-hoc signed by build-app.sh: without a paid Apple Developer
# account we cannot notarize it, so Gatekeeper asks for confirmation once.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" AppResources/Info.plist)
CONFIG="${1:-release}"

./Scripts/build-app.sh "$CONFIG"

STAGING=$(mktemp -d "${TMPDIR:-/tmp}/mixbar-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT

cp -R "build/MixBar.app" "$STAGING/MixBar.app"
ln -s /Applications "$STAGING/Applications"

DMG="build/MixBar-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "MixBar" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "Built $DMG"
