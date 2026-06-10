#!/bin/bash

set -euo pipefail

DEFAULT_VERSION="2.0.4"
if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [version]"
    echo "   or: MEMENTO_VERSION=1.2.3 $0"
    exit 1
fi

VERSION="${MEMENTO_VERSION:-${1:-$DEFAULT_VERSION}}"
APP_GROUP_IDENTIFIER="${MEMENTO_APP_GROUP_IDENTIFIER:-group.com.memento.shared}"
INSTALL_PATH="/Applications"
OUTPUT_DIR="dist-appstore"
APP_PATH="${OUTPUT_DIR}/Memento Capture.app"
PKG_PATH="${OUTPUT_DIR}/Memento-Capture-AppStore-${VERSION}.pkg"
REQS_PLIST="${OUTPUT_DIR}/product-requirements.plist"
REQUIRE_SIGNED_PACKAGE="${MEMENTO_REQUIRE_SIGNED_PACKAGE:-0}"
INSTALLER_IDENTITY="${MEMENTO_INSTALLER_IDENTITY:-}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid version: $VERSION"
    exit 1
fi

if [ ! -x "./build-appstore-bundle.sh" ]; then
    chmod +x ./build-appstore-bundle.sh
fi

./build-appstore-bundle.sh "$VERSION"

cat > "$REQS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>os</key>
    <array>
        <string>14.0</string>
    </array>
    <key>arch</key>
    <array>
        <string>arm64</string>
        <string>x86_64</string>
    </array>
    <key>home</key>
    <false/>
</dict>
</plist>
EOF

PRODUCTBUILD_CMD=(
    productbuild
    --component "$APP_PATH" "$INSTALL_PATH"
    --product "$REQS_PLIST"
    "$PKG_PATH"
)

if [ -n "$INSTALLER_IDENTITY" ]; then
    PRODUCTBUILD_CMD=(
        productbuild
        --sign "$INSTALLER_IDENTITY"
        --timestamp
        --component "$APP_PATH" "$INSTALL_PATH"
        --product "$REQS_PLIST"
        "$PKG_PATH"
    )
else
    echo "No Mac App Store installer identity configured."
    echo "Set MEMENTO_INSTALLER_IDENTITY to your 'Mac Installer Distribution: ...' certificate to create an uploadable package."
    if [ "$REQUIRE_SIGNED_PACKAGE" = "1" ]; then
        exit 1
    fi
    echo "Continuing with an unsigned package for local validation only."
fi

"${PRODUCTBUILD_CMD[@]}"

echo
echo "Package created:"
echo "  $PKG_PATH"
echo
if [ -n "$INSTALLER_IDENTITY" ]; then
    echo "Package signing identity:"
    echo "  $INSTALLER_IDENTITY"
else
    echo "Package is unsigned and cannot be uploaded to App Store Connect."
fi
