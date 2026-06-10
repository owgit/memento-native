#!/bin/bash

set -euo pipefail

DEFAULT_VERSION="2.0.4"
PROJECT_FILE="Memento.xcodeproj"
SCHEME="Memento Capture"
if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [version]"
    echo "   or: MEMENTO_VERSION=1.2.3 $0"
    exit 1
fi

VERSION="${MEMENTO_VERSION:-${1:-$DEFAULT_VERSION}}"
APP_GROUP_IDENTIFIER="${MEMENTO_APP_GROUP_IDENTIFIER:-group.com.memento.shared}"
OUTPUT_DIR="dist-appstore"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DERIVED_DATA_DIR="${OUTPUT_DIR}/DerivedData"
CAPTURE_APP="${OUTPUT_DIR}/Memento Capture.app"
BUILT_APP="${DERIVED_DATA_DIR}/Build/Products/Release/Memento Capture.app"
CAPTURE_ENTITLEMENTS="${OUTPUT_DIR}/MementoCapture.appstore.entitlements"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid version: $VERSION"
    exit 1
fi

select_sign_identity() {
    if [ -n "${MEMENTO_CODESIGN_IDENTITY:-}" ]; then
        echo "$MEMENTO_CODESIGN_IDENTITY"
        return
    fi

    local identities
    local detected
    identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    detected="$(printf '%s\n' "$identities" | awk -F'\"' '/Apple Distribution:/{print $2; exit}')"
    if [ -z "$detected" ]; then
        detected="$(printf '%s\n' "$identities" | awk -F'\"' '/Apple Development:/{print $2; exit}')"
    fi
    if [ -z "$detected" ]; then
        detected="-"
    fi
    echo "$detected"
}

render_entitlements() {
    local template_path="$1"
    local output_path="$2"
    sed "s|__APP_GROUP_IDENTIFIER__|${APP_GROUP_IDENTIFIER}|g" "$template_path" > "$output_path"
}

version_to_build_number() {
    echo "$1" | tr -d '.'
}

ensure_project() {
    if [ -f "${SCRIPT_DIR}/project.yml" ] && command -v xcodegen >/dev/null 2>&1; then
        (cd "$SCRIPT_DIR" && xcodegen generate >/dev/null)
    fi

    if [ ! -d "${SCRIPT_DIR}/${PROJECT_FILE}" ]; then
        echo "Missing ${PROJECT_FILE}. Run xcodegen generate first."
        exit 1
    fi
}

build_release_app() {
    local build_number
    build_number="$(version_to_build_number "$VERSION")"

    xcodebuild \
        -project "${SCRIPT_DIR}/${PROJECT_FILE}" \
        -scheme "$SCHEME" \
        -configuration Release \
        -derivedDataPath "${SCRIPT_DIR}/${DERIVED_DATA_DIR}" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGN_ENTITLEMENTS="${SCRIPT_DIR}/${CAPTURE_ENTITLEMENTS}" \
        MARKETING_VERSION="$VERSION" \
        CURRENT_PROJECT_VERSION="$build_number" \
        MEMENTO_DISTRIBUTION_CHANNEL=app-store \
        MEMENTO_APP_GROUP_IDENTIFIER="$APP_GROUP_IDENTIFIER" \
        build
}

sign_app() {
    local app_path="$1"
    local entitlements_path="$2"
    codesign --force --options runtime --timestamp \
        --entitlements "$entitlements_path" \
        --sign "$SIGN_IDENTITY" "$app_path"
}

SIGN_IDENTITY="$(select_sign_identity)"
echo "Using signing identity: $SIGN_IDENTITY"
echo "Using app group: $APP_GROUP_IDENTIFIER"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

ensure_project
render_entitlements "${SCRIPT_DIR}/MementoCapture/MementoCapture.appstore.entitlements.template" "$CAPTURE_ENTITLEMENTS"

echo "Building release app from Xcode project..."
build_release_app

if [ ! -d "$BUILT_APP" ]; then
    echo "Expected app bundle not found at $BUILT_APP"
    exit 1
fi

echo "Copying bundle..."
/usr/bin/ditto "$BUILT_APP" "$CAPTURE_APP"

echo "Signing main capture app..."
sign_app "$CAPTURE_APP" "$CAPTURE_ENTITLEMENTS"

echo "Single-app App Store-style bundle created at:"
echo "  $CAPTURE_APP"
echo
echo "Next step for real submission:"
echo "  - Sign with your Apple Distribution identity"
echo "  - Register the same app group in Apple Developer"
echo "  - Archive/package with your App Store submission flow"
