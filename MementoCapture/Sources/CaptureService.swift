import Foundation
import AppKit
import Vision
import AVFoundation
import CoreGraphics

/// Main capture service - captures screenshots, performs OCR, stores results
@available(macOS 14.0, *)
@MainActor
class CaptureService {
    static let shared = CaptureService()
    
    // Configuration
    var captureInterval: TimeInterval { Settings.shared.captureInterval }
    let framesPerVideo = 5  // 5 frames per video file
    
    // State
    private var frameCount = 0
    private var timer: Timer?
    private var previousImage: CGImage?
    private var highMotionMediaStreak = 0
    private var videoPauseUntil: Date?
    private var pausedVideoBundleId: String?
    private(set) var lastSuccessfulCaptureAt: Date?
    
    // Components
    private let screenshotCapture = ScreenshotCapture()
    private let ocrEngine = VisionOCR()
    private var videoEncoder: VideoEncoder
    private var database: Database
    private let embeddingService = EmbeddingService()
    
    // Paths
    private(set) var cachePath: URL
    
    private init() {
        // Setup cache path from settings
        cachePath = Settings.shared.storageURL
        
        // Create cache directory
        try? FileManager.default.createDirectory(at: cachePath, withIntermediateDirectories: true)
        
        // Initialize components
        database = Database(path: cachePath.appendingPathComponent("memento.db").path)
        videoEncoder = VideoEncoder(outputDirectory: cachePath, framesPerVideo: framesPerVideo)
        
        // Continue from last frame
        frameCount = database.getMaxFrameId() + 1
        
        print("📁 Cache path: \(cachePath.path)")
        print("📊 Continuing from frame \(frameCount)")
        
        // Start video with frame_id as name
        videoEncoder.startNewVideo(index: frameCount)
    }
    
    func start() {
        guard timer == nil else { return }

        print("▶️  Starting capture service...")
        print("   Interval: \(captureInterval)s")
        print("   Resolution: Auto-detect")

        applyRetentionPolicyIfNeeded()
        
        // Start capture timer
        timer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.captureFrame()
            }
        }
        
        // Fire immediately
        Task {
            await captureFrame()
        }
    }
    
    func stop() {
        print("⏹️  Stopping capture service...")
        timer?.invalidate()
        timer = nil
        previousImage = nil  // Release memory
        highMotionMediaStreak = 0
        videoPauseUntil = nil
        pausedVideoBundleId = nil
        videoEncoder.finalize()
    }

    func switchStoragePath(to newPath: URL) throws -> StorageMigrator.Result {
        let normalizedPath = newPath.standardizedFileURL
        let currentPath = cachePath.standardizedFileURL
        guard normalizedPath.path != currentPath.path else { return StorageMigrator.Result() }

        let wasRunning = timer != nil
        if wasRunning {
            stop()
        }

        // Close DB before migrating files so WAL/shm can move cleanly.
        database.close()

        try FileManager.default.createDirectory(at: normalizedPath, withIntermediateDirectories: true)
        let migrationResult = try StorageMigrator.migrateDirectory(from: currentPath, to: normalizedPath)

        cachePath = normalizedPath
        database = Database(path: cachePath.appendingPathComponent("memento.db").path)
        frameCount = database.getMaxFrameId() + 1

        videoEncoder = VideoEncoder(outputDirectory: cachePath, framesPerVideo: framesPerVideo)
        videoEncoder.startNewVideo(index: frameCount)

        print("📦 Storage migrated to: \(cachePath.path)")
        if migrationResult.movedItems > 0 || migrationResult.copiedItems > 0 || migrationResult.conflictRenames > 0 {
            print("   moved: \(migrationResult.movedItems), copied: \(migrationResult.copiedItems), renamed conflicts: \(migrationResult.conflictRenames), skipped: \(migrationResult.skippedItems)")
        }

        if wasRunning {
            start()
        }

        return migrationResult
    }
    
    private func captureFrame() async {
        let startTime = Date()
        
        // Get active app info
        let activeApp = getActiveApp()
        let appBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        
        // Skip capture when Timeline app is open (saves resources)
        if appBundleId == "com.memento.timeline" || activeApp == "Memento Timeline" || activeApp == "MementoTimeline" {
            print("⏸️  Skipping capture - Timeline app is active")
            return
        }
        
        // Skip capture when screen is locked or screensaver is active
        if isScreenLocked() {
            print("🔒 Skipping capture - Screen locked or screensaver active")
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
        
        // Get clipboard content (if enabled)
        let clipboardContent = ClipboardCapture.shared.getNewClipboardContent()
        
        // Capture screenshot using ScreenCaptureKit
        guard let screenshot = await screenshotCapture.capture() else {
            print("⚠️  Failed to capture screenshot")
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
                print("⏭️  Frame \(frameCount): skipped (diff: \(String(format: "%.2f", diff)))")
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
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        // Get app category from system
        let appCategory = getAppCategory(bundleId: appBundleId)
        
        // Store in database with extended metadata
        database.insertFrame(
            frameId: frameCount,
            windowTitle: activeApp,
            time: timestamp,
            textBlocks: ocrResults,
            url: browserInfo?.url,
            tabTitle: browserInfo?.title,
            appBundleId: appBundleId,
            clipboard: clipboardContent,
            appCategory: appCategory
        )
        
        // Generate quantized embedding for semantic search (8x smaller storage)
        // Include OCR + URL + tab title + clipboard for better semantic search
        var embeddingParts: [String] = []
        
        if let url = browserInfo?.url, !url.isEmpty { embeddingParts.append(url) }
        if let title = browserInfo?.title, !title.isEmpty { embeddingParts.append(title) }
        if !activeApp.isEmpty { embeddingParts.append(activeApp) }
        if let clip = clipboardContent, !clip.isEmpty { embeddingParts.append(clip) }
        embeddingParts.append(contentsOf: ocrResults.map { $0.text })
        
        let allText = embeddingParts.joined(separator: " ")
        if !allText.isEmpty, let vector = embeddingService.embed(allText) {
            let quantized = embeddingService.quantize(vector)
            let vectorData = embeddingService.quantizedToData(quantized)
            let summary = String(allText.prefix(200))
            database.insertEmbedding(frameId: frameCount, vector: vectorData, textSummary: summary, quantized: true)
        }
        
        // Add to video encoder
        videoEncoder.addFrame(screenshot, frameIndex: frameCount)
        
        // Log
        let elapsed = Date().timeIntervalSince(startTime)
        print("📸 Frame \(frameCount): \(ocrResults.count) texts, \(String(format: "%.2f", elapsed))s, app: \(activeApp)")
        lastSuccessfulCaptureAt = Date()
        
        frameCount += 1
        
        // Check if we need to start new video
        if frameCount % framesPerVideo == 0 {
            videoEncoder.finalize()
            // Use frame_id as video name so Timeline can map correctly
            videoEncoder.startNewVideo(index: frameCount)
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
            print("😴 Skipping capture - User idle (\(Int(idleSeconds))s)")
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
        print("🎬 Skipping capture - Video playback detected (\(remaining)s left)")
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
        print("🎬 Skipping capture - Likely video/streaming detected (\(Int(pauseSeconds))s)")
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
        let cutoffString = ISO8601DateFormatter().string(from: cutoffDate)
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
                print("🧹 Retention cleanup: \(result.deletedFrames) frames, \(result.deletedVideos) videos deleted")
            }
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
    let confidence: Float
}
