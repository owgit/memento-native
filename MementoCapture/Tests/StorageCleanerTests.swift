import XCTest
import SQLite3
@testable import MementoCapture

final class StorageCleanerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("memento-storage-cleaner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testDeleteAllClearsContentFTSRows() throws {
        let dbPath = temporaryDirectory.appendingPathComponent("memento.db").path
        let database = Database(path: dbPath)
        XCTAssertTrue(
            database.insertFrame(
                frameId: 0,
                windowTitle: "Finder",
                time: "2026-04-24T09:00:00Z",
                textBlocks: [TextBlock(text: "private searchable text", x: 1, y: 2, width: 3, height: 4)]
            )
        )
        database.close()

        XCTAssertEqual(try scalarCount("CONTENT_FTS", dbPath: dbPath), 1)

        let result = StorageCleaner.cleanup(
            dbPath: dbPath,
            cachePath: temporaryDirectory,
            deleteAll: true
        )

        XCTAssertEqual(result.deletedFrames, 1)
        XCTAssertEqual(try scalarCount("FRAME", dbPath: dbPath), 0)
        XCTAssertEqual(try scalarCount("CONTENT", dbPath: dbPath), 0)
        XCTAssertEqual(try scalarCount("CONTENT_FTS", dbPath: dbPath), 0)
    }

    func testPartialRetentionDeletesOnlyWholeVideoSegments() throws {
        let dbPath = temporaryDirectory.appendingPathComponent("memento.db").path
        let formatter = ISO8601DateFormatter()
        let startDate = Date(timeIntervalSince1970: 1_775_000_000)
        let database = Database(path: dbPath)

        for frameId in 0..<10 {
            XCTAssertTrue(
                database.insertFrame(
                    frameId: frameId,
                    windowTitle: "Safari",
                    time: formatter.string(from: startDate.addingTimeInterval(Double(frameId * 60))),
                    textBlocks: [TextBlock(text: "frame \(frameId)", x: 0, y: 0, width: 10, height: 10)]
                )
            )
        }
        database.close()

        try Data(repeating: 0, count: 32).write(to: temporaryDirectory.appendingPathComponent("0.mp4"))
        try Data(repeating: 0, count: 32).write(to: temporaryDirectory.appendingPathComponent("5.mp4"))

        let cutoff = formatter.string(from: startDate.addingTimeInterval(7 * 60))
        let result = StorageCleaner.cleanup(
            dbPath: dbPath,
            cachePath: temporaryDirectory,
            cutoffISO8601: cutoff,
            framesPerVideo: 5
        )

        XCTAssertEqual(result.deletedFrames, 5)
        XCTAssertEqual(result.deletedVideos, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("0.mp4").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("5.mp4").path))
        XCTAssertEqual(try frameIds(dbPath: dbPath), [5, 6, 7, 8, 9])
        XCTAssertEqual(try scalarCount("CONTENT_FTS", dbPath: dbPath), 5)
    }

    private func scalarCount(_ table: String, dbPath: String) throws -> Int {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \(table)", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }

        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        return Int(sqlite3_column_int(statement, 0))
    }

    private func frameIds(dbPath: String) throws -> [Int] {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "SELECT id FROM FRAME ORDER BY id", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }

        var ids: [Int] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            ids.append(Int(sqlite3_column_int(statement, 0)))
        }
        return ids
    }
}
