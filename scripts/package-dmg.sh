#!/bin/bash
# Builds a "drag to Applications" install DMG using create-dmg (Homebrew).
# We tried hand-rolled AppleScript first — it kept losing window bounds on
# large displays in macOS Tahoe. create-dmg writes the .DS_Store properly.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="QalamAI"
APP_PATH="./build/Export/QalamAI.app"
VERSION=$(grep 'static let version' Qalam/App/Constants.swift | sed -E 's/.*"([^"]+)".*/\1/')
VERSION=${VERSION:-1.0.0}
DMG_NAME="QalamAI-${VERSION}-arm64.dmg"
FINAL_DMG="./build/${DMG_NAME}"
VOLUME_NAME="QalamAI"
BG_SRC="scripts/dmg-resources/background.png"
BG_SRC_2X="scripts/dmg-resources/background@2x.png"

if [[ ! -d "$APP_PATH" ]]; then
    echo "✗ ERROR: $APP_PATH not found. Run scripts/build.sh first."
    exit 1
fi

CREATE_DMG=$(command -v create-dmg || echo /opt/homebrew/bin/create-dmg)
if [[ ! -x "$CREATE_DMG" ]]; then
    echo "✗ ERROR: create-dmg not found. Install with: brew install create-dmg"
    exit 1
fi

# Pre-flight: kill any prior mount.
hdiutil detach "/Volumes/$VOLUME_NAME" -quiet 2>/dev/null || true
rm -f "$FINAL_DMG"

# Use the 2× background so it stays sharp on Retina mounts. create-dmg accepts
# a single image and writes it as-is.
BG_TO_USE="$BG_SRC_2X"
[[ -f "$BG_TO_USE" ]] || BG_TO_USE="$BG_SRC"

echo "→ Building DMG with create-dmg..."
# Layout matches background.png (800×500 @ 1×):
#   app icon position    = (200, 280)
#   apps shortcut pos    = (600, 280)
#   icon size            = 128 pt
# create-dmg expects coords in the BACKGROUND IMAGE space (not point space),
# so the same numbers we used to render the arrow apply directly.
"$CREATE_DMG" \
    --volname "$VOLUME_NAME" \
    --background "$BG_TO_USE" \
    --window-pos 400 120 \
    --window-size 800 500 \
    --icon-size 128 \
    --icon "$APP_NAME.app" 200 280 \
    --app-drop-link 600 280 \
    --hide-extension "$APP_NAME.app" \
    --format UDZO \
    --no-internet-enable \
    "$FINAL_DMG" \
    "$APP_PATH"

echo "→ Verifying..."
hdiutil verify "$FINAL_DMG" 2>&1 | tail -2

echo "✓ Done: $FINAL_DMG ($(du -h "$FINAL_DMG" | cut -f1))"
