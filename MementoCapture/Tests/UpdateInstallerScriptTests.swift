import XCTest
@testable import MementoCapture

final class UpdateInstallerScriptTests: XCTestCase {
    func testTeamIdentifierChecksDoNotUseGrepQuietUnderPipefail() {
        let script = UpdateInstallerScript.render(
            dmgPath: "/tmp/Memento-Native-2.1.2.dmg",
            expectedVersion: "v2.1.2"
        )

        XCTAssertTrue(script.contains("set -euo pipefail"))
        XCTAssertFalse(script.contains(#"/usr/bin/grep -Fq "TeamIdentifier=$EXPECTED_TEAM_ID""#))
        XCTAssertEqual(
            countOccurrences(
                of: #"/usr/bin/grep -F "TeamIdentifier=$EXPECTED_TEAM_ID" >/dev/null"#,
                in: script
            ),
            2
        )
    }

    func testInstallReplacesExistingAppInsteadOfOverlayingIt() {
        let script = UpdateInstallerScript.render(
            dmgPath: "/tmp/Memento-Native-2.1.2.dmg",
            expectedVersion: "2.1.2"
        )

        XCTAssertTrue(script.contains(#"DEST_APP="/Applications/Memento Capture.app""#))
        XCTAssertTrue(script.contains(#"TMP_APP="/Applications/.Memento Capture.app.installing.$$""#))
        XCTAssertTrue(script.contains(#"/bin/rm -rf "$DEST_APP""#))
        XCTAssertTrue(script.contains(#"/bin/mv "$TMP_APP" "$DEST_APP""#))
        XCTAssertTrue(script.contains(#"/usr/bin/codesign --verify --deep --strict --verbose=2 "$DEST_APP" >/dev/null 2>&1"#))
        XCTAssertFalse(script.contains(#"/usr/bin/ditto "$APP_PATH" "/Applications/Memento Capture.app""#))
    }

    private func countOccurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}
