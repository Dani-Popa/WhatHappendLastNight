#!/usr/bin/env bash
#
# make-dmg.sh — package an existing WhatHappendLastNight.app into a drag-to-install .dmg.
#
# Usage:
#   ./scripts/make-dmg.sh /path/to/WhatHappendLastNight.app
#
# Output: dist/WhatHappendLastNight-<version>.dmg
#
set -euo pipefail

APP_SRC="${1:-}"
if [[ -z "$APP_SRC" || ! -d "$APP_SRC" ]]; then
    echo "Usage: $0 /path/to/WhatHappendLastNight.app"
    exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCT="WhatHappendLastNight"
DIST_DIR="$PROJECT_ROOT/dist"
STAGE="$PROJECT_ROOT/build/dmg-stage"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_SRC/Contents/Info.plist" 2>/dev/null || echo "1.0")
DMG_PATH="$DIST_DIR/$PRODUCT-$VERSION.dmg"

mkdir -p "$DIST_DIR"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_SRC" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
    -volname "$PRODUCT" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo "Built: $DMG_PATH"
