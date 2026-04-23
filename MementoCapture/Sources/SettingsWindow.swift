import SwiftUI
import AppKit

/// Settings window controller
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        let window = resolveWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func resolveWindow() -> NSWindow {
        if let window {
            return window
        }

        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = L.settings
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 450, height: 560)
        window.setContentSize(NSSize(width: 520, height: 680))
        window.setFrameAutosaveName("SettingsWindow")
        window.center()
        self.window = window
        return window
    }
}

// MARK: - SwiftUI View

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var newExcludedApp = ""
    @State private var isMigratingStorage = false
    @State private var hasLegacyTimelineApp = LegacyTimelineMigration.hasLegacyTimelineApp

    private var normalizedExcludedAppInput: String {
        newExcludedApp.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddExcludedApp: Bool {
        !normalizedExcludedAppInput.isEmpty &&
        !settings.excludedApps.contains { $0.compare(normalizedExcludedAppInput, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    var body: some View {
        ScrollView {
            Form {
                // Capture Section
                Section {
                    HStack {
                        Text(L.captureInterval)
                        Spacer()
                        Picker("", selection: $settings.captureInterval) {
                            Text("1s").tag(1.0)
                            Text("2s").tag(2.0)
                            Text("3s").tag(3.0)
                            Text("5s").tag(5.0)
                            Text("10s").tag(10.0)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }

                    Toggle(L.pauseWhenIdle, isOn: $settings.pauseWhenIdle)

                    if settings.pauseWhenIdle {
                        HStack {
                            Text(L.idleAfter)
                            Spacer()
                            Picker("", selection: $settings.idleThresholdSeconds) {
                                Text("30s").tag(30.0)
                                Text("60s").tag(60.0)
                                Text("90s").tag(90.0)
                                Text("2m").tag(120.0)
                                Text("5m").tag(300.0)
                            }
                            .frame(width: 140)
                        }
                    }

                    Toggle(L.pauseDuringVideo, isOn: $settings.pauseDuringVideo)
                    Toggle(L.pauseDuringPrivateBrowsing, isOn: $settings.pauseDuringPrivateBrowsing)

                    Text(L.smartPauseHint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Label(L.captureSettings, systemImage: "camera")
                        .font(.headline)
                }

                // Privacy Section
                Section {
                    Toggle(L.clipboardMonitoring, isOn: $settings.clipboardMonitoring)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.excludedApps)
                            .font(.subheadline)

                        ForEach(settings.excludedApps, id: \.self) { app in
                            HStack {
                                Text(app)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(action: { settings.removeExcludedApp(app) }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack {
                            TextField(L.appName, text: $newExcludedApp)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(addExcludedAppFromInput)
                            Button(L.add, action: addExcludedAppFromInput)
                                .disabled(!canAddExcludedApp)
                        }
                    }

                    Text(L.excludedAppsHint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Label(L.privacy, systemImage: "hand.raised")
                        .font(.headline)
                }

                // Storage Section
                Section {
                    HStack {
                        Text(L.retentionDays)
                        Spacer()
                        Picker("", selection: $settings.retentionDays) {
                            Text("1 " + L.day).tag(1)
                            Text("3 " + L.days).tag(3)
                            Text("7 " + L.days).tag(7)
                            Text("14 " + L.days).tag(14)
                            Text("30 " + L.days).tag(30)
                            Text("∞").tag(9999)
                        }
                        .frame(width: 120)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.storageLocation)
                            .font(.subheadline)
                        HStack {
                            Text(settings.storagePath)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if isMigratingStorage {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Spacer()
                            if settings.supportsCustomStorageLocation {
                                Button(L.change) {
                                    selectFolder()
                                }
                                .disabled(isMigratingStorage)
                            }
                        }

                        if !settings.supportsCustomStorageLocation {
                            Text(L.appStoreStorageHint)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let size = folderSize() {
                        HStack {
                            Text(L.currentUsage)
                            Spacer()
                            Text(size)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Label(L.storage, systemImage: "folder")
                        .font(.headline)
                }

                // System Section
                Section {
                    Button(action: {
                        PermissionGuideController.shared.show()
                    }) {
                        HStack {
                            Image(systemName: "checklist")
                            Text(L.fixPermissionsAfterUpdate)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    Toggle(L.autoStart, isOn: $settings.autoStart)

                    if settings.usesSystemManagedAutoStart {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L.autoStartSystemManaged)
                            Text(L.autoStartSystemManagedHint)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if hasLegacyTimelineApp {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L.legacyTimelineCleanupTitle)
                                .font(.subheadline)
                            Text(L.legacyTimelineCleanupHint(LegacyTimelineMigration.existingLegacyAppDisplayPaths))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack {
                                Button(L.moveToTrash) {
                                    if LegacyTimelineMigration.moveExistingLegacyAppsToTrash() {
                                        refreshLegacyTimelineStatus()
                                    }
                                }
                                Button(L.showInFinder) {
                                    LegacyTimelineMigration.revealExistingLegacyApps()
                                }
                            }
                        }
                    }
                } header: {
                    Label(L.system, systemImage: "gearshape")
                        .font(.headline)
                }

                // Support Section
                Section {
                    Button(action: {
                        if let url = URL(string: "https://buymeacoffee.com/uygarduzgun") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "cup.and.saucer.fill")
                                .foregroundColor(.orange)
                            Text(L.buyMeACoffee)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Label(L.support, systemImage: "heart.fill")
                        .font(.headline)
                }
            }
            .formStyle(.grouped)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 450, minHeight: 620)
        .onAppear(perform: refreshLegacyTimelineStatus)
    }

    private func addExcludedAppFromInput() {
        guard canAddExcludedApp else { return }
        settings.addExcludedApp(normalizedExcludedAppInput)
        newExcludedApp = ""
    }

    private func refreshLegacyTimelineStatus() {
        hasLegacyTimelineApp = LegacyTimelineMigration.hasLegacyTimelineApp
    }

    private func selectFolder() {
        guard settings.supportsCustomStorageLocation else {
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: settings.storagePath)

        if panel.runModal() == .OK, let url = panel.url {
            isMigratingStorage = true

            Task { @MainActor in
                defer { isMigratingStorage = false }

                do {
                    let result = try await settings.updateStoragePath(url.path)
                    let alert = NSAlert()
                    alert.messageText = L.storageMigrationDone
                    alert.informativeText = L.storageMigrationSummary(
                        (settings.storagePath as NSString).abbreviatingWithTildeInPath,
                        result.movedItems,
                        result.copiedItems,
                        result.conflictRenames,
                        result.skippedItems
                    )
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: L.ok)
                    alert.runModal()
                } catch {
                    let alert = NSAlert()
                    alert.messageText = L.storageMigrationFailed
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: L.ok)
                    alert.runModal()
                }
            }
        }
    }

    private func folderSize() -> String? {
        let url = URL(fileURLWithPath: settings.storagePath)
        guard let totalSize = StorageMetrics.totalBytes(in: url) else {
            return nil
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }
}

// MARK: - Localization Extensions

private extension L {
    static var settings: String { isSwedish ? "Inställningar" : "Settings" }
    static var captureSettings: String { isSwedish ? "Inspelning" : "Capture" }
    static var captureInterval: String { isSwedish ? "Intervall" : "Interval" }
    static var pauseWhenIdle: String { isSwedish ? "Pausa när jag är inaktiv" : "Pause when I'm idle" }
    static var idleAfter: String { isSwedish ? "Inaktiv efter" : "Idle after" }
    static var pauseDuringVideo: String { isSwedish ? "Pausa under film/streaming" : "Pause during video/streaming" }
    static var pauseDuringPrivateBrowsing: String { isSwedish ? "Pausa i inkognito/privat läge" : "Pause in private/incognito mode" }
    static var smartPauseHint: String {
        isSwedish
            ? "Smart pause stoppar inspelning automatiskt i känsliga eller irrelevanta lägen."
            : "Smart pause automatically pauses capture in sensitive or low-value contexts."
    }
    static var privacy: String { isSwedish ? "Sekretess" : "Privacy" }
    static var clipboardMonitoring: String { isSwedish ? "Fånga urklipp" : "Capture clipboard" }
    static var excludedApps: String { isSwedish ? "Exkluderade appar" : "Excluded apps" }
    static var excludedAppsHint: String {
        isSwedish
            ? "Lägg till appar som aldrig ska OCR-tolkas."
            : "Add apps that should never be OCR scanned."
    }
    static var appName: String { isSwedish ? "Appnamn" : "App name" }
    static var add: String { isSwedish ? "Lägg till" : "Add" }
    static var storage: String { isSwedish ? "Lagring" : "Storage" }
    static var retentionDays: String { isSwedish ? "Behåll data" : "Keep data" }
    static var day: String { isSwedish ? "dag" : "day" }
    static var days: String { isSwedish ? "dagar" : "days" }
    static var storageLocation: String { isSwedish ? "Lagringsplats" : "Storage location" }
    static var appStoreStorageHint: String {
        isSwedish
            ? "App Store-versionen använder appens delade container för lagring tills stöd för security-scoped bookmarks finns."
            : "The App Store build stores data in the shared app container until security-scoped bookmark support is added."
    }
    static var change: String { isSwedish ? "Ändra" : "Change" }
    static var currentUsage: String { isSwedish ? "Använt utrymme" : "Current usage" }
    static var storageMigrationDone: String { isSwedish ? "Migrering klar" : "Migration complete" }
    static func storageMigrationSummary(_ path: String, _ moved: Int, _ copied: Int, _ renamed: Int, _ skipped: Int) -> String {
        if isSwedish {
            return """
            Ny plats: \(path)

            Flyttade: \(moved)
            Kopierade: \(copied)
            Konflikt-omdöpta: \(renamed)
            Skippade: \(skipped)
            """
        }

        return """
        New location: \(path)

        Moved: \(moved)
        Copied: \(copied)
        Conflict-renamed: \(renamed)
        Skipped: \(skipped)
        """
    }
    static var storageMigrationFailed: String { isSwedish ? "Migrering misslyckades" : "Migration failed" }
    static var system: String { isSwedish ? "System" : "System" }
    static var autoStart: String { isSwedish ? "Starta vid inloggning" : "Start at login" }
    static var autoStartSystemManaged: String {
        isSwedish ? "Autostart hanteras av systemets login items" : "Start at login is managed by the system login items"
    }
    static var autoStartSystemManagedHint: String {
        isSwedish
            ? "I App Store-spåret registreras huvudappen via SMAppService i stället för en användarskapad LaunchAgent."
            : "For the App Store track, the main app is registered through SMAppService instead of a user-managed LaunchAgent."
    }
    static var legacyTimelineCleanupTitle: String {
        isSwedish ? "Gammal Timeline-app" : "Old Timeline app"
    }
    static func legacyTimelineCleanupHint(_ paths: [String]) -> String {
        let joinedPaths = paths.joined(separator: "\n")
        if isSwedish {
            return """
            Timeline öppnas nu direkt i Memento Capture via menyradsikonen. Den gamla appen används inte längre.

            \(joinedPaths)
            """
        }

        return """
        Timeline now opens directly inside Memento Capture from the menu bar icon. The old app is no longer used.

        \(joinedPaths)
        """
    }
    static var fixPermissionsAfterUpdate: String { isSwedish ? "Öppna Setup Hub" : "Open Setup Hub" }
    static var support: String { isSwedish ? "Stöd" : "Support" }
}
