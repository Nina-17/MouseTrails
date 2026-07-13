#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/.build/MouseTrails.app"
DIST="$ROOT/dist"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/MouseTrails-dmg.XXXXXX")
DMG="$DIST/MouseTrails-${VERSION}.dmg"

cleanup() {
    rm -rf "$STAGING"
}
trap cleanup EXIT HUP INT TERM

"$ROOT/scripts/build-app.sh"

mkdir -p "$DIST"
rm -f "$DMG"
ditto "$APP" "$STAGING/MouseTrails.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "MouseTrails" \
    -srcfolder "$STAGING" \
    -format UDZO \
    -ov \
    "$DMG" >/dev/null

echo "$DMG"
