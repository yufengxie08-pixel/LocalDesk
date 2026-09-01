#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/LocalDesk.app"

cd "$ROOT_DIR"
UNIVERSAL_BINARY="$ROOT_DIR/.build/universal/LocalDesk"
"$ROOT_DIR/scripts/build-universal.sh" "$UNIVERSAL_BINARY"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$UNIVERSAL_BINARY" "$APP_DIR/Contents/MacOS/LocalDesk"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP_DIR"
echo "Built $APP_DIR"
