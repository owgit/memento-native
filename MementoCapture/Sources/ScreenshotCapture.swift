import Foundation
import CoreGraphics
import AppKit
import ScreenCaptureKit

/// Modern macOS screenshot capture using ScreenCaptureKit (macOS 14+)
@available(macOS 14.0, *)
class ScreenshotCapture {
    
    private var hasWarnedAboutPermission = false
    private var hasLoggedDisplayInfo = false
    
    /// Check if screen recording permission is granted
    static func hasPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }
    
    /// Request screen recording permission
    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }
    
    /// Open System Preferences to Screen Recording settings
    static func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Capture the entire screen using ScreenCaptureKit
    /// Returns nil silently if permission not granted (no dialog triggered)
    func capture() async -> CGImage? {
        // Check permission FIRST - don't trigger dialog automatically
        if !ScreenshotCapture.hasPermission() {
            if !hasWarnedAboutPermission {
                print("⚠️ Screen Recording permission not granted - capture disabled")
                print("   Grant permission in: System Settings > Privacy & Security > Screen Recording")
                hasWarnedAboutPermission = true
            }
            return nil
        }
        
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            
            // Debug: log available displays once
            if !hasLoggedDisplayInfo {
                print("📺 Available displays: \(content.displays.count)")
                for (i, display) in content.displays.enumerated() {
                    print("   Display \(i): \(display.width)x\(display.height), ID: \(display.displayID)")
                }
                print("🪟 Available windows: \(content.windows.count)")
                print("📱 Available apps: \(content.applications.count)")
                hasLoggedDisplayInfo = true
            }
            
            // Find main display
            let mainDisplayID = CGMainDisplayID()
            let display = content.displays.first { $0.displayID == mainDisplayID } ?? content.displays.first
            
            guard let display = display else {
                print("ERROR: No display found")
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
            print("ERROR: Screenshot capture failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Capture at specific resolution
    func capture(maxWidth: Int, maxHeight: Int) async -> CGImage? {
        guard let fullImage = await capture() else { return nil }
        
        // Check if resize needed
        if fullImage.width <= maxWidth && fullImage.height <= maxHeight {
            return fullImage
        }
        
        // Calculate scale
        let scaleX = Double(maxWidth) / Double(fullImage.width)
        let scaleY = Double(maxHeight) / Double(fullImage.height)
        let scale = min(scaleX, scaleY)
        
        let newWidth = Int(Double(fullImage.width) * scale)
        let newHeight = Int(Double(fullImage.height) * scale)
        
        // Create resized image
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return fullImage
        }
        
        context.interpolationQuality = .high
        context.draw(fullImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        
        return context.makeImage()
    }
}
