import Foundation
import CoreGraphics
import AppKit

/// Native macOS screenshot capture using CGWindowListCreateImage
class ScreenshotCapture {
    
    /// Capture the entire screen
    func capture() -> CGImage? {
        let image = CGWindowListCreateImage(
            CGRect.infinite,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        )
        return image
    }
    
    /// Capture at specific resolution
    func capture(maxWidth: Int, maxHeight: Int) -> CGImage? {
        guard let fullImage = capture() else { return nil }
        
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
