---
description: How to build and release the Memento Capture app
---
# Build Memento Capture

## Steps

1. Navigate to `MementoCapture` directory
2. Run `./bundle.sh` to build and update the app

// turbo-all

## Important Reminders

- **Always update version numbers** when making changes
- The build number is automatically generated from timestamp (format: YYYYMMDDHHMM)
- Version is shown in the menu bar dropdown (bottom)
- After rebuilding, the user may need to re-grant Screen Recording permission in System Settings

## Files

- `bundle.sh` - Build script that creates/updates the app bundle
- `Sources/MenuBarManager.swift` - Shows version in menu
- `/Applications/Memento Capture.app/Contents/Info.plist` - Contains version info
