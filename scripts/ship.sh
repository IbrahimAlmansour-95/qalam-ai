#!/bin/bash
# One-shot ship: nuke prior DMG, rebuild app, repackage installer.
# Run this every time you want a fresh distributable.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=$(grep 'static let version' Qalam/App/Constants.swift | sed -E 's/.*"([^"]+)".*/\1/')
VERSION=${VERSION:-1.0.0}
DMG_NAME="QalamAI-${VERSION}-arm64.dmg"
FINAL_DMG="./build/$DMG_NAME"

echo "▶ Cleaning previous artifacts..."
# Detach any prior mount so unlinking the DMG won't fail.
hdiutil detach "/Volumes/QalamAI" -quiet 2>/dev/null || true
rm -f "$FINAL_DMG"
rm -rf ./build/Export
rm -rf ./build/dmg-staging

echo "▶ Building app..."
bash scripts/build.sh

echo "▶ Packaging DMG..."
bash scripts/package-dmg.sh

if [[ ! -f "$FINAL_DMG" ]]; then
    echo "✗ Packaging finished but $FINAL_DMG is missing."
    exit 1
fi

SIZE=$(du -h "$FINAL_DMG" | cut -f1)
echo
echo "════════════════════════════════════════════════════════════════"
echo "✓ FRESH DMG"
echo "  Path:   $FINAL_DMG"
echo "  Size:   $SIZE"
echo "  SHA256: $(shasum -a 256 "$FINAL_DMG" | cut -d' ' -f1)"
echo "  Built:  $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════════════════"

# Always publish the DMG to a GitHub release matching the version. Best-effort:
# skips cleanly when gh isn't authenticated or NO_RELEASE=1 is set.
if [[ "${NO_RELEASE:-0}" != "1" ]]; then
    echo
    echo "▶ Publishing to GitHub releases…"
    bash scripts/release.sh || echo "  (release step skipped — see message above)"
fi
