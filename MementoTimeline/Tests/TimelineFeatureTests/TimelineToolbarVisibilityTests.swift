import XCTest
@testable import TimelineFeature

final class TimelineToolbarVisibilityTests: XCTestCase {
    func testManualHideSuppressesAutomaticRevealUntilManualShow() {
        var visibility = TimelineToolbarVisibility()

        XCTAssertTrue(visibility.isToolbarVisible)
        XCTAssertFalse(visibility.isManuallyHidden)

        visibility.hideManually()

        XCTAssertFalse(visibility.isToolbarVisible)
        XCTAssertTrue(visibility.isManuallyHidden)
        XCTAssertTrue(visibility.shouldShowRevealButton)

        visibility.showTemporarily()

        XCTAssertFalse(visibility.isToolbarVisible)
        XCTAssertTrue(visibility.isManuallyHidden)

        visibility.showManually()

        XCTAssertTrue(visibility.isToolbarVisible)
        XCTAssertFalse(visibility.isManuallyHidden)
        XCTAssertFalse(visibility.shouldShowRevealButton)
    }
}
