import Foundation
import AppKit
import SwiftUI

/// App delegate for handling lifecycle
class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?
    private let lastLaunchVersionKey = "lastLaunchVersion"
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 Memento Capture Service starting...")

        // Start capture service
        let service = CaptureService.shared
        service.start()
        
        // Setup menu bar icon
        menuBarManager = MenuBarManager()
        menuBarManager?.setup(captureService: service)

        Task { @MainActor in
            self.showStartupGuideIfNeeded()
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Keep running in background
    }

    @MainActor
    private func showStartupGuideIfNeeded() {
        guard let info = Bundle.main.infoDictionary else { return }
        let shortVersion = info["CFBundleShortVersionString"] as? String ?? "?"
        let buildVersion = info["CFBundleVersion"] as? String ?? "?"
        let currentVersion = "\(shortVersion) (\(buildVersion))"

        let defaults = UserDefaults.standard
        let previousVersion = defaults.string(forKey: lastLaunchVersionKey)
        let isFirstLaunch = previousVersion == nil
        let isUpdate = previousVersion != nil && previousVersion != currentVersion
        defaults.set(currentVersion, forKey: lastLaunchVersionKey)

        let hasPermission = CGPreflightScreenCaptureAccess()
        
        // Unified setup hub handles first launch, updates, and permission recovery.
        if isFirstLaunch {
            PermissionGuideController.shared.show(reason: .firstLaunch)
            return
        }

        if !hasPermission {
            PermissionGuideController.shared.show(reason: .permissionMissing)
            return
        }

        if isUpdate, let previousVersion {
            PermissionGuideController.shared.show(
                reason: .updated(previous: previousVersion, current: currentVersion)
            )
        }
    }
}

// Create and run application
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // No dock icon
app.run()
