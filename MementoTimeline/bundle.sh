#!/bin/bash
# Bundle MementoTimeline as a proper macOS app

set -e

APP_NAME="Memento Timeline"
BUNDLE_ID="com.memento.timeline"
APP_DIR="/Applications/${APP_NAME}.app"
BINARY_PATH="$APP_DIR/Contents/MacOS/MementoTimeline"

echo "🔨 Building release..."
swift build -c release

# Check if app exists and binary is same
if [ -f "$BINARY_PATH" ]; then
    if cmp -s .build/release/MementoTimeline "$BINARY_PATH"; then
        echo "✅ App already up to date"
        exit 0
    fi
    echo "📦 Updating binary..."
    cp .build/release/MementoTimeline "$BINARY_PATH"
    echo "✅ Binary updated"
    exit 0
fi

# First time - create full bundle
echo "📦 Creating app bundle..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp .build/release/MementoTimeline "$BINARY_PATH"

cat > "$APP_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MementoTimeline</string>
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
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "🔐 Signing app..."
codesign --force --deep --sign - "$APP_DIR"

echo ""
echo "✅ App bundle created: $APP_DIR"

