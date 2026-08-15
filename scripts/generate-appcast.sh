#!/bin/sh

set -eu

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <archives-directory> <generate_appcast-path> <download-url-prefix>" >&2
    exit 64
fi

ARCHIVES=$1
GENERATE_APPCAST=$2
DOWNLOAD_URL_PREFIX=$3

if [ ! -d "$ARCHIVES" ]; then
    echo "Archives directory does not exist: $ARCHIVES" >&2
    exit 1
fi

ARCHIVE_COUNT=0
ARCHIVE_PATH=
for CANDIDATE in "$ARCHIVES"/*.dmg; do
    [ -f "$CANDIDATE" ] || continue
    ARCHIVE_COUNT=$((ARCHIVE_COUNT + 1))
    ARCHIVE_PATH=$CANDIDATE
done

if [ "$ARCHIVE_COUNT" -ne 1 ]; then
    echo "Expected exactly one published DMG in $ARCHIVES; found $ARCHIVE_COUNT." >&2
    exit 1
fi

ARCHIVE_NAME=${ARCHIVE_PATH##*/}
case "$ARCHIVE_NAME" in
    MouseTrails-*.dmg)
        ARCHIVE_VERSION=${ARCHIVE_NAME#MouseTrails-}
        ARCHIVE_VERSION=${ARCHIVE_VERSION%.dmg}
        ;;
    *)
        echo "Unexpected archive name: $ARCHIVE_NAME" >&2
        exit 1
        ;;
esac

if [ -z "$ARCHIVE_VERSION" ]; then
    echo "Could not determine a version from $ARCHIVE_NAME" >&2
    exit 1
fi

EXPECTED_URL_SUFFIX="/releases/download/v${ARCHIVE_VERSION}/"
case "$DOWNLOAD_URL_PREFIX" in
    *"$EXPECTED_URL_SUFFIX") ;;
    *)
        echo "Download URL prefix does not match $ARCHIVE_NAME: $DOWNLOAD_URL_PREFIX" >&2
        exit 1
        ;;
esac

if [ -z "${SPARKLE_ED25519_PRIVATE_KEY:-}" ]; then
    echo "SPARKLE_ED25519_PRIVATE_KEY must be provided through a secure environment variable." >&2
    exit 1
fi

# The private key is supplied on stdin and is never persisted in the checkout.
printf '%s' "$SPARKLE_ED25519_PRIVATE_KEY" | "$GENERATE_APPCAST" \
    --ed-key-file - \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
    --link "https://github.com/Nina-17/MouseTrails" \
    --maximum-versions 3 \
    "$ARCHIVES"
