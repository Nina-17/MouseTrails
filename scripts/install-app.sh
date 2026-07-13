#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE="$ROOT/.build/MouseTrails.app"
DESTINATION="$HOME/Applications/MouseTrails.app"
LEGACY_DESTINATION="$HOME/Applications/MouseIncMac.app"

"$ROOT/scripts/build-app.sh"
pkill -x MouseIncMac 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$DESTINATION"
rm -rf "$LEGACY_DESTINATION"
ditto "$SOURCE" "$DESTINATION"
open -n "$DESTINATION"

echo "$DESTINATION"
