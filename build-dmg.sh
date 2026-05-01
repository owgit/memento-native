#!/bin/bash
# Build DMG installer for the single-app Memento distribution.

set -euo pipefail

DEFAULT_VERSION="2.1.1"
PROJECT_FILE="Memento.xcodeproj"
SCHEME="Memento Capture"
if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [version]"
    echo "   or: MEMENTO_VERSION=1.2.3 $0"
    exit 1
fi

VERSION="${MEMENTO_VERSION:-${1:-$DEFAULT_VERSION}}"
DISTRIBUTION_CHANNEL="${MEMENTO_DISTRIBUTION_CHANNEL:-direct}"
APP_GROUP_IDENTIFIER="${MEMENTO_APP_GROUP_IDENTIFIER:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ Invalid version: $VERSION"
    echo "   Expected format: MAJOR.MINOR.PATCH (example: 1.0.4)"
    exit 1
fi

DMG_NAME="Memento-Native-${VERSION}"
DMG_DIR="dist"
STAGING_DIR="${DMG_DIR}/staging"
DERIVED_DATA_DIR="${DMG_DIR}/DerivedData"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NOTARY_PROFILE=""
DMG_PATH="${DMG_DIR}/${DMG_NAME}.dmg"
BUILT_APP="${DERIVED_DATA_DIR}/Build/Products/Release/Memento Capture.app"
CAPTURE_APP="${STAGING_DIR}/Memento Capture.app"
ALLOW_UNTRUSTED_RELEASE="${MEMENTO_ALLOW_UNTRUSTED_RELEASE:-0}"
PREFERRED_NOTARY_PROFILES=("MEMENTO_NOTARY" "memento-notary")

resolve_notary_profile() {
    if [ -n "${MEMENTO_NOTARY_PROFILE:-}" ]; then
        echo "$MEMENTO_NOTARY_PROFILE"
        return
    fi

    local profile
    for profile in "${PREFERRED_NOTARY_PROFILES[@]}"; do
        if xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
            echo "$profile"
            return
        fi
    done

    echo ""
}

select_sign_identity() {
    if [ -n "${MEMENTO_CODESIGN_IDENTITY:-}" ]; then
        echo "$MEMENTO_CODESIGN_IDENTITY"
        return
    fi
    if [ -n "${CODESIGN_IDENTITY:-}" ]; then
        echo "$CODESIGN_IDENTITY"
        return
    fi

    local identities
    local detected
    identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    detected="$(printf '%s\n' "$identities" | awk -F'"' '/Developer ID Application:/{print $2; exit}')"
    if [ -z "$detected" ]; then
        detected="$(printf '%s\n' "$identities" | awk -F'"' '/Apple Development:/{print $2; exit}')"
    fi
    if [ -z "$detected" ]; then
        detected="$(printf '%s\n' "$identities" | awk -F'"' '/Mac Developer:/{print $2; exit}')"
    fi
    if [ -n "$detected" ]; then
        echo "$detected"
    else
        echo "-"
    fi
}

version_to_build_number() {
    echo "$1" | tr -d '.'
}

ensure_project() {
    if [ -f "${SCRIPT_DIR}/project.yml" ] && command -v xcodegen >/dev/null 2>&1; then
        (cd "$SCRIPT_DIR" && xcodegen generate >/dev/null)
    fi

    if [ ! -d "${SCRIPT_DIR}/${PROJECT_FILE}" ]; then
        echo "❌ Missing ${PROJECT_FILE}. Run xcodegen generate first."
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
        MARKETING_VERSION="$VERSION" \
        CURRENT_PROJECT_VERSION="$build_number" \
        MEMENTO_DISTRIBUTION_CHANNEL="$DISTRIBUTION_CHANNEL" \
        MEMENTO_APP_GROUP_IDENTIFIER="$APP_GROUP_IDENTIFIER" \
        build
}

SIGN_IDENTITY="$(select_sign_identity)"
NOTARY_PROFILE="$(resolve_notary_profile)"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "⚠️  No signing identity found. Falling back to ad-hoc signing."
    echo "   Set MEMENTO_CODESIGN_IDENTITY=\"Developer ID Application: ...\" for trusted releases."
else
    echo "🔏 Using signing identity: $SIGN_IDENTITY"
fi
if [ -n "$NOTARY_PROFILE" ]; then
    echo "🧾 Using notarization profile: $NOTARY_PROFILE"
fi

if [ "$ALLOW_UNTRUSTED_RELEASE" != "1" ]; then
    if [[ "$SIGN_IDENTITY" != Developer\ ID\ Application:* ]]; then
        echo "❌ Refusing public release build without a Developer ID Application certificate."
        echo "   Current identity: ${SIGN_IDENTITY}"
        echo "   For local testing only, set:"
        echo "   MEMENTO_ALLOW_UNTRUSTED_RELEASE=1 ./build-dmg.sh ${VERSION}"
        exit 1
    fi
    if [ -z "$NOTARY_PROFILE" ]; then
        echo "❌ Refusing public release build without notarization profile."
        echo "   Set MEMENTO_NOTARY_PROFILE to your notarytool keychain profile,"
        echo "   or create one of the default profiles: MEMENTO_NOTARY / memento-notary."
        echo "   Example:"
        echo "   xcrun notarytool store-credentials MEMENTO_NOTARY --apple-id \"<apple-id>\" --team-id \"<team-id>\" --password \"<app-password>\""
        echo "   For local testing only, set:"
        echo "   MEMENTO_ALLOW_UNTRUSTED_RELEASE=1 ./build-dmg.sh ${VERSION}"
        exit 1
    fi
fi

# In local/untrusted mode, prefer ad-hoc signing for compatibility.
# Apple Development certificates are not suitable for public internet distribution.
if [ "$ALLOW_UNTRUSTED_RELEASE" = "1" ] && [[ "$SIGN_IDENTITY" != Developer\ ID\ Application:* ]]; then
    echo "ℹ️  Untrusted release mode: forcing ad-hoc app signing for compatibility."
    SIGN_IDENTITY="-"
fi

echo "🏗️  Building Memento Native v${VERSION}"
echo ""

# Clean
rm -rf "$DMG_DIR"
mkdir -p "$STAGING_DIR"

ensure_project

echo "📦 Building Memento Capture from Xcode project..."
build_release_app

if [ ! -d "$BUILT_APP" ]; then
    echo "❌ Expected app bundle not found at ${BUILT_APP}"
    exit 1
fi

echo "🎁 Staging Memento Capture.app..."
/usr/bin/ditto "$BUILT_APP" "$CAPTURE_APP"

# Sign app (Hardened Runtime + entitlements)
echo "🔐 Signing app..."
codesign --force --options runtime --timestamp \
    --entitlements "${SCRIPT_DIR}/MementoCapture/MementoCapture.entitlements" \
    --sign "$SIGN_IDENTITY" "$CAPTURE_APP"

# Create Applications symlink for DMG
ln -s /Applications "${STAGING_DIR}/Applications"

# Create DMG background
echo "🎨 Creating DMG background..."
mkdir -p "${STAGING_DIR}/.background"
cat > "${STAGING_DIR}/.background/background.svg" << 'EOF'
<svg width="600" height="400" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#1a1a2e"/>
      <stop offset="100%" style="stop-color:#16213e"/>
    </linearGradient>
  </defs>
  <rect width="600" height="400" fill="url(#bg)"/>
  <text x="300" y="50" text-anchor="middle" fill="#a855f7" font-family="SF Pro Display, Helvetica" font-size="28" font-weight="600">Memento Native</text>
  <text x="300" y="80" text-anchor="middle" fill="#9ca3af" font-family="SF Pro Display, Helvetica" font-size="14">Drag Memento Capture to Applications</text>
  <text x="300" y="380" text-anchor="middle" fill="#4b5563" font-family="SF Pro Display, Helvetica" font-size="11">Timeline now opens inside the app</text>
</svg>
EOF

# Convert SVG to PNG (if rsvg-convert available)
if command -v rsvg-convert &> /dev/null; then
    rsvg-convert -w 600 -h 400 "${STAGING_DIR}/.background/background.svg" -o "${STAGING_DIR}/.background/background.png"
fi

# Create README
cat > "${STAGING_DIR}/README.txt" << 'EOF'
MEMENTO NATIVE - Installation
==============================

1. Drag Memento Capture to Applications folder
2. Open "Memento Capture" from Applications
3. Grant Screen Recording permission when prompted
4. Use "Open Timeline" from the menu bar to search your history

UPDATING FROM A PREVIOUS VERSION
================================

1. Quit Memento Capture
2. Replace Memento Capture in /Applications
3. Launch Memento Capture
4. If capture stops working:
   - System Settings -> Privacy & Security -> Screen Recording
   - Toggle Memento Capture OFF/ON, or remove and add it again

Requirements: macOS 14.0+

More info: https://github.com/owgit/memento-native

---

LICENSE: PolyForm Noncommercial 1.0.0
Free for personal use. Commercial sale prohibited.
https://polyformproject.org/licenses/noncommercial/1.0.0

Copyright 2024-2025 Uygar Düzgün

---

☕️ Support the project
If you find Memento useful, consider buying me a coffee!
https://buymeacoffee.com/uygarduzgun
EOF

# Copy LICENSE file
cp LICENSE "${STAGING_DIR}/LICENSE.txt"

# Create DMG
echo "💿 Creating DMG..."
hdiutil create -volname "Memento Native" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "${DMG_PATH}"

if [[ "$SIGN_IDENTITY" == Developer\ ID\ Application:* ]]; then
    echo "🔐 Signing DMG..."
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "${DMG_PATH}"
fi

# Optional notarization for trusted public distribution.
# Requires:
#   - Developer ID Application certificate
#   - MEMENTO_NOTARY_PROFILE set to an existing notarytool keychain profile
if [[ "$SIGN_IDENTITY" == Developer\ ID\ Application:* ]] && [ -n "$NOTARY_PROFILE" ]; then
    echo "🛡️  Notarizing DMG with profile: $NOTARY_PROFILE"
    xcrun notarytool submit "${DMG_PATH}" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "📌 Stapling notarization ticket..."
    xcrun stapler staple "${DMG_PATH}"
elif [ -n "$NOTARY_PROFILE" ]; then
    echo "⚠️  Notarization skipped: selected identity is not Developer ID Application."
else
    echo "ℹ️  Notarization skipped (set MEMENTO_NOTARY_PROFILE to enable)."
fi

# Cleanup
rm -rf "$STAGING_DIR"

echo ""
echo "✅ DMG created: ${DMG_PATH}"
echo ""
echo "📊 Size: $(du -h "${DMG_PATH}" | cut -f1)"
