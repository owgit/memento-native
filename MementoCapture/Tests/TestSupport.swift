import Foundation
import SQLite3
import XCTest

enum TestSupport {
    /// Creates a unique temp directory; caller cleans up via defer if desired.
    static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("memento-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Column names for a table, via an independent connection.
    static func columnNames(table: String, dbPath: String) -> [String] {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var names: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cString = sqlite3_column_text(stmt, 1) {
                names.append(String(cString: cString))
            }
        }
        return names
    }

    /// Scalar integer query (e.g. COUNT(*)), via an independent connection.
    static func scalarInt(_ sql: String, dbPath: String) -> Int {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return -1 }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    /// Executes raw SQL on a fresh connection (for seeding legacy schemas).
    static func executeRaw(_ sql: String, dbPath: String) {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            XCTFail("could not open \(dbPath)")
            return
        }
        defer { sqlite3_close(db) }
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            XCTFail("raw SQL failed: \(sql)")
        }
    }
}
