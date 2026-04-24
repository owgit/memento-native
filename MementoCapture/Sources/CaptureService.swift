import Foundation
import AppKit
import CoreGraphics
import Combine

/// Main capture service - captures screenshots, performs OCR, stores results
@available(macOS 14.0, *)
@MainActor
final class CaptureService {
    static let shared = CaptureService()
    private static let iso8601Formatter = ISO8601DateFormatter()
    
    // Configuration
    var captureInterval: TimeInterval { Settings.shared.captureInterval }
    let framesPerVideo = 5  // 5 frames per video file
    
    // State
    private var frameCount = 0
    private var timer: Timer?
    private var captureTask: Task<Void, Never>?
    private var captureInFlight = false
    private var previousImage: CGImage?
    private var highMotionMediaStreak = 0
    private var videoPauseUntil: Date?
    private var pausedVideoBundleId: String?
    var lastCapturedImage: CGImage? { previousImage }
    private(set) var lastSuccessfulCaptureAt: Date?
    private var settingsObservation: AnyCancellable?
    private var hasPreparedCaptureResources = false
    
    // Components
    private let screenshotCapture = ScreenshotCapture()
    private lazy var ocrEngine = VisionOCR()
    private var videoEncoder: VideoEncoder?
    private var database: Database?
    private lazy var embeddingService = EmbeddingService()
    
    // Paths
    private(set) var cachePath: URL
    
    private init() {
        cachePath = Settings.shared.storageURL
        observeSettings()
    }
    
    func start() {
        guard timer == nil else { return }
        prepareCaptureResourcesIfNeeded()

        AppLog.info("▶️  Starting capture service...")
        AppLog.info("   Interval: \(captureInterval)s")
        AppLog.info("   Resolution: Auto-detect")

        applyRetentionPolicyIfNeeded()
        
        scheduleCaptureTimer()

        // Fire immediately
        enqueueCaptureIfNeeded()
    }
    
    func stop() async {
        AppLog.info("⏹️  Stopping capture service...")
        timer?.invalidate()
        timer = nil

        if let captureTask {
            captureTask.cancel()
            self.captureTask = nil
            await captureTask.value
        }

        previousImage = nil  // Release memory
        highMotionMediaStreak = 0
        videoPauseUntil = nil
        pausedVideoBundleId = nil
        do {
            try await videoEncoder?.finalize()
            rebuildVideoEncoder(frameDuration: captureInterval)
        } catch {
            AppLog.warning("⚠️ Failed to finalize video during stop: \(error.localizedDescription)")
            rebuildVideoEncoder(frameDuration: captureInterval)
        }
    }

    func switchStoragePath(to newPath: URL) async throws -> StorageMigrator.Result {
        let normalizedPath = newPath.standardizedFileURL
        let currentPath = cachePath.standardizedFileURL
        guard normalizedPath.path != currentPath.path else { return StorageMigrator.Result() }

        let wasRunning = timer != nil
        if wasRunning {
            await stop()
        }

        // Close DB before migrating files so WAL/shm can move cleanly.
        let hadPreparedResources = hasPreparedCaptureResources
        database?.close()
        database = nil
        videoEncoder = nil
        hasPreparedCaptureResources = false
        frameCount = 0

        do {
            try FileManager.default.createDirectory(at: normalizedPath, withIntermediateDirectories: true)
            let migrationResult = try await Task.detached(priority: .utility) {
                try StorageMigrator.migrateDirectory(from: currentPath, to: normalizedPath)
            }.value

            cachePath = normalizedPath

            AppLog.info("📦 Storage migrated to: \(cachePath.path)")
            if migrationResult.movedItems > 0 || migrationResult.copiedItems > 0 || migrationResult.conflictRenames > 0 {
                AppLog.info("   moved: \(migrationResult.movedItems), copied: \(migrationResult.copiedItems), renamed conflicts: \(migrationResult.conflictRenames), skipped: \(migrationResult.skippedItems)")
            }

            if wasRunning {
                start()
            }

            return migrationResult
        } catch {
            cachePath = currentPath
            if hadPreparedResources {
                prepareCaptureResourcesIfNeeded()
            }

            if wasRunning {
                start()
            }

            throw error
        }
    }
    
    private func captureFrame() async {
        guard !captureInFlight else { return }
        captureInFlight = true
        defer { captureInFlight = false }

        let startTime = Date()
        
        // Get active app info
        let activeApp = getActiveApp()
        let appBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        
        // Skip capture while one of Memento's own windows is frontmost.
        if shouldPauseForOwnedUI(activeBundleId: appBundleId) {
            AppLog.info("⏸️  Skipping capture - Memento UI is active")
            return
        }
        
        // Skip capture when screen is locked or screensaver is active
        if isScreenLocked() {
            AppLog.info("🔒 Skipping capture - Screen locked or screensaver active")
            return
        }

        // Skip capture if user is idle
        if shouldPauseForIdle() {
            return
        }

        // Skip capture while a likely video playback pause window is active
        if shouldPauseForDetectedVideo(activeBundleId: appBundleId) {
            return
        }
        
        // Get browser URL and tab title
        let browserInfo = BrowserCapture.getCurrentBrowserInfo()

        // Skip capture in private/incognito browsing contexts.
        if Settings.shared.pauseDuringPrivateBrowsing && browserInfo?.isPrivateBrowsing == true {
            highMotionMediaStreak = 0
            videoPauseUntil = nil
            pausedVideoBundleId = nil
            AppLog.info("🕶️  Skipping capture - Private/incognito browsing detected")
            return
        }
        
        // Get clipboard content (if enabled)
        let clipboardContent = ClipboardCapture.shared.getNewClipboardContent()
        
        // Capture screenshot using ScreenCaptureKit
        guard let screenshot = await screenshotCapture.capture() else {
            AppLog.warning("⚠️  Failed to capture screenshot")
            return
        }
        
        // Check if frame changed significantly
        let shouldOCR: Bool
        let diffScore: Double
        if let previous = previousImage {
            let diff = imageDifference(screenshot, previous)
            diffScore = diff
            shouldOCR = diff > 0.02  // OCR if >2% change (was 50% - too aggressive)
            if !shouldOCR {
                AppLog.info("⏭️  Frame \(frameCount): skipped (diff: \(String(format: "%.2f", diff)))")
            }
        } else {
            diffScore = 0
            shouldOCR = true
        }
        previousImage = screenshot

        // Skip saving frames during likely media playback (video/streaming).
        if shouldPauseForLikelyVideoPlayback(
            activeApp: activeApp,
            bundleId: appBundleId,
            browserInfo: browserInfo,
            diffScore: diffScore
        ) {
            return
        }
        
        // Skip OCR for excluded apps
        let isExcluded = Settings.shared.isAppExcluded(activeApp)
        
        // Perform OCR
        var ocrResults: [TextBlock] = []
        if shouldOCR && !isExcluded {
            ocrResults = await ocrEngine.recognizeText(in: screenshot)
        }
        
        // Get timestamp
        let timestamp = Self.iso8601Formatter.string(from: Date())
        
        // Get app category from system
        let appCategory = getAppCategory(bundleId: appBundleId)

        guard let database else {
            AppLog.warning("⚠️ Database unavailable; skipping frame persistence")
            return
        }
        
        // Store in database with extended metadata
        guard database.insertFrame(
            frameId: frameCount,
            windowTitle: activeApp,
            time: timestamp,
            textBlocks: ocrResults,
            url: browserInfo?.url,
            tabTitle: browserInfo?.title,
            appBundleId: appBundleId,
            clipboard: clipboardContent,
            appCategory: appCategory
        ) else {
            AppLog.warning("⚠️ Failed to persist frame \(frameCount); skipping encoder write")
            return
        }
        
        // Generate a language-aware embedding using structured signals instead of a raw text blob.
        let semanticDocument = buildSemanticDocument(
            activeApp: activeApp,
            url: browserInfo?.url,
            tabTitle: browserInfo?.title,
            clipboardContent: clipboardContent,
            ocrResults: ocrResults
        )
        if !semanticDocument.embeddingText.isEmpty,
           let embedding = embeddingService.embed(semanticDocument.embeddingText) {
            let quantized = embeddingService.quantize(embedding.vector)
            let vectorData = embeddingService.quantizedToData(quantized)
            if !database.insertEmbedding(
                frameId: frameCount,
                vector: vectorData,
                textSummary: semanticDocument.summary,
                quantized: true,
                language: embedding.language.rawValue,
                revision: embedding.revision
            ) {
                AppLog.warning("⚠️ Failed to persist embedding for frame \(frameCount)")
            }
        }
        
        // Add to video encoder
        guard let videoEncoder else {
            AppLog.warning("⚠️ Video encoder unavailable; skipping frame encoding")
            return
        }
        let shouldRotateVideo: Bool
        do {
            shouldRotateVideo = try videoEncoder.addFrame(screenshot)
        } catch {
            AppLog.warning("⚠️ Video encoding failed for frame \(frameCount): \(error.localizedDescription)")
            frameCount += 1
            rebuildVideoEncoder(frameDuration: captureInterval)
            return
        }
        
        // Log
        let elapsed = Date().timeIntervalSince(startTime)
        AppLog.info("📸 Frame \(frameCount): \(ocrResults.count) texts, \(String(format: "%.2f", elapsed))s, app: \(activeApp)")
        lastSuccessfulCaptureAt = Date()
        
        frameCount += 1

        if shouldRotateVideo {
            do {
                try await videoEncoder.finalize()
                // Use frame_id as video name so Timeline can map correctly
                videoEncoder.startNewVideo(index: frameCount)
            } catch {
                AppLog.warning("⚠️ Video finalize failed after frame \(frameCount - 1): \(error.localizedDescription)")
                rebuildVideoEncoder(frameDuration: captureInterval)
            }
        }
    }
    
    private func getActiveApp() -> String {
        if let app = NSWorkspace.shared.frontmostApplication {
            return app.localizedName ?? "Unknown"
        }
        return "Unknown"
    }
    
    /// Get app category from bundle Info.plist (LSApplicationCategoryType)
    private func getAppCategory(bundleId: String?) -> String? {
        guard let bundleId = bundleId,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
              let bundle = Bundle(url: appURL),
              let category = bundle.infoDictionary?["LSApplicationCategoryType"] as? String else {
            return nil
        }
        // Strip "public.app-category." prefix for cleaner storage
        return category.replacingOccurrences(of: "public.app-category.", with: "")
    }
    
    /// Check if screen is locked or screensaver is active
    private func isScreenLocked() -> Bool {
        // Check session dictionary for screen lock state
        if let sessionDict = CGSessionCopyCurrentDictionary() as? [String: Any] {
            // CGSSessionScreenIsLocked = true when locked
            if let isLocked = sessionDict["CGSSessionScreenIsLocked"] as? Bool, isLocked {
                return true
            }
            // kCGSSessionOnConsoleKey = false when switched user or locked
            if let onConsole = sessionDict["kCGSSessionOnConsoleKey"] as? Bool, !onConsole {
                return true
            }
        }
        
        // Check if ScreenSaverEngine is running
        let runningApps = NSWorkspace.shared.runningApplications
        if runningApps.contains(where: { $0.bundleIdentifier == "com.apple.ScreenSaver.Engine" }) {
            return true
        }
        
        return false
    }

    private func shouldPauseForIdle() -> Bool {
        guard Settings.shared.pauseWhenIdle else { return false }
        guard let idleSeconds = secondsSinceLastUserInput() else { return false }

        if idleSeconds >= Settings.shared.idleThresholdSeconds {
            highMotionMediaStreak = 0
            AppLog.info("😴 Skipping capture - User idle (\(Int(idleSeconds))s)")
            return true
        }
        return false
    }

    private func secondsSinceLastUserInput() -> TimeInterval? {
        let state: CGEventSourceStateID = .hidSystemState
        let eventTypes: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .mouseMoved, .scrollWheel]
        let values = eventTypes.map { CGEventSource.secondsSinceLastEventType(state, eventType: $0) }
        guard let minValue = values.min(), minValue.isFinite else { return nil }
        return minValue
    }

    private func shouldPauseForDetectedVideo(activeBundleId: String?) -> Bool {
        guard Settings.shared.pauseDuringVideo else {
            videoPauseUntil = nil
            pausedVideoBundleId = nil
            return false
        }

        guard let pauseUntil = videoPauseUntil else { return false }
        if Date() >= pauseUntil {
            videoPauseUntil = nil
            pausedVideoBundleId = nil
            return false
        }

        if let pausedBundleId = pausedVideoBundleId,
           let activeBundleId,
           pausedBundleId != activeBundleId {
            videoPauseUntil = nil
            pausedVideoBundleId = nil
            return false
        }

        let remaining = max(1, Int(pauseUntil.timeIntervalSinceNow.rounded()))
        AppLog.info("🎬 Skipping capture - Video playback detected (\(remaining)s left)")
        return true
    }

    private func shouldPauseForLikelyVideoPlayback(
        activeApp: String,
        bundleId: String?,
        browserInfo: BrowserCapture.BrowserInfo?,
        diffScore: Double
    ) -> Bool {
        guard Settings.shared.pauseDuringVideo else {
            highMotionMediaStreak = 0
            return false
        }

        let isMediaContext = isLikelyMediaContext(activeApp: activeApp, bundleId: bundleId, browserInfo: browserInfo)
        let hasRapidMotion = diffScore > 0.12

        if isMediaContext && hasRapidMotion {
            highMotionMediaStreak += 1
        } else {
            highMotionMediaStreak = 0
            return false
        }

        // Require multiple consecutive high-motion frames to avoid false positives.
        if highMotionMediaStreak < 3 {
            return false
        }

        highMotionMediaStreak = 0
        let pauseSeconds: TimeInterval = 30
        videoPauseUntil = Date().addingTimeInterval(pauseSeconds)
        pausedVideoBundleId = bundleId
        AppLog.info("🎬 Skipping capture - Likely video/streaming detected (\(Int(pauseSeconds))s)")
        return true
    }

    private func isLikelyMediaContext(
        activeApp: String,
        bundleId: String?,
        browserInfo: BrowserCapture.BrowserInfo?
    ) -> Bool {
        let mediaBundleIds: Set<String> = [
            "com.apple.TV",
            "com.apple.QuickTimePlayerX",
            "org.videolan.vlc",
            "com.colliderli.iina",
            "tv.plex.desktop"
        ]

        if let bundleId, mediaBundleIds.contains(bundleId) {
            return true
        }

        let mediaAppNames = ["QuickTime Player", "VLC", "IINA", "TV", "Plex", "Infuse"]
        if mediaAppNames.contains(where: { activeApp.localizedCaseInsensitiveContains($0) }) {
            return true
        }

        if let url = browserInfo?.url?.lowercased() {
            let mediaHosts = [
                "youtube.com",
                "youtu.be",
                "netflix.com",
                "twitch.tv",
                "disneyplus.com",
                "max.com",
                "primevideo.com",
                "vimeo.com"
            ]
            if mediaHosts.contains(where: { url.contains($0) }) {
                return true
            }
        }

        if let title = browserInfo?.title?.lowercased() {
            let mediaKeywords = ["youtube", "netflix", "twitch", "disney", "prime video", "vimeo", "watch", "trailer"]
            if mediaKeywords.contains(where: { title.contains($0) }) {
                return true
            }
        }

        return false
    }
    
    private func imageDifference(_ img1: CGImage, _ img2: CGImage) -> Double {
        // Quick size check
        guard img1.width == img2.width && img1.height == img2.height else {
            return 1.0  // Different size = different image
        }
        
        // Sample pixels for quick comparison
        let sampleSize = 100
        var diffSum: Double = 0
        
        guard let data1 = img1.dataProvider?.data,
              let data2 = img2.dataProvider?.data else {
            return 1.0
        }
        
        let ptr1 = CFDataGetBytePtr(data1)
        let ptr2 = CFDataGetBytePtr(data2)
        let length = CFDataGetLength(data1)
        
        let step = max(1, length / sampleSize)
        var samples = 0
        
        for i in stride(from: 0, to: length, by: step) {
            let diff = abs(Int(ptr1![i]) - Int(ptr2![i]))
            diffSum += Double(diff)
            samples += 1
        }
        
        return diffSum / Double(samples * 255)
    }

    private func enqueueCaptureIfNeeded() {
        guard captureTask == nil else { return }
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.captureFrame()
            self.captureTask = nil
        }
    }

    private func scheduleCaptureTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.enqueueCaptureIfNeeded()
            }
        }
    }

    private func prepareCaptureResourcesIfNeeded() {
        guard !hasPreparedCaptureResources else { return }

        let frameDuration = Settings.shared.captureInterval
        try? FileManager.default.createDirectory(at: cachePath, withIntermediateDirectories: true)

        let databasePath = cachePath.appendingPathComponent("memento.db").path
        let database = Database(path: databasePath)
        let videoEncoder = VideoEncoder(
            outputDirectory: cachePath,
            framesPerVideo: framesPerVideo,
            frameDuration: frameDuration
        )

        frameCount = database.getMaxFrameId() + 1
        self.database = database
        self.videoEncoder = videoEncoder
        hasPreparedCaptureResources = true

        AppLog.info("📁 Cache path: \(cachePath.path)")
        AppLog.info("📊 Continuing from frame \(frameCount)")

        videoEncoder.startNewVideo(index: frameCount)
    }

    private func rebuildVideoEncoder(frameDuration: TimeInterval) {
        guard hasPreparedCaptureResources else { return }

        let encoder = VideoEncoder(
            outputDirectory: cachePath,
            framesPerVideo: framesPerVideo,
            frameDuration: frameDuration
        )
        encoder.startNewVideo(index: frameCount)
        videoEncoder = encoder
    }

    private func observeSettings() {
        settingsObservation = Settings.shared.$captureInterval
            .dropFirst()
            .sink { [weak self] newInterval in
                guard let self else { return }
                Task { @MainActor in
                    await self.applyCaptureIntervalChange(newInterval)
                }
            }
    }

    private func applyCaptureIntervalChange(_ newInterval: TimeInterval) async {
        let wasRunning = timer != nil
        timer?.invalidate()
        timer = nil

        if let captureTask {
            captureTask.cancel()
            self.captureTask = nil
            await captureTask.value
        }

        do {
            try await videoEncoder?.finalize()
        } catch {
            AppLog.warning("⚠️ Failed to finalize video before applying new interval: \(error.localizedDescription)")
        }

        rebuildVideoEncoder(frameDuration: newInterval)

        if wasRunning {
            AppLog.info("🔄 Applying new capture interval: \(newInterval)s")
            scheduleCaptureTimer()
        }
    }

    private func applyRetentionPolicyIfNeeded() {
        let daysToKeep = Settings.shared.retentionDays
        guard daysToKeep > 0 && daysToKeep < 9999 else { return }

        let defaults = UserDefaults.standard
        let lastCleanupKey = "lastRetentionCleanupAt"
        let minimumInterval: TimeInterval = 12 * 60 * 60
        let now = Date()

        if let lastCleanup = defaults.object(forKey: lastCleanupKey) as? Date,
           now.timeIntervalSince(lastCleanup) < minimumInterval {
            return
        }
        defaults.set(now, forKey: lastCleanupKey)

        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysToKeep, to: now) else {
            return
        }
        let cutoffString = Self.iso8601Formatter.string(from: cutoffDate)
        let dbPath = cachePath.appendingPathComponent("memento.db").path
        let framesPerVideo = self.framesPerVideo
        let cachePath = self.cachePath

        Task.detached(priority: .utility) {
            let result = StorageCleaner.cleanup(
                dbPath: dbPath,
                cachePath: cachePath,
                cutoffISO8601: cutoffString,
                deleteAll: false,
                framesPerVideo: framesPerVideo
            )

            if result.deletedFrames > 0 || result.deletedVideos > 0 {
                AppLog.info("🧹 Retention cleanup: \(result.deletedFrames) frames, \(result.deletedVideos) videos deleted")
            }
        }
    }

    private struct SemanticDocument {
        let embeddingText: String
        let summary: String
    }

    private func buildSemanticDocument(
        activeApp: String,
        url: String?,
        tabTitle: String?,
        clipboardContent: String?,
        ocrResults: [TextBlock]
    ) -> SemanticDocument {
        let title = sanitizeSemanticSegment(tabTitle, maxLength: 180)
        let urlString = sanitizeSemanticSegment(url, maxLength: 220)
        let host = sanitizedHost(from: url)
        let app = sanitizeSemanticSegment(activeApp, maxLength: 80)
        let clipboard = sanitizeSemanticSegment(clipboardContent, maxLength: 240)

        var uniqueOCRLines: [String] = []
        var seenOCRLines = Set<String>()
        for block in ocrResults {
            let cleaned = sanitizeSemanticSegment(block.text, maxLength: 120)
            guard !cleaned.isEmpty else { continue }

            let signature = cleaned.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if seenOCRLines.insert(signature).inserted {
                uniqueOCRLines.append(cleaned)
            }
            if uniqueOCRLines.count >= 24 {
                break
            }
        }

        let ocrSummary = uniqueOCRLines.prefix(8).joined(separator: " • ")
        let ocrText = uniqueOCRLines.joined(separator: " ")

        var embeddingSections: [String] = []
        var summarySections: [String] = []

        if !title.isEmpty {
            embeddingSections.append("page title \(title)")
            summarySections.append(title)
        }
        if !host.isEmpty {
            embeddingSections.append("website \(host)")
        }
        if !urlString.isEmpty {
            embeddingSections.append("url \(urlString)")
            if summarySections.isEmpty {
                summarySections.append(urlString)
            }
        }
        if !app.isEmpty {
            embeddingSections.append("application \(app)")
            summarySections.append(app)
        }
        if !clipboard.isEmpty {
            embeddingSections.append("clipboard \(clipboard)")
            summarySections.append(String(clipboard.prefix(80)))
        }
        if !ocrText.isEmpty {
            embeddingSections.append("screen text \(ocrText)")
            if !ocrSummary.isEmpty {
                summarySections.append(ocrSummary)
            }
        }

        let embeddingText = embeddingSections.joined(separator: ". ")
        let summary = summarySections
            .joined(separator: " • ")
            .prefix(240)
            .description

        return SemanticDocument(embeddingText: embeddingText, summary: summary)
    }

    private func sanitizeSemanticSegment(_ value: String?, maxLength: Int) -> String {
        guard let value else { return "" }
        return value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(maxLength)
            .description
    }

    private func sanitizedHost(from urlString: String?) -> String {
        guard let urlString,
              let components = URLComponents(string: urlString),
              let host = components.host else {
            return ""
        }
        return sanitizeSemanticSegment(host, maxLength: 80)
    }

    private func shouldPauseForOwnedUI(activeBundleId: String?) -> Bool {
        guard activeBundleId == Bundle.main.bundleIdentifier else {
            return false
        }

        return NSApp.windows.contains { window in
            window.isVisible && !window.isMiniaturized
        }
    }
}

/// Text block from OCR
struct TextBlock {
    let text: String
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}
