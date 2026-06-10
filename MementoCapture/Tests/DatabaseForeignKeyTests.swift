import Foundation
import XCTest
@testable import MementoCapture

final class DatabaseForeignKeyTests: XCTestCase {
    func testReplacingFrameWithOcrChildrenFailsLoudly() throws {
        let dir = try TestSupport.makeTempDirectory()
        let database = Database(path: dir.appendingPathComponent("memento.db").path)
        defer { database.close() }

        let block = TextBlock(text: "hello", x: 1, y: 2, width: 3, height: 4)
        XCTAssertTrue(database.insertFrame(
            frameId: 1, windowTitle: "App", time: "2026-06-10T00:00:00Z", textBlocks: [block]
        ))

        // REPLACE would delete the old FRAME row and orphan its CONTENT child.
        // With foreign_keys=ON this must fail (loudly) instead.
        XCTAssertFalse(database.insertFrame(
            frameId: 1, windowTitle: "App", time: "2026-06-10T00:00:01Z", textBlocks: []
        ))
    }

    func testReplacingChildlessFrameSucceeds() throws {
        let dir = try TestSupport.makeTempDirectory()
        let database = Database(path: dir.appendingPathComponent("memento.db").path)
        defer { database.close() }

        XCTAssertTrue(database.insertFrame(
            frameId: 2, windowTitle: "App", time: "2026-06-10T00:00:00Z", textBlocks: []
        ))
        XCTAssertTrue(database.insertFrame(
            frameId: 2, windowTitle: "App", time: "2026-06-10T00:00:01Z", textBlocks: []
        ))
    }
}
