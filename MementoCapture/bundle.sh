#!/bin/bash
# Bundle memento-capture as a proper macOS app

set -e

APP_NAME="Memento Capture"
BUNDLE_ID="com.memento.capture"
APP_DIR="/Applications/${APP_NAME}.app"
BINARY_PATH="$APP_DIR/Contents/MacOS/memento-capture"

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
    # Re-sign after binary update
    codesign --force --deep --sign - "$APP_DIR" 2>/dev/null
    echo "✅ Binary updated"
    echo ""
    echo "ℹ️  If screen capture stops working, use the in-app Permission Guide"
    echo "   (Menu > Permissions... > follow instructions)"
    exit 0
fi

# First time - create full bundle
echo "📦 Creating app bundle..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
cp .build/release/memento-capture "$BINARY_PATH"

# Copy icon
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/"

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << EOF
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
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
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
</dict>
</plist>
EOF

# Sign the app (ad-hoc signing)
echo "🔐 Signing app..."
codesign --force --deep --sign - "$APP_DIR"

echo ""
echo "✅ App bundle created: $APP_DIR"
echo ""
echo "📋 First time setup:"
echo "   1. Open System Settings > Privacy & Security > Screen Recording"
echo "   2. Click + and add: $APP_DIR"
echo "   3. Enable it"
echo "   4. Restart the app"
