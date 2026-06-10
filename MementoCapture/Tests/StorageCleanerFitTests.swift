import Foundation
import XCTest
@testable import MementoCapture

final class StorageCleanerFitTests: XCTestCase {
    /// Seeds 10 frames (1...10) and two 1 MB videos: 1.mp4 (frames 1-5) and
    /// 6.mp4 (frames 6-10). Returns (dir, dbPath).
    private func seedStorage() throws -> (URL, String) {
        let dir = try TestSupport.makeTempDirectory()
        let dbPath = dir.appendingPathComponent("memento.db").path

        let database = Database(path: dbPath)
        for id in 1...10 {
            XCTAssertTrue(database.insertFrame(
                frameId: id, windowTitle: "App", time: "2026-06-10T00:00:0\(id)Z", textBlocks: []
            ))
        }
        database.close()

        try Data(count: 1_000_000).write(to: dir.appendingPathComponent("1.mp4"))
        try Data(count: 1_000_000).write(to: dir.appendingPathComponent("6.mp4"))
        return (dir, dbPath)
    }

    func testEvictsOldestWholeVideoWhenOverCap() throws {
        let (dir, dbPath) = try seedStorage()

        let result = StorageCleaner.cleanupToFit(
            maxBytes: 1_500_000, dbPath: dbPath, cachePath: dir, framesPerVideo: 5
        )

        XCTAssertEqual(result.deletedVideos, 1)
        XCTAssertEqual(result.deletedFrames, 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("1.mp4").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("6.mp4").path))
        XCTAssertEqual(TestSupport.scalarInt("SELECT COUNT(*) FROM FRAME", dbPath: dbPath), 5)
        XCTAssertEqual(TestSupport.scalarInt("SELECT MIN(id) FROM FRAME", dbPath: dbPath), 6)
    }

    func testNeverDeletesTheNewestVideo() throws {
        let (dir, dbPath) = try seedStorage()

        // Cap so small that even deleting 1.mp4 cannot reach it.
        let result = StorageCleaner.cleanupToFit(
            maxBytes: 100_000, dbPath: dbPath, cachePath: dir, framesPerVideo: 5
        )

        XCTAssertEqual(result.deletedVideos, 1, "only the oldest video may go; the newest is protected")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("6.mp4").path))
    }

    func testNoOpWhenUnderCap() throws {
        let (dir, dbPath) = try seedStorage()

        let result = StorageCleaner.cleanupToFit(
            maxBytes: 50_000_000, dbPath: dbPath, cachePath: dir, framesPerVideo: 5
        )

        XCTAssertEqual(result.deletedVideos, 0)
        XCTAssertEqual(result.deletedFrames, 0)
        XCTAssertEqual(TestSupport.scalarInt("SELECT COUNT(*) FROM FRAME", dbPath: dbPath), 10)
    }

    func testNoOpWhenCapIsZero() throws {
        let (dir, dbPath) = try seedStorage()

        let result = StorageCleaner.cleanupToFit(
            maxBytes: 0, dbPath: dbPath, cachePath: dir, framesPerVideo: 5
        )

        XCTAssertEqual(result.deletedVideos, 0)
        XCTAssertEqual(result.deletedFrames, 0)
    }
}
