#!/bin/bash
# Bundle memento-capture as a proper macOS app

set -e

APP_NAME="Memento Capture"
BUNDLE_ID="com.memento.capture"
APP_DIR="$HOME/Applications/${APP_NAME}.app"

echo "🔨 Building release..."
swift build -c release

echo "📦 Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
cp .build/release/memento-capture "$APP_DIR/Contents/MacOS/"

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
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Memento behöver skärminspelning för att fånga och söka i din skärmhistorik.</string>
</dict>
</plist>
EOF

# Sign the app (ad-hoc signing)
echo "🔐 Signing app..."
codesign --force --deep --sign - "$APP_DIR"

echo ""
echo "✅ App bundle created: $APP_DIR"
echo ""
echo "📋 Nästa steg:"
echo "   1. Öppna Systeminställningar > Integritet och säkerhet > Skärminspelning"
echo "   2. Ta bort gamla memento-capture poster"
echo "   3. Öppna appen: open '$APP_DIR'"
echo "   4. Ge behörighet när dialogen visas"
echo "   5. Starta om appen"

