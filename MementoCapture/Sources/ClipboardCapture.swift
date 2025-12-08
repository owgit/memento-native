import Foundation
import AppKit

/// Captures clipboard content (can be disabled in settings)
class ClipboardCapture {
    
    static let shared = ClipboardCapture()
    
    private var lastChangeCount: Int = 0
    
    /// Enable/disable clipboard capture (controlled by Settings)
    var isEnabled: Bool = false
    
    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }
    
    /// Get clipboard content if it changed since last check
    /// Returns nil if disabled or unchanged
    func getNewClipboardContent() -> String? {
        guard isEnabled else { return nil }
        
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return nil }
        
        lastChangeCount = currentCount
        
        // Only capture text content
        guard let content = NSPasteboard.general.string(forType: .string) else { return nil }
        
        // Skip if too long (probably not useful text)
        guard content.count < 10000 else { return nil }
        
        // Skip if it looks like a file path or binary data
        if content.hasPrefix("/") && content.contains(".") && !content.contains(" ") {
            return nil
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
