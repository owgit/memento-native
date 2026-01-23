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
    
    // Components
    private let screenshotCapture = ScreenshotCapture()
    private let ocrEngine = VisionOCR()
    private let videoEncoder: VideoEncoder
    private let database: Database
    private let embeddingService = EmbeddingService()
    
    // Paths
    let cachePath: URL
    
    private init() {
        // Setup cache path
        let home = FileManager.default.homeDirectoryForCurrentUser
        cachePath = home.appendingPathComponent(".cache/memento")
        
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
        print("▶️  Starting capture service...")
        print("   Interval: \(captureInterval)s")
        print("   Resolution: Auto-detect")
        
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
        videoEncoder.finalize()
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
        if let previous = previousImage {
            let diff = imageDifference(screenshot, previous)
            shouldOCR = diff > 0.02  // OCR if >2% change (was 50% - too aggressive)
            if !shouldOCR {
                print("⏭️  Frame \(frameCount): skipped (diff: \(String(format: "%.2f", diff)))")
            }
        } else {
            shouldOCR = true
        }
        previousImage = screenshot
        
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
