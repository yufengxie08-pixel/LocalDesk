#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/LocalDesk.app"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
DMG_PATH="$DIST_DIR/LocalDesk-$VERSION.dmg"
SIGNING_IDENTITY_VALUE="${SIGNING_IDENTITY:-}"
NOTARY_PROFILE_VALUE="${NOTARY_PROFILE:-}"

cd "$ROOT_DIR"
swift test
UNIVERSAL_BINARY="$ROOT_DIR/.build/universal/LocalDesk"
"$ROOT_DIR/scripts/build-universal.sh" "$UNIVERSAL_BINARY"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$UNIVERSAL_BINARY" "$APP_DIR/Contents/MacOS/LocalDesk"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

RELEASE_STATUS="local-test-ad-hoc"
if [[ -n "$SIGNING_IDENTITY_VALUE" ]]; then
    codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY_VALUE" "$APP_DIR"
    RELEASE_STATUS="developer-id-signed-not-notarized"
else
    codesign --force --deep --sign - "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
plutil -lint "$APP_DIR/Contents/Info.plist"

RELEASE_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/localdesk-release.XXXXXX")"
DMG_STAGE="$RELEASE_WORK_DIR/dmg"
cleanup() {
    rm -rf "$RELEASE_WORK_DIR"
}
trap cleanup EXIT
mkdir -p "$DMG_STAGE"

if [[ -n "$NOTARY_PROFILE_VALUE" ]]; then
    if [[ -z "$SIGNING_IDENTITY_VALUE" ]]; then
        print -u2 "NOTARY_PROFILE 已设置，但缺少 SIGNING_IDENTITY；不能公证 ad-hoc 构建。"
        exit 2
    fi

    APP_ARCHIVE="$RELEASE_WORK_DIR/LocalDesk-$VERSION.zip"
    ditto -c -k --keepParent "$APP_DIR" "$APP_ARCHIVE"
    xcrun notarytool submit "$APP_ARCHIVE" --keychain-profile "$NOTARY_PROFILE_VALUE" --wait
    xcrun stapler staple "$APP_DIR"
    xcrun stapler validate "$APP_DIR"
fi

cp -R "$APP_DIR" "$DMG_STAGE/LocalDesk.app"
ln -s /Applications "$DMG_STAGE/Applications"
cp "$ROOT_DIR/Resources/INSTALL.txt" "$DMG_STAGE/安装说明.txt"
rm -f "$DMG_PATH"
hdiutil create -volname "LocalDesk $VERSION" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH"

if [[ -n "$SIGNING_IDENTITY_VALUE" ]]; then
    codesign --force --timestamp --sign "$SIGNING_IDENTITY_VALUE" "$DMG_PATH"
fi

if [[ -n "$NOTARY_PROFILE_VALUE" ]]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE_VALUE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    RELEASE_STATUS="developer-id-signed-and-notarized"
fi

CHECKSUM="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
STATUS_PATH="$DIST_DIR/LocalDesk-$VERSION-release-status.txt"
{
    print "LocalDesk $VERSION ($BUILD_NUMBER)"
    print "status=$RELEASE_STATUS"
    print "app=$APP_DIR"
    print "dmg=$DMG_PATH"
    print "sha256=$CHECKSUM"
    if [[ "$RELEASE_STATUS" == "local-test-ad-hoc" ]]; then
        print "note=未检测到 Developer ID 身份；此产物未正式签名或公证，仅用于本机测试。"
    fi
} > "$STATUS_PATH"

print "Release status: $RELEASE_STATUS"
print "App: $APP_DIR"
print "DMG: $DMG_PATH"
print "SHA-256: $CHECKSUM"
print "Status file: $STATUS_PATH"
