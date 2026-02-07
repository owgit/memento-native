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

        let isSwedish = Locale.current.language.languageCode?.identifier == "sv"
        let hasPermission = CGPreflightScreenCaptureAccess()
        
        // First launch should open the guide directly so permissions are handled in one place.
        if isFirstLaunch {
            PermissionGuideController.shared.show()
            return
        }

        // If permission is missing on any later launch, only show the guide (avoid double popups).
        if !hasPermission {
            PermissionGuideController.shared.show()
            return
        }

        guard isUpdate, let previousVersion else { return }

        let alert = NSAlert()
        if isSwedish {
            alert.messageText = "Memento uppdaterad till \(shortVersion)"
            alert.informativeText = hasPermission
                ? "Version \(previousVersion) → \(currentVersion).\nOm inspelning slutar fungera: öppna guiden och kör \"Fixa efter uppdatering\"."
                : "Version \(previousVersion) → \(currentVersion).\nmacOS kan kräva att skärminspelningsbehörigheten återställs efter uppdatering."
            alert.addButton(withTitle: "Öppna uppdateringsguide")
            alert.addButton(withTitle: "Senare")
        } else {
            alert.messageText = "Memento updated to \(shortVersion)"
            alert.informativeText = hasPermission
                ? "Version \(previousVersion) → \(currentVersion).\nIf capture stops working, open the guide and run \"Fix after update\"."
                : "Version \(previousVersion) → \(currentVersion).\nmacOS may require re-authorizing Screen Recording after updates."
            alert.addButton(withTitle: "Open update guide")
            alert.addButton(withTitle: "Later")
        }

        if alert.runModal() == .alertFirstButtonReturn || !hasPermission {
            PermissionGuideController.shared.show()
        }
    }
}

// Create and run application
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // No dock icon
app.run()
