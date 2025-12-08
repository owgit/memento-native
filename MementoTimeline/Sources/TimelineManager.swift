import SwiftUI
import AVFoundation
import SQLite3

@MainActor
class TimelineManager: ObservableObject {
    @Published var currentFrame: NSImage?
    @Published var currentFrameIndex: Int = 0
    @Published var totalFrames: Int = 0
    @Published var isSearching: Bool = false
    @Published var searchQuery: String = ""
    @Published var searchResults: [SearchResult] = []
    @Published var isLoading: Bool = false
    @Published var currentTime: String = ""
    @Published var currentApp: String = ""
    @Published var currentFrameText: [TextBlock] = []
    @Published var showTextOverlay: Bool = false
    @Published var copiedNotification: Bool = false
    @Published var timelineSegments: [TimelineSegment] = []
    @Published var groupedByDay: [String: [TimelineSegment]] = [:]
    @Published var useSemanticSearch: Bool = false
    
    struct TextBlock: Identifiable {
        let id = UUID()
        let text: String
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }
    
    private let cachePath: String
    private let dbPath: String
    private var videoFiles: [Int: URL] = [:]  // index -> URL
    private var videoIds: [Int] = []  // ordered list of video IDs (for frame_id lookup)
    private let framesPerVideo = 5 // FPS * SECONDS_PER_REC = 0.5 * 10
    
    struct SearchResult: Identifiable {
        let id = UUID()
        let frameId: Int
        let text: String
        let timestamp: String
        let appName: String
        var score: Float = 0  // Similarity score for semantic search (0-1)
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
    
    // Set of learned apps (new apps we discover)
    @Published var learnedApps: Set<String> = []
    
    // Segment cache for pagination - only keep visible range in memory
    private var segmentCache: [Int: TimelineSegment] = [:]
    private let maxCachedSegments = 500
    
    // Generate a consistent color for a new app based on its name
    static func generateColorForApp(_ appName: String) -> Color {
        // Use hash of app name to generate consistent color
        let hash = abs(appName.hashValue)
        let hue = Double(hash % 360) / 360.0
        let saturation = 0.5 + Double((hash / 360) % 50) / 100.0
        let brightness = 0.7 + Double((hash / 18000) % 30) / 100.0
        
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
    
    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        cachePath = home.appendingPathComponent(".cache/memento").path
        dbPath = home.appendingPathComponent(".cache/memento/memento.db").path
        
        loadVideoFiles()
        loadTimelineMetadata()
        if totalFrames > 0 {
            currentFrameIndex = totalFrames - 1
            loadFrame(at: currentFrameIndex)
        }
    }
    
    private func loadVideoFiles() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(atPath: cachePath) else { return }
        
        let mp4Files = files.filter { $0.hasSuffix(".mp4") }
            .compactMap { filename -> (Int, URL)? in
                let name = filename.replacingOccurrences(of: ".mp4", with: "")
                guard let id = Int(name) else { return nil }
                let url = URL(fileURLWithPath: cachePath).appendingPathComponent(filename)
                
                // Skip small/corrupted files (less than 10KB)
                if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int64,
                   size < 10000 {
                    return nil
                }
                
                return (id, url)
            }
            .sorted { $0.0 < $1.0 }
        
        videoIds = []
        for (index, (id, url)) in mp4Files.enumerated() {
            videoFiles[index] = url
            videoIds.append(id)  // Store the actual video ID for database lookup
        }
        
        totalFrames = (videoFiles.count) * framesPerVideo
        print("📹 Loaded \(videoFiles.count) valid video files, \(totalFrames) total frames")
    }
    
    // Get the database frame_id for a given display index
    func getFrameIdForIndex(_ index: Int) -> Int {
        let videoIndex = index / framesPerVideo
        guard videoIndex < videoIds.count else { return 0 }
        let videoId = videoIds[videoIndex]
        let frameInVideo = index % framesPerVideo
        // Video filename is the starting frame_id, so add offset
        return videoId + frameInVideo
    }
    
    // Convert frame_id to display index (for search results)
    func getIndexForFrameId(_ frameId: Int) -> Int? {
        // Find which video contains this frame_id
        for (videoIndex, videoId) in videoIds.enumerated() {
            let videoEndId = videoId + framesPerVideo
            if frameId >= videoId && frameId < videoEndId {
                let frameInVideo = frameId - videoId
                return videoIndex * framesPerVideo + frameInVideo
            }
        }
        return nil
    }
    
    // Jump directly to a frame_id (from search)
    func jumpToFrameId(_ frameId: Int) {
        if let index = getIndexForFrameId(frameId) {
            jumpToFrame(index)
        } else {
            log("⚠️ Could not find display index for frame_id \(frameId)")
        }
    }
    
    // Load timeline metadata from database - paginated for memory efficiency
    func loadTimelineMetadata() {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        
        // Only load metadata for videos we actually have (not all historical frames)
        let videoIdsList = videoIds.map { String($0) }.joined(separator: ",")
        let sql = videoIds.isEmpty 
            ? "SELECT id, window_title, time FROM FRAME ORDER BY id"
            : "SELECT id, window_title, time FROM FRAME WHERE id IN (\(videoIdsList)) ORDER BY id"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.locale = Locale(identifier: "sv_SE")
        
        // Use autoreleasepool to manage memory during bulk loading
        var segments: [TimelineSegment] = []
        segments.reserveCapacity(min(videoIds.count, maxCachedSegments))
        var grouped: [String: [TimelineSegment]] = [:]
        
        while sqlite3_step(statement) == SQLITE_ROW {
            autoreleasepool {
                let frameId = Int(sqlite3_column_int(statement, 0))
                
                let windowTitle: String
                if let titlePtr = sqlite3_column_text(statement, 1) {
                    windowTitle = String(cString: titlePtr)
                } else {
                    windowTitle = "Unknown"
                }
                
                let timeString: String
                var date: Date? = nil
                if let timePtr = sqlite3_column_text(statement, 2) {
                    let rawTime = String(cString: timePtr).replacingOccurrences(of: "\"", with: "")
                    timeString = rawTime
                    date = dateFormatter.date(from: rawTime)
                } else {
                    timeString = ""
                }
                
                // Extract app name from window title
                let appName = extractAppName(from: windowTitle)
                
                // Get or generate color for this app
                let color: Color
                if let existingColor = Self.appColors[appName] {
                    color = existingColor
                } else {
                    // Learn this new app and generate a color
                    let newColor = Self.generateColorForApp(appName)
                    Self.appColors[appName] = newColor
                    learnedApps.insert(appName)
                    color = newColor
                }
                
                // Find display index for this frame_id
                if let displayIndex = videoIds.firstIndex(of: frameId) {
                    let segment = TimelineSegment(
                        id: frameId,
                        displayIndex: displayIndex * framesPerVideo,
                        time: date,
                        timeString: timeString,
                        appName: appName,
                        color: color
                    )
                    segments.append(segment)
                    segmentCache[frameId] = segment  // Cache for quick lookup
                    
                    // Group by day
                    if let date = date {
                        let dayKey = dayFormatter.string(from: date)
                        if grouped[dayKey] == nil {
                            grouped[dayKey] = []
                        }
                        grouped[dayKey]?.append(segment)
                    }
                }
            }
        }
        
        timelineSegments = segments
        groupedByDay = grouped
        log("📅 Loaded \(segments.count) timeline segments, \(grouped.count) days, cache: \(segmentCache.count)")
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
        let frameId = getFrameIdForIndex(currentFrameIndex)
        return timelineSegments.first(where: { $0.id == frameId })?.color ?? Self.appColors["default"]!
    }
    
    func getSegmentForIndex(_ index: Int) -> TimelineSegment? {
        let videoIndex = index / framesPerVideo
        guard videoIndex < videoIds.count else { return nil }
        let frameId = videoIds[videoIndex]
        return timelineSegments.first(where: { $0.id == frameId })
    }
    
    func loadFrame(at index: Int) {
        guard index >= 0 && index < totalFrames else { return }
        
        let videoIndex = index / framesPerVideo
        let frameInVideo = index % framesPerVideo
        
        guard let videoURL = videoFiles[videoIndex] else {
            currentFrame = createPlaceholderImage()
            return
        }
        
        Task {
            isLoading = true
            defer { isLoading = false }
            
            let asset = AVAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            
            // Calculate time for the specific frame
            let duration = try? await asset.load(.duration)
            let totalSeconds = duration?.seconds ?? 10.0
            let timePerFrame = totalSeconds / Double(framesPerVideo)
            let targetTime = CMTime(seconds: Double(frameInVideo) * timePerFrame, preferredTimescale: 600)
            
            do {
                let (cgImage, _) = try await generator.image(at: targetTime)
                await MainActor.run {
                    self.currentFrame = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                }
            } catch {
                // Silently skip corrupted files and try next frame
                print("⚠️ Skipping corrupted video \(videoIndex)")
                await MainActor.run {
                    // Try to load next valid frame
                    if index < totalFrames - 1 {
                        self.currentFrameIndex = index + 1
                        self.loadFrame(at: self.currentFrameIndex)
                    } else {
                        self.currentFrame = createPlaceholderImage()
                    }
                }
            }
            
            // Load metadata
            loadMetadata(for: index)
        }
    }
    
    private func loadMetadata(for frameIndex: Int) {
        // First try to get from timeline segments (database)
        if let segment = getSegmentForIndex(frameIndex) {
            currentTime = segment.timeString
            currentApp = segment.appName
            return
        }
        
        // Fallback: Try to load from JSON metadata files
        let videoIndex = frameIndex / framesPerVideo
        guard videoIndex < videoIds.count else { return }
        let videoId = videoIds[videoIndex]
        
        let jsonPath = URL(fileURLWithPath: cachePath).appendingPathComponent("\(videoId).json")
        if let data = try? Data(contentsOf: jsonPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let time = json["time"] as? String {
                currentTime = time.replacingOccurrences(of: "\"", with: "")
            }
            if let app = json["window_title"] as? String {
                currentApp = extractAppName(from: app)
            }
        }
    }
    
    private func createPlaceholderImage() -> NSImage {
        let size = NSSize(width: 1920, height: 1080)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
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
        }
    }
    
    func jumpToFrame(_ index: Int) {
        guard index >= 0 && index < totalFrames else { return }
        currentFrameIndex = index
        loadFrame(at: index)
    }
    
    func loadTextForCurrentFrame() {
        let frameId = getFrameIdForIndex(currentFrameIndex)
        currentFrameText = []
        
        log("📝 Loading text for display index \(currentFrameIndex), frame_id \(frameId)")
        
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { 
            log("❌ Failed to open database")
            return 
        }
        defer { sqlite3_close(db) }
        
        let sql = "SELECT text, x, y, w, h FROM CONTENT WHERE frame_id = ? ORDER BY y, x"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { 
            log("❌ Failed to prepare statement")
            return 
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int(statement, 1, Int32(frameId))
        
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let textPtr = sqlite3_column_text(statement, 0) else { continue }
            let text = String(cString: textPtr)
            let x = Int(sqlite3_column_int(statement, 1))
            let y = Int(sqlite3_column_int(statement, 2))
            let w = Int(sqlite3_column_int(statement, 3))
            let h = Int(sqlite3_column_int(statement, 4))
            
            currentFrameText.append(TextBlock(text: text, x: x, y: y, width: w, height: h))
        }
        
        log("📝 Loaded \(currentFrameText.count) text blocks for frame_id \(frameId)")
    }
    
    func getAllTextForCurrentFrame() -> String {
        if currentFrameText.isEmpty {
            loadTextForCurrentFrame()
        }
        return currentFrameText.map { $0.text }.joined(separator: "\n")
    }
    
    func copyAllText() {
        let text = getAllTextForCurrentFrame()
        if !text.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copiedNotification = true
            
            // Hide notification after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.copiedNotification = false
            }
        }
    }
    
    func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedNotification = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.copiedNotification = false
        }
    }
    
    private func log(_ message: String) {
        print(message)
        // Also write to log file for debugging
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/memento/swift_timeline.log")
        let logMessage = "\(Date()): \(message)\n"
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath.path) {
                if let handle = try? FileHandle(forWritingTo: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logPath)
            }
        }
    }
    
    func search(_ query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        searchResults = []
        log("🔍 Searching for: '\(query)' in database: \(dbPath)")
        
        // Check if database file exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: dbPath) {
            log("❌ Database file does not exist at: \(dbPath)")
            return
        }
        log("✅ Database file exists")
        
        var db: OpaquePointer?
        let openResult = sqlite3_open(dbPath, &db)
        guard openResult == SQLITE_OK else {
            log("❌ Failed to open database: \(openResult)")
            return
        }
        defer { sqlite3_close(db) }
        log("✅ Database opened successfully")
        
        // Direct query with embedded search term (debug)
        let escapedQuery = query.replacingOccurrences(of: "'", with: "''")
        let sql = "SELECT frame_id, text FROM CONTENT WHERE text LIKE '%\(escapedQuery)%' COLLATE NOCASE ORDER BY frame_id DESC LIMIT 100"
        log("📝 SQL: \(sql)")
        
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            log("❌ Failed to prepare statement: \(errorMsg)")
            return
        }
        defer { sqlite3_finalize(statement) }
        log("✅ Statement prepared")
        
        var rowCount = 0
        var frameIds: [(Int, String)] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            rowCount += 1
            let frameId = Int(sqlite3_column_int(statement, 0))
            guard let textPtr = sqlite3_column_text(statement, 1) else { continue }
            let text = String(cString: textPtr)
            frameIds.append((frameId, String(text.prefix(100))))
        }
        
        // Fetch timestamps for each result
        for (frameId, text) in frameIds {
            let metaSql = "SELECT time, window_title FROM FRAME WHERE id = ?"
            var metaStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, metaSql, -1, &metaStmt, nil) == SQLITE_OK {
                sqlite3_bind_int(metaStmt, 1, Int32(frameId))
                if sqlite3_step(metaStmt) == SQLITE_ROW {
                    let timestamp = sqlite3_column_text(metaStmt, 0).map { String(cString: $0) } ?? ""
                    let appName = sqlite3_column_text(metaStmt, 1).map { String(cString: $0) } ?? ""
                    searchResults.append(SearchResult(
                        frameId: frameId,
                        text: text,
                        timestamp: timestamp,
                        appName: appName
                    ))
                }
                sqlite3_finalize(metaStmt)
            }
        }
        
        log("🔍 Found \(searchResults.count) results for '\(query)' (processed \(rowCount) rows)")
    }
    
    // MARK: - Semantic Search
    
    private let embeddingService = EmbeddingService()
    
    func semanticSearch(_ query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        log("🧠 Semantic search for: '\(query)'")
        
        // Generate query embedding and quantize
        guard let queryVector = embeddingService.embed(query) else {
            log("⚠️ Failed to embed query")
            search(query)  // Fallback to text search
            return
        }
        let queryQuantized = embeddingService.quantize(queryVector)
        
        // Load all embeddings from database
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        
        let sql = "SELECT frame_id, vector, quantized, text_summary FROM EMBEDDING"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        var matches: [(frameId: Int, similarity: Float, summary: String)] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let frameId = Int(sqlite3_column_int(stmt, 0))
            
            guard let blobPtr = sqlite3_column_blob(stmt, 1) else { continue }
            let blobSize = Int(sqlite3_column_bytes(stmt, 1))
            let vectorData = Data(bytes: blobPtr, count: blobSize)
            let isQuantized = sqlite3_column_int(stmt, 2) == 1
            
            let summary: String
            if let textPtr = sqlite3_column_text(stmt, 3) {
                summary = String(cString: textPtr)
            } else {
                summary = ""
            }
            
            // Calculate similarity (use quantized if stored that way)
            let similarity: Float
            if isQuantized {
                let storedQuantized = embeddingService.dataToQuantized(vectorData)
                similarity = embeddingService.cosineSimilarityQuantized(queryQuantized, storedQuantized)
            } else {
                let storedVector = embeddingService.dataToVector(vectorData)
                similarity = embeddingService.cosineSimilarity(queryVector, storedVector)
            }
            
            if similarity > 0.3 {  // Threshold
                matches.append((frameId, similarity, summary))
            }
        }
        
        // Sort by similarity (highest first)
        matches.sort { $0.similarity > $1.similarity }
        
        // Get frame metadata for top matches
        let topMatches = Array(matches.prefix(50))
        var results: [SearchResult] = []
        
        for match in topMatches {
            let metaSql = "SELECT time, window_title FROM FRAME WHERE id = ?"
            var metaStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, metaSql, -1, &metaStmt, nil) == SQLITE_OK {
                sqlite3_bind_int(metaStmt, 1, Int32(match.frameId))
                if sqlite3_step(metaStmt) == SQLITE_ROW {
                    let timestamp = sqlite3_column_text(metaStmt, 0).map { String(cString: $0) } ?? ""
                    let appName = sqlite3_column_text(metaStmt, 1).map { String(cString: $0) } ?? ""
                    results.append(SearchResult(
                        frameId: match.frameId,
                        text: match.summary,
                        timestamp: timestamp,
                        appName: appName,
                        score: match.similarity
                    ))
                }
                sqlite3_finalize(metaStmt)
            }
        }
        
        searchResults = results
        log("🧠 Found \(searchResults.count) semantic matches")
    }
}

