#!/bin/bash

set -euo pipefail

PROVIDER_PUBLIC_ID="${MEMENTO_PROVIDER_PUBLIC_ID:-}"
FILTER_BUNDLE_ID="${MEMENTO_FILTER_BUNDLE_ID:-}"

if [ -z "$PROVIDER_PUBLIC_ID" ]; then
    echo "Missing provider id."
    echo "Set MEMENTO_PROVIDER_PUBLIC_ID from ./list-appstore-providers.sh output."
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

CMD=(
    xcrun altool
    --list-apps
    --provider-public-id "$PROVIDER_PUBLIC_ID"
    --filter-platform macos
    --output-format json
)

if [ -n "$FILTER_BUNDLE_ID" ]; then
    CMD+=(--filter-bundle-id "$FILTER_BUNDLE_ID")
fi

"${CMD[@]}" "${AUTH_ARGS[@]}"
