import Foundation
import AppKit

/// App delegate for handling lifecycle
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?
    private let lastLaunchVersionKey = "lastLaunchVersion"
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.info("🚀 Memento Capture Service starting...")

        // Initialize capture service (actual start is permission-gated in MenuBarManager)
        let service = CaptureService.shared
        
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
        let currentVersion = AppVersionInfo.displayVersion

        let defaults = UserDefaults.standard
        let previousVersion = defaults.string(forKey: lastLaunchVersionKey)
        let isFirstLaunch = previousVersion == nil
        let isUpdate = previousVersion != nil && previousVersion != currentVersion
        defaults.set(currentVersion, forKey: lastLaunchVersionKey)

        if isFirstLaunch {
            PermissionGuideController.shared.show(reason: .firstLaunch)
            return
        }

        Task { @MainActor in
            let hasPermission = await ScreenshotCapture.verifyPermission()

            if !hasPermission {
                PermissionGuideController.shared.show(reason: .permissionMissing)
                return
            }

            if isUpdate, let previousVersion {
                PermissionGuideController.shared.show(
                    reason: .updated(previous: previousVersion, current: currentVersion)
                )
                return
            }

            if LegacyTimelineMigration.shouldPrompt {
                LegacyTimelineMigration.showPromptIfNeeded()
            }
        }
    }
}

// Create and run application
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // No dock icon
app.run()
