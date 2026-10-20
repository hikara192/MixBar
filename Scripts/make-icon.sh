#!/bin/bash
# Regenerates AppResources/AppIcon.icns from Scripts/make-icon.swift.
# Headless: needs only the Swift toolchain and Xcode CLT's iconutil.
# Usage: Scripts/make-icon.sh [--preview]
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="AppResources/AppIcon.icns"
TMPROOT="${TMPDIR:-/tmp}"
TMPROOT="${TMPROOT%/}"
TMP="$(mktemp -d "$TMPROOT/mixbar-icon.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"

if [ "${1:-}" = "--preview" ]; then
    swift Scripts/make-icon.swift --outdir "$ICONSET" --preview "$TMP/preview.png"
else
    swift Scripts/make-icon.swift --outdir "$ICONSET"
fi

iconutil --convert icns --output "$OUT" "$ICONSET"
echo "Wrote $OUT"

if [ "${1:-}" = "--preview" ]; then
    mkdir -p build
    cp "$TMP/preview.png" build/icon-preview.png
    echo "Wrote build/icon-preview.png"
fi
