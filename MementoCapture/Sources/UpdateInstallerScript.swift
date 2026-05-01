import Foundation

enum UpdateInstallerScript {
    static func render(dmgPath: String, expectedVersion: String) -> String {
        let cleanExpectedVersion = expectedVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

        return """
        #!/bin/bash
        set -euo pipefail

        DMG_PATH=\(shellQuote(dmgPath))
        EXPECTED_VERSION=\(shellQuote(cleanExpectedVersion))
        EXPECTED_BUNDLE_ID="com.memento.capture"
        EXPECTED_TEAM_ID="7GNHCUW7HN"
        DEST_APP="/Applications/Memento Capture.app"
        TMP_APP="/Applications/.Memento Capture.app.installing.$$"
        MOUNT_POINT=$(/usr/bin/mktemp -d /tmp/memento-install.XXXXXX)
        MOUNTED=0
        SPCTL_LOG=""

        cleanup() {
            if [ -n "${SPCTL_LOG:-}" ]; then
                /bin/rm -f "$SPCTL_LOG" || true
            fi
            if [ -n "${TMP_APP:-}" ] && [ -d "$TMP_APP" ]; then
                /bin/rm -rf "$TMP_APP" || true
            fi
            if [ "${MOUNTED:-0}" = "1" ]; then
                /usr/bin/hdiutil detach "$MOUNT_POINT" -quiet || true
            fi
            /bin/rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
        }
        trap cleanup EXIT

        /usr/bin/codesign --verify --verbose=2 "$DMG_PATH" >/dev/null 2>&1
        if ! /usr/bin/codesign -dv --verbose=4 "$DMG_PATH" 2>&1 | /usr/bin/grep -F "TeamIdentifier=$EXPECTED_TEAM_ID" >/dev/null; then
            echo "Downloaded DMG is not signed by the expected team."
            exit 1
        fi

        /usr/bin/hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_POINT" "$DMG_PATH" >/dev/null
        MOUNTED=1

        APP_PATH="$MOUNT_POINT/Memento Capture.app"
        if [ ! -d "$APP_PATH" ]; then
            echo "Memento Capture.app was not found in the DMG."
            exit 1
        fi

        BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Contents/Info.plist")
        APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
        if [ "$BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]; then
            echo "Unexpected bundle identifier: $BUNDLE_ID"
            exit 1
        fi
        if [ "$APP_VERSION" != "$EXPECTED_VERSION" ]; then
            echo "Unexpected app version: $APP_VERSION"
            exit 1
        fi

        /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null 2>&1
        if ! /usr/bin/codesign -dv --verbose=4 "$APP_PATH" 2>&1 | /usr/bin/grep -F "TeamIdentifier=$EXPECTED_TEAM_ID" >/dev/null; then
            echo "Memento Capture.app is not signed by the expected team."
            exit 1
        fi

        SPCTL_LOG=$(/usr/bin/mktemp /tmp/memento-spctl.XXXXXX)
        if ! /usr/sbin/spctl -a -vv --type execute "$APP_PATH" >"$SPCTL_LOG" 2>&1; then
            if ! /usr/bin/grep -Fqi "Unnotarized Developer ID" "$SPCTL_LOG"; then
                /bin/cat "$SPCTL_LOG"
                exit 1
            fi
        fi
        /bin/rm -f "$SPCTL_LOG"
        SPCTL_LOG=""

        /bin/rm -rf "$TMP_APP"
        /usr/bin/ditto "$APP_PATH" "$TMP_APP"
        /usr/bin/codesign --verify --deep --strict --verbose=2 "$TMP_APP" >/dev/null 2>&1
        /bin/rm -rf "$DEST_APP"
        /bin/mv "$TMP_APP" "$DEST_APP"
        /usr/bin/codesign --verify --deep --strict --verbose=2 "$DEST_APP" >/dev/null 2>&1
        TMP_APP=""
        """
    }

    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
