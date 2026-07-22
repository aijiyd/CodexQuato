#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
OUTPUT_DIR="$ROOT_DIR/outputs"
STAGING_DIR="$(mktemp -d /private/tmp/codexquota-package.XXXXXX)"
APP_DIR="$STAGING_DIR/CodexQuota.app"
ZIP_PATH="$OUTPUT_DIR/CodexQuota.app.zip"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cd "$ROOT_DIR"
swift build --disable-sandbox -c release --product CodexQuota

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/.build/release/CodexQuota" "$APP_DIR/Contents/MacOS/CodexQuota"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP_DIR"
plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --verify --deep --strict "$APP_DIR"

mkdir -p "$OUTPUT_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "$ZIP_PATH"
