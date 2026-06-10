import Foundation
import SQLite3
import XCTest
@testable import MementoCapture

final class DatabaseMigrationTests: XCTestCase {
    func testLegacySchemaGainsNewColumnsOnInit() throws {
        let dir = try TestSupport.makeTempDirectory()
        let dbPath = dir.appendingPathComponent("memento.db").path

        TestSupport.executeRaw(
            "CREATE TABLE FRAME (id INTEGER PRIMARY KEY, window_title TEXT NOT NULL, time TEXT NOT NULL)",
            dbPath: dbPath
        )

        let database = Database(path: dbPath)
        database.close()

        let frameColumns = TestSupport.columnNames(table: "FRAME", dbPath: dbPath)
        for expected in ["url", "tab_title", "app_bundle_id", "clipboard", "app_category"] {
            XCTAssertTrue(frameColumns.contains(expected), "missing FRAME column \(expected)")
        }
    }

    func testRepeatedInitIsIdempotent() throws {
        let dir = try TestSupport.makeTempDirectory()
        let dbPath = dir.appendingPathComponent("memento.db").path

        Database(path: dbPath).close()
        Database(path: dbPath).close()

        let frameColumns = TestSupport.columnNames(table: "FRAME", dbPath: dbPath)
        XCTAssertEqual(frameColumns.filter { $0 == "url" }.count, 1)
        let embeddingColumns = TestSupport.columnNames(table: "EMBEDDING", dbPath: dbPath)
        for expected in ["language", "revision"] {
            XCTAssertTrue(embeddingColumns.contains(expected), "missing EMBEDDING column \(expected)")
        }
    }

    func testColumnExistsHelper() throws {
        let dir = try TestSupport.makeTempDirectory()
        let dbPath = dir.appendingPathComponent("memento.db").path

        let database = Database(path: dbPath)
        defer { database.close() }

        XCTAssertTrue(database.columnExists(table: "FRAME", column: "url"))
        XCTAssertFalse(database.columnExists(table: "FRAME", column: "no_such_column"))
    }
}
