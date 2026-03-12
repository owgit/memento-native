#!/bin/bash
# Bundle memento-capture as a proper macOS app

set -e

RELEASE_VERSION="${MEMENTO_VERSION:-2.0.3}"
APP_NAME="Memento Capture"
BUNDLE_ID="com.memento.capture"
APP_DIR="/Applications/${APP_NAME}.app"
BINARY_PATH="$APP_DIR/Contents/MacOS/memento-capture"

select_sign_identity() {
    if [ -n "${MEMENTO_CODESIGN_IDENTITY:-}" ]; then
        echo "$MEMENTO_CODESIGN_IDENTITY"
        return
    fi
    if [ -n "${CODESIGN_IDENTITY:-}" ]; then
        echo "$CODESIGN_IDENTITY"
        return
    fi

    local detected
    detected=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application:.*\|Apple Development:.*\|Mac Developer:.*\)"/\1/p' \
        | head -n 1)
    if [ -n "$detected" ]; then
        echo "$detected"
    else
        echo "-"
    fi
}

SIGN_IDENTITY="$(select_sign_identity)"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "⚠️  No signing identity found. Falling back to ad-hoc signing."
    echo "   Set MEMENTO_CODESIGN_IDENTITY=\"Developer ID Application: ...\" (or Apple Development) for stable signing."
else
    echo "🔏 Using signing identity: $SIGN_IDENTITY"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

sign_app() {
    codesign --force --options runtime --timestamp \
        --entitlements "${SCRIPT_DIR}/MementoCapture.entitlements" \
        --sign "$SIGN_IDENTITY" "$APP_DIR"
}

ensure_apple_events_usage_description() {
    local plist="$APP_DIR/Contents/Info.plist"
    local message="Memento needs Automation access to read the active browser tab URL and title for search history."

    if /usr/libexec/PlistBuddy -c "Print :NSAppleEventsUsageDescription" "$plist" >/dev/null 2>&1; then
        /usr/libexec/PlistBuddy -c "Set :NSAppleEventsUsageDescription $message" "$plist"
    else
        /usr/libexec/PlistBuddy -c "Add :NSAppleEventsUsageDescription string $message" "$plist"
    fi
}

echo "🔨 Building release..."
swift build -c release

# Check if app exists and binary is same (no need to re-bundle)
if [ -f "$BINARY_PATH" ]; then
    if cmp -s .build/release/memento-capture "$BINARY_PATH"; then
        echo "✅ App already up to date, no changes needed"
        exit 0
    fi
    echo "📦 Updating binary..."
    cp .build/release/memento-capture "$BINARY_PATH"
    
    # Update Info.plist with new build number
    BUILD_NUMBER=$(date +%Y%m%d%H%M)
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $RELEASE_VERSION" "$APP_DIR/Contents/Info.plist"
    ensure_apple_events_usage_description
    
    # Re-sign after binary update
    sign_app
    echo "✅ Binary updated (build $BUILD_NUMBER)"
    echo ""
    echo "ℹ️  If screen capture stops working, use the in-app Setup Hub"
    echo "   (Menu > Setup Hub... > follow instructions)"
    exit 0
fi

# First time - create full bundle
echo "📦 Creating app bundle..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
cp .build/release/memento-capture "$BINARY_PATH"

# Copy icon
cp "$SCRIPT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/"

# Create Info.plist with dynamic build number
BUILD_NUMBER=$(date +%Y%m%d%H%M)
cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>memento-capture</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key>
    <string>${RELEASE_VERSION}</string>
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
    <key>NSAppleEventsUsageDescription</key>
    <string>Memento needs Automation access to read the active browser tab URL and title for search history.</string>
</dict>
</plist>
EOF

# Sign the app
echo "🔐 Signing app..."
sign_app

echo ""
echo "✅ App bundle created: $APP_DIR"
echo ""
echo "📋 First time setup:"
echo "   1. Open System Settings > Privacy & Security > Screen Recording"
echo "   2. Click + and add: $APP_DIR"
echo "   3. Enable it"
echo "   4. Restart the app"
