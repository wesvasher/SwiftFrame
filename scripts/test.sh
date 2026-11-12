#!/bin/zsh
# Run the unit tests.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

xcodegen generate --quiet
xcodebuild -project SwiftFrame.xcodeproj -scheme SwiftFrame -configuration Debug \
  -derivedDataPath build/DerivedData -destination "platform=macOS,arch=$(uname -m)" \
  test -quiet
