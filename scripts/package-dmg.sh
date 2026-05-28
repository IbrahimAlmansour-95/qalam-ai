#!/bin/bash
# Builds a "drag to Applications" install DMG using create-dmg (Homebrew).
# We tried hand-rolled AppleScript first — it kept losing window bounds on
# large displays in macOS Tahoe. create-dmg writes the .DS_Store properly.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="QalamAI"
APP_PATH="./build/Export/QalamAI.app"
DMG_NAME="QalamAI-1.0.0-arm64.dmg"
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

# Notarize + staple when Apple Developer credentials are present. This makes
# the DMG open on any Mac with no Gatekeeper warning and no Terminal dance.
# Requires a paid Apple Developer account. Set:
#   QALAM_NOTARY_APPLE_ID   = your Apple ID email
#   QALAM_NOTARY_TEAM_ID    = your 10-char Team ID
#   QALAM_NOTARY_PASSWORD   = an app-specific password (appleid.apple.com)
# (and QALAM_SIGN_IDENTITY during build.sh so the app is Developer ID signed).
if [[ -n "${QALAM_NOTARY_APPLE_ID:-}" && -n "${QALAM_NOTARY_TEAM_ID:-}" && -n "${QALAM_NOTARY_PASSWORD:-}" ]]; then
    echo "→ Submitting to Apple notary service (this can take a few minutes)…"
    if xcrun notarytool submit "$FINAL_DMG" \
        --apple-id "$QALAM_NOTARY_APPLE_ID" \
        --team-id "$QALAM_NOTARY_TEAM_ID" \
        --password "$QALAM_NOTARY_PASSWORD" \
        --wait; then
        echo "→ Stapling notarization ticket…"
        xcrun stapler staple "$FINAL_DMG" && echo "  ✓ stapled"
        echo "→ Gatekeeper assessment:"
        spctl -a -t open --context context:primary-signature -vv "$FINAL_DMG" 2>&1 | tail -3 || true
    else
        echo "  ✗ Notarization failed — DMG is signed but not notarized."
    fi
else
    echo "ℹ︎ Skipping notarization (set QALAM_NOTARY_* env vars + QALAM_SIGN_IDENTITY to enable)."
    echo "  Without it, recipients on other Macs must clear quarantine — see README."
fi

echo "✓ Done: $FINAL_DMG ($(du -h "$FINAL_DMG" | cut -f1))"
