import SwiftUI
import AppKit

/// Settings window controller
@MainActor
class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    
    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let contentView = SettingsView()
        let hostingController = NSHostingController(rootView: contentView)
        
        window = NSWindow(contentViewController: hostingController)
        window?.title = L.settings
        window?.styleMask = [.titled, .closable]
        window?.setContentSize(NSSize(width: 450, height: 500))
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - SwiftUI View

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var newExcludedApp = ""
    @State private var showingFolderPicker = false
    
    var body: some View {
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
            } header: {
                Label(L.captureSettings, systemImage: "camera")
                    .font(.headline)
            }
            
            Divider().padding(.vertical, 8)
            
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
                        Button(L.add) {
                            if !newExcludedApp.isEmpty {
                                settings.addExcludedApp(newExcludedApp)
                                newExcludedApp = ""
                            }
                        }
                        .disabled(newExcludedApp.isEmpty)
                    }
                }
            } header: {
                Label(L.privacy, systemImage: "hand.raised")
                    .font(.headline)
            }
            
            Divider().padding(.vertical, 8)
            
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
                        Spacer()
                        Button(L.change) {
                            selectFolder()
                        }
                    }
                }
                
                // Storage info
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
            
            Divider().padding(.vertical, 8)
            
            // System Section
            Section {
                Toggle(L.autoStart, isOn: $settings.autoStart)
                
                Button(action: {
                    PermissionGuideController.shared.show()
                }) {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text(L.fixPermissionsAfterUpdate)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Label(L.system, systemImage: "gearshape")
                    .font(.headline)
            }
            
            Divider().padding(.vertical, 8)
            
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
        .frame(width: 450, height: 550)
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: settings.storagePath)
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let result = try settings.updateStoragePath(url.path)
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
    
    private func folderSize() -> String? {
        let url = URL(fileURLWithPath: settings.storagePath)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return nil
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
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
    static var privacy: String { isSwedish ? "Sekretess" : "Privacy" }
    static var clipboardMonitoring: String { isSwedish ? "Fånga urklipp" : "Capture clipboard" }
    static var excludedApps: String { isSwedish ? "Exkluderade appar" : "Excluded apps" }
    static var appName: String { isSwedish ? "Appnamn" : "App name" }
    static var add: String { isSwedish ? "Lägg till" : "Add" }
    static var storage: String { isSwedish ? "Lagring" : "Storage" }
    static var retentionDays: String { isSwedish ? "Behåll data" : "Keep data" }
    static var day: String { isSwedish ? "dag" : "day" }
    static var days: String { isSwedish ? "dagar" : "days" }
    static var storageLocation: String { isSwedish ? "Lagringsplats" : "Storage location" }
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
    static var fixPermissionsAfterUpdate: String { isSwedish ? "Fixa behörighet efter uppdatering" : "Fix permissions after update" }
    static var support: String { isSwedish ? "Stöd" : "Support" }
}
