#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

swift build -c release

APP="$ROOT/.build/MouseTrails.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP"
mkdir -p "$MACOS"
cp "$ROOT/.build/release/MouseIncMac" "$MACOS/MouseIncMac"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
mkdir -p "$RESOURCES"
cp "$ROOT/Resources/MouseTrails.icns" "$RESOURCES/MouseTrails.icns"
cp "$ROOT/Resources/default-config.json" "$RESOURCES/default-config.json"

if command -v codesign >/dev/null 2>&1; then
    IDENTITY=${CODE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
        | head -n 1)}
    if [ -n "$IDENTITY" ]; then
        if ! codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"; then
            if [ "${MOUSETRAILS_REQUIRE_STABLE_SIGNING:-0}" = "1" ]; then
                echo "Apple Development signing failed. The login keychain must be unlocked before installing MouseTrails, otherwise macOS will require its privacy permissions again." >&2
                exit 1
            fi
            echo "Apple Development signing failed; falling back to ad-hoc signing." >&2
            codesign --force --deep --sign - "$APP"
        fi
    elif [ "${MOUSETRAILS_REQUIRE_STABLE_SIGNING:-0}" = "1" ]; then
        echo "No Apple Development signing identity is available; refusing to install an ad-hoc build that would lose macOS privacy permissions after code changes." >&2
        exit 1
    else
        codesign --force --deep --sign - "$APP"
    fi
fi

echo "$APP"
