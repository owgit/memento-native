import XCTest
@testable import MementoCapture

final class DirectAutoStartRegistrationTests: XCTestCase {
    func testExecutableURLUsesCurrentBundleExecutableName() {
        let bundleURL = URL(fileURLWithPath: "/Applications/Memento Capture.app", isDirectory: true)

        let executableURL = DirectAutoStartRegistration.executableURL(
            bundleURL: bundleURL,
            executableName: "Memento Capture"
        )

        XCTAssertEqual(
            executableURL.path,
            "/Applications/Memento Capture.app/Contents/MacOS/Memento Capture"
        )
    }

    func testLaunchAgentPlistUsesResolvedExecutablePath() {
        let executableURL = URL(fileURLWithPath: "/Applications/Memento Capture.app/Contents/MacOS/Memento Capture")

        let plist = DirectAutoStartRegistration.plist(executableURL: executableURL)

        XCTAssertEqual(plist["Label"] as? String, "com.memento.capture")
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [executableURL.path])
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist["KeepAlive"] as? Bool, false)
    }
}
