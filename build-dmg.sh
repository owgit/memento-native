#!/bin/bash
# Build DMG installer for Memento Native
# Creates a professional DMG with both apps

set -euo pipefail

DEFAULT_VERSION="1.0.4"
if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [version]"
    echo "   or: MEMENTO_VERSION=1.2.3 $0"
    exit 1
fi

VERSION="${MEMENTO_VERSION:-${1:-$DEFAULT_VERSION}}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ Invalid version: $VERSION"
    echo "   Expected format: MAJOR.MINOR.PATCH (example: 1.0.4)"
    exit 1
fi

DMG_NAME="Memento-Native-${VERSION}"
DMG_DIR="dist"
STAGING_DIR="${DMG_DIR}/staging"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NOTARY_PROFILE="${MEMENTO_NOTARY_PROFILE:-}"
DMG_PATH="${DMG_DIR}/${DMG_NAME}.dmg"
ALLOW_UNTRUSTED_RELEASE="${MEMENTO_ALLOW_UNTRUSTED_RELEASE:-0}"

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

SIGN_IDENTITY="$(select_sign_identity)"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "⚠️  No signing identity found. Falling back to ad-hoc signing."
    echo "   Set MEMENTO_CODESIGN_IDENTITY=\"Developer ID Application: ...\" for trusted releases."
else
    echo "🔏 Using signing identity: $SIGN_IDENTITY"
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
        echo "   Set MEMENTO_NOTARY_PROFILE to your notarytool keychain profile."
        echo "   For local testing only, set:"
        echo "   MEMENTO_ALLOW_UNTRUSTED_RELEASE=1 ./build-dmg.sh ${VERSION}"
        exit 1
    fi
fi

echo "🏗️  Building Memento Native v${VERSION}"
echo ""

# Clean
rm -rf "$DMG_DIR"
mkdir -p "$STAGING_DIR"

# Build both apps
echo "📦 Building Memento Capture..."
cd MementoCapture
swift build -c release
cd ..

echo "📦 Building Memento Timeline..."
cd MementoTimeline
swift build -c release
cd ..

# Create Memento Capture.app
echo "🎁 Creating Memento Capture.app..."
CAPTURE_APP="${STAGING_DIR}/Memento Capture.app"
mkdir -p "$CAPTURE_APP/Contents/MacOS"
mkdir -p "$CAPTURE_APP/Contents/Resources"

cp MementoCapture/.build/release/memento-capture "$CAPTURE_APP/Contents/MacOS/"
cp MementoCapture/AppIcon.icns "$CAPTURE_APP/Contents/Resources/" 2>/dev/null || true

cat > "$CAPTURE_APP/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>memento-capture</string>
    <key>CFBundleIdentifier</key>
    <string>com.memento.capture</string>
    <key>CFBundleName</key>
    <string>Memento Capture</string>
    <key>CFBundleDisplayName</key>
    <string>Memento Capture</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Memento needs screen recording to capture and search your screen history.</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2024-2025 Uygar Düzgün. PolyForm Noncommercial License.</string>
</dict>
</plist>
EOF

# Create Memento Timeline.app
echo "🎁 Creating Memento Timeline.app..."
TIMELINE_APP="${STAGING_DIR}/Memento Timeline.app"
mkdir -p "$TIMELINE_APP/Contents/MacOS"
mkdir -p "$TIMELINE_APP/Contents/Resources"

cp MementoTimeline/.build/release/MementoTimeline "$TIMELINE_APP/Contents/MacOS/"
cp MementoTimeline/AppIcon.icns "$TIMELINE_APP/Contents/Resources/" 2>/dev/null || true

cat > "$TIMELINE_APP/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MementoTimeline</string>
    <key>CFBundleIdentifier</key>
    <string>com.memento.timeline</string>
    <key>CFBundleName</key>
    <string>Memento Timeline</string>
    <key>CFBundleDisplayName</key>
    <string>Memento Timeline</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2024-2025 Uygar Düzgün. PolyForm Noncommercial License.</string>
</dict>
</plist>
EOF

# Sign both apps
echo "🔐 Signing apps..."
codesign --force --deep --sign "$SIGN_IDENTITY" "$CAPTURE_APP"
codesign --force --deep --sign "$SIGN_IDENTITY" "$TIMELINE_APP"

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
  <text x="300" y="80" text-anchor="middle" fill="#9ca3af" font-family="SF Pro Display, Helvetica" font-size="14">Drag both apps to Applications</text>
  <text x="300" y="380" text-anchor="middle" fill="#4b5563" font-family="SF Pro Display, Helvetica" font-size="11">Then open Memento Capture from Applications</text>
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

1. Drag both apps to Applications folder
2. Open "Memento Capture" from Applications
3. Grant Screen Recording permission when prompted
4. Use "Memento Timeline" to search your history

UPDATING FROM A PREVIOUS VERSION
================================

1. Quit both Memento apps
2. Replace both apps in /Applications
3. Launch Memento Capture first
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

if [ "$SIGN_IDENTITY" != "-" ]; then
    echo "🔐 Signing DMG..."
    codesign --force --sign "$SIGN_IDENTITY" "${DMG_PATH}"
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
