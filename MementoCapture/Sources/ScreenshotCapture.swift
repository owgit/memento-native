import Foundation
import CoreGraphics
import ScreenCaptureKit

/// Modern macOS screenshot capture using ScreenCaptureKit (macOS 14+)
@available(macOS 14.0, *)
@MainActor
final class ScreenshotCapture {
    
    private var hasWarnedAboutPermission = false
    private var hasLoggedDisplayInfo = false
    
    /// Check if screen recording permission is granted
    static func hasPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }
    
    /// Capture the entire screen using ScreenCaptureKit
    /// Returns nil silently if permission not granted (no dialog triggered)
    func capture() async -> CGImage? {
        // Check permission FIRST - don't trigger dialog automatically
        if !ScreenshotCapture.hasPermission() {
            if !hasWarnedAboutPermission {
                AppLog.warning("⚠️ Screen Recording permission not granted - capture disabled")
                AppLog.info("   Grant permission in: System Settings > Privacy & Security > Screen Recording")
                hasWarnedAboutPermission = true
            }
            return nil
        }
        
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            
            // Debug: log available displays once
            if !hasLoggedDisplayInfo {
                AppLog.info("📺 Available displays: \(content.displays.count)")
                for (i, display) in content.displays.enumerated() {
                    AppLog.info("   Display \(i): \(display.width)x\(display.height), ID: \(display.displayID)")
                }
                AppLog.info("🪟 Available windows: \(content.windows.count)")
                AppLog.info("📱 Available apps: \(content.applications.count)")
                hasLoggedDisplayInfo = true
            }
            
            // Find main display
            let mainDisplayID = CGMainDisplayID()
            let display = content.displays.first { $0.displayID == mainDisplayID } ?? content.displays.first
            
            guard let display = display else {
                AppLog.error("No display found")
                return nil
            }
            
            // Get all on-screen windows
            let onScreenWindows = content.windows.filter { window in
                window.isOnScreen && window.frame.width > 0 && window.frame.height > 0
            }
            
            // Create filter
            let filter = SCContentFilter(display: display, including: onScreenWindows)
            
            // Configure screenshot
            let config = SCStreamConfiguration()
            config.width = display.width * 2
            config.height = display.height * 2
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = false
            config.captureResolution = .best
            config.scalesToFit = false
            
            // Capture
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return image
            
        } catch {
            AppLog.error("Screenshot capture failed: \(error.localizedDescription)")
            return nil
        }
    }
    
}
