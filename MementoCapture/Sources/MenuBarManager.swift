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
        let statusMenuItem = NSMenuItem(title: "● Spelar in", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Toggle capture
        let toggleItem = NSMenuItem(title: "Pausa inspelning", action: #selector(toggleCapture), keyEquivalent: "p")
        toggleItem.target = self
        toggleItem.tag = 101
        menu.addItem(toggleItem)
        
        // Open Timeline
        let timelineItem = NSMenuItem(title: "Öppna Timeline", action: #selector(openTimeline), keyEquivalent: "t")
        timelineItem.target = self
        menu.addItem(timelineItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Stats
        let statsItem = NSMenuItem(title: "Statistik...", action: #selector(showStats), keyEquivalent: "s")
        statsItem.target = self
        menu.addItem(statsItem)
        
        // Clean up
        let cleanItem = NSMenuItem(title: "Rensa gamla frames...", action: #selector(cleanOldFrames), keyEquivalent: "")
        cleanItem.target = self
        menu.addItem(cleanItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Avsluta Memento", action: #selector(quitApp), keyEquivalent: "q")
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
            menu.item(withTag: 100)?.title = isCapturing ? "● Spelar in" : "○ Pausad"
            menu.item(withTag: 101)?.title = isCapturing ? "Pausa inspelning" : "Fortsätt inspelning"
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
        // Get stats from database
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dbPath = home.appendingPathComponent(".cache/memento/memento.db").path
        let cachePath = home.appendingPathComponent(".cache/memento")
        
        var frameCount = 0
        var embeddingCount = 0
        var diskUsage = "?"
        
        // Count frames and embeddings
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
        
        // Get disk usage
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
        
        // Show alert with stats
        let alert = NSAlert()
        alert.messageText = "Memento Statistik"
        alert.informativeText = """
        📊 Frames: \(frameCount)
        🧠 Embeddings: \(embeddingCount)
        💾 Disk: \(diskUsage)
        📁 Plats: ~/.cache/memento/
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Öppna mapp")
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(cachePath)
        }
    }
    
    @objc private func cleanOldFrames() {
        let alert = NSAlert()
        alert.messageText = "Rensa gamla frames"
        alert.informativeText = "Välj hur gamla frames du vill ta bort:"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Äldre än 7 dagar")
        alert.addButton(withTitle: "Äldre än 30 dagar")
        alert.addButton(withTitle: "Avbryt")
        
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
        
        // Calculate cutoff date
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysToKeep, to: Date())!
        let cutoffString = ISO8601DateFormatter().string(from: cutoffDate)
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dbPath = home.appendingPathComponent(".cache/memento/memento.db").path
        let cachePath = home.appendingPathComponent(".cache/memento")
        
        var deletedFrames = 0
        var deletedVideos = 0
        
        // Delete from database
        var db: OpaquePointer?
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            // Get frame IDs to delete
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
            
            // Delete embeddings
            sqlite3_exec(db, "DELETE FROM EMBEDDING WHERE frame_id IN (SELECT id FROM FRAME WHERE time < '\(cutoffString)')", nil, nil, nil)
            
            // Delete content
            sqlite3_exec(db, "DELETE FROM CONTENT WHERE frame_id IN (SELECT id FROM FRAME WHERE time < '\(cutoffString)')", nil, nil, nil)
            
            // Delete frames
            sqlite3_exec(db, "DELETE FROM FRAME WHERE time < '\(cutoffString)'", nil, nil, nil)
            
            deletedFrames = frameIds.count
            
            // Delete video files
            for frameId in frameIds {
                let videoPath = cachePath.appendingPathComponent("\(frameId).mp4")
                if FileManager.default.fileExists(atPath: videoPath.path) {
                    try? FileManager.default.removeItem(at: videoPath)
                    deletedVideos += 1
                }
            }
            
            // Vacuum database
            sqlite3_exec(db, "VACUUM", nil, nil, nil)
            sqlite3_close(db)
        }
        
        // Show result
        let resultAlert = NSAlert()
        resultAlert.messageText = "Rensning klar"
        resultAlert.informativeText = "Raderade \(deletedFrames) frames och \(deletedVideos) video-filer."
        resultAlert.alertStyle = .informational
        resultAlert.addButton(withTitle: "OK")
        resultAlert.runModal()
    }
    
    @objc private func quitApp() {
        captureService?.stop()
        NSApp.terminate(nil)
    }
}
