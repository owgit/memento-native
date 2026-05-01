import SwiftUI
import TimelineFeature
import XCTest
@testable import MementoCapture

@MainActor
final class TimelineWindowControllerTests: XCTestCase {
    func testTimelineHostingControllerUsesResizeFriendlySizingOptions() {
        let controller = TimelineWindowController.makeTimelineHostingController(manager: TimelineManager())

        XCTAssertEqual(controller.sizingOptions, [.minSize])
    }

    func testTimelineHostingViewFollowsWindowBoundsAfterResize() {
        let controller = TimelineWindowController.makeTimelineHostingController(manager: TimelineManager())
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 1000, height: 625))
        window.contentView?.layoutSubtreeIfNeeded()

        window.setContentSize(NSSize(width: 1400, height: 875))
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertEqual(controller.view.frame.width, window.contentView?.bounds.width ?? 0, accuracy: 1)
        XCTAssertEqual(controller.view.frame.height, window.contentView?.bounds.height ?? 0, accuracy: 1)
    }
}
