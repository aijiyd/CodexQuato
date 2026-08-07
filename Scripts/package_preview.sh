#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
STAGING_DIR="$(mktemp -d /private/tmp/codexquota-preview.XXXXXX)"
STAGING_APP="$STAGING_DIR/Codex 额度监控 预览版.app"
PREVIEW_APP="$ROOT_DIR/preview/Codex 额度监控 预览版.app"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cd "$ROOT_DIR"
swift build --disable-sandbox -c release --product CodexQuota

mkdir -p "$STAGING_APP/Contents/MacOS" "$STAGING_APP/Contents/Resources"
cp "$ROOT_DIR/.build/release/CodexQuota" "$STAGING_APP/Contents/MacOS/CodexQuota"
cp "$ROOT_DIR/Resources/Info.plist" "$STAGING_APP/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$STAGING_APP/Contents/Resources/AppIcon.icns"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.dengjiayi.codexquota.preview" "$STAGING_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Codex 额度监控 预览版" "$STAGING_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.4.0" "$STAGING_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 10" "$STAGING_APP/Contents/Info.plist"

codesign --force --deep --sign - "$STAGING_APP"
plutil -lint "$STAGING_APP/Contents/Info.plist"
codesign --verify --deep --strict "$STAGING_APP"

mkdir -p "$ROOT_DIR/preview"
rm -rf "$PREVIEW_APP"
ditto "$STAGING_APP" "$PREVIEW_APP"

echo "$PREVIEW_APP"
