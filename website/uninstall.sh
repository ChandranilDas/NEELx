#!/usr/bin/env bash
#
# NEELx — 1-Click macOS Uninstaller
#
# Usage:
#   curl -fsSL https://chandranildas.github.io/NEELx/uninstall.sh | bash
#
set -euo pipefail

echo ""
echo "=========================================="
echo "   NEELx for macOS — 1-Click Uninstaller"
echo "=========================================="
echo ""

echo "Terminating any running NEELx processes..."
pkill -9 NEELx 2>/dev/null || true
sleep 1

if [ -d "/Applications/NEELx.app" ]; then
    echo "Removing /Applications/NEELx.app..."
    rm -rf "/Applications/NEELx.app"
    echo "✓ NEELx has been successfully uninstalled from /Applications."
else
    echo "Notice: /Applications/NEELx.app was not found."
fi

echo ""
echo "Uninstall complete."
