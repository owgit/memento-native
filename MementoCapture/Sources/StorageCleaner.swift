import Foundation
import SQLite3

/// Shared storage cleanup utility used by manual cleanup and retention policy.
enum StorageCleaner {
    struct Result {
        let deletedFrames: Int
        let deletedVideos: Int
    }

    static func cleanup(
        dbPath: String,
        cachePath: URL,
        cutoffISO8601: String? = nil,
        deleteAll: Bool = false,
        framesPerVideo: Int = 5
    ) -> Result {
        let frameIdsToDelete: [Int]
        var db: OpaquePointer?

        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            return Result(deletedFrames: 0, deletedVideos: 0)
        }
        defer { sqlite3_close(db) }

        if deleteAll {
            frameIdsToDelete = fetchFrameIds(db: db, sql: "SELECT id FROM FRAME")
            execute(db: db, sql: "BEGIN TRANSACTION")
            execute(db: db, sql: "DELETE FROM EMBEDDING")
            execute(db: db, sql: "DELETE FROM CONTENT")
            execute(db: db, sql: "DELETE FROM FRAME")
            execute(db: db, sql: "COMMIT")
        } else {
            guard let cutoffISO8601 else {
                return Result(deletedFrames: 0, deletedVideos: 0)
            }

            frameIdsToDelete = fetchFrameIdsOlderThan(db: db, cutoffISO8601: cutoffISO8601)
            guard !frameIdsToDelete.isEmpty else {
                return Result(deletedFrames: 0, deletedVideos: 0)
            }

            execute(db: db, sql: "BEGIN TRANSACTION")
            executeWithBoundDate(
                db: db,
                sql: "DELETE FROM EMBEDDING WHERE frame_id IN (SELECT id FROM FRAME WHERE time < ?)",
                cutoffISO8601: cutoffISO8601
            )
            executeWithBoundDate(
                db: db,
                sql: "DELETE FROM CONTENT WHERE frame_id IN (SELECT id FROM FRAME WHERE time < ?)",
                cutoffISO8601: cutoffISO8601
            )
            executeWithBoundDate(
                db: db,
                sql: "DELETE FROM FRAME WHERE time < ?",
                cutoffISO8601: cutoffISO8601
            )
            execute(db: db, sql: "COMMIT")
        }

        let deletedVideos = deleteVideoFiles(
            cachePath: cachePath,
            deletedFrameIds: Set(frameIdsToDelete),
            deleteAll: deleteAll,
            framesPerVideo: framesPerVideo
        )

        return Result(deletedFrames: frameIdsToDelete.count, deletedVideos: deletedVideos)
    }

    private static func fetchFrameIds(db: OpaquePointer?, sql: String) -> [Int] {
        var stmt: OpaquePointer?
        var frameIds: [Int] = []
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return frameIds
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            frameIds.append(Int(sqlite3_column_int(stmt, 0)))
        }
        return frameIds
    }

    private static func fetchFrameIdsOlderThan(db: OpaquePointer?, cutoffISO8601: String) -> [Int] {
        let sql = "SELECT id FROM FRAME WHERE time < ?"
        var stmt: OpaquePointer?
        var frameIds: [Int] = []

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return frameIds
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, cutoffISO8601, -1, nil)

        while sqlite3_step(stmt) == SQLITE_ROW {
            frameIds.append(Int(sqlite3_column_int(stmt, 0)))
        }
        return frameIds
    }

    private static func executeWithBoundDate(db: OpaquePointer?, sql: String, cutoffISO8601: String) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, cutoffISO8601, -1, nil)
        sqlite3_step(stmt)
    }

    private static func execute(db: OpaquePointer?, sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private static func deleteVideoFiles(
        cachePath: URL,
        deletedFrameIds: Set<Int>,
        deleteAll: Bool,
        framesPerVideo: Int
    ) -> Int {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: cachePath, includingPropertiesForKeys: nil) else {
            return 0
        }

        var deletedVideos = 0
        for file in files where file.pathExtension == "mp4" {
            if deleteAll {
                if (try? fileManager.removeItem(at: file)) != nil {
                    deletedVideos += 1
                }
                continue
            }

            guard let videoStartFrameId = Int(file.deletingPathExtension().lastPathComponent) else {
                continue
            }

            let canDeleteVideo = (0..<framesPerVideo).allSatisfy { offset in
                deletedFrameIds.contains(videoStartFrameId + offset)
            }
            guard canDeleteVideo else { continue }

            if (try? fileManager.removeItem(at: file)) != nil {
                deletedVideos += 1
            }
        }

        return deletedVideos
    }
}

