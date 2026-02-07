#!/bin/bash
# Bundle MementoTimeline as a proper macOS app

set -e

APP_NAME="Memento Timeline"
BUNDLE_ID="com.memento.timeline"
APP_DIR="/Applications/${APP_NAME}.app"
BINARY_PATH="$APP_DIR/Contents/MacOS/MementoTimeline"

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

sign_app() {
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
}

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

    BUILD_NUMBER=$(date +%Y%m%d%H%M)
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"

    echo "🔐 Re-signing app..."
    sign_app
    echo "✅ Binary updated (build $BUILD_NUMBER)"
    exit 0
fi

# First time - create full bundle
echo "📦 Creating app bundle..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp .build/release/MementoTimeline "$BINARY_PATH"

# Copy icon
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/"

BUILD_NUMBER=$(date +%Y%m%d%H%M)
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
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "🔐 Signing app..."
sign_app

echo ""
echo "✅ App bundle created: $APP_DIR"
