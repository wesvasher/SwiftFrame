#!/bin/zsh
# Build a local Debug preview of SwiftFrame and launch it.
# Usage: scripts/build.sh [--no-open]
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

xcodegen generate --quiet
xcodebuild -project SwiftFrame.xcodeproj -scheme SwiftFrame -configuration Debug \
  -derivedDataPath build/DerivedData -destination "platform=macOS,arch=$(uname -m)" \
  build -quiet

APP="build/DerivedData/Build/Products/Debug/SwiftFrame.app"
echo "Built $APP"
# Tell macOS about this build so Finder and the Dock show its current icon.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
if [[ "${1:-}" != "--no-open" ]]; then
  pkill -x SwiftFrame 2>/dev/null || true
  # Wait for the old copy to quit, or `open` can fail with error -600.
  for _ in {1..50}; do pgrep -x SwiftFrame >/dev/null || break; sleep 0.1; done
  # LaunchServices can still be tearing down the old copy; retry briefly.
  for _ in {1..10}; do open "$APP" 2>/dev/null && break; sleep 0.5; done
fi
