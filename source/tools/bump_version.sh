#!/usr/bin/env bash
set -euo pipefail

# NEELx Automated Version Bumper & Synchronizer
# Usage:
#   ./source/tools/bump_version.sh               # Auto-bumps beta (e.g. 2.0.0-beta.6 -> 2.0.0-beta.7)
#   ./source/tools/bump_version.sh 2.0.0-beta.7   # Explicit version target
#   ./source/tools/bump_version.sh --package     # Bumps and immediately packages Universal DMG & updates hashes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION_FILE="$SCRIPT_DIR/VERSION"

CURRENT_VERSION="2.0.0-beta.5"
if [ -f "$VERSION_FILE" ]; then
    CURRENT_VERSION="$(cat "$VERSION_FILE" | tr -d '[:space:]')"
fi

TARGET_VERSION=""
DO_PACKAGE=false

for arg in "$@"; do
    case "$arg" in
        --package) DO_PACKAGE=true ;;
        --help|-h)
            echo "Usage: $0 [new_version] [--package]"
            exit 0
            ;;
        *)
            if [[ "$arg" != --* ]]; then
                TARGET_VERSION="$arg"
            fi
            ;;
    esac
done

if [ -z "$TARGET_VERSION" ]; then
    # Auto-increment beta number: e.g. 2.0.0-beta.6 -> 2.0.0-beta.7
    if [[ "$CURRENT_VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+-beta\.)([0-9]+)$ ]]; then
        PREFIX="${BASH_REMATCH[1]}"
        BETA_NUM="${BASH_REMATCH[2]}"
        NEXT_BETA=$((BETA_NUM + 1))
        TARGET_VERSION="${PREFIX}${NEXT_BETA}"
    else
        TARGET_VERSION="${CURRENT_VERSION}.1"
    fi
fi

echo "=========================================="
echo "   Bumping NEELx Version: $CURRENT_VERSION ➔ $TARGET_VERSION"
echo "=========================================="

# 1. Update VERSION file
echo "$TARGET_VERSION" > "$VERSION_FILE"

# 2. Update Casks/neelx.rb
if [ -f "$SCRIPT_DIR/Casks/neelx.rb" ]; then
    sed -i '' "s/version \"[^\"]*\"/version \"$TARGET_VERSION\"/" "$SCRIPT_DIR/Casks/neelx.rb"
fi

# 3. Update website/index.html
if [ -f "$SCRIPT_DIR/website/index.html" ]; then
    sed -i '' "s/$CURRENT_VERSION/$TARGET_VERSION/g" "$SCRIPT_DIR/website/index.html"
fi

# 4. Update website/install.sh
if [ -f "$SCRIPT_DIR/website/install.sh" ]; then
    sed -i '' "s/FALLBACK_VERSION=\"v[^\"]*\"/FALLBACK_VERSION=\"v$TARGET_VERSION\"/" "$SCRIPT_DIR/website/install.sh"
fi

# 5. Update README.md (macOS sections)
if [ -f "$SCRIPT_DIR/README.md" ]; then
    sed -i '' "s/macOS: v$CURRENT_VERSION/macOS: v$TARGET_VERSION/g" "$SCRIPT_DIR/README.md"
fi

# 6. Update source/README.md
if [ -f "$SCRIPT_DIR/source/README.md" ]; then
    sed -i '' "s/$CURRENT_VERSION/$TARGET_VERSION/g" "$SCRIPT_DIR/source/README.md"
fi

echo "✅ macOS version manifests updated to $TARGET_VERSION!"

if [[ "$DO_PACKAGE" == "true" ]]; then
    echo ""
    echo "Packaging Universal DMG for $TARGET_VERSION..."
    "$SCRIPT_DIR/package_dmg.sh" --universal
    
    DMG_PATH="$SCRIPT_DIR/NEELx-v${TARGET_VERSION}-universal.dmg"
    if [ -f "$DMG_PATH" ]; then
        NEW_HASH="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
        echo "Computed SHA-256: $NEW_HASH"
        
        # Inject new SHA-256 into Casks/neelx.rb
        if [ -f "$SCRIPT_DIR/Casks/neelx.rb" ]; then
            sed -i '' "s/sha256 \"[a-f0-9]*\"/sha256 \"$NEW_HASH\"/" "$SCRIPT_DIR/Casks/neelx.rb"
        fi
        
        # Inject new SHA-256 into website/index.html
        if [ -f "$SCRIPT_DIR/website/index.html" ]; then
            sed -i '' -E "s/[a-f0-9]{64}  NEELx-v[0-9a-zA-Z.-]*-universal.dmg/$NEW_HASH  NEELx-v$TARGET_VERSION-universal.dmg/g" "$SCRIPT_DIR/website/index.html"
            sed -i '' -E "s/sha256: <code>[a-f0-9]{64}<\/code>/sha256: <code>$NEW_HASH<\/code>/g" "$SCRIPT_DIR/website/index.html"
        fi

        echo "✅ Injected real SHA-256 into Cask and website!"
    fi
fi

echo ""
echo "Version bump complete: v$TARGET_VERSION"
