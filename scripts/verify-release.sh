#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
APP_PATH="${1:-$ROOT_DIR/dist/LocalDesk.app}"
DMG_PATH="${2:-$ROOT_DIR/dist/LocalDesk-$VERSION.dmg}"
REQUIRE_NOTARIZATION_VALUE="${REQUIRE_NOTARIZATION:-0}"

[[ -d "$APP_PATH" ]] || { print -u2 "App 不存在：$APP_PATH"; exit 1; }
[[ -f "$DMG_PATH" ]] || { print -u2 "DMG 不存在：$DMG_PATH"; exit 1; }

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
plutil -lint "$APP_PATH/Contents/Info.plist"
lipo "$APP_PATH/Contents/MacOS/LocalDesk" -verify_arch arm64 x86_64
hdiutil verify "$DMG_PATH"

BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
[[ "$BUNDLE_VERSION" == "$VERSION" ]] || { print -u2 "版本不一致：$BUNDLE_VERSION != $VERSION"; exit 1; }

SIGNATURE_DETAILS="$(codesign -dvvv "$APP_PATH" 2>&1)"
if [[ "$SIGNATURE_DETAILS" == *"Signature=adhoc"* ]]; then
    print "Signature: ad-hoc（本地测试版）"
else
    print "Signature: Developer ID"
    spctl --assess --type execute --verbose=2 "$APP_PATH"
fi

if xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1; then
    print "Notarization ticket: valid"
elif [[ "$REQUIRE_NOTARIZATION_VALUE" == "1" ]]; then
    print -u2 "要求公证，但 DMG 没有有效公证票据。"
    exit 1
else
    print "Notarization ticket: not present（本地测试版允许）"
fi

if [[ "$REQUIRE_NOTARIZATION_VALUE" == "1" ]]; then
    xcrun stapler validate "$APP_PATH"
fi

MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/localdesk-verify.XXXXXX")"
cleanup() {
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
    rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
}
trap cleanup EXIT
hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_POINT" -quiet
[[ -d "$MOUNT_POINT/LocalDesk.app" ]] || { print -u2 "DMG 中缺少 LocalDesk.app"; exit 1; }
[[ -L "$MOUNT_POINT/Applications" ]] || { print -u2 "DMG 中缺少 Applications 快捷方式"; exit 1; }
[[ -f "$MOUNT_POINT/安装说明.txt" ]] || { print -u2 "DMG 中缺少安装说明"; exit 1; }

print "DMG contents: valid"
print "SHA-256: $(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
