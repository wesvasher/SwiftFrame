#!/bin/zsh
# Build a Release copy of SwiftFrame and package it as dist/SwiftFrame-<version>.dmg
# Usage: scripts/make-dmg.sh [version]   (defaults to MARKETING_VERSION in project.yml)
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

VERSION="${1:-$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' project.yml)}"
VERSION="${VERSION#v}"

xcodegen generate --quiet
xcodebuild -project SwiftFrame.xcodeproj -scheme SwiftFrame -configuration Release \
  -derivedDataPath build/DerivedData -destination 'generic/platform=macOS' \
  MARKETING_VERSION="$VERSION" build -quiet

APP="build/DerivedData/Build/Products/Release/SwiftFrame.app"
# Stage and create the image in a temp dir: hdiutil can't write images to exFAT drives.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/stage" dist
ditto "$APP" "$WORK/stage/SwiftFrame.app"
ln -s /Applications "$WORK/stage/Applications"

DMG="dist/SwiftFrame-$VERSION.dmg"
hdiutil create -volname "SwiftFrame $VERSION" -srcfolder "$WORK/stage" -ov -format UDZO "$WORK/out.dmg" >/dev/null 2>&1
rm -f "$DMG"
cp "$WORK/out.dmg" "$DMG"
echo "Created $DMG"
