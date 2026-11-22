#!/usr/bin/env bash
#
# NEELx — 1-Click macOS Installer
#
# Bypasses macOS Gatekeeper quarantine automatically by downloading directly via curl,
# removing extended quarantine attributes, installing to /Applications, and launching.
#
# Usage:
#   curl -fsSL https://chandranildas.github.io/NEELx/install.sh | bash
#
set -euo pipefail

REPO="ChandranilDas/NEELx"
FALLBACK_VERSION="v2.0.0-beta.18"
APP_NAME="NEELx"
TARGET_APP="/Applications/${APP_NAME}.app"

echo ""
echo "=========================================="
echo "   NEELx for macOS — 1-Click Installer"
echo "=========================================="
echo ""

# 1. Resolve latest release version (SemVer-aware with fallback)
echo "Checking latest release..."
VERSION=""
if command -v curl >/dev/null 2>&1; then
    # Try official releases/latest endpoint first
    VERSION=$(curl -sSL -H "Accept: application/vnd.github+json" "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | grep -m1 '"tag_name":' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' || true)

    # Fallback to listing releases and sorting by version
    if [ -z "${VERSION}" ]; then
        VERSION=$(curl -sSL -H "Accept: application/vnd.github+json" "https://api.github.com/repos/${REPO}/releases?per_page=20" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' | sort -V | tail -n1 || true)
    fi
fi

# If remote returned nothing, or if fallback is higher, use fallback
if [ -z "${VERSION}" ]; then
    VERSION="${FALLBACK_VERSION}"
else
    HIGHEST=$(printf "%s\n%s\n" "${VERSION}" "${FALLBACK_VERSION}" | sort -V | tail -n1)
    VERSION="${HIGHEST}"
fi
echo "Target version: ${VERSION}"

# 2. Prepare temp working directory
TEMP_DIR=$(mktemp -d /tmp/neelx-install.XXXXXX)
trap 'rm -rf "${TEMP_DIR}"' EXIT

DMG_NAME="NEELx-${VERSION}-universal.dmg"
DMG_URL="https://github.com/${REPO}/releases/download/${VERSION}/${DMG_NAME}"
DMG_PATH="${TEMP_DIR}/${DMG_NAME}"

echo "Downloading ${DMG_NAME} (All-in-One Complete Bundle)..."
curl -fSL --progress-bar "${DMG_URL}" -o "${DMG_PATH}"

# 3. Mount DMG
echo "Mounting disk image..."
MOUNT_POINT=$(hdiutil attach "${DMG_PATH}" -nobrowse -readonly | grep -E '/Volumes/' | awk -F '\t' '{print $NF}' | head -n1)
if [ -z "${MOUNT_POINT}" ] || [ ! -d "${MOUNT_POINT}" ]; then
    echo "Error: Failed to mount disk image."
    exit 1
fi

# Ensure unmount on exit
cleanup_mount() {
    hdiutil detach "${MOUNT_POINT}" -force -quiet || true
}
trap 'cleanup_mount; rm -rf "${TEMP_DIR}"' EXIT

SOURCE_APP="${MOUNT_POINT}/${APP_NAME}.app"
if [ ! -d "${SOURCE_APP}" ]; then
    SOURCE_APP=$(find "${MOUNT_POINT}" -maxdepth 2 -name "${APP_NAME}.app" | head -n1)
fi

if [ -z "${SOURCE_APP}" ] || [ ! -d "${SOURCE_APP}" ]; then
    echo "Error: NEELx.app not found inside DMG."
    exit 1
fi

# 4. Quit existing running instance cleanly if present
pkill -x "${APP_NAME}" 2>/dev/null || true
sleep 0.5

# 5. Install to /Applications
echo "Installing to ${TARGET_APP}..."
rm -rf "${TARGET_APP}"
cp -R "${SOURCE_APP}" "${TARGET_APP}"

# 6. CRITICAL: Strip Gatekeeper Quarantine extended attribute
# This eliminates "Apple could not verify NEELx is free of malware" completely!
echo "Clearing macOS Gatekeeper quarantine..."
xattr -cr "${TARGET_APP}" 2>/dev/null || true

# Re-sign: prefer user's local Apple Development certificate if available in Keychain;
# otherwise fall back to ad-hoc (-) so macOS TCC permissions remain rock solid
if command -v codesign >/dev/null 2>&1; then
    DEV_CERT=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development:" | head -n 1 | awk '{print $2}' || true)
    if [ -n "${DEV_CERT}" ]; then
        echo "Found local developer certificate (${DEV_CERT}) — signing with your certificate to preserve macOS permissions across updates..."
        codesign --force --deep -s "${DEV_CERT}" "${TARGET_APP}" 2>/dev/null || codesign --force --deep -s - "${TARGET_APP}" 2>/dev/null || true
    else
        codesign --force --deep -s - "${TARGET_APP}" 2>/dev/null || true
    fi
fi

# 7. Unmount DMG cleanly
cleanup_mount
trap 'rm -rf "${TEMP_DIR}"' EXIT

echo ""
echo "=========================================="
echo "  Installed NEELx ${VERSION} successfully!"
echo "=========================================="
echo "  Location : ${TARGET_APP}"
echo "  Security : Gatekeeper quarantine cleared"
echo "  Vault    : Preserved in ~/Library/Application Support/NEELx"
echo ""

# 8. Launch NEELx
echo "Launching NEELx..."
open -a "${TARGET_APP}"
echo "Done! Welcome to NEELx."
