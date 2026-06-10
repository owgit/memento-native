import XCTest
@testable import MementoCapture

final class RetentionOptionsTests: XCTestCase {
    func testPresetRecognition() {
        XCTAssertTrue(RetentionOptions.isPreset(1))
        XCTAssertTrue(RetentionOptions.isPreset(7))
        XCTAssertTrue(RetentionOptions.isPreset(30))
        XCTAssertTrue(RetentionOptions.isPreset(RetentionOptions.forever))
        XCTAssertFalse(RetentionOptions.isPreset(12))
        XCTAssertFalse(RetentionOptions.isPreset(365))
    }

    func testClampingCustomDays() {
        XCTAssertEqual(RetentionOptions.clampedCustom(0), 1)
        XCTAssertEqual(RetentionOptions.clampedCustom(-5), 1)
        XCTAssertEqual(RetentionOptions.clampedCustom(12), 12)
        XCTAssertEqual(RetentionOptions.clampedCustom(365), 365)
        XCTAssertEqual(RetentionOptions.clampedCustom(9000), 365)
    }
}
