#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE="$ROOT/.build/MouseTrails.app"
DESTINATION="/Applications/MouseTrails.app"
DEVELOPMENT_DESTINATION="$HOME/Applications/MouseTrails.app"
LEGACY_DESTINATION="$HOME/Applications/MouseIncMac.app"

MOUSETRAILS_REQUIRE_STABLE_SIGNING=1 "$ROOT/scripts/build-app.sh"
pkill -x MouseIncMac 2>/dev/null || true
rm -rf "$DESTINATION"
rm -rf "$DEVELOPMENT_DESTINATION"
rm -rf "$LEGACY_DESTINATION"
ditto "$SOURCE" "$DESTINATION"
open -n "$DESTINATION"

echo "$DESTINATION"
