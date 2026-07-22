#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
STAGING_DIR="$(mktemp -d /private/tmp/codexquota-dmg.XXXXXX)"
DMG_ROOT="$STAGING_DIR/Codex 额度监控"
DMG_PATH="$ROOT_DIR/outputs/CodexQuota-$VERSION.dmg"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cd "$ROOT_DIR"
"$ROOT_DIR/Scripts/package_app.sh"

mkdir -p "$DMG_ROOT"
ditto -x -k "$ROOT_DIR/outputs/CodexQuota.app.zip" "$DMG_ROOT"
ln -s /Applications "$DMG_ROOT/Applications"

rm -f "$DMG_PATH"
hdiutil makehybrid \
    -hfs \
    -hfs-volume-name "Codex 额度监控" \
    -o "$DMG_PATH" \
    "$DMG_ROOT"
hdiutil checksum -type SHA256 "$DMG_PATH"

echo "$DMG_PATH"
