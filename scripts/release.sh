#!/bin/bash
# Publishes the current DMG to a GitHub release matching Constants.version.
# Creates the vX.Y.Z release if missing, or replaces its DMG asset if it
# exists. Release notes are pulled from the matching CHANGELOG.md section.
#
# Requires: gh authenticated (`gh auth status`). Safe to re-run.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=$(grep 'static let version' Qalam/App/Constants.swift | sed -E 's/.*"([^"]+)".*/\1/')
VERSION=${VERSION:-1.0.0}
TAG="v${VERSION}"
DMG="./build/QalamAI-${VERSION}-arm64.dmg"

if [[ ! -f "$DMG" ]]; then
    echo "✗ $DMG not found. Run scripts/ship.sh first."
    exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
    echo "✗ gh is not authenticated (run: gh auth login). Skipping release."
    exit 1
fi

# Extract the CHANGELOG section for this version (## X.Y.Z … up to next ##).
NOTES=$(awk -v v="## ${VERSION}" '
    $0 ~ "^"v { capture=1; print; next }
    capture && /^## / { exit }
    capture { print }
' CHANGELOG.md)
[[ -z "$NOTES" ]] && NOTES="QalamAI ${VERSION}"

if gh release view "$TAG" >/dev/null 2>&1; then
    echo "→ Release $TAG exists — replacing DMG asset…"
    gh release upload "$TAG" "$DMG" --clobber
    # Refresh notes too, in case the CHANGELOG changed.
    printf '%s' "$NOTES" | gh release edit "$TAG" --notes-file - >/dev/null 2>&1 || true
else
    echo "→ Creating release $TAG …"
    printf '%s' "$NOTES" | gh release create "$TAG" \
        --target main \
        --title "QalamAI ${VERSION}" \
        --notes-file - \
        "$DMG"
fi

URL=$(gh release view "$TAG" --json url --jq .url 2>/dev/null || echo "")
echo "✓ Published $TAG"
[[ -n "$URL" ]] && echo "  $URL"
