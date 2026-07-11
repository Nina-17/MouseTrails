#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

swift build -c release

APP="$ROOT/.build/MouseIncMac.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

rm -rf "$APP"
mkdir -p "$MACOS"
cp "$ROOT/.build/release/MouseIncMac" "$MACOS/MouseIncMac"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

if command -v codesign >/dev/null 2>&1; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
        | head -n 1)
    if [ -n "$IDENTITY" ]; then
        codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"
    else
        codesign --force --deep --sign - "$APP"
    fi
fi

echo "$APP"
