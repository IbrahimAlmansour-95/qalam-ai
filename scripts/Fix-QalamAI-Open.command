#!/bin/bash
# Double-click this file to let QalamAI open on a Mac where macOS blocked it
# with "QalamAI.app can't be opened".
#
# QalamAI is ad-hoc signed (not notarized through a paid Apple Developer
# account), so when it's downloaded to another Mac macOS quarantines it and
# Gatekeeper refuses to launch it. This removes that quarantine flag.
#
# Apple Silicon only — QalamAI does not run on Intel Macs.

set -e

APP="/Applications/QalamAI.app"
if [[ ! -d "$APP" ]]; then
    # Fall back to ~/Applications or alongside this script's parent.
    if [[ -d "$HOME/Applications/QalamAI.app" ]]; then
        APP="$HOME/Applications/QalamAI.app"
    else
        echo "Could not find QalamAI.app in /Applications or ~/Applications."
        echo "Drag QalamAI into your Applications folder first, then run this again."
        read -n 1 -s -r -p "Press any key to close."
        exit 1
    fi
fi

echo "→ Checking your Mac's chip…"
ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" ]]; then
    echo "✗ This Mac is Intel ($ARCH). QalamAI is Apple-Silicon-only and cannot run here."
    read -n 1 -s -r -p "Press any key to close."
    exit 1
fi

echo "→ Removing the quarantine flag from $APP …"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "✓ Done. Opening QalamAI…"
open "$APP"

echo
echo "QalamAI should launch now and appear in your menu bar (the قلم icon)."
read -n 1 -s -r -p "Press any key to close."
