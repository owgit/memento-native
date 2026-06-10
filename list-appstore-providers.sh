#!/bin/bash

set -euo pipefail

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

xcrun altool --list-providers \
    --output-format json \
    "${AUTH_ARGS[@]}"
