import SwiftUI
import AVFoundation
import SQLite3
import NaturalLanguage

private struct VideoClip: Sendable {
    let startFrameId: Int
    let frameCount: Int
}

private struct VideoFrameLocation: Sendable {
    let clipIndex: Int
    let frameOffset: Int
    let clip: VideoClip
}

private struct VideoCatalogEntry: Sendable {
    let url: URL
    let modDate: Date?
    let clip: VideoClip
}

private struct VideoCatalogSnapshot: Sendable {
    let catalog: [VideoCatalogEntry]
    let lookup: VideoFrameLookup
    let refreshedAt: Date
}

private struct VideoFrameLookup: Sendable {
    let clips: [VideoClip]
    private let displayStarts: [Int]
    let totalFrames: Int

    init(clips: [VideoClip]) {
        self.clips = clips

        var starts: [Int] = []
        starts.reserveCapacity(clips.count)

        var runningTotal = 0
        for clip in clips {
            starts.append(runningTotal)
            runningTotal += clip.frameCount
        }

        self.displayStarts = starts
        self.totalFrames = runningTotal
    }

    func frameId(forDisplayIndex index: Int) -> Int? {
        guard let location = location(forDisplayIndex: index) else { return nil }
        return location.clip.startFrameId + location.frameOffset
    }

    func displayIndex(forFrameId frameId: Int) -> Int? {
        guard let clipIndex = clipIndex(containing: frameId) else { return nil }
        let clip = clips[clipIndex]
        return displayStarts[clipIndex] + (frameId - clip.startFrameId)
    }

    func location(forDisplayIndex index: Int) -> VideoFrameLocation? {
        guard index >= 0, index < totalFrames else { return nil }

        var low = 0
        var high = displayStarts.count - 1
        var match = 0

        while low <= high {
            let mid = (low + high) / 2
            if displayStarts[mid] <= index {
                match = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        let clip = clips[match]
        let frameOffset = index - displayStarts[match]
        guard frameOffset < clip.frameCount else { return nil }

        return VideoFrameLocation(clipIndex: match, frameOffset: frameOffset, clip: clip)
    }

    private func clipIndex(containing frameId: Int) -> Int? {
        guard !clips.isEmpty else { return nil }

        var low = 0
        var high = clips.count - 1
        var match: Int?

        while low <= high {
            let mid = (low + high) / 2
            if clips[mid].startFrameId <= frameId {
                match = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        guard let match else { return nil }
        let clip = clips[match]
        let clipEnd = clip.startFrameId + clip.frameCount
        return frameId < clipEnd ? match : nil
    }
}

private struct TimelineSearchRequest: Sendable {
    let dbPath: String
    let query: String
    let lookup: VideoFrameLookup
    let textSearchLimit: Int
    let metadataSearchLimit: Int
}

private struct TimelineSearchExecutionResult: Sendable {
    let results: [TimelineManager.SearchResult]
    let errorMessage: String?
}

private struct TimelineMetadataRow: Sendable {
    let frameId: Int
    let windowTitle: String
    let timeString: String
}

private struct RecentFrameRow: Sendable {
    let frameId: Int
    let windowTitle: String
    let timeString: String
}

private struct TimelineBootstrapResult: Sendable {
    let snapshot: VideoCatalogSnapshot
    let visibleEntries: [VideoCatalogEntry]
    let metadataRows: [TimelineMetadataRow]
}

private enum VideoCatalogLoader {
    static func refreshIfNeeded(
        cachePath: String,
        dbPath: String,
        framesPerVideo: Int,
        existingCatalog: [VideoCatalogEntry],
        lastRefreshAt: Date,
        refreshInterval: TimeInterval,
        force: Bool = false
    ) -> VideoCatalogSnapshot {
        let now = Date()
        if !force,
           !existingCatalog.isEmpty,
           now.timeIntervalSince(lastRefreshAt) < refreshInterval {
            return VideoCatalogSnapshot(
                catalog: existingCatalog,
                lookup: VideoFrameLookup(clips: existingCatalog.map(\.clip)),
                refreshedAt: lastRefreshAt
            )
        }

        let fileManager = FileManager.default
        let cacheURL = URL(fileURLWithPath: cachePath)
        let resourceKeys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]

        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return VideoCatalogSnapshot(
                catalog: [],
                lookup: VideoFrameLookup(clips: []),
                refreshedAt: now
            )
        }

        let maxFrameId = fetchMaxFrameId(dbPath: dbPath)
        let sortedVideos = files
            .filter { $0.pathExtension == "mp4" }
            .compactMap { fileURL -> (startFrameId: Int, url: URL, modDate: Date?)? in
                guard let startFrameId = Int(fileURL.deletingPathExtension().lastPathComponent),
                      let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                      let fileSize = values.fileSize,
                      fileSize >= 10_000 else {
                    return nil
                }

                return (startFrameId, fileURL, values.contentModificationDate)
            }
            .sorted { $0.startFrameId < $1.startFrameId }

        let catalog = sortedVideos.enumerated().compactMap { index, video in
            let nextStartFrameId = sortedVideos.indices.contains(index + 1)
                ? sortedVideos[index + 1].startFrameId
                : (maxFrameId + 1)
            let inferredFrameCount = min(framesPerVideo, nextStartFrameId - video.startFrameId)
            let frameCount = max(1, inferredFrameCount)

            return VideoCatalogEntry(
                url: video.url,
                modDate: video.modDate,
                clip: VideoClip(startFrameId: video.startFrameId, frameCount: frameCount)
            )
        }

        return VideoCatalogSnapshot(
            catalog: catalog,
            lookup: VideoFrameLookup(clips: catalog.map(\.clip)),
            refreshedAt: now
        )
    }

    private static func fetchMaxFrameId(dbPath: String) -> Int {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT MAX(id) FROM FRAME", -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }
}

private enum TimelineTimestampParser {
    static func parse(_ rawValue: String) -> Date? {
        let cleaned = rawValue.replacingOccurrences(of: "\"", with: "")

        if let parsed = try? Date(cleaned, strategy: .iso8601) {
            return parsed
        }

        let fallbackISO8601Formatter = ISO8601DateFormatter()
        fallbackISO8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fallbackISO8601Formatter.date(from: cleaned) {
            return parsed
        }

        let legacyFormatter = DateFormatter()
        legacyFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        legacyFormatter.locale = Locale(identifier: "en_US_POSIX")
        legacyFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return legacyFormatter.date(from: cleaned)
    }
}

private final class TimelineLogWriter: @unchecked Sendable {
    static let shared = TimelineLogWriter()

    private let queue = DispatchQueue(label: "com.memento.timeline.log-writer", qos: .utility)
    private let logPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/memento/swift_timeline.log")
    private var fileHandle: FileHandle?

    private init() {}

    func append(_ message: String) {
        let line = "\(Date()): \(message)\n"

        queue.async { [weak self] in
            guard let self else { return }
            guard let data = line.data(using: .utf8) else { return }
            ensureHandle()
            fileHandle?.seekToEndOfFile()
            fileHandle?.write(data)
        }
    }

    private func ensureHandle() {
        if fileHandle != nil {
            return
        }

        let directory = logPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logPath.path) {
            FileManager.default.createFile(atPath: logPath.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: logPath)
    }
}

private enum TimelineSearchWorker {
    private static let duplicateFrameWindow = 12
    private static let duplicateTimeWindow: TimeInterval = 15 * 60
    private static let fallbackCandidateMultiplier = 4
    private static let semanticSimilarityThreshold: Float = 0.15

    static func performTextSearch(_ request: TimelineSearchRequest) -> TimelineSearchExecutionResult {
        var db: OpaquePointer?
        guard sqlite3_open_v2(request.dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return TimelineSearchExecutionResult(results: [], errorMessage: L.searchDatabaseError)
        }
        defer { sqlite3_close(db) }

        var results: [TimelineManager.SearchResult] = []
        let likePattern = "%\(request.query)%"
        let searchTokens = normalizedSearchTokens(for: request.query)
        let normalizedQuery = normalizeForSearch(request.query)
        let ftsPattern = buildFTSPattern(from: searchTokens)
        var seenFrames = Set<Int>()

        let ftsSql = """
            SELECT fts.frame_id, fts.text, f.time, f.window_title, f.url, bm25(CONTENT_FTS) AS rank
            FROM CONTENT_FTS fts
            JOIN FRAME f ON CAST(fts.frame_id AS INTEGER) = f.id
            WHERE CONTENT_FTS MATCH ?
            ORDER BY rank ASC
            LIMIT \(request.textSearchLimit)
        """

        var stmt: OpaquePointer?
        if !ftsPattern.isEmpty,
           sqlite3_prepare_v2(db, ftsSql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, ftsPattern, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            while sqlite3_step(stmt) == SQLITE_ROW {
                if Task.isCancelled {
                    sqlite3_finalize(stmt)
                    return TimelineSearchExecutionResult(results: [], errorMessage: nil)
                }

                let frameId = Int(sqlite3_column_int(stmt, 0))
                guard !seenFrames.contains(frameId) else { continue }
                guard request.lookup.displayIndex(forFrameId: frameId) != nil else { continue }
                seenFrames.insert(frameId)

                let text = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                let timestamp = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                let appName = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
                let url = sqlite3_column_text(stmt, 4).map { String(cString: $0) }

                results.append(
                    TimelineManager.SearchResult(
                        frameId: frameId,
                        text: String(text.prefix(100)),
                        timestamp: timestamp,
                        appName: appName,
                        score: textMatchScore(
                            text: text,
                            url: url,
                            normalizedQuery: normalizedQuery,
                            tokens: searchTokens,
                            matchType: .ocr,
                            rankIndex: results.count
                        ),
                        url: url,
                        matchType: .ocr
                    )
                )
            }
            sqlite3_finalize(stmt)
        }

        appendAggregatedOCRMatches(
            from: db,
            request: request,
            normalizedQuery: normalizedQuery,
            tokens: searchTokens,
            seenFrames: &seenFrames,
            results: &results
        )

        let metaSql = """
            SELECT id, url, tab_title, clipboard, window_title, time
            FROM FRAME
            WHERE url LIKE ? COLLATE NOCASE
               OR tab_title LIKE ? COLLATE NOCASE
               OR clipboard LIKE ? COLLATE NOCASE
            ORDER BY id DESC
            LIMIT \(request.metadataSearchLimit)
        """

        if sqlite3_prepare_v2(db, metaSql, -1, &stmt, nil) == SQLITE_OK {
            for index in 1...3 {
                sqlite3_bind_text(stmt, Int32(index), likePattern, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }

            while sqlite3_step(stmt) == SQLITE_ROW {
                if Task.isCancelled {
                    sqlite3_finalize(stmt)
                    return TimelineSearchExecutionResult(results: [], errorMessage: nil)
                }

                let frameId = Int(sqlite3_column_int(stmt, 0))
                guard !seenFrames.contains(frameId) else { continue }
                guard request.lookup.displayIndex(forFrameId: frameId) != nil else { continue }

                let url = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
                let tabTitle = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                let clipboard = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
                let windowTitle = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
                let timestamp = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""

                let matchType: TimelineManager.SearchResult.MatchType
                let displayText: String

                if let url, normalizeForSearch(url).contains(normalizedQuery) {
                    matchType = .url
                    displayText = url
                } else if let tabTitle, normalizeForSearch(tabTitle).contains(normalizedQuery) {
                    matchType = .title
                    displayText = tabTitle
                } else if let clipboard, normalizeForSearch(clipboard).contains(normalizedQuery) {
                    matchType = .clipboard
                    displayText = String(clipboard.prefix(100))
                } else {
                    continue
                }

                let result = TimelineManager.SearchResult(
                    frameId: frameId,
                    text: displayText,
                    timestamp: timestamp,
                    appName: windowTitle,
                    score: textMatchScore(
                        text: displayText,
                        url: url,
                        normalizedQuery: normalizedQuery,
                        tokens: searchTokens,
                        matchType: matchType,
                        rankIndex: results.count
                    ),
                    url: url,
                    matchType: matchType
                )
                results.append(result)
                seenFrames.insert(frameId)
            }
            sqlite3_finalize(stmt)
        }

        let sortedResults = results.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.frameId > rhs.frameId
            }
            return lhs.score > rhs.score
        }

        return TimelineSearchExecutionResult(
            results: deduplicate(sortedResults),
            errorMessage: nil
        )
    }

    private static func appendAggregatedOCRMatches(
        from db: OpaquePointer?,
        request: TimelineSearchRequest,
        normalizedQuery: String,
        tokens: [String],
        seenFrames: inout Set<Int>,
        results: inout [TimelineManager.SearchResult]
    ) {
        guard let db, !tokens.isEmpty, !normalizedQuery.isEmpty else { return }
        guard results.count < request.textSearchLimit else { return }

        let candidatePattern = buildFTSAnyTokenPattern(from: tokens)
        guard !candidatePattern.isEmpty else { return }

        let fallbackLimit = max(32, request.textSearchLimit * fallbackCandidateMultiplier)
        let fallbackSql = """
            WITH candidate_frames AS (
                SELECT DISTINCT CAST(frame_id AS INTEGER) AS frame_id
                FROM CONTENT_FTS
                WHERE CONTENT_FTS MATCH ?
                LIMIT \(fallbackLimit)
            )
            SELECT f.id, GROUP_CONCAT(c.text, ' ') AS all_text, f.time, f.window_title, f.url
            FROM candidate_frames candidates
            JOIN FRAME f ON f.id = candidates.frame_id
            JOIN CONTENT c ON c.frame_id = f.id
            GROUP BY f.id
            ORDER BY f.id DESC
            LIMIT \(fallbackLimit)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, fallbackSql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, candidatePattern, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        while sqlite3_step(stmt) == SQLITE_ROW {
            if Task.isCancelled || results.count >= request.textSearchLimit {
                return
            }

            let frameId = Int(sqlite3_column_int(stmt, 0))
            guard !seenFrames.contains(frameId) else { continue }
            guard request.lookup.displayIndex(forFrameId: frameId) != nil else { continue }

            let aggregatedText = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            guard matchesNormalizedOCRText(aggregatedText, normalizedQuery: normalizedQuery, tokens: tokens) else {
                continue
            }

            let timestamp = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let appName = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
            let url = sqlite3_column_text(stmt, 4).map { String(cString: $0) }

            results.append(
                TimelineManager.SearchResult(
                    frameId: frameId,
                    text: searchSnippet(from: aggregatedText, query: request.query, tokens: tokens),
                    timestamp: timestamp,
                    appName: appName,
                    score: textMatchScore(
                        text: aggregatedText,
                        url: url,
                        normalizedQuery: normalizedQuery,
                        tokens: tokens,
                        matchType: .ocr,
                        rankIndex: results.count
                    ),
                    url: url,
                    matchType: .ocr
                )
            )
            seenFrames.insert(frameId)
        }
    }

    static func performSemanticSearch(_ request: TimelineSearchRequest) -> TimelineSearchExecutionResult {
        let embeddingService = EmbeddingService()

        let queryEmbeddings = embeddingService.queryEmbeddingResults(for: request.query)
        guard !queryEmbeddings.isEmpty else {
            return performTextSearch(request)
        }
        let quantizedQueryEmbeddings = queryEmbeddings.mapValues { embeddingService.quantize($0.vector) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(request.dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return TimelineSearchExecutionResult(results: [], errorMessage: L.searchDatabaseError)
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT frame_id, vector, quantized, text_summary, language FROM EMBEDDING"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return TimelineSearchExecutionResult(results: [], errorMessage: nil)
        }
        defer { sqlite3_finalize(stmt) }

        var semanticMatches: [(frameId: Int, similarity: Float, summary: String)] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            if Task.isCancelled {
                return TimelineSearchExecutionResult(results: [], errorMessage: nil)
            }

            let frameId = Int(sqlite3_column_int(stmt, 0))
            guard request.lookup.displayIndex(forFrameId: frameId) != nil else { continue }

            guard let blobPtr = sqlite3_column_blob(stmt, 1) else { continue }
            let blobSize = Int(sqlite3_column_bytes(stmt, 1))
            let vectorData = Data(bytes: blobPtr, count: blobSize)
            let isQuantized = sqlite3_column_int(stmt, 2) == 1
            let summary = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
            let storedLanguage = sqlite3_column_text(stmt, 4).map { NLLanguage(rawValue: String(cString: $0)) }

            let similarity: Float
            if isQuantized {
                let storedQuantized = embeddingService.dataToQuantized(vectorData)
                if let storedLanguage,
                   let queryQuantized = quantizedQueryEmbeddings[storedLanguage] {
                    similarity = embeddingService.cosineSimilarityQuantized(queryQuantized, storedQuantized)
                } else {
                    similarity = quantizedQueryEmbeddings.values.reduce(into: -1) { best, queryQuantized in
                        best = max(best, embeddingService.cosineSimilarityQuantized(queryQuantized, storedQuantized))
                    }
                }
            } else {
                let storedVector = embeddingService.dataToVector(vectorData)
                if let storedLanguage,
                   let queryEmbedding = queryEmbeddings[storedLanguage] {
                    similarity = embeddingService.cosineSimilarity(queryEmbedding.vector, storedVector)
                } else {
                    similarity = queryEmbeddings.values.reduce(into: -1) { best, candidate in
                        best = max(best, embeddingService.cosineSimilarity(candidate.vector, storedVector))
                    }
                }
            }

            if similarity > semanticSimilarityThreshold {
                semanticMatches.append((frameId, similarity, summary))
            }
        }

        semanticMatches.sort { $0.similarity > $1.similarity }
        let topSemanticMatches = Array(semanticMatches.prefix(30))

        let frameIds = topSemanticMatches.map { String($0.frameId) }.joined(separator: ",")
        let metaSql = frameIds.isEmpty
            ? nil
            : "SELECT id, time, window_title, url FROM FRAME WHERE id IN (\(frameIds))"

        var metaStmt: OpaquePointer?
        var frameMetadata: [Int: (time: String, app: String, url: String?)] = [:]

        if let metaSql,
           sqlite3_prepare_v2(db, metaSql, -1, &metaStmt, nil) == SQLITE_OK {
            while sqlite3_step(metaStmt) == SQLITE_ROW {
                let frameId = Int(sqlite3_column_int(metaStmt, 0))
                let time = sqlite3_column_text(metaStmt, 1).map { String(cString: $0) } ?? ""
                let app = sqlite3_column_text(metaStmt, 2).map { String(cString: $0) } ?? ""
                let url = sqlite3_column_text(metaStmt, 3).map { String(cString: $0) }
                frameMetadata[frameId] = (time, app, url)
            }
            sqlite3_finalize(metaStmt)
        }

        let semanticResults = topSemanticMatches.compactMap { match -> TimelineManager.SearchResult? in
            guard let metadata = frameMetadata[match.frameId] else { return nil }
            return TimelineManager.SearchResult(
                frameId: match.frameId,
                text: match.summary,
                timestamp: metadata.time,
                appName: metadata.app,
                score: match.similarity,
                url: metadata.url
            )
        }

        let textFallbackResults = Array(performTextSearch(request).results.prefix(20))
        let blendedResults = blendSemanticResults(semanticResults, with: textFallbackResults)

        return TimelineSearchExecutionResult(
            results: deduplicate(blendedResults),
            errorMessage: nil
        )
    }

    private static func blendSemanticResults(
        _ semanticResults: [TimelineManager.SearchResult],
        with textFallbackResults: [TimelineManager.SearchResult]
    ) -> [TimelineManager.SearchResult] {
        var mergedByFrame: [Int: TimelineManager.SearchResult] = [:]
        mergedByFrame.reserveCapacity(semanticResults.count + textFallbackResults.count)

        for semantic in semanticResults {
            mergedByFrame[semantic.frameId] = semantic
        }

        for (index, textResult) in textFallbackResults.enumerated() {
            if var semantic = mergedByFrame[textResult.frameId] {
                if semantic.text.isEmpty || textResult.matchType != .ocr {
                    semantic.text = textResult.text
                }
                if textResult.matchType != .ocr || semantic.matchType == .ocr {
                    semantic.matchType = textResult.matchType
                }
                semantic.score = blendedScore(
                    semanticScore: semantic.score,
                    textScore: textResult.score,
                    matchType: textResult.matchType,
                    textRank: index
                )
                mergedByFrame[textResult.frameId] = semantic
                continue
            }

            var boostedText = textResult
            boostedText.score = blendedScore(
                semanticScore: 0,
                textScore: textResult.score,
                matchType: textResult.matchType,
                textRank: index
            )
            mergedByFrame[textResult.frameId] = boostedText
        }

        return mergedByFrame.values.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.frameId > rhs.frameId
            }
            return lhs.score > rhs.score
        }
    }

    private static func normalizedSearchTokens(for query: String) -> [String] {
        normalizeForSearch(query)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private static func buildFTSPattern(from tokens: [String]) -> String {
        tokens.map { "\($0)*" }.joined(separator: " ")
    }

    private static func buildFTSAnyTokenPattern(from tokens: [String]) -> String {
        tokens.map { "\($0)*" }.joined(separator: " OR ")
    }

    private static func normalizeForSearch(_ value: String) -> String {
        let folded = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        let normalizedScalars = folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }

        return String(normalizedScalars)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matchesNormalizedOCRText(
        _ text: String,
        normalizedQuery: String,
        tokens: [String]
    ) -> Bool {
        let normalizedText = normalizeForSearch(text)
        guard !normalizedText.isEmpty else { return false }

        if normalizedText.contains(normalizedQuery) {
            return true
        }

        return containsOrderedTokens(tokens, in: normalizedText)
    }

    private static func containsOrderedTokens(_ tokens: [String], in text: String) -> Bool {
        guard !tokens.isEmpty else { return false }

        var searchStart = text.startIndex

        for token in tokens {
            guard let range = text.range(of: token, range: searchStart..<text.endIndex) else {
                return false
            }
            searchStart = range.upperBound
        }

        return true
    }

    private static func searchSnippet(from text: String, query: String, tokens: [String]) -> String {
        let collapsedText = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsedText.count > 120 else {
            return collapsedText
        }

        if let range = collapsedText.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            return snippet(in: collapsedText, around: range.lowerBound, window: 56)
        }

        for token in tokens {
            if let range = collapsedText.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) {
                return snippet(in: collapsedText, around: range.lowerBound, window: 56)
            }
        }

        return String(collapsedText.prefix(120))
    }

    private static func snippet(in text: String, around index: String.Index, window: Int) -> String {
        let start = text.index(index, offsetBy: -window, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(index, offsetBy: window, limitedBy: text.endIndex) ?? text.endIndex

        var snippet = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if start > text.startIndex {
            snippet = "..." + snippet
        }
        if end < text.endIndex {
            snippet += "..."
        }
        return snippet
    }

    private static func textMatchScore(
        text: String,
        url: String?,
        normalizedQuery: String,
        tokens: [String],
        matchType: TimelineManager.SearchResult.MatchType,
        rankIndex: Int
    ) -> Float {
        let primaryText = matchType == .url ? (url ?? text) : text
        let normalizedText = normalizeForSearch(primaryText)

        let tokenMatches = tokens.reduce(into: 0) { count, token in
            if normalizedText.contains(token) {
                count += 1
            }
        }
        let coverage = tokens.isEmpty ? 0 : Float(tokenMatches) / Float(tokens.count)
        let exactBoost: Float = normalizedQuery.isEmpty || !normalizedText.contains(normalizedQuery) ? 0 : 0.12
        let coverageBoost = coverage * 0.14
        let rankPenalty = min(0.12, Float(rankIndex) * 0.008)

        let base: Float
        switch matchType {
        case .url:
            base = 0.82
        case .title:
            base = 0.77
        case .clipboard:
            base = 0.72
        case .ocr:
            base = 0.62
        }

        return max(0.16, min(0.99, base + exactBoost + coverageBoost - rankPenalty))
    }

    private static func blendedScore(
        semanticScore: Float,
        textScore: Float,
        matchType: TimelineManager.SearchResult.MatchType,
        textRank: Int
    ) -> Float {
        let textRankPenalty = min(0.08, Float(textRank) * 0.006)
        let textWeight: Float = matchType == .ocr ? 0.35 : 0.5
        let baseScore = max(semanticScore, semanticScore * 0.78 + textScore * textWeight)
        return min(0.99, max(baseScore, textScore - textRankPenalty))
    }

    private static func deduplicate(
        _ results: [TimelineManager.SearchResult]
    ) -> [TimelineManager.SearchResult] {
        var deduplicated: [TimelineManager.SearchResult] = []

        for result in results {
            if isNearDuplicate(result, comparedTo: deduplicated) {
                continue
            }
            deduplicated.append(result)
        }

        return deduplicated
    }

    private static func isNearDuplicate(
        _ candidate: TimelineManager.SearchResult,
        comparedTo existingResults: [TimelineManager.SearchResult]
    ) -> Bool {
        let candidateSignature = duplicateSignature(for: candidate)
        let candidateDate = TimelineTimestampParser.parse(candidate.timestamp)

        for existing in existingResults.reversed() {
            guard duplicateSignature(for: existing) == candidateSignature else { continue }

            if abs(existing.frameId - candidate.frameId) <= duplicateFrameWindow {
                return true
            }

            if let candidateDate,
               let existingDate = TimelineTimestampParser.parse(existing.timestamp),
               abs(candidateDate.timeIntervalSince(existingDate)) <= duplicateTimeWindow {
                return true
            }
        }

        return false
    }

    private static func duplicateSignature(for result: TimelineManager.SearchResult) -> String {
        let primaryText: String
        switch result.matchType {
        case .url:
            primaryText = result.url ?? result.text
        case .ocr, .title, .clipboard:
            primaryText = result.text
        }

        return [
            normalizeForDuplicateCheck(matchTypeKey(result.matchType)),
            normalizeForDuplicateCheck(result.appName),
            normalizeForDuplicateCheck(primaryText)
        ].joined(separator: "|")
    }

    private static func matchTypeKey(_ matchType: TimelineManager.SearchResult.MatchType) -> String {
        switch matchType {
        case .ocr:
            return "ocr"
        case .url:
            return "url"
        case .title:
            return "title"
        case .clipboard:
            return "clipboard"
        }
    }

    private static func normalizeForDuplicateCheck(_ value: String) -> String {
        let folded = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        let collapsedWhitespace = folded.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        let trimmed = collapsedWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(160))
    }
}

@MainActor
final class TimelineManager: ObservableObject {
    @Published var currentFrame: NSImage?
    @Published var currentFrameIndex: Int = 0
    @Published var totalFrames: Int = 0
    @Published var isSearching: Bool = false
    @Published var isCommandPaletteOpen: Bool = false
    @Published var searchQuery: String = ""
    @Published var searchResults: [SearchResult] = []
    @Published var isLoading: Bool = false
    @Published var timelineSegments: [TimelineSegment] = []
    @Published var useSemanticSearch: Bool = false
    @Published var isPreparingSearchHistory: Bool = false
    @Published var isSearchRunning: Bool = false
    @Published var searchErrorMessage: String?
    @Published var recentSearchSelections: [RecentSearchSelection] = []
    
    private let cachePath: String
    private let dbPath: String
    private var videoFiles: [Int: URL] = [:]  // index -> URL
    private var videoIds: [Int] = []  // ordered list of video IDs (for frame_id lookup)
    private let framesPerVideo = 5 // FPS * SECONDS_PER_REC = 0.5 * 10
    private var frameLookup = VideoFrameLookup(clips: [])
    private var allFrameLookup = VideoFrameLookup(clips: [])
    private var videoCatalog: [VideoCatalogEntry] = []
    private var lastVideoCatalogRefreshAt = Date.distantPast
    private let videoCatalogRefreshInterval: TimeInterval = 2
    private let textSearchLimit = 500
    private let metadataSearchLimit = 200
    private let previewImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 96
        return cache
    }()
    private let frameImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 12
        return cache
    }()
    
    struct SearchResult: Identifiable, Sendable {
        let id = UUID()
        let frameId: Int
        var text: String
        let timestamp: String
        let appName: String
        var score: Float = 0  // Similarity score for semantic search (0-1)
        var url: String? = nil  // URL if from browser
        var matchType: MatchType = .ocr
        
        enum MatchType: Sendable {
            case ocr, url, title, clipboard
        }
    }

    struct RecentSearchSelection: Identifiable, Sendable {
        let id = UUID()
        let frameId: Int
        let text: String
        let timestamp: String
        let appName: String
        let matchType: SearchResult.MatchType
    }
    
    struct TimelineSegment: Identifiable {
        let id: Int  // video ID
        let displayIndex: Int
        let time: Date?
        let timeString: String
        let appName: String
        let color: Color
    }
    
    // App colors for timeline - learns new apps over time
    static var appColors: [String: Color] = [
        "Cursor": Color(red: 0.4, green: 0.6, blue: 1.0),
        "Safari": Color(red: 0.3, green: 0.7, blue: 1.0),
        "Chrome": Color(red: 1.0, green: 0.7, blue: 0.2),
        "Firefox": Color(red: 1.0, green: 0.5, blue: 0.2),
        "Terminal": Color(red: 0.3, green: 0.8, blue: 0.3),
        "iTerm": Color(red: 0.3, green: 0.8, blue: 0.4),
        "Slack": Color(red: 0.8, green: 0.3, blue: 0.5),
        "Discord": Color(red: 0.5, green: 0.4, blue: 0.9),
        "Messages": Color(red: 0.2, green: 0.8, blue: 0.4),
        "Mail": Color(red: 0.3, green: 0.6, blue: 1.0),
        "Finder": Color(red: 0.4, green: 0.7, blue: 0.9),
        "Notes": Color(red: 1.0, green: 0.8, blue: 0.2),
        "Preview": Color(red: 0.6, green: 0.6, blue: 0.6),
        "Xcode": Color(red: 0.3, green: 0.6, blue: 1.0),
        "VS Code": Color(red: 0.2, green: 0.5, blue: 0.8),
        "Code": Color(red: 0.2, green: 0.5, blue: 0.8),
        "Spotify": Color(red: 0.2, green: 0.8, blue: 0.4),
        "YouTube": Color(red: 1.0, green: 0.2, blue: 0.2),
        "Twitter": Color(red: 0.3, green: 0.7, blue: 0.9),
        "Arc": Color(red: 0.6, green: 0.4, blue: 0.9),
        "Notion": Color(red: 0.9, green: 0.9, blue: 0.9),
        "Figma": Color(red: 0.6, green: 0.3, blue: 0.9),
        "Photoshop": Color(red: 0.2, green: 0.5, blue: 0.9),
        "Sketch": Color(red: 1.0, green: 0.6, blue: 0.2),
        "Zoom": Color(red: 0.3, green: 0.5, blue: 1.0),
        "Teams": Color(red: 0.4, green: 0.4, blue: 0.7),
        "WhatsApp": Color(red: 0.2, green: 0.7, blue: 0.4),
        "Telegram": Color(red: 0.3, green: 0.6, blue: 0.9),
        "Calendar": Color(red: 1.0, green: 0.3, blue: 0.3),
        "Reminders": Color(red: 1.0, green: 0.5, blue: 0.2),
        "Photos": Color(red: 0.9, green: 0.4, blue: 0.6),
        "Music": Color(red: 1.0, green: 0.3, blue: 0.4),
        "Podcasts": Color(red: 0.6, green: 0.3, blue: 0.8),
        "Books": Color(red: 1.0, green: 0.6, blue: 0.2),
        "News": Color(red: 1.0, green: 0.2, blue: 0.3),
        "Stocks": Color(red: 0.2, green: 0.7, blue: 0.3),
        "Maps": Color(red: 0.3, green: 0.7, blue: 0.4),
        "Weather": Color(red: 0.4, green: 0.7, blue: 1.0),
        "Settings": Color(red: 0.5, green: 0.5, blue: 0.5),
        "System Preferences": Color(red: 0.5, green: 0.5, blue: 0.5),
        "Activity Monitor": Color(red: 0.3, green: 0.8, blue: 0.3),
        "Other": Color(red: 0.5, green: 0.5, blue: 0.6),
        "default": Color(red: 0.5, green: 0.5, blue: 0.6)
    ]
    
    // Segment cache for pagination - only keep visible range in memory
    private var segmentCache: [Int: TimelineSegment] = [:]
    private let maxCachedSegments = 500
    
    // Lazy loading - start with 1 day, expand as needed
    private var loadedFromDate: Date = Date()
    private var loadedToDate: Date = Date()
    private let initialLoadHours: Int = 12  // Last 12 hours on startup
    private let expandHours: Int = 24       // Load 24h more when scrolling back
    @Published var isLoadingMore: Bool = false
    private var pendingJumpTask: Task<Void, Never>?
    private var frameLoadTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var activeFrameLoadToken = UUID()
    private var hasBootstrapped = false
    
    // Generate a consistent color for a new app based on its name
    static func generateColorForApp(_ appName: String) -> Color {
        // Use hash of app name to generate consistent color
        let hash = abs(appName.hashValue)
        let hue = Double(hash % 360) / 360.0
        let saturation = 0.5 + Double((hash / 360) % 50) / 100.0
        let brightness = 0.7 + Double((hash / 18000) % 30) / 100.0
        
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
    
    // Get color for app (from cache or generate)
    static func colorForApp(_ appName: String) -> Color {
        if let color = appColors[appName] {
            return color
        }
        return generateColorForApp(appName)
    }
    
    init() {
        let storagePath = Self.resolveStoragePath()
        cachePath = storagePath
        dbPath = URL(fileURLWithPath: storagePath).appendingPathComponent("memento.db").path
        
        loadedToDate = Date()
        loadedFromDate = Calendar.current.date(byAdding: .hour, value: -initialLoadHours, to: Date()) ?? Date()
        isLoading = true
    }

    deinit {
        bootstrapTask?.cancel()
        pendingJumpTask?.cancel()
        frameLoadTask?.cancel()
        searchTask?.cancel()
        semanticSearchTask?.cancel()
    }

    func bootstrapIfNeeded() async {
        if hasBootstrapped {
            return
        }

        if let bootstrapTask {
            await bootstrapTask.value
            return
        }

        let cachePath = self.cachePath
        let dbPath = self.dbPath
        let framesPerVideo = self.framesPerVideo
        let existingCatalog = self.videoCatalog
        let lastRefreshAt = self.lastVideoCatalogRefreshAt
        let refreshInterval = self.videoCatalogRefreshInterval
        let startDate = self.loadedFromDate
        let endDate = self.loadedToDate

        let task = Task { [weak self] in
            guard let self else { return }

            let bootstrapResult = await Task.detached(priority: .utility) {
                Self.loadBootstrapResult(
                    cachePath: cachePath,
                    dbPath: dbPath,
                    framesPerVideo: framesPerVideo,
                    existingCatalog: existingCatalog,
                    lastRefreshAt: lastRefreshAt,
                    refreshInterval: refreshInterval,
                    startDate: startDate,
                    endDate: endDate
                )
            }.value

            guard !Task.isCancelled else { return }
            self.applyBootstrapResult(bootstrapResult)
        }

        bootstrapTask = task
        await task.value
        bootstrapTask = nil
    }

    private func cancelBootstrap(markBootstrapped: Bool = true) {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        if markBootstrapped {
            hasBootstrapped = true
        }
    }

    nonisolated private static func loadBootstrapResult(
        cachePath: String,
        dbPath: String,
        framesPerVideo: Int,
        existingCatalog: [VideoCatalogEntry],
        lastRefreshAt: Date,
        refreshInterval: TimeInterval,
        startDate: Date,
        endDate: Date
    ) -> TimelineBootstrapResult {
        var recentRows = loadRecentFrameRows(
            dbPath: dbPath,
            startDate: startDate,
            endDate: endDate
        )

        if recentRows.isEmpty {
            recentRows = loadRecentFrameRows(
                dbPath: dbPath,
                startDate: startDate,
                endDate: endDate,
                normalizeTimestamps: true
            )
        }

        let maxFrameId = fetchMaxFrameId(dbPath: dbPath)
        let cacheURL = URL(fileURLWithPath: cachePath)
        let resourceKeys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]

        var visibleEntries: [VideoCatalogEntry] = []
        visibleEntries.reserveCapacity(recentRows.count)
        var metadataRows: [TimelineMetadataRow] = []
        metadataRows.reserveCapacity(recentRows.count)

        for row in recentRows {
            let fileURL = cacheURL.appendingPathComponent("\(row.frameId).mp4")
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                  let fileSize = values.fileSize,
                  fileSize >= 10_000 else {
                continue
            }

            visibleEntries.append(
                VideoCatalogEntry(
                    url: fileURL,
                    modDate: values.contentModificationDate,
                    clip: VideoClip(startFrameId: row.frameId, frameCount: 1)
                )
            )
            metadataRows.append(
                TimelineMetadataRow(
                    frameId: row.frameId,
                    windowTitle: row.windowTitle,
                    timeString: row.timeString
                )
            )
        }

        for index in visibleEntries.indices {
            let startFrameId = visibleEntries[index].clip.startFrameId
            let nextStartFrameId = visibleEntries.indices.contains(index + 1)
                ? visibleEntries[index + 1].clip.startFrameId
                : (maxFrameId + 1)
            let inferredFrameCount = min(framesPerVideo, nextStartFrameId - startFrameId)
            visibleEntries[index] = VideoCatalogEntry(
                url: visibleEntries[index].url,
                modDate: visibleEntries[index].modDate,
                clip: VideoClip(startFrameId: startFrameId, frameCount: max(1, inferredFrameCount))
            )
        }

        let snapshot = VideoCatalogSnapshot(
            catalog: visibleEntries,
            lookup: VideoFrameLookup(clips: visibleEntries.map(\.clip)),
            refreshedAt: .distantPast
        )

        return TimelineBootstrapResult(snapshot: snapshot, visibleEntries: visibleEntries, metadataRows: metadataRows)
    }

    nonisolated private static func loadTimelineMetadataRows(
        dbPath: String,
        frameIds: [Int]
    ) -> [TimelineMetadataRow] {
        guard !frameIds.isEmpty else { return [] }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        let frameIdsList = frameIds.map(String.init).joined(separator: ",")
        let sql = "SELECT id, window_title, time FROM FRAME WHERE id IN (\(frameIdsList)) ORDER BY id"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var rows: [TimelineMetadataRow] = []
        rows.reserveCapacity(frameIds.count)

        while sqlite3_step(statement) == SQLITE_ROW {
            let frameId = Int(sqlite3_column_int(statement, 0))
            let windowTitle = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "Unknown"
            let timeString = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            rows.append(
                TimelineMetadataRow(
                    frameId: frameId,
                    windowTitle: windowTitle,
                    timeString: timeString.replacingOccurrences(of: "\"", with: "")
                )
            )
        }

        return rows
    }

    nonisolated private static func loadRecentFrameRows(
        dbPath: String,
        startDate: Date,
        endDate: Date,
        normalizeTimestamps: Bool = false
    ) -> [RecentFrameRow] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        let formatter = ISO8601DateFormatter()
        let startString = formatter.string(from: startDate)
        let endString = formatter.string(from: endDate)

        let sql: String
        if normalizeTimestamps {
            sql = """
                SELECT id, window_title, time
                FROM FRAME
                WHERE datetime(time) >= datetime(?)
                  AND datetime(time) <= datetime(?)
                ORDER BY id
            """
        } else {
            sql = """
                SELECT id, window_title, time
                FROM FRAME
                WHERE time >= ? AND time <= ?
                ORDER BY id
            """
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, startString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(statement, 2, endString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        var rows: [RecentFrameRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(
                RecentFrameRow(
                    frameId: Int(sqlite3_column_int(statement, 0)),
                    windowTitle: sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "Unknown",
                    timeString: sqlite3_column_text(statement, 2).map { String(cString: $0) }?.replacingOccurrences(of: "\"", with: "") ?? ""
                )
            )
        }

        return rows
    }

    nonisolated private static func fetchMaxFrameId(dbPath: String) -> Int {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT MAX(id) FROM FRAME", -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func applyBootstrapResult(_ bootstrapResult: TimelineBootstrapResult) {
        applyVideoCatalogSnapshot(bootstrapResult.snapshot)
        applyVisibleEntries(bootstrapResult.visibleEntries)
        applyTimelineMetadataRows(bootstrapResult.metadataRows)
        hasBootstrapped = true

        guard totalFrames > 0 else {
            currentFrame = nil
            currentFrameIndex = 0
            isLoading = false
            return
        }

        let safeIndex = max(0, totalFrames - 1 - (framesPerVideo * 2))
        currentFrameIndex = safeIndex
        currentFrame = nil
        isLoading = false
    }

    private static func resolveStoragePath() -> String {
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/memento").path

        // Prefer Capture app settings domain so both apps stay aligned.
        if let captureDefaults = UserDefaults(suiteName: "com.memento.capture"),
           let path = captureDefaults.string(forKey: "storagePath"),
           !path.isEmpty {
            return path
        }

        if let captureDomain = UserDefaults.standard.persistentDomain(forName: "com.memento.capture"),
           let path = captureDomain["storagePath"] as? String,
           !path.isEmpty {
            return path
        }

        if let path = UserDefaults.standard.string(forKey: "storagePath"),
           !path.isEmpty {
            return path
        }

        return defaultPath
    }

    private static func resolveCaptureInterval() -> TimeInterval {
        if let captureDefaults = UserDefaults(suiteName: "com.memento.capture"),
           let value = captureDefaults.object(forKey: "captureInterval") as? Double,
           value > 0 {
            return value
        }

        if let captureDomain = UserDefaults.standard.persistentDomain(forName: "com.memento.capture"),
           let value = captureDomain["captureInterval"] as? Double,
           value > 0 {
            return value
        }

        if let value = UserDefaults.standard.object(forKey: "captureInterval") as? Double,
           value > 0 {
            return value
        }

        return 2.0
    }

    private func loadVideoFiles(from startDate: Date? = nil, to endDate: Date? = nil) {
        refreshVideoCatalogIfNeeded()

        let visibleEntries = videoCatalog.filter { video in
            if let startDate, let modDate = video.modDate, modDate < startDate {
                return false
            }
            if let endDate, let modDate = video.modDate, modDate > endDate {
                return false
            }
            return true
        }

        applyVisibleEntries(visibleEntries)
        AppLog.info("📹 Loaded \(videoFiles.count) videos (\(totalFrames) frames) for date range")
    }

    private func refreshVideoCatalogIfNeeded(force: Bool = false) {
        applyVideoCatalogSnapshot(
            VideoCatalogLoader.refreshIfNeeded(
                cachePath: cachePath,
                dbPath: dbPath,
                framesPerVideo: framesPerVideo,
                existingCatalog: videoCatalog,
                lastRefreshAt: lastVideoCatalogRefreshAt,
                refreshInterval: videoCatalogRefreshInterval,
                force: force
            )
        )
    }

    private func applyVideoCatalogSnapshot(_ snapshot: VideoCatalogSnapshot) {
        videoCatalog = snapshot.catalog
        allFrameLookup = snapshot.lookup
        lastVideoCatalogRefreshAt = snapshot.refreshedAt
    }

    private func applyVisibleEntries(_ entries: [VideoCatalogEntry]) {
        videoIds = []
        videoFiles = [:]

        guard !entries.isEmpty else {
            frameLookup = VideoFrameLookup(clips: [])
            totalFrames = 0
            return
        }

        var clips: [VideoClip] = []
        clips.reserveCapacity(entries.count)

        for (index, entry) in entries.enumerated() {
            videoFiles[index] = entry.url
            videoIds.append(entry.clip.startFrameId)
            clips.append(entry.clip)
        }

        frameLookup = VideoFrameLookup(clips: clips)
        totalFrames = frameLookup.totalFrames
    }
    
    /// Load older history when user navigates to start
    func loadMoreHistory() {
        guard !isLoadingMore else { return }
        cancelBootstrap()
        isLoadingMore = true

        let preservedFrameId = getFrameIdForIndex(currentFrameIndex)
        
        let newFromDate = Calendar.current.date(byAdding: .hour, value: -expandHours, to: loadedFromDate) ?? loadedFromDate
        AppLog.info("📅 Expanding history: \(loadedFromDate) -> \(newFromDate)")
        
        Task { @MainActor in
            loadedFromDate = newFromDate
            loadVideoFiles(from: loadedFromDate, to: loadedToDate)
            loadTimelineMetadata()
            if preservedFrameId > 0, let restoredIndex = getIndexForFrameId(preservedFrameId) {
                currentFrameIndex = restoredIndex
            }
            isLoadingMore = false
        }
    }
    
    /// Load all history (for search)
    func loadAllHistory() {
        guard !isLoadingMore else { return }
        cancelBootstrap()
        isLoadingMore = true
        let preservedFrameId = getFrameIdForIndex(currentFrameIndex)
        AppLog.info("📅 Loading all history for search...")
        
        Task { @MainActor in
            loadedFromDate = Date.distantPast
            loadVideoFiles(from: nil, to: nil)
            loadTimelineMetadata()
            if preservedFrameId > 0, let restoredIndex = getIndexForFrameId(preservedFrameId) {
                currentFrameIndex = restoredIndex
            }
            isLoadingMore = false
        }
    }
    
    // Get the database frame_id for a given display index
    func getFrameIdForIndex(_ index: Int) -> Int {
        frameLookup.frameId(forDisplayIndex: index) ?? 0
    }
    
    // Convert frame_id to display index (for search results)
    func getIndexForFrameId(_ frameId: Int) -> Int? {
        frameLookup.displayIndex(forFrameId: frameId)
    }
    
    // Jump directly to a frame_id (from search)
    func jumpToFrameId(_ frameId: Int, completion: ((Bool) -> Void)? = nil) {
        if let index = getIndexForFrameId(frameId) {
            jumpToFrame(index)
            completion?(true)
            return
        }

        guard loadedFromDate > Date.distantPast else {
            log("⚠️ Could not find display index for frame_id \(frameId)")
            completion?(false)
            return
        }

        // Search can return old frames outside the currently loaded range.
        log("📅 Frame \(frameId) not loaded yet, loading full history...")
        loadAllHistory()

        pendingJumpTask?.cancel()
        pendingJumpTask = Task { @MainActor in
            do {
                while isLoadingMore {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
            } catch is CancellationError {
                completion?(false)
                return
            } catch {
                completion?(false)
                return
            }

            if let index = getIndexForFrameId(frameId) {
                jumpToFrame(index)
                completion?(true)
            } else {
                log("⚠️ Could not find display index for frame_id \(frameId) after loading full history")
                completion?(false)
            }

            pendingJumpTask = nil
        }
    }
    
    // Load timeline metadata from database - paginated for memory efficiency
    func loadTimelineMetadata() {
        guard !videoIds.isEmpty else {
            segmentCache.removeAll(keepingCapacity: true)
            timelineSegments = []
            log("📅 Loaded 0 timeline segments, cache: 0")
            return
        }

        applyTimelineMetadataRows(
            Self.loadTimelineMetadataRows(
                dbPath: dbPath,
                frameIds: videoIds
            )
        )
    }

    private func applyTimelineMetadataRows(_ rows: [TimelineMetadataRow]) {
        segmentCache.removeAll(keepingCapacity: true)

        var segments: [TimelineSegment] = []
        segments.reserveCapacity(min(rows.count, maxCachedSegments))

        for row in rows {
            autoreleasepool {
                let appName = extractAppName(from: row.windowTitle)

                let color: Color
                if let existingColor = Self.appColors[appName] {
                    color = existingColor
                } else {
                    let newColor = Self.generateColorForApp(appName)
                    Self.appColors[appName] = newColor
                    color = newColor
                }

                guard let displayIndex = frameLookup.displayIndex(forFrameId: row.frameId) else {
                    return
                }

                let parsedDate = row.timeString.isEmpty ? nil : TimelineTimestampParser.parse(row.timeString)
                let segment = TimelineSegment(
                    id: row.frameId,
                    displayIndex: displayIndex,
                    time: parsedDate,
                    timeString: row.timeString,
                    appName: appName,
                    color: color
                )
                segments.append(segment)
                segmentCache[row.frameId] = segment
            }
        }

        if segmentCache.count > maxCachedSegments {
            let sortedKeys = segmentCache.keys.sorted()
            let keysToRemove = sortedKeys.prefix(segmentCache.count - maxCachedSegments)
            for key in keysToRemove {
                segmentCache.removeValue(forKey: key)
            }
        }

        timelineSegments = segments
        log("📅 Loaded \(segments.count) timeline segments, cache: \(segmentCache.count)")
    }
    
    private func extractAppName(from windowTitle: String) -> String {
        // Common app patterns
        let patterns = [
            "Cursor", "Safari", "Chrome", "Firefox", "Terminal", "iTerm",
            "Slack", "Discord", "Messages", "Mail", "Finder", "Notes",
            "Preview", "Xcode", "VS Code", "Code", "Spotify", "YouTube", 
            "Twitter", "Arc", "Notion", "Figma", "Photoshop", "Sketch"
        ]
        
        for pattern in patterns {
            if windowTitle.localizedCaseInsensitiveContains(pattern) {
                return pattern
            }
        }
        
        // Try to extract app from common title patterns like "Document - AppName"
        if let dashIndex = windowTitle.lastIndex(of: "-") {
            let afterDash = String(windowTitle[windowTitle.index(after: dashIndex)...]).trimmingCharacters(in: .whitespaces)
            if afterDash.count < 30 {
                return afterDash
            }
        }
        
        return "Other"
    }
    
    func getColorForCurrentFrame() -> Color {
        return getSegmentForIndex(currentFrameIndex)?.color ?? Self.appColors["default"] ?? Color.gray
    }

    private func videoLocation(for index: Int) -> VideoFrameLocation? {
        frameLookup.location(forDisplayIndex: index)
    }

    private func previewCacheKey(for location: VideoFrameLocation, maxDimension: CGFloat) -> NSString {
        "\(location.clip.startFrameId):\(location.frameOffset):\(Int(maxDimension.rounded()))" as NSString
    }

    private func frameCacheKey(for frameId: Int) -> NSString {
        "\(frameId)" as NSString
    }

    nonisolated private static func targetTime(
        for location: VideoFrameLocation,
        totalSeconds: Double,
        fallbackFrameDuration: TimeInterval
    ) -> CMTime {
        let framePositionDenominator = max(1, location.clip.frameCount - 1)
        let proportionalSeconds = totalSeconds > 0
            ? (Double(location.frameOffset) / Double(framePositionDenominator)) * totalSeconds
            : Double(location.frameOffset) * fallbackFrameDuration
        let clampedSeconds = totalSeconds > 0
            ? min(max(0, proportionalSeconds), totalSeconds)
            : max(0, proportionalSeconds)
        return CMTime(seconds: clampedSeconds, preferredTimescale: 600)
    }

    nonisolated private static func renderFrameImage(
        from videoURL: URL,
        location: VideoFrameLocation,
        maxDimension: CGFloat?,
        tolerance: CMTime,
        fallbackFrameDuration: TimeInterval
    ) async throws -> NSImage {
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        generator.maximumSize = maxDimension.map { CGSize(width: $0, height: $0) } ?? .zero
        generator.apertureMode = .cleanAperture

        let duration = try? await asset.load(.duration)
        let totalSeconds = max(0, duration?.seconds ?? 0)
        let targetTime = targetTime(
            for: location,
            totalSeconds: totalSeconds,
            fallbackFrameDuration: fallbackFrameDuration
        )
        let (cgImage, _) = try await generator.image(at: targetTime)
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }
    
    func getSegmentForIndex(_ index: Int) -> TimelineSegment? {
        guard let location = videoLocation(for: index) else { return nil }
        let frameId = location.clip.startFrameId
        return segmentCache[frameId] ?? timelineSegments.first(where: { $0.id == frameId })
    }

    func loadPreviewFrame(at index: Int, maxDimension: CGFloat = 420) async -> NSImage? {
        guard index >= 0 && index < totalFrames else { return nil }

        guard let location = videoLocation(for: index),
              let videoURL = videoFiles[location.clipIndex] else { return nil }
        let previewKey = previewCacheKey(for: location, maxDimension: maxDimension)
        if let cached = previewImageCache.object(forKey: previewKey) {
            return cached
        }
        let fallbackFrameDuration = Self.resolveCaptureInterval()

        let imageTask = Task.detached(priority: .utility) { () -> NSImage? in
            do {
                return try await Self.renderFrameImage(
                    from: videoURL,
                    location: location,
                    maxDimension: maxDimension,
                    tolerance: CMTime(seconds: 0.08, preferredTimescale: 600),
                    fallbackFrameDuration: fallbackFrameDuration
                )
            } catch {
                return nil
            }
        }
        let image = await imageTask.value

        if let image {
            previewImageCache.setObject(image, forKey: previewKey)
        }

        return image
    }
    
    func loadFrame(at index: Int) {
        guard index >= 0 && index < totalFrames else { return }

        activeFrameLoadToken = UUID()
        let token = activeFrameLoadToken
        frameLoadTask?.cancel()

        guard let location = videoLocation(for: index) else {
            return
        }
        let initialFrameId = location.clip.startFrameId + location.frameOffset
        let initialFrameKey = frameCacheKey(for: initialFrameId)
        if let cached = frameImageCache.object(forKey: initialFrameKey) {
            currentFrame = cached
            return
        }
        let fallbackFrameDuration = Self.resolveCaptureInterval()

        frameLoadTask = Task { [weak self] in
            guard let self else { return }

            isLoading = true
            defer {
                if activeFrameLoadToken == token {
                    isLoading = false
                }
            }

            var candidateIndex = index

            while candidateIndex < totalFrames {
                if Task.isCancelled || activeFrameLoadToken != token {
                    return
                }

                guard let candidateLocation = videoLocation(for: candidateIndex),
                      let videoURL = videoFiles[candidateLocation.clipIndex] else {
                    candidateIndex += 1
                    continue
                }

                let frameId = candidateLocation.clip.startFrameId + candidateLocation.frameOffset
                let frameKey = frameCacheKey(for: frameId)

                if let cached = frameImageCache.object(forKey: frameKey) {
                    if activeFrameLoadToken != token {
                        return
                    }
                    currentFrameIndex = candidateIndex
                    currentFrame = cached
                    return
                }

                do {
                    let image = try await Self.renderFrameImage(
                        from: videoURL,
                        location: candidateLocation,
                        maxDimension: nil,
                        tolerance: .zero,
                        fallbackFrameDuration: fallbackFrameDuration
                    )

                    if Task.isCancelled || activeFrameLoadToken != token {
                        return
                    }

                    frameImageCache.setObject(image, forKey: frameKey)
                    currentFrameIndex = candidateIndex
                    currentFrame = image
                    return
                } catch is CancellationError {
                    return
                } catch {
                    AppLog.warning("⚠️ Skipping corrupted video \(candidateLocation.clipIndex): \(error.localizedDescription)")
                    candidateIndex += 1
                }
            }
        }
    }
    
    func nextFrame() {
        if currentFrameIndex < totalFrames - 1 {
            currentFrameIndex += 1
            loadFrame(at: currentFrameIndex)
        }
    }
    
    func previousFrame() {
        if currentFrameIndex > 0 {
            currentFrameIndex -= 1
            loadFrame(at: currentFrameIndex)
            
            // Load more history when nearing start
            if currentFrameIndex < framesPerVideo * 3 && loadedFromDate > Date.distantPast {
                loadMoreHistory()
            }
        } else if loadedFromDate > Date.distantPast {
            // At start - try to load more history
            loadMoreHistory()
        }
    }
    
    func jumpToFrame(_ index: Int) {
        guard index >= 0 && index < totalFrames else { return }
        currentFrameIndex = index
        loadFrame(at: index)
        
        // Load more history when jumping near start
        if index < framesPerVideo * 3 && loadedFromDate > Date.distantPast {
            loadMoreHistory()
        }
    }

    func jumpToClosestTime(hour: Int, minute: Int) -> Bool {
        guard !timelineSegments.isEmpty else { return false }

        let targetMinutes = (hour * 60) + minute
        var bestSegment: TimelineSegment?
        var bestDistance = Int.max

        for segment in timelineSegments {
            guard let segmentMinutes = minutesOfDay(for: segment) else { continue }
            let distance = abs(segmentMinutes - targetMinutes)
            if distance < bestDistance {
                bestDistance = distance
                bestSegment = segment
            }
        }

        guard let bestSegment else { return false }
        jumpToFrame(bestSegment.displayIndex)
        return true
    }

    private func minutesOfDay(for segment: TimelineSegment) -> Int? {
        if let date = segment.time {
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            guard let hour = components.hour, let minute = components.minute else { return nil }
            return (hour * 60) + minute
        }

        let clean = segment.timeString.replacingOccurrences(of: "\"", with: "")
        let parts = clean.contains("T") ? clean.split(separator: "T") : clean.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let timePart = String(parts[1]).replacingOccurrences(of: "Z", with: "")
        let components = timePart.split(separator: ":")
        guard components.count >= 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else { return nil }
        return (hour * 60) + minute
    }
    
    func rememberRecentSearch(_ result: SearchResult) {
        let cleanedText = String(result.text.prefix(140))
        recentSearchSelections.removeAll { $0.frameId == result.frameId }
        recentSearchSelections.insert(
            RecentSearchSelection(
                frameId: result.frameId,
                text: cleanedText,
                timestamp: result.timestamp,
                appName: result.appName,
                matchType: result.matchType
            ),
            at: 0
        )

        if recentSearchSelections.count > 8 {
            recentSearchSelections = Array(recentSearchSelections.prefix(8))
        }
    }
    
    private func log(_ message: String) {
        AppLog.info(message)
        TimelineLogWriter.shared.append(message)
    }
    
    private var searchTask: Task<Void, Never>?
    private var latestSearchToken = UUID()

    func search(_ query: String) {
        // Cancel previous search
        searchTask?.cancel()
        semanticSearchTask?.cancel()
        let token = UUID()
        latestSearchToken = token
        
        guard !query.isEmpty else {
            searchResults = []
            isPreparingSearchHistory = false
            isSearchRunning = false
            searchErrorMessage = nil
            return
        }

        isSearchRunning = true
        searchErrorMessage = nil

        searchTask = Task { [weak self] in
            guard let self = self else { return }
            self.isPreparingSearchHistory = true
            let cachePath = self.cachePath
            let dbPath = self.dbPath
            let framesPerVideo = self.framesPerVideo
            let existingCatalog = self.videoCatalog
            let lastRefreshAt = self.lastVideoCatalogRefreshAt
            let refreshInterval = self.videoCatalogRefreshInterval
            let snapshot = await Task.detached(priority: .utility) {
                VideoCatalogLoader.refreshIfNeeded(
                    cachePath: cachePath,
                    dbPath: dbPath,
                    framesPerVideo: framesPerVideo,
                    existingCatalog: existingCatalog,
                    lastRefreshAt: lastRefreshAt,
                    refreshInterval: refreshInterval
                )
            }.value
            self.applyVideoCatalogSnapshot(snapshot)
            self.isPreparingSearchHistory = false
            guard !Task.isCancelled else { return }

            let request = self.makeSearchRequest(for: query)
            let result = await self.performDetachedSearch(request: request, semantic: false)
            guard !Task.isCancelled, self.latestSearchToken == token else { return }

            self.searchErrorMessage = result.errorMessage
            self.searchResults = result.results
            self.isSearchRunning = false
        }
    }
    
    // MARK: - Semantic Search

    private var semanticSearchTask: Task<Void, Never>?

    func semanticSearch(_ query: String) {
        semanticSearchTask?.cancel()
        searchTask?.cancel()
        let token = UUID()
        latestSearchToken = token
        
        guard !query.isEmpty else {
            searchResults = []
            isPreparingSearchHistory = false
            isSearchRunning = false
            searchErrorMessage = nil
            return
        }

        isSearchRunning = true
        searchErrorMessage = nil

        semanticSearchTask = Task { [weak self] in
            guard let self = self else { return }
            self.isPreparingSearchHistory = true
            let cachePath = self.cachePath
            let dbPath = self.dbPath
            let framesPerVideo = self.framesPerVideo
            let existingCatalog = self.videoCatalog
            let lastRefreshAt = self.lastVideoCatalogRefreshAt
            let refreshInterval = self.videoCatalogRefreshInterval
            let snapshot = await Task.detached(priority: .utility) {
                VideoCatalogLoader.refreshIfNeeded(
                    cachePath: cachePath,
                    dbPath: dbPath,
                    framesPerVideo: framesPerVideo,
                    existingCatalog: existingCatalog,
                    lastRefreshAt: lastRefreshAt,
                    refreshInterval: refreshInterval
                )
            }.value
            self.applyVideoCatalogSnapshot(snapshot)
            self.isPreparingSearchHistory = false
            guard !Task.isCancelled else { return }

            let request = self.makeSearchRequest(for: query)
            let result = await self.performDetachedSearch(request: request, semantic: true)
            guard !Task.isCancelled, self.latestSearchToken == token else { return }

            self.searchErrorMessage = result.errorMessage
            self.searchResults = result.results
            self.isSearchRunning = false
        }
    }

    private func makeSearchRequest(for query: String) -> TimelineSearchRequest {
        TimelineSearchRequest(
            dbPath: dbPath,
            query: query,
            lookup: allFrameLookup,
            textSearchLimit: textSearchLimit,
            metadataSearchLimit: metadataSearchLimit
        )
    }

    private func performDetachedSearch(
        request: TimelineSearchRequest,
        semantic: Bool
    ) async -> TimelineSearchExecutionResult {
        let worker = Task.detached(priority: .userInitiated) {
            semantic
                ? TimelineSearchWorker.performSemanticSearch(request)
                : TimelineSearchWorker.performTextSearch(request)
        }

        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

}
