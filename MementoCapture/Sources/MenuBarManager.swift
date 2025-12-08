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
        
        // Stats
        let statsItem = NSMenuItem(title: L.statistics, action: #selector(showStats), keyEquivalent: "s")
        statsItem.target = self
        menu.addItem(statsItem)
        
        // Clean up
        let cleanItem = NSMenuItem(title: L.cleanOldFrames, action: #selector(cleanOldFrames), keyEquivalent: "")
        cleanItem.target = self
        menu.addItem(cleanItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: L.quitMemento, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
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
        let timelineAppPath = "/Users/uygarduzgun/Sites/Memento/Memento Timeline Swift.app"
        NSWorkspace.shared.open(URL(fileURLWithPath: timelineAppPath))
    }
    
    @objc private func showStats() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dbPath = home.appendingPathComponent(".cache/memento/memento.db").path
        let cachePath = home.appendingPathComponent(".cache/memento")
        
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
        📁 \(L.location): ~/.cache/memento/
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
        alert.addButton(withTitle: L.cancel)
        
        let response = alert.runModal()
        
        var daysToKeep = 0
        switch response {
        case .alertFirstButtonReturn:
            daysToKeep = 7
        case .alertSecondButtonReturn:
            daysToKeep = 30
        default:
            return
        }
        
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysToKeep, to: Date())!
        let cutoffString = ISO8601DateFormatter().string(from: cutoffDate)
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dbPath = home.appendingPathComponent(".cache/memento/memento.db").path
        let cachePath = home.appendingPathComponent(".cache/memento")
        
        var deletedFrames = 0
        var deletedVideos = 0
        
        var db: OpaquePointer?
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            var frameIds: [Int] = []
            var stmt: OpaquePointer?
            let selectSQL = "SELECT id FROM FRAME WHERE time < ?"
            if sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, cutoffString, -1, nil)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    frameIds.append(Int(sqlite3_column_int(stmt, 0)))
                }
                sqlite3_finalize(stmt)
            }
            
            sqlite3_exec(db, "DELETE FROM EMBEDDING WHERE frame_id IN (SELECT id FROM FRAME WHERE time < '\(cutoffString)')", nil, nil, nil)
            sqlite3_exec(db, "DELETE FROM CONTENT WHERE frame_id IN (SELECT id FROM FRAME WHERE time < '\(cutoffString)')", nil, nil, nil)
            sqlite3_exec(db, "DELETE FROM FRAME WHERE time < '\(cutoffString)'", nil, nil, nil)
            
            deletedFrames = frameIds.count
            
            for frameId in frameIds {
                let videoPath = cachePath.appendingPathComponent("\(frameId).mp4")
                if FileManager.default.fileExists(atPath: videoPath.path) {
                    try? FileManager.default.removeItem(at: videoPath)
                    deletedVideos += 1
                }
            }
            
            sqlite3_exec(db, "VACUUM", nil, nil, nil)
            sqlite3_close(db)
        }
        
        let resultAlert = NSAlert()
        resultAlert.messageText = L.cleanDone
        resultAlert.informativeText = L.cleanResult(deletedFrames, deletedVideos)
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
        let hasPermission = ScreenshotCapture.hasPermission()
        
        if hasPermission {
            let alert = NSAlert()
            alert.messageText = L.permissionsOkTitle
            alert.informativeText = L.permissionsOkMessage
            alert.alertStyle = .informational
            alert.addButton(withTitle: L.ok)
            alert.runModal()
        } else {
            let alert = NSAlert()
            alert.messageText = L.permissionsMissingTitle
            alert.informativeText = L.permissionsMissingMessage
            alert.alertStyle = .warning
            alert.addButton(withTitle: L.openSettings)
            alert.addButton(withTitle: L.cancel)
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                ScreenshotCapture.openPermissionSettings()
            }
        }
        
        updatePermissionMenuItem()
    }
    
    private func updatePermissionMenuItem() {
        if let menu = statusItem?.menu, let item = menu.item(withTag: 102) {
            let hasPermission = ScreenshotCapture.hasPermission()
            item.title = hasPermission ? L.permissionsOk : L.permissionsMissing
        }
    }
    
    @objc private func quitApp() {
        captureService?.stop()
        NSApp.terminate(nil)
    }
}
