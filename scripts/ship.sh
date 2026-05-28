#!/bin/bash
# One-shot ship: nuke prior DMG, rebuild app, repackage installer.
# Run this every time you want a fresh distributable.
set -euo pipefail

cd "$(dirname "$0")/.."

DMG_NAME="QalamAI-1.0.0-arm64.dmg"
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
