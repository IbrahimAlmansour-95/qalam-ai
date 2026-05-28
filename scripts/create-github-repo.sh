#!/bin/bash
# Creates the private GitHub repo and pushes the first commit. Run this once
# AFTER `gh auth login` succeeds.
set -euo pipefail

cd "$(dirname "$0")/.."

REPO_NAME="${1:-qalamai}"
DESCRIPTION="${2:-QalamAI — free local-first AI autocomplete for macOS. Inline ghost text + Tab acceptance in every Mac app.}"

echo "▶ Verifying gh auth..."
if ! gh auth status >/dev/null 2>&1; then
    echo "✗ gh is not authenticated. Run:  gh auth login"
    exit 1
fi
gh auth status 2>&1 | grep "Logged in" | head -1

echo "▶ Creating private repo \"$REPO_NAME\"..."
gh repo create "$REPO_NAME" \
    --private \
    --description "$DESCRIPTION" \
    --source=. \
    --remote=origin \
    --push

URL=$(gh repo view --json url --jq .url)
echo
echo "════════════════════════════════════════════════════════════════"
echo "✓ Repo created and pushed"
echo "  URL: $URL"
echo "  Remote: $(git remote get-url origin)"
echo "════════════════════════════════════════════════════════════════"
echo
echo "Optional next step — attach the DMG as a release:"
echo "  gh release create v1.0.0 \\"
echo "    --title \"QalamAI 1.0.0\" \\"
echo "    --notes-file CHANGELOG.md \\"
echo "    build/QalamAI-1.0.0-arm64.dmg"
