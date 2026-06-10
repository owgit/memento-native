#!/bin/bash

set -euo pipefail

DEFAULT_VERSION="2.0.4"
if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [version]"
    echo "   or: MEMENTO_VERSION=1.2.3 $0"
    exit 1
fi

VERSION="${MEMENTO_VERSION:-${1:-$DEFAULT_VERSION}}"
PKG_PATH="${MEMENTO_APPSTORE_PKG_PATH:-dist-appstore/Memento-Capture-AppStore-${VERSION}.pkg}"
BUNDLE_ID="${MEMENTO_BUNDLE_ID:-com.memento.capture}"
BUNDLE_VERSION="${MEMENTO_BUNDLE_VERSION:-$VERSION}"
BUNDLE_SHORT_VERSION="${MEMENTO_BUNDLE_SHORT_VERSION:-$VERSION}"
APPLE_APP_ID="${MEMENTO_APPLE_APP_ID:-}"
PROVIDER_PUBLIC_ID="${MEMENTO_PROVIDER_PUBLIC_ID:-}"
WAIT_FOR_PROCESSING="${MEMENTO_WAIT_FOR_PROCESSING:-1}"

if [ ! -f "$PKG_PATH" ]; then
    echo "Package not found: $PKG_PATH"
    echo "Run ./build-appstore-package.sh $VERSION first."
    exit 1
fi

if [ -z "$APPLE_APP_ID" ]; then
    echo "Missing numeric app Apple ID."
    echo "Set MEMENTO_APPLE_APP_ID from App Store Connect."
    exit 1
fi

build_auth_args() {
    if [ -n "${MEMENTO_ASC_API_KEY:-}" ] && [ -n "${MEMENTO_ASC_API_ISSUER:-}" ]; then
        printf -- "--api-key\n%s\n--api-issuer\n%s\n" "$MEMENTO_ASC_API_KEY" "$MEMENTO_ASC_API_ISSUER"
        return
    fi

    if [ -n "${MEMENTO_ASC_USERNAME:-}" ] && [ -n "${MEMENTO_ASC_PASSWORD:-}" ]; then
        printf -- "--username\n%s\n--password\n%s\n" "$MEMENTO_ASC_USERNAME" "$MEMENTO_ASC_PASSWORD"
        return
    fi

    echo "Missing App Store Connect authentication."
    echo "Set either:"
    echo "  MEMENTO_ASC_API_KEY + MEMENTO_ASC_API_ISSUER"
    echo "or:"
    echo "  MEMENTO_ASC_USERNAME + MEMENTO_ASC_PASSWORD"
    exit 1
}

mapfile -t AUTH_ARGS < <(build_auth_args)

VALIDATE_CMD=(
    xcrun altool
    --validate-app "$PKG_PATH"
    --output-format json
)

UPLOAD_CMD=(
    xcrun altool
    --upload-package "$PKG_PATH"
    -t macos
    --apple-id "$APPLE_APP_ID"
    --bundle-id "$BUNDLE_ID"
    --bundle-version "$BUNDLE_VERSION"
    --bundle-short-version-string "$BUNDLE_SHORT_VERSION"
    --output-format json
    --show-progress
)

if [ -n "$PROVIDER_PUBLIC_ID" ]; then
    UPLOAD_CMD+=(--provider-public-id "$PROVIDER_PUBLIC_ID")
fi

if [ "$WAIT_FOR_PROCESSING" = "1" ]; then
    UPLOAD_CMD+=(--wait)
fi

echo "Validating package with altool..."
"${VALIDATE_CMD[@]}" "${AUTH_ARGS[@]}"

echo
echo "Uploading package to App Store Connect..."
"${UPLOAD_CMD[@]}" "${AUTH_ARGS[@]}"
