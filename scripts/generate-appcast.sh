#!/bin/sh

set -eu

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <archives-directory> <generate_appcast-path> <download-url-prefix>" >&2
    exit 64
fi

ARCHIVES=$1
GENERATE_APPCAST=$2
DOWNLOAD_URL_PREFIX=$3

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
