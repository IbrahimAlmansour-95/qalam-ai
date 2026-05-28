#!/bin/bash
# Manual build script — bypasses xcodebuild (which is broken on this machine due
# to an Xcode 26.5 / DVTDownloads framework symbol mismatch). Uses swiftc,
# iconutil, codesign, and embeds Ollama.app inside the bundle.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="QalamAI"
BUNDLE_ID="com.qalamai.app"
BUILD_DIR="./build"
EXPORT_DIR="$BUILD_DIR/Export"
APP_BUNDLE="$EXPORT_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
HELPERS_DIR="$CONTENTS/Helpers"

# Where we cache the downloaded Ollama-darwin.zip between rebuilds.
CACHE_DIR="$BUILD_DIR/cache"
OLLAMA_ZIP="$CACHE_DIR/Ollama-darwin.zip"
OLLAMA_URL="https://github.com/ollama/ollama/releases/latest/download/Ollama-darwin.zip"

SDK=$(/usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
SWIFTC=$(/usr/bin/xcrun --find swiftc 2>/dev/null || echo /Library/Developer/CommandLineTools/usr/bin/swiftc)

echo "→ Using SDK: $SDK"
echo "→ Using swiftc: $SWIFTC"

# Walk a directory tree and strip every universal Mach-O down to arm64. Files
# that are already arm64-only are left alone; files that are x86_64-only are
# deleted (the arm64 build doesn't need them).
slim_ollama_to_arm64() {
    local root="$1"
    [[ -d "$root" ]] || return 0
    echo "  → Slimming $root to arm64 only ..."
    local before
    before=$(du -sh "$root" | cut -f1)

    local thinned=0
    local removed=0
    local untouched=0

    # Iterate every regular file. Mach-O detection via `file`.
    while IFS= read -r -d '' f; do
        local info
        info=$(file -b "$f" 2>/dev/null || true)
        case "$info" in
            *"Mach-O universal"*|*"universal binary"*)
                if /usr/bin/lipo -info "$f" 2>/dev/null | grep -q "arm64"; then
                    if /usr/bin/lipo -thin arm64 "$f" -output "$f.arm64.tmp" 2>/dev/null; then
                        mv "$f.arm64.tmp" "$f"
                        chmod --reference="$f" "$f.arm64.tmp" 2>/dev/null || true
                        thinned=$((thinned + 1))
                    fi
                else
                    rm -f "$f"
                    removed=$((removed + 1))
                fi
                ;;
            *"Mach-O"*"x86_64"*)
                # x86_64-only Mach-O — useless on arm64.
                rm -f "$f"
                removed=$((removed + 1))
                ;;
            *)
                untouched=$((untouched + 1))
                ;;
        esac
    done < <(find "$root" -type f -print0)

    local after
    after=$(du -sh "$root" | cut -f1)
    echo "    thinned=$thinned removed=$removed untouched=$untouched"
    echo "    $before → $after"
}

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$HELPERS_DIR" "$CACHE_DIR"

echo "→ Gathering Swift sources..."
SOURCES=$(find Qalam -name "*.swift" -not -path "*/build/*" | sort)
NUM_FILES=$(echo "$SOURCES" | wc -l | tr -d ' ')
echo "  $NUM_FILES files"

echo "→ Compiling Swift → $MACOS_DIR/$APP_NAME ..."
"$SWIFTC" \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -O \
  -swift-version 6 \
  -strict-concurrency=complete \
  -module-name "$APP_NAME" \
  -emit-executable \
  -parse-as-library \
  -framework AppKit \
  -framework SwiftUI \
  -framework Foundation \
  -framework ApplicationServices \
  -framework CoreGraphics \
  -framework Carbon \
  -framework ServiceManagement \
  -framework Vision \
  -framework ScreenCaptureKit \
  -framework FoundationModels \
  -o "$MACOS_DIR/$APP_NAME" \
  $SOURCES

echo "→ Building AppIcon.icns via iconutil..."
ICONSET_SRC="Qalam/Resources/Assets.xcassets/AppIcon.appiconset"
ICONSET_TMP="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET_TMP"
mkdir -p "$ICONSET_TMP"
cp "$ICONSET_SRC/icon_16.png"     "$ICONSET_TMP/icon_16x16.png"
cp "$ICONSET_SRC/icon_16@2x.png"  "$ICONSET_TMP/icon_16x16@2x.png"
cp "$ICONSET_SRC/icon_32.png"     "$ICONSET_TMP/icon_32x32.png"
cp "$ICONSET_SRC/icon_32@2x.png"  "$ICONSET_TMP/icon_32x32@2x.png"
cp "$ICONSET_SRC/icon_128.png"    "$ICONSET_TMP/icon_128x128.png"
cp "$ICONSET_SRC/icon_128@2x.png" "$ICONSET_TMP/icon_128x128@2x.png"
cp "$ICONSET_SRC/icon_256.png"    "$ICONSET_TMP/icon_256x256.png"
cp "$ICONSET_SRC/icon_256@2x.png" "$ICONSET_TMP/icon_256x256@2x.png"
cp "$ICONSET_SRC/icon_512.png"    "$ICONSET_TMP/icon_512x512.png"
cp "$ICONSET_SRC/icon_512@2x.png" "$ICONSET_TMP/icon_512x512@2x.png"
iconutil -c icns -o "$RESOURCES_DIR/AppIcon.icns" "$ICONSET_TMP"

echo "→ Copying emoji shortcodes..."
cp Qalam/Resources/emoji-shortcodes.json "$RESOURCES_DIR/"

echo "→ Copying menu bar icon..."
if [[ -f Qalam/Resources/MenuBarIcon.png ]]; then
    cp Qalam/Resources/MenuBarIcon.png "$RESOURCES_DIR/"
    cp Qalam/Resources/MenuBarIcon@2x.png "$RESOURCES_DIR/" 2>/dev/null || true
fi

echo "→ Copying onboarding logo..."
if [[ -f Qalam/Resources/OnboardingLogo.png ]]; then
    cp Qalam/Resources/OnboardingLogo.png "$RESOURCES_DIR/"
    cp Qalam/Resources/OnboardingLogo@2x.png "$RESOURCES_DIR/" 2>/dev/null || true
fi

echo "→ Embedding Ollama engine..."
SKIP_OLLAMA="${SKIP_OLLAMA:-0}"
if [[ "$SKIP_OLLAMA" == "1" ]]; then
    echo "  SKIP_OLLAMA=1 → skipping. The app will auto-download on first launch."
else
    if [[ ! -f "$OLLAMA_ZIP" ]]; then
        echo "  Downloading $OLLAMA_URL → $OLLAMA_ZIP ..."
        if ! curl -fL --progress-bar -o "$OLLAMA_ZIP.tmp" "$OLLAMA_URL"; then
            echo "  ✗ Ollama download failed. The app will auto-install on first launch instead."
            rm -f "$OLLAMA_ZIP.tmp"
        else
            mv "$OLLAMA_ZIP.tmp" "$OLLAMA_ZIP"
        fi
    else
        echo "  Using cached $OLLAMA_ZIP"
    fi
    if [[ -f "$OLLAMA_ZIP" ]]; then
        UNZIP_TMP="$BUILD_DIR/ollama-unzip"
        rm -rf "$UNZIP_TMP"
        mkdir -p "$UNZIP_TMP"
        unzip -q "$OLLAMA_ZIP" -d "$UNZIP_TMP"
        if [[ -d "$UNZIP_TMP/Ollama.app" ]]; then
            cp -R "$UNZIP_TMP/Ollama.app" "$HELPERS_DIR/Ollama.app"
            echo "  ✓ Embedded Ollama.app ($(du -sh "$HELPERS_DIR/Ollama.app" | cut -f1))"
            slim_ollama_to_arm64 "$HELPERS_DIR/Ollama.app"
        else
            echo "  ✗ Ollama.app not found inside zip. The app will auto-install on first launch."
        fi
        rm -rf "$UNZIP_TMP"
    fi
fi

echo "→ Writing Info.plist..."
cp Qalam/Info.plist "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$CONTENTS/Info.plist" 2>/dev/null || true
# Stamp the version from the single source of truth (Constants.version) so the
# bundle, Info.plist and DMG never drift.
VERSION=$(grep 'static let version' Qalam/App/Constants.swift | sed -E 's/.*"([^"]+)".*/\1/')
if [[ -n "$VERSION" ]]; then
    echo "  version: $VERSION"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$CONTENTS/Info.plist" 2>/dev/null || true
fi

echo "→ Writing PkgInfo..."
printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "→ Ad-hoc codesigning with entitlements..."
codesign --force --deep --sign - \
  --entitlements Qalam/Resources/Qalam.entitlements \
  "$APP_BUNDLE"

echo "→ Verifying arm64..."
BINARY="$MACOS_DIR/$APP_NAME"
ARCH_INFO=$(file "$BINARY")
echo "  $ARCH_INFO"
if [[ "$ARCH_INFO" != *"arm64"* ]]; then
    echo "✗ ERROR: Binary is not arm64."
    exit 1
fi
if [[ "$ARCH_INFO" == *"x86_64"* ]]; then
    echo "✗ ERROR: Binary contains x86_64 slice."
    exit 1
fi
echo "✓ arm64 verified."
echo "✓ App at: $APP_BUNDLE"
du -sh "$APP_BUNDLE"
