#!/usr/bin/env bash
set -euo pipefail

# NEELx Beta & Release DMG Packager
# Usage:
#   ./package_dmg.sh                        # Native arch DMG with bundled 3D Depth model (if present)
#   ./package_dmg.sh --lite                 # Lightweight ~15 MB DMG (testers 1-click download 3D Depth in-app)
#   ./package_dmg.sh --universal            # Universal Binary (Apple Silicon arm64 + Intel x86_64)
#   ./package_dmg.sh --notarize             # Submit DMG to Apple notarytool (requires NOTARY_PROFILE env var)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/source/NEELx"
ARCH="$(uname -m)"
VERSION="${NEELX_VERSION:-2.0.0-beta.5}"
IS_LITE=false
IS_UNIVERSAL=false
DO_NOTARIZE=false
BUILD_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --lite)      IS_LITE=true ;;
        --universal) IS_UNIVERSAL=true ;;
        --notarize)  DO_NOTARIZE=true ;;
        *)           BUILD_ARGS+=("$arg") ;;
    esac
done

SUFFIX="$ARCH"
if [[ "$IS_UNIVERSAL" == "true" ]]; then
    SUFFIX="universal"
fi
if [[ "$IS_LITE" == "true" ]]; then
    SUFFIX="${SUFFIX}-lite"
fi

DMG_NAME="NEELx-v${VERSION}-${SUFFIX}.dmg"
DMG_PATH="$SCRIPT_DIR/$DMG_NAME"
STAGE_DIR="/tmp/neelx_dmg_stage"

echo "=========================================="
echo "   Packaging $DMG_NAME"
echo "=========================================="

# 1. Build base NEELx.app
"$SCRIPT_DIR/build.sh" ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}

rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$STAGE_DIR"
ditto --norsrc "$SCRIPT_DIR/NEELx.app" "$STAGE_DIR/NEELx.app"

# 2. Optional Universal Binary (compile x86_64 slice and lipo with arm64)
if [[ "$IS_UNIVERSAL" == "true" ]]; then
    echo "Compiling x86_64 slice for Universal Binary..."
    DEV_DIR="/Applications/Xcode.app/Contents/Developer"
    [ -d "$DEV_DIR" ] || DEV_DIR="$(xcode-select -p)"
    SDK="$DEV_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    SWIFTC="$DEV_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"

    SWIFT_FILES=()
    while IFS= read -r -d '' file; do
        SWIFT_FILES+=("$file")
    done < <(find "$SRC_DIR" -name "*.swift" -print0)

    X86_BIN="/tmp/NEELx_x86_64"
    ARM_BIN="/tmp/NEELx_arm64"
    cp "$STAGE_DIR/NEELx.app/Contents/MacOS/NEELx" "$ARM_BIN"

    "$SWIFTC" \
        -O -whole-module-optimization -parse-as-library \
        -swift-version 5 -default-isolation MainActor \
        -enable-upcoming-feature NonisolatedNonsendingByDefault \
        -sdk "$SDK" -target x86_64-apple-macos15.0 \
        -module-cache-path "$SCRIPT_DIR/ModuleCache" \
        -module-name NEELx -o "$X86_BIN" "${SWIFT_FILES[@]}"

    lipo -create "$ARM_BIN" "$X86_BIN" -output "$STAGE_DIR/NEELx.app/Contents/MacOS/NEELx"
    rm -f "$ARM_BIN" "$X86_BIN"
    echo "✅ Created Universal Binary (arm64 + x86_64)"
fi

# 3. Optional Lite DMG (strips optional 47 MB Depth model; testers 1-click download in-app)
if [[ "$IS_LITE" == "true" ]]; then
    echo "Creating lightweight beta DMG (in-app 3D Depth download enabled)..."
    rm -rf "$STAGE_DIR/NEELx.app/Contents/Resources/DepthAnythingV2SmallF16.mlmodelc"
fi

# Public distribution DMGs must ONLY use a real "Developer ID Application:" cert — NEVER a personal
# "Apple Development:" cert (which can trigger AMFI signature rejections on other users' Macs).
# When no Developer ID cert is installed, ad-hoc '-' runs cleanly on every Mac after Right-Click -> Open.
SIGN_IDENTITY="${NEELX_DIST_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application:" | head -n 1 | awk '{print $2}' || true)"
fi
[ -z "$SIGN_IDENTITY" ] && SIGN_IDENTITY="-"
echo "Public DMG signing identity: $SIGN_IDENTITY"

xattr -cr "$STAGE_DIR/NEELx.app" 2>/dev/null || true
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - --strip-disallowed-xattrs \
        --entitlements "$SRC_DIR/NEELx.entitlements" "$STAGE_DIR/NEELx.app"
else
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp --strip-disallowed-xattrs \
        --entitlements "$SRC_DIR/NEELx.entitlements" "$STAGE_DIR/NEELx.app"
fi
codesign --verify --deep --strict "$STAGE_DIR/NEELx.app"

ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
    -volname "NEELx" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGE_DIR"

# 4. Optional Apple Notarization (requires `xcrun notarytool store-credentials` profile)
if [[ "$DO_NOTARIZE" == "true" ]]; then
    NOTARY_PROFILE="${NOTARY_PROFILE:-neelx-notary}"
    echo "Submitting $DMG_NAME to Apple Notarization (profile: $NOTARY_PROFILE)..."
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    echo "✅ Notarized and stapled!"
fi

SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
SIZE_MB="$(du -m "$DMG_PATH" | awk '{print $1}')"

echo ""
echo "✅ Release DMG ready: $DMG_PATH (${SIZE_MB} MB)"
echo "   SHA-256: $SHA256"
echo "   Upload directly to GitHub Releases — testers drag NEELx.app into Applications!"
