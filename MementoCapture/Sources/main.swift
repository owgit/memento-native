import Foundation
import AppKit
import SwiftUI

/// App delegate for handling lifecycle
class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboarding: OnboardingWindow?
    private var menuBarManager: MenuBarManager?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 Memento Capture Service starting...")
        
        // Show onboarding on first launch
        onboarding = OnboardingWindow()
        onboarding?.showIfNeeded()
        
        // Start capture service
        let service = CaptureService.shared
        service.start()
        
        // Setup menu bar icon
        menuBarManager = MenuBarManager()
        menuBarManager?.setup(captureService: service)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Keep running in background
    }
}

// Create and run application
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // No dock icon
app.run()
