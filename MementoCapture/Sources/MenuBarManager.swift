import SwiftUI
import AppKit
import SQLite3
import UserNotifications

/// Menu bar icon manager for Memento Capture
@MainActor
class MenuBarManager {
    private var statusItem: NSStatusItem?
    private var isCapturing = true
    private var captureService: CaptureService?
    private var hasScreenPermission = ScreenshotCapture.hasPermission()
    private var permissionMonitorTimer: Timer?
    private var updateTimer: Timer?
    private var isCheckingUpdates = false
    private var availableReleaseVersion: String?
    private var availableReleaseURL: URL?

    private let updateMenuTag = 103
    private let permissionCheckInterval: TimeInterval = 5
    private let updateCheckInterval: TimeInterval = 6 * 60 * 60
    private let updateAPIURL = URL(string: "https://api.github.com/repos/owgit/memento-native/releases/latest")!
    private let fallbackReleaseURL = URL(string: "https://github.com/owgit/memento-native/releases/latest")!
    private let lastNotifiedUpdateVersionKey = "lastNotifiedUpdateVersion"
    
    init() {}
    
    func setup(captureService: CaptureService) {
        self.captureService = captureService
        hasScreenPermission = ScreenshotCapture.hasPermission()
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Memento")
            button.image?.isTemplate = true
            updateIcon()
        }
        
        setupMenu()
        refreshPermissionState(forceIconUpdate: true)
        startPermissionMonitoring()
        startUpdateChecks()
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

        // Update check
        let updateItem = NSMenuItem(title: L.checkForUpdates, action: #selector(handleUpdateMenuAction), keyEquivalent: "")
        updateItem.target = self
        updateItem.tag = updateMenuTag
        menu.addItem(updateItem)
        
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
            if !hasScreenPermission {
                button.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "Permission required")
                button.toolTip = L.permissionMissingStatus
            } else if isCapturing {
                button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Recording")
                button.toolTip = nil
            } else {
                button.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Paused")
                button.toolTip = nil
            }
            button.image?.isTemplate = true
        }
        
        // Update menu items
        if let menu = statusItem?.menu {
            menu.item(withTag: 100)?.title = hasScreenPermission ? (isCapturing ? L.recording : L.paused) : L.permissionMissingStatus
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

    // MARK: - Updates

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: String
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
        }
    }

    @objc private func handleUpdateMenuAction() {
        if let version = availableReleaseVersion,
           isRemoteVersionNewer(version, than: currentVersionString()),
           let releaseURL = availableReleaseURL {
            NSWorkspace.shared.open(releaseURL)
            return
        }

        checkForUpdates(silent: false)
    }

    private func startUpdateChecks() {
        refreshUpdateMenuItem()
        checkForUpdates(silent: true)

        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForUpdates(silent: true)
            }
        }
        if let updateTimer {
            RunLoop.main.add(updateTimer, forMode: .common)
        }
    }

    private func startPermissionMonitoring() {
        permissionMonitorTimer?.invalidate()
        permissionMonitorTimer = Timer.scheduledTimer(withTimeInterval: permissionCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissionState()
            }
        }
        if let permissionMonitorTimer {
            RunLoop.main.add(permissionMonitorTimer, forMode: .common)
        }
    }

    private func refreshPermissionState(forceIconUpdate: Bool = false) {
        let latestPermission = ScreenshotCapture.hasPermission()
        let changed = latestPermission != hasScreenPermission
        hasScreenPermission = latestPermission
        updatePermissionMenuItem()
        if changed || forceIconUpdate {
            updateIcon()
        }
    }

    private func checkForUpdates(silent: Bool) {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        refreshUpdateMenuItem()

        Task {
            do {
                let release = try await fetchLatestRelease()
                handleUpdateSuccess(release, silent: silent)
            } catch {
                handleUpdateFailure(error, silent: silent)
            }
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: updateAPIURL)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MementoCapture", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "UpdateCheck", code: 1)
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func handleUpdateSuccess(_ release: GitHubRelease, silent: Bool) {
        isCheckingUpdates = false

        // Ignore pre-release/draft for end users.
        guard !release.draft, !release.prerelease else {
            availableReleaseVersion = nil
            availableReleaseURL = nil
            refreshUpdateMenuItem()
            if !silent {
                showUpToDateAlert(localVersion: currentVersionString())
            }
            return
        }

        let remoteVersion = release.tagName
        let localVersion = currentVersionString()

        if isRemoteVersionNewer(remoteVersion, than: localVersion) {
            availableReleaseVersion = remoteVersion
            availableReleaseURL = URL(string: release.htmlURL) ?? fallbackReleaseURL
            refreshUpdateMenuItem()

            if silent {
                maybeNotifyForUpdate(version: remoteVersion)
            } else if let releaseURL = availableReleaseURL {
                showUpdateAvailableAlert(localVersion: localVersion, remoteVersion: remoteVersion, releaseURL: releaseURL)
            }
            return
        }

        availableReleaseVersion = nil
        availableReleaseURL = nil
        refreshUpdateMenuItem()

        if !silent {
            showUpToDateAlert(localVersion: localVersion)
        }
    }

    private func handleUpdateFailure(_ error: Error, silent: Bool) {
        isCheckingUpdates = false
        refreshUpdateMenuItem()

        if !silent {
            let alert = NSAlert()
            alert.messageText = L.updateCheckFailedTitle
            alert.informativeText = L.updateCheckFailedMessage + "\n\n\(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: L.ok)
            alert.runModal()
        }
    }

    private func refreshUpdateMenuItem() {
        guard let menu = statusItem?.menu,
              let item = menu.item(withTag: updateMenuTag) else { return }

        if isCheckingUpdates {
            item.title = L.checkingForUpdates
            item.isEnabled = false
            return
        }

        if let version = availableReleaseVersion,
           isRemoteVersionNewer(version, than: currentVersionString()) {
            item.title = L.updateAvailableMenu(version)
            item.isEnabled = true
            return
        }

        item.title = L.checkForUpdates
        item.isEnabled = true
    }

    private func currentVersionString() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private func isRemoteVersionNewer(_ remote: String, than local: String) -> Bool {
        guard let remoteComponents = parseVersionComponents(remote),
              let localComponents = parseVersionComponents(local) else {
            return false
        }

        let maxCount = max(remoteComponents.count, localComponents.count)
        for index in 0..<maxCount {
            let remotePart = index < remoteComponents.count ? remoteComponents[index] : 0
            let localPart = index < localComponents.count ? localComponents[index] : 0
            if remotePart != localPart {
                return remotePart > localPart
            }
        }
        return false
    }

    private func parseVersionComponents(_ version: String) -> [Int]? {
        var cleaned = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("v") {
            cleaned.removeFirst()
        }
        if let suffixIndex = cleaned.firstIndex(of: "-") {
            cleaned = String(cleaned[..<suffixIndex])
        }

        let parts = cleaned.split(separator: ".")
        guard !parts.isEmpty else { return nil }

        var numbers: [Int] = []
        numbers.reserveCapacity(parts.count)
        for part in parts {
            let digits = part.prefix { $0.isNumber }
            guard !digits.isEmpty, let value = Int(digits) else { return nil }
            numbers.append(value)
        }
        return numbers
    }

    private func maybeNotifyForUpdate(version: String) {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: lastNotifiedUpdateVersionKey) == version {
            return
        }

        defaults.set(version, forKey: lastNotifiedUpdateVersionKey)
        postUpdateNotification(version: version)
    }

    private func postUpdateNotification(version: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized:
                Task { @MainActor in
                    self.enqueueUpdateNotification(version: version)
                }
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    Task { @MainActor in
                        self.enqueueUpdateNotification(version: version)
                    }
                }
            default:
                break
            }
        }
    }

    private func enqueueUpdateNotification(version: String) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = L.updateNotificationTitle
        content.body = L.updateNotificationBody(version)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "memento-update-\(version)",
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
    }

    private func showUpdateAvailableAlert(localVersion: String, remoteVersion: String, releaseURL: URL) {
        let alert = NSAlert()
        alert.messageText = L.updateAvailableTitle
        alert.informativeText = L.updateAvailableMessage(localVersion, remoteVersion)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L.openReleasePage)
        alert.addButton(withTitle: L.later)

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(releaseURL)
        }
    }

    private func showUpToDateAlert(localVersion: String) {
        let alert = NSAlert()
        alert.messageText = L.upToDateTitle
        alert.informativeText = L.upToDateMessage(localVersion)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L.ok)
        alert.runModal()
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
        refreshPermissionState(forceIconUpdate: true)
    }
    
    private func updatePermissionMenuItem() {
        if let menu = statusItem?.menu, let item = menu.item(withTag: 102) {
            item.title = hasScreenPermission ? L.permissionsOk : L.permissionsMissing
        }
    }
    
    @objc private func openBuyMeACoffee() {
        if let url = URL(string: "https://buymeacoffee.com/uygarduzgun") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func quitApp() {
        permissionMonitorTimer?.invalidate()
        permissionMonitorTimer = nil
        updateTimer?.invalidate()
        updateTimer = nil
        captureService?.stop()
        NSApp.terminate(nil)
    }
}
