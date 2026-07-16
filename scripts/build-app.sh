#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

swift build -c release

APP="$ROOT/.build/MouseTrails.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"

rm -rf "$APP"
mkdir -p "$MACOS"
cp "$ROOT/.build/release/MouseIncMac" "$MACOS/MouseIncMac"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
mkdir -p "$RESOURCES"
cp "$ROOT/Resources/MouseTrails.icns" "$RESOURCES/MouseTrails.icns"
cp "$ROOT/Resources/default-config.json" "$RESOURCES/default-config.json"

# SwiftPM places Sparkle's binary framework in its artifact cache.  Copy the
# entire framework (including XPC services and symlinks) into the app bundle so
# Sparkle can replace MouseTrails safely after a verified update.
SPARKLE_FRAMEWORK=$(find "$ROOT/.build/artifacts" -type d -name Sparkle.framework -print -quit 2>/dev/null || true)
if [ -z "$SPARKLE_FRAMEWORK" ]; then
    echo "Sparkle.framework was not produced by SwiftPM." >&2
    exit 1
fi
mkdir -p "$FRAMEWORKS"
ditto "$SPARKLE_FRAMEWORK" "$FRAMEWORKS/Sparkle.framework"

# SwiftPM links binary frameworks through @rpath but does not add the standard
# app-bundle Frameworks location to this manually assembled bundle.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/MouseIncMac"

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
