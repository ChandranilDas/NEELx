#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "   Building NEELx for macOS"
echo "=========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/source/NEELx"
APP_BUNDLE="$SCRIPT_DIR/NEELx.app"
ARCH="$(uname -m)"

# Locate Xcode toolchain
if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    DEV_DIR="/Applications/Xcode.app/Contents/Developer"
else
    DEV_DIR="$(xcode-select -p)"
fi

SDK="$DEV_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
SWIFTC="$DEV_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
COREMLC="$DEV_DIR/usr/bin/coremlc"
ACTOOL="$DEV_DIR/usr/bin/actool"

if [ ! -x "$SWIFTC" ]; then
    echo "Error: swiftc not found. Please install Xcode from the Mac App Store."
    exit 1
fi

echo "Architecture: $ARCH"
echo "SDK: $SDK"

# Prepare app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy static resources (animations, icons, precompiled models if present)
cp -R "$SRC_DIR/Resources/"* "$APP_BUNDLE/Contents/Resources/"

# Optional: fetch Stage 3 Neural 3D Depth model if requested
for arg in "$@"; do
    if [[ "$arg" == "--with-depth" ]]; then
        if [ ! -d "$SRC_DIR/Models/DepthAnythingV2SmallF16.mlpackage" ]; then
            echo "Fetching Stage 3 Neural 3D Depth model (DepthAnythingV2SmallF16)..."
            python3 "$SCRIPT_DIR/source/tools/fetch_depth_model.py"
        fi
    fi
done

# Compile Core ML ArcFace model from .mlpackage if not already compiled
if [ ! -d "$APP_BUNDLE/Contents/Resources/ArcFace.mlmodelc" ] && [ -x "$COREMLC" ]; then
    echo "Compiling ArcFace.mlpackage..."
    "$COREMLC" compile "$SRC_DIR/Models/ArcFace.mlpackage" "$APP_BUNDLE/Contents/Resources"
fi

# Compile Stage 3 Neural 3D Depth model if .mlpackage is present
if [ ! -d "$APP_BUNDLE/Contents/Resources/DepthAnythingV2SmallF16.mlmodelc" ] && [ -d "$SRC_DIR/Models/DepthAnythingV2SmallF16.mlpackage" ] && [ -x "$COREMLC" ]; then
    echo "Compiling DepthAnythingV2SmallF16.mlpackage (Stage 3 Neural 3D Depth)..."
    "$COREMLC" compile "$SRC_DIR/Models/DepthAnythingV2SmallF16.mlpackage" "$APP_BUNDLE/Contents/Resources"
fi

# Compile Asset Catalog if not already compiled
if [ ! -f "$APP_BUNDLE/Contents/Resources/Assets.car" ] && [ -x "$ACTOOL" ]; then
    echo "Compiling Assets.xcassets..."
    "$ACTOOL" --compile "$APP_BUNDLE/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 15.0 \
        "$SRC_DIR/Assets.xcassets" >/dev/null
fi

if [ -f "$SCRIPT_DIR/VERSION" ]; then
    VERSION="${NEELX_VERSION:-$(cat "$SCRIPT_DIR/VERSION" | tr -d '[:space:]')}"
else
    VERSION="${NEELX_VERSION:-2.0.0-beta.13}"
fi
if [[ "$VERSION" =~ -beta\.([0-9]+) ]]; then
    DEFAULT_BUILD="${BASH_REMATCH[1]}"
else
    DEFAULT_BUILD="13"
fi
BUILD_NUM="${NEELX_BUILD:-$DEFAULT_BUILD}"

# Write Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>local.neelx</string>
    <key>CFBundleName</key>
    <string>NEELx</string>
    <key>CFBundleDisplayName</key>
    <string>NEELx</string>
    <key>CFBundleExecutable</key>
    <string>NEELx</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUM}</string>
    <key>CFBundleIconFile</key>
    <string>NEELx</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>NEELx uses the camera on-device to recognize your face for unlocking your Mac.</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>NEELx uses Bluetooth Low Energy to detect proximity to your paired phone or tablet for companion biometric unlock.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>NEELx uses Bluetooth to securely communicate with your paired iPhone or iPad.</string>
    <key>NSHumanReadableCopyright</key>
    <string>NEELx — Open-Source Biometric Face Unlock for macOS (MIT License)</string>
</dict>
</plist>
EOF

printf "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Collect all Swift source files
SWIFT_FILES=()
while IFS= read -r -d '' file; do
    SWIFT_FILES+=("$file")
done < <(find "$SRC_DIR" -name "*.swift" -print0)

echo "Compiling ${#SWIFT_FILES[@]} Swift files..."
mkdir -p "$SCRIPT_DIR/ModuleCache"

"$SWIFTC" \
    -O \
    -whole-module-optimization \
    -parse-as-library \
    -swift-version 5 \
    -default-isolation MainActor \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -sdk "$SDK" \
    -target "${ARCH}-apple-macos15.0" \
    -module-cache-path "$SCRIPT_DIR/ModuleCache" \
    -module-name NEELx \
    -o "$APP_BUNDLE/Contents/MacOS/NEELx" \
    "${SWIFT_FILES[@]}"

echo "Cleaning metadata and signing bundle..."
STAGE_BUNDLE="/tmp/NEELx_stage.app"
rm -rf "$STAGE_BUNDLE"
ditto --norsrc "$APP_BUNDLE" "$STAGE_BUNDLE"
xattr -cr "$STAGE_BUNDLE" 2>/dev/null || true
dot_clean "$STAGE_BUNDLE" 2>/dev/null || true

# Use a stable Apple Development identity if available in Keychain so macOS Accessibility & Camera
# permissions survive rebuilds without re-toggling; gracefully fall back to ad-hoc '-' for open-source users.
SIGN_IDENTITY="${NEELX_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development:" | head -n 1 | awk '{print $2}' || true)"
fi
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="-"
    echo "Signing identity: ad-hoc (-)"
else
    echo "Signing identity: $SIGN_IDENTITY (stable developer certificate — preserves macOS permissions across rebuilds)"
fi

codesign --force --sign "$SIGN_IDENTITY" \
    --options runtime \
    --strip-disallowed-xattrs \
    --entitlements "$SRC_DIR/NEELx.entitlements" \
    "$STAGE_BUNDLE"

codesign --verify --deep --strict "$STAGE_BUNDLE"

rm -rf "$APP_BUNDLE"
ditto --norsrc "$STAGE_BUNDLE" "$APP_BUNDLE"
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "✅ Built NEELx.app successfully!"

DO_INSTALL=false
for arg in "$@"; do
    if [[ "$arg" == "--install" ]]; then
        DO_INSTALL=true
    fi
done

if [[ "$DO_INSTALL" == "true" ]]; then
    echo "Installing to /Applications/NEELx.app..."
    pkill -x NEELx 2>/dev/null || true
    rm -rf /Applications/NEELx.app
    ditto --norsrc "$STAGE_BUNDLE" /Applications/NEELx.app
    xattr -cr /Applications/NEELx.app 2>/dev/null || true
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --strip-disallowed-xattrs \
        --entitlements "$SRC_DIR/NEELx.entitlements" /Applications/NEELx.app
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted /Applications/NEELx.app 2>/dev/null || true
    mdimport /Applications/NEELx.app 2>/dev/null || true
    rm -rf "$STAGE_BUNDLE"
    echo "✅ Installed to /Applications/NEELx.app! Launching..."
    open /Applications/NEELx.app
else
    rm -rf "$STAGE_BUNDLE"
    echo "Run './build.sh --install' to install into /Applications and launch NEELx."
fi
