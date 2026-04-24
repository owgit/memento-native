import Foundation
import SQLite3

/// Shared storage cleanup utility used by manual cleanup and retention policy.
enum StorageCleaner {
    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    struct Result {
        let deletedFrames: Int
        let deletedVideos: Int
    }

    private struct VideoRange {
        let fileURL: URL
        let frameIds: ClosedRange<Int>
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

        let maxFrameId = fetchMaxFrameId(db: db)
        let videoRanges = buildVideoRanges(
            cachePath: cachePath,
            maxFrameId: maxFrameId,
            defaultFramesPerVideo: framesPerVideo
        )

        if deleteAll {
            frameIdsToDelete = fetchFrameIds(db: db, sql: "SELECT id FROM FRAME")
            guard execute(db: db, sql: "BEGIN TRANSACTION") else {
                return Result(deletedFrames: 0, deletedVideos: 0)
            }

            let didDeleteRows = execute(db: db, sql: "DELETE FROM CONTENT_FTS")
                && execute(db: db, sql: "DELETE FROM EMBEDDING")
                && execute(db: db, sql: "DELETE FROM CONTENT")
                && execute(db: db, sql: "DELETE FROM FRAME")
                && execute(db: db, sql: "COMMIT")

            guard didDeleteRows else {
                execute(db: db, sql: "ROLLBACK")
                return Result(deletedFrames: 0, deletedVideos: 0)
            }
        } else {
            guard let cutoffISO8601 else {
                return Result(deletedFrames: 0, deletedVideos: 0)
            }

            let olderFrameIds = fetchFrameIdsOlderThan(db: db, cutoffISO8601: cutoffISO8601)
            frameIdsToDelete = wholeVideoFrameIdsToDelete(
                olderFrameIds,
                videoRanges: videoRanges
            )
            guard !frameIdsToDelete.isEmpty else {
                return Result(deletedFrames: 0, deletedVideos: 0)
            }

            guard execute(db: db, sql: "BEGIN TRANSACTION"),
                  deleteRows(forFrameIds: frameIdsToDelete, db: db),
                  execute(db: db, sql: "COMMIT") else {
                execute(db: db, sql: "ROLLBACK")
                return Result(deletedFrames: 0, deletedVideos: 0)
            }
        }

        let deletedVideos = deleteVideoFiles(
            deletedFrameIds: Set(frameIdsToDelete),
            videoRanges: videoRanges,
            deleteAll: deleteAll
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

    private static func fetchMaxFrameId(db: OpaquePointer?) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT MAX(id) FROM FRAME", -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private static func fetchFrameIdsOlderThan(db: OpaquePointer?, cutoffISO8601: String) -> [Int] {
        let sql = "SELECT id FROM FRAME WHERE time < ?"
        var stmt: OpaquePointer?
        var frameIds: [Int] = []

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return frameIds
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, cutoffISO8601, -1, SQLITE_TRANSIENT)

        while sqlite3_step(stmt) == SQLITE_ROW {
            frameIds.append(Int(sqlite3_column_int(stmt, 0)))
        }
        return frameIds
    }

    private static func wholeVideoFrameIdsToDelete(
        _ frameIds: [Int],
        videoRanges: [VideoRange]
    ) -> [Int] {
        let candidates = Set(frameIds)
        guard !candidates.isEmpty else { return [] }

        var safeToDelete = candidates
        for videoRange in videoRanges {
            let frameIdsInVideo = Set(videoRange.frameIds)
            let deletedInVideo = frameIdsInVideo.intersection(candidates)
            guard !deletedInVideo.isEmpty, deletedInVideo.count < frameIdsInVideo.count else {
                continue
            }

            safeToDelete.subtract(deletedInVideo)
        }

        return frameIds.filter { safeToDelete.contains($0) }
    }

    private static func deleteRows(forFrameIds frameIds: [Int], db: OpaquePointer?) -> Bool {
        deleteRows(db: db, sql: "DELETE FROM CONTENT_FTS WHERE frame_id = ?", frameIds: frameIds)
            && deleteRows(db: db, sql: "DELETE FROM EMBEDDING WHERE frame_id = ?", frameIds: frameIds)
            && deleteRows(db: db, sql: "DELETE FROM CONTENT WHERE frame_id = ?", frameIds: frameIds)
            && deleteRows(db: db, sql: "DELETE FROM FRAME WHERE id = ?", frameIds: frameIds)
    }

    private static func deleteRows(db: OpaquePointer?, sql: String, frameIds: [Int]) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        for frameId in frameIds {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_int(stmt, 1, Int32(frameId))

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                return false
            }
        }

        return true
    }

    @discardableResult
    private static func execute(db: OpaquePointer?, sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private static func buildVideoRanges(
        cachePath: URL,
        maxFrameId: Int,
        defaultFramesPerVideo: Int
    ) -> [VideoRange] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: cachePath, includingPropertiesForKeys: nil) else {
            return []
        }

        let sortedVideos = files
            .filter { $0.pathExtension == "mp4" }
            .compactMap { fileURL -> (startFrameId: Int, fileURL: URL)? in
                guard let startFrameId = Int(fileURL.deletingPathExtension().lastPathComponent) else {
                    return nil
                }
                return (startFrameId, fileURL)
            }
            .sorted { $0.startFrameId < $1.startFrameId }

        return sortedVideos.enumerated().compactMap { index, video in
            let nextStartFrameId = sortedVideos.indices.contains(index + 1)
                ? sortedVideos[index + 1].startFrameId
                : (maxFrameId + 1)
            let endExclusive = min(video.startFrameId + defaultFramesPerVideo, nextStartFrameId)
            guard endExclusive > video.startFrameId else { return nil }
            return VideoRange(
                fileURL: video.fileURL,
                frameIds: video.startFrameId...(endExclusive - 1)
            )
        }
    }

    private static func deleteVideoFiles(
        deletedFrameIds: Set<Int>,
        videoRanges: [VideoRange],
        deleteAll: Bool
    ) -> Int {
        let fileManager = FileManager.default

        var deletedVideos = 0
        for videoRange in videoRanges {
            if deleteAll {
                if (try? fileManager.removeItem(at: videoRange.fileURL)) != nil {
                    deletedVideos += 1
                }
                continue
            }

            let canDeleteVideo = videoRange.frameIds.allSatisfy { deletedFrameIds.contains($0) }
            guard canDeleteVideo else { continue }

            if (try? fileManager.removeItem(at: videoRange.fileURL)) != nil {
                deletedVideos += 1
            }
        }

        return deletedVideos
    }
}
