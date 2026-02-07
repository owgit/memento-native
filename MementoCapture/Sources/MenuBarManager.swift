import SwiftUI
import AppKit
import SQLite3

/// Menu bar icon manager for Memento Capture
@MainActor
class MenuBarManager {
    private var statusItem: NSStatusItem?
    private var isCapturing = true
    private var captureService: CaptureService?
    
    init() {}
    
    func setup(captureService: CaptureService) {
        self.captureService = captureService
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Memento")
            button.image?.isTemplate = true
            updateIcon()
        }
        
        setupMenu()
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        // Status
        let statusMenuItem = NSMenuItem(title: L.recording, action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Toggle capture
        let toggleItem = NSMenuItem(title: L.pauseRecording, action: #selector(toggleCapture), keyEquivalent: "p")
        toggleItem.target = self
        toggleItem.tag = 101
        menu.addItem(toggleItem)
        
        // Open Timeline
        let timelineItem = NSMenuItem(title: L.openTimeline, action: #selector(openTimeline), keyEquivalent: "t")
        timelineItem.target = self
        menu.addItem(timelineItem)
        
        // Settings
        let settingsItem = NSMenuItem(title: L.settingsMenu, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Permission status
        let permissionItem = NSMenuItem(title: L.permissions, action: #selector(checkPermission), keyEquivalent: "")
        permissionItem.target = self
        permissionItem.tag = 102
        menu.addItem(permissionItem)
        updatePermissionMenuItem()
        
        // Debug screenshot
        let debugItem = NSMenuItem(title: L.saveDebugScreenshot, action: #selector(saveDebugScreenshot), keyEquivalent: "d")
        debugItem.target = self
        menu.addItem(debugItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Stats
        let statsItem = NSMenuItem(title: L.statistics, action: #selector(showStats), keyEquivalent: "s")
        statsItem.target = self
        menu.addItem(statsItem)
        
        // Clean up
        let cleanItem = NSMenuItem(title: L.cleanOldFrames, action: #selector(cleanOldFrames), keyEquivalent: "")
        cleanItem.target = self
        menu.addItem(cleanItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Buy me a coffee
        let coffeeItem = NSMenuItem(title: "☕️ " + L.buyMeACoffee, action: #selector(openBuyMeACoffee), keyEquivalent: "")
        coffeeItem.target = self
        menu.addItem(coffeeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: L.quitMemento, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        // Version (at the bottom, disabled)
        menu.addItem(NSMenuItem.separator())
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "v\(version) (\(build))", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        
        statusItem?.menu = menu
    }
    
    private func updateIcon() {
        if let button = statusItem?.button {
            if isCapturing {
                button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Recording")
            } else {
                button.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Paused")
            }
            button.image?.isTemplate = true
        }
        
        // Update menu items
        if let menu = statusItem?.menu {
            menu.item(withTag: 100)?.title = isCapturing ? L.recording : L.paused
            menu.item(withTag: 101)?.title = isCapturing ? L.pauseRecording : L.resumeRecording
        }
    }
    
    @objc private func toggleCapture() {
        isCapturing.toggle()
        if isCapturing {
            captureService?.start()
        } else {
            captureService?.stop()
        }
        updateIcon()
    }
    
    @objc private func openTimeline() {
        // Try /Applications first, then ~/Applications
        let paths = [
            "/Applications/Memento Timeline.app",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Memento Timeline.app").path
        ]
        for path in paths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.open(url)
                return
            }
        }
        print("⚠️ Memento Timeline not found")
    }
    
    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }
    
    @objc private func showStats() {
        let cachePath = Settings.shared.storageURL
        let dbPath = cachePath.appendingPathComponent("memento.db").path
        let displayPath = (cachePath.path as NSString).abbreviatingWithTildeInPath
        
        var frameCount = 0
        var embeddingCount = 0
        var diskUsage = "?"
        
        var db: OpaquePointer?
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM FRAME", -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    frameCount = Int(sqlite3_column_int(stmt, 0))
                }
                sqlite3_finalize(stmt)
            }
            if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM EMBEDDING", -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    embeddingCount = Int(sqlite3_column_int(stmt, 0))
                }
                sqlite3_finalize(stmt)
            }
            sqlite3_close(db)
        }
        
        if let enumerator = FileManager.default.enumerator(at: cachePath, includingPropertiesForKeys: [.fileSizeKey]) {
            var totalSize: Int64 = 0
            while let url = enumerator.nextObject() as? URL {
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
            if totalSize > 1_000_000_000 {
                diskUsage = String(format: "%.1f GB", Double(totalSize) / 1_000_000_000)
            } else {
                diskUsage = String(format: "%.0f MB", Double(totalSize) / 1_000_000)
            }
        }
        
        let alert = NSAlert()
        alert.messageText = L.statisticsTitle
        alert.informativeText = """
        📊 \(L.frames): \(frameCount)
        🧠 \(L.embeddings): \(embeddingCount)
        💾 \(L.disk): \(diskUsage)
        📁 \(L.location): \(displayPath)/
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: L.ok)
        alert.addButton(withTitle: L.openFolder)
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(cachePath)
        }
    }
    
    @objc private func cleanOldFrames() {
        let alert = NSAlert()
        alert.messageText = L.cleanTitle
        alert.informativeText = L.cleanMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.olderThan7Days)
        alert.addButton(withTitle: L.olderThan30Days)
        alert.addButton(withTitle: L.deleteAll)
        alert.addButton(withTitle: L.cancel)
        
        let response = alert.runModal()
        
        var deleteAll = false
        var daysToKeep = 0
        switch response {
        case .alertFirstButtonReturn:
            daysToKeep = 7
        case .alertSecondButtonReturn:
            daysToKeep = 30
        case .alertThirdButtonReturn:
            deleteAll = true
        default:
            return
        }

        let cachePath = Settings.shared.storageURL
        let dbPath = cachePath.appendingPathComponent("memento.db").path
        let cutoffString = deleteAll
            ? nil
            : ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: -daysToKeep, to: Date())!)

        let result = StorageCleaner.cleanup(
            dbPath: dbPath,
            cachePath: cachePath,
            cutoffISO8601: cutoffString,
            deleteAll: deleteAll,
            framesPerVideo: 5
        )

        print("🗑️ Cleanup: \(result.deletedFrames) frames, \(result.deletedVideos) videos deleted")
        
        let resultAlert = NSAlert()
        resultAlert.messageText = L.cleanDone
        resultAlert.informativeText = L.cleanResult(result.deletedFrames, result.deletedVideos)
        resultAlert.alertStyle = .informational
        resultAlert.addButton(withTitle: L.ok)
        resultAlert.runModal()
    }
    
    @objc private func saveDebugScreenshot() {
        Task {
            let capture = ScreenshotCapture()
            guard let image = await capture.capture() else {
                let alert = NSAlert()
                alert.messageText = L.errorTitle
                alert.informativeText = L.screenshotError
                alert.runModal()
                return
            }
            
            let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            let path = desktop.appendingPathComponent("memento-debug-\(Int(Date().timeIntervalSince1970)).png")
            
            let bitmap = NSBitmapImageRep(cgImage: image)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try? data.write(to: path)
                
                let alert = NSAlert()
                alert.messageText = L.debugScreenshotSaved
                alert.informativeText = L.screenshotSavedMessage(path.lastPathComponent, image.width, image.height)
                alert.addButton(withTitle: L.open)
                alert.addButton(withTitle: L.ok)
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(path)
                }
            }
        }
    }
    
    @objc private func checkPermission() {
        PermissionGuideController.shared.show()
        updatePermissionMenuItem()
    }
    
    private func updatePermissionMenuItem() {
        if let menu = statusItem?.menu, let item = menu.item(withTag: 102) {
            let hasPermission = ScreenshotCapture.hasPermission()
            item.title = hasPermission ? L.permissionsOk : L.permissionsMissing
        }
    }
    
    @objc private func openBuyMeACoffee() {
        if let url = URL(string: "https://buymeacoffee.com/uygarduzgun") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func quitApp() {
        captureService?.stop()
        NSApp.terminate(nil)
    }
}
