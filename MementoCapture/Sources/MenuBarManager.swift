import SwiftUI
import AppKit
import SQLite3
import UserNotifications

/// Menu bar icon manager for Memento Capture
@MainActor
class MenuBarManager {
    private var statusItem: NSStatusItem?
    private var isCapturing = true
    private var isCaptureServiceRunning = false
    private var captureService: CaptureService?
    private var controlCenterView: ControlCenterMenuView?
    private var hasScreenPermission = ScreenshotCapture.hasPermission()
    private var permissionMonitorTimer: Timer?
    private var statusRefreshTimer: Timer?
    private var updateTimer: Timer?
    private var isCheckingUpdates = false
    private var isInstallingUpdate = false
    private var availableReleaseVersion: String?
    private var availableReleaseURL: URL?
    private var availableReleaseDownloadURL: URL?

    private let updateMenuTag = 103
    private let permissionCheckInterval: TimeInterval = 5
    private let statusRefreshInterval: TimeInterval = 1
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
        syncCaptureServiceState()
        startPermissionMonitoring()
        startStatusRefresh()
        startUpdateChecks()
    }
    
    private func setupMenu() {
        let menu = NSMenu()

        // Control Center mini panel
        let controlCenterItem = NSMenuItem()
        let controlCenterView = ControlCenterMenuView()
        controlCenterView.onRecordingTap = { [weak self] in
            self?.setCaptureEnabledFromControlCenter(true)
        }
        controlCenterView.onPausedTap = { [weak self] in
            self?.setCaptureEnabledFromControlCenter(false)
        }
        controlCenterView.onPermissionTap = { [weak self] in
            self?.checkPermission()
        }
        controlCenterView.onLastCaptureTap = { [weak self] in
            self?.openTimeline()
        }
        controlCenterItem.view = controlCenterView
        menu.addItem(controlCenterItem)
        self.controlCenterView = controlCenterView

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
        updateControlCenter()
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
            menu.item(withTag: 101)?.title = isCapturing ? L.pauseRecording : L.resumeRecording
        }
        updateControlCenter()
    }
    
    @objc private func toggleCapture() {
        isCapturing.toggle()
        syncCaptureServiceState()
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
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let htmlURL: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
            case assets
        }
    }

    @objc private func handleUpdateMenuAction() {
        if isInstallingUpdate {
            return
        }

        if let version = availableReleaseVersion,
           isRemoteVersionNewer(version, than: currentVersionString()),
           let releaseURL = availableReleaseURL {
            showUpdateAvailableAlert(
                localVersion: currentVersionString(),
                remoteVersion: version,
                releaseURL: releaseURL,
                downloadURL: availableReleaseDownloadURL
            )
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

    private func startStatusRefresh() {
        statusRefreshTimer?.invalidate()
        statusRefreshTimer = Timer.scheduledTimer(withTimeInterval: statusRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateControlCenter()
            }
        }
        if let statusRefreshTimer {
            RunLoop.main.add(statusRefreshTimer, forMode: .common)
        }
    }

    private func refreshPermissionState(forceIconUpdate: Bool = false) {
        let latestPermission = ScreenshotCapture.hasPermission()
        let changed = latestPermission != hasScreenPermission
        hasScreenPermission = latestPermission
        syncCaptureServiceState()
        updatePermissionMenuItem()
        if changed || forceIconUpdate {
            updateIcon()
        }
    }

    private func syncCaptureServiceState() {
        let shouldRun = isCapturing && hasScreenPermission
        setCaptureServiceRunning(shouldRun)
    }

    private func setCaptureServiceRunning(_ shouldRun: Bool) {
        guard shouldRun != isCaptureServiceRunning else { return }
        if shouldRun {
            captureService?.start()
        } else {
            captureService?.stop()
        }
        isCaptureServiceRunning = shouldRun
        updateControlCenter()
    }

    private func setCaptureEnabledFromControlCenter(_ enabled: Bool) {
        isCapturing = enabled
        syncCaptureServiceState()
        updateIcon()
        updateControlCenter()
        statusItem?.menu?.cancelTracking()
    }

    private func updateControlCenter() {
        guard let controlCenterView else { return }

        let state = ControlCenterState(
            isRecording: isCaptureServiceRunning,
            hasPermission: hasScreenPermission,
            lastCapture: captureService?.lastSuccessfulCaptureAt,
            lastCaptureText: lastCaptureChipText()
        )
        controlCenterView.render(state: state)
    }

    private func lastCaptureChipText() -> String {
        guard let date = captureService?.lastSuccessfulCaptureAt else {
            return L.chipLastCaptureNoneShort
        }

        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 {
            return L.chipLastCaptureNowShort
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return L.chipLastCaptureMinutesShort(minutes)
        }
        let hours = minutes / 60
        if hours < 24 {
            return L.chipLastCaptureHoursShort(hours)
        }
        let days = hours / 24
        return L.chipLastCaptureDaysShort(days)
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
            availableReleaseDownloadURL = nil
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
            availableReleaseDownloadURL = preferredDMGDownloadURL(from: release.assets, remoteVersion: remoteVersion)
            refreshUpdateMenuItem()

            if silent {
                maybeNotifyForUpdate(version: remoteVersion)
            } else if let releaseURL = availableReleaseURL {
                showUpdateAvailableAlert(
                    localVersion: localVersion,
                    remoteVersion: remoteVersion,
                    releaseURL: releaseURL,
                    downloadURL: availableReleaseDownloadURL
                )
            }
            return
        }

        availableReleaseVersion = nil
        availableReleaseURL = nil
        availableReleaseDownloadURL = nil
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

        if isInstallingUpdate {
            item.title = L.installingUpdate
            item.isEnabled = false
            return
        }

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

    private func preferredDMGDownloadURL(from assets: [GitHubRelease.Asset], remoteVersion: String) -> URL? {
        let dmgAssets = assets.filter { $0.name.lowercased().hasSuffix(".dmg") }
        guard !dmgAssets.isEmpty else { return nil }

        var normalizedVersion = remoteVersion.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedVersion.hasPrefix("v") {
            normalizedVersion.removeFirst()
        }

        if let exact = dmgAssets.first(where: { $0.name.lowercased().contains(normalizedVersion) }),
           let url = URL(string: exact.browserDownloadURL) {
            return url
        }
        if let preferred = dmgAssets.first(where: { $0.name.lowercased().contains("memento-native") }),
           let url = URL(string: preferred.browserDownloadURL) {
            return url
        }
        return URL(string: dmgAssets[0].browserDownloadURL)
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

    private func showUpdateAvailableAlert(localVersion: String, remoteVersion: String, releaseURL: URL, downloadURL: URL?) {
        let alert = NSAlert()
        alert.messageText = L.updateAvailableTitle
        alert.informativeText = L.updateAvailableMessage(localVersion, remoteVersion)
        alert.alertStyle = .informational
        if downloadURL != nil {
            alert.addButton(withTitle: L.installUpdateNow)
            alert.addButton(withTitle: L.openReleasePage)
            alert.addButton(withTitle: L.later)
        } else {
            alert.addButton(withTitle: L.openReleasePage)
            alert.addButton(withTitle: L.later)
        }

        let response = alert.runModal()

        if downloadURL != nil && response == .alertFirstButtonReturn, let downloadURL {
            Task { @MainActor in
                await self.installUpdate(remoteVersion: remoteVersion, downloadURL: downloadURL, releaseURL: releaseURL)
            }
            return
        }

        if (downloadURL == nil && response == .alertFirstButtonReturn) ||
            (downloadURL != nil && response == .alertSecondButtonReturn) {
            NSWorkspace.shared.open(releaseURL)
        }
    }

    private func installUpdate(remoteVersion: String, downloadURL: URL, releaseURL: URL) async {
        guard !isInstallingUpdate else { return }
        isInstallingUpdate = true
        refreshUpdateMenuItem()

        do {
            let dmgPath = try await downloadReleaseDMG(remoteVersion: remoteVersion, from: downloadURL)
            defer { try? FileManager.default.removeItem(at: dmgPath) }
            try runPrivilegedInstallScript(dmgPath: dmgPath.path)
            showUpdateInstalledAlert()
        } catch {
            showUpdateInstallFailedAlert(error: error, releaseURL: releaseURL)
        }

        isInstallingUpdate = false
        refreshUpdateMenuItem()
    }

    private func downloadReleaseDMG(remoteVersion: String, from downloadURL: URL) async throws -> URL {
        var request = URLRequest(url: downloadURL)
        request.timeoutInterval = 180
        request.setValue("MementoCapture", forHTTPHeaderField: "User-Agent")

        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "UpdateInstall", code: 10)
        }

        let fileManager = FileManager.default
        let tmpDirectory = fileManager.temporaryDirectory.appendingPathComponent("memento-update", isDirectory: true)
        try fileManager.createDirectory(at: tmpDirectory, withIntermediateDirectories: true)

        let cleanVersion = remoteVersion.replacingOccurrences(of: "/", with: "-")
        let destination = tmpDirectory.appendingPathComponent("Memento-Native-\(cleanVersion)-\(UUID().uuidString).dmg")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func runPrivilegedInstallScript(dmgPath: String) throws {
        let fileManager = FileManager.default
        let scriptURL = fileManager.temporaryDirectory.appendingPathComponent("memento-install-\(UUID().uuidString).sh")
        let script = """
        #!/bin/bash
        set -euo pipefail

        DMG_PATH=\(shellQuote(dmgPath))
        MOUNT_POINT=""

        /usr/sbin/spctl -a -vv --type open "$DMG_PATH" >/dev/null 2>&1

        cleanup() {
            if [ -n "${MOUNT_POINT:-}" ]; then
                /usr/bin/hdiutil detach "$MOUNT_POINT" -quiet || true
            fi
        }
        trap cleanup EXIT

        MOUNT_POINT=$(/usr/bin/hdiutil attach -nobrowse -readonly "$DMG_PATH" | /usr/bin/awk '/\\/Volumes\\// {print substr($0, index($0, "/Volumes/")); exit}')
        if [ -z "$MOUNT_POINT" ]; then
            echo "Failed to mount DMG"
            exit 1
        fi

        /usr/sbin/spctl -a -vv --type execute "$MOUNT_POINT/Memento Capture.app" >/dev/null 2>&1
        /usr/sbin/spctl -a -vv --type execute "$MOUNT_POINT/Memento Timeline.app" >/dev/null 2>&1

        /usr/bin/ditto "$MOUNT_POINT/Memento Capture.app" "/Applications/Memento Capture.app"
        /usr/bin/ditto "$MOUNT_POINT/Memento Timeline.app" "/Applications/Memento Timeline.app"
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        defer { try? fileManager.removeItem(at: scriptURL) }

        let command = "/bin/bash \(shellQuote(scriptURL.path))"
        let appleScriptCommand = "do shell script \"\(escapeForAppleScript(command))\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScriptCommand]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "UpdateInstall",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message?.isEmpty == false ? message! : "Installer failed"]
            )
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func escapeForAppleScript(_ command: String) -> String {
        command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func showUpdateInstalledAlert() {
        let alert = NSAlert()
        alert.messageText = L.updateInstallCompleteTitle
        alert.informativeText = L.updateInstallCompleteMessage
        alert.alertStyle = .informational
        alert.addButton(withTitle: L.restartNow)
        alert.addButton(withTitle: L.later)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            relaunchAfterUpdateInstall()
        }
    }

    private func relaunchAfterUpdateInstall() {
        let relaunchScriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("memento-relaunch-\(UUID().uuidString).sh")
        let script = """
        #!/bin/bash
        /bin/sleep 1
        /usr/bin/open "/Applications/Memento Capture.app"
        """
        try? script.write(to: relaunchScriptURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: relaunchScriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [relaunchScriptURL.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    private func showUpdateInstallFailedAlert(error: Error, releaseURL: URL) {
        let alert = NSAlert()
        alert.messageText = L.updateInstallFailedTitle
        alert.informativeText = L.updateInstallFailedMessage + "\n\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.openReleasePage)
        alert.addButton(withTitle: L.ok)

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
        PermissionGuideController.shared.show(reason: .manual)
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
        statusRefreshTimer?.invalidate()
        statusRefreshTimer = nil
        updateTimer?.invalidate()
        updateTimer = nil
        setCaptureServiceRunning(false)
        NSApp.terminate(nil)
    }
}

private struct ControlCenterState {
    let isRecording: Bool
    let hasPermission: Bool
    let lastCapture: Date?
    let lastCaptureText: String
}

private final class ControlCenterMenuView: NSView {
    var onRecordingTap: (() -> Void)?
    var onPausedTap: (() -> Void)?
    var onPermissionTap: (() -> Void)?
    var onLastCaptureTap: (() -> Void)?

    private let modeControl = NSSegmentedControl(
        labels: [L.chipRecordingTiny, L.chipPausedTiny],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let permissionChip = NSButton(title: L.chipPermissionMissingShort, target: nil, action: nil)
    private let lastCaptureChip = NSButton(title: L.chipLastCaptureNoneShort, target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 44))
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    func render(state: ControlCenterState) {
        modeControl.isEnabled = state.hasPermission
        modeControl.selectedSegment = state.hasPermission ? (state.isRecording ? 0 : 1) : -1
        modeControl.alphaValue = state.hasPermission ? 1.0 : 0.65

        permissionChip.title = state.hasPermission ? L.chipPermissionOkTiny : L.chipPermissionMissingShort
        lastCaptureChip.title = state.lastCaptureText

        permissionChip.image = icon(named: state.hasPermission ? "checkmark.shield" : "exclamationmark.shield")
        styleStatusChip(permissionChip, active: !state.hasPermission, tint: .systemOrange)

        lastCaptureChip.image = icon(named: "clock")
        styleStatusChip(lastCaptureChip, active: state.lastCapture != nil, tint: .systemBlue)
    }

    private func setupView() {
        modeControl.segmentStyle = .rounded
        modeControl.controlSize = .small
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        modeControl.setWidth(52, forSegment: 0)
        modeControl.setWidth(52, forSegment: 1)
        modeControl.target = self
        modeControl.action = #selector(handleModeChanged)
        modeControl.toolTip = L.chipRecording + " / " + L.chipPaused
        modeControl.heightAnchor.constraint(equalToConstant: 24).isActive = true
        modeControl.widthAnchor.constraint(equalToConstant: 108).isActive = true

        let chips = [permissionChip, lastCaptureChip]
        chips.forEach { chip in
            chip.setButtonType(.momentaryPushIn)
            chip.bezelStyle = .inline
            chip.isBordered = false
            chip.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
            chip.focusRingType = .none
            chip.wantsLayer = true
            chip.layer?.cornerRadius = 7
            chip.layer?.masksToBounds = true
            chip.imagePosition = .imageLeading
            chip.imageHugsTitle = true
            chip.contentTintColor = .secondaryLabelColor
            chip.translatesAutoresizingMaskIntoConstraints = false
            chip.heightAnchor.constraint(equalToConstant: 24).isActive = true
            chip.cell?.lineBreakMode = .byTruncatingTail
            chip.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        permissionChip.widthAnchor.constraint(equalToConstant: 88).isActive = true
        lastCaptureChip.widthAnchor.constraint(equalToConstant: 74).isActive = true

        permissionChip.target = self
        permissionChip.action = #selector(handlePermissionTap)
        lastCaptureChip.target = self
        lastCaptureChip.action = #selector(handleLastCaptureTap)

        let mainStack = NSStackView(views: [modeControl, permissionChip, lastCaptureChip])
        mainStack.orientation = .horizontal
        mainStack.alignment = .centerY
        mainStack.spacing = 6
        mainStack.distribution = .fill
        mainStack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        render(
            state: ControlCenterState(
                isRecording: false,
                hasPermission: false,
                lastCapture: nil,
                lastCaptureText: L.chipLastCaptureNoneShort
            )
        )
    }

    private func styleStatusChip(_ chip: NSButton, active: Bool, tint: NSColor) {
        chip.layer?.backgroundColor = (active ? tint.withAlphaComponent(0.15) : NSColor.clear).cgColor
        chip.layer?.borderWidth = 1
        chip.layer?.borderColor = (active ? tint.withAlphaComponent(0.45) : NSColor.separatorColor.withAlphaComponent(0.45)).cgColor
        chip.contentTintColor = active ? .labelColor : .secondaryLabelColor
    }

    private func icon(named symbolName: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    @objc private func handleModeChanged() {
        switch modeControl.selectedSegment {
        case 0:
            onRecordingTap?()
        case 1:
            onPausedTap?()
        default:
            break
        }
    }

    @objc private func handlePermissionTap() {
        onPermissionTap?()
    }

    @objc private func handleLastCaptureTap() {
        onLastCaptureTap?()
    }
}
