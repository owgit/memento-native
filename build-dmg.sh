#!/bin/bash
# Build DMG installer for Memento Native
# Creates a professional DMG with both apps

set -e

VERSION="1.0.0"
DMG_NAME="Memento-Native-${VERSION}"
DMG_DIR="dist"
STAGING_DIR="${DMG_DIR}/staging"

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

cat > "$CAPTURE_APP/Contents/Info.plist" << 'EOF'
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
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
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

# Create Memento Timeline.app
echo "🎁 Creating Memento Timeline.app..."
TIMELINE_APP="${STAGING_DIR}/Memento Timeline.app"
mkdir -p "$TIMELINE_APP/Contents/MacOS"
mkdir -p "$TIMELINE_APP/Contents/Resources"

cp MementoTimeline/.build/release/MementoTimeline "$TIMELINE_APP/Contents/MacOS/"
cp MementoTimeline/AppIcon.icns "$TIMELINE_APP/Contents/Resources/" 2>/dev/null || true

cat > "$TIMELINE_APP/Contents/Info.plist" << 'EOF'
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
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
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

# Sign both apps (ad-hoc)
echo "🔐 Signing apps..."
codesign --force --deep --sign - "$CAPTURE_APP"
codesign --force --deep --sign - "$TIMELINE_APP"

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

Requirements: macOS 14.0+

More info: https://github.com/owgit/memento-native

---

☕️ Support the project
If you find Memento useful, consider buying me a coffee!
https://buymeacoffee.com/uygarduzgun

Thank you for your support! 🙏
EOF

# Create DMG
echo "💿 Creating DMG..."
hdiutil create -volname "Memento Native" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "${DMG_DIR}/${DMG_NAME}.dmg"

# Cleanup
rm -rf "$STAGING_DIR"

echo ""
echo "✅ DMG created: ${DMG_DIR}/${DMG_NAME}.dmg"
echo ""
echo "📊 Size: $(du -h "${DMG_DIR}/${DMG_NAME}.dmg" | cut -f1)"

