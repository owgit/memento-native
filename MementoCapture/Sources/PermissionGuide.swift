import SwiftUI
import AppKit

/// Permission guide window with step-by-step instructions
@MainActor
class PermissionGuideController {
    static let shared = PermissionGuideController()
    private var window: NSWindow?
    
    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let contentView = PermissionGuideView()
        let hostingController = NSHostingController(rootView: contentView)
        
        window = NSWindow(contentViewController: hostingController)
        window?.title = isSwedish ? "Behörighetsguide" : "Permission Guide"
        window?.styleMask = [.titled, .closable]
        window?.setContentSize(NSSize(width: 540, height: 640))
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private var isSwedish: Bool {
        Locale.current.language.languageCode?.identifier == "sv"
    }
}

// MARK: - SwiftUI View

struct PermissionGuideView: View {
    @State private var hasPermission = false
    @State private var checkingPermission = false
    @State private var repairingPermission = false
    @State private var repairStatusMessage: String?
    @State private var repairStatusIsError = false
    
    private var isSwedish: Bool {
        Locale.current.language.languageCode?.identifier == "sv"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        Image(systemName: "video.badge.checkmark")
                            .font(.system(size: 40))
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading) {
                            Text(isSwedish ? "Skärminspelning krävs" : "Screen Recording Required")
                                .font(.title2.bold())
                            Text(isSwedish ? "Memento behöver detta för att kunna spela in skärmen" : "Memento needs this to capture your screen")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.bottom, 10)
                    
                    Divider()
                    
                    // Current status
                    statusSection
                    
                    Divider()
                    
                    // Why needed
                    whySection
                    
                    Divider()
                    
                    // Instructions
                    instructionsSection
                    
                    Divider()
                    
                    // Troubleshooting
                    troubleshootingSection
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                if let repairStatusMessage {
                    Label(repairStatusMessage, systemImage: repairStatusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(repairStatusIsError ? .orange : .green)
                }
                
                actionButtons
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 540, height: 640)
        .onAppear { checkPermission() }
    }
    
    private var statusSection: some View {
        HStack(spacing: 12) {
            Image(systemName: hasPermission ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title)
                .foregroundColor(hasPermission ? .green : .red)
            
            VStack(alignment: .leading) {
                Text(isSwedish ? "Status" : "Status")
                    .font(.headline)
                Text(hasPermission 
                     ? (isSwedish ? "✓ Behörighet beviljad" : "✓ Permission granted")
                     : (isSwedish ? "✗ Behörighet saknas" : "✗ Permission missing"))
                    .foregroundColor(hasPermission ? .green : .red)
            }
            
            Spacer()
            
            Button(action: checkPermission) {
                if checkingPermission {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Label(isSwedish ? "Kontrollera" : "Check", systemImage: "arrow.clockwise")
                }
            }
            .disabled(checkingPermission)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var whySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(isSwedish ? "Varför behövs detta?" : "Why is this needed?", systemImage: "questionmark.circle")
                .font(.headline)
            
            Text(isSwedish 
                 ? "Memento tar skärmbilder varannan sekund för att bygga en sökbar historik. Utan behörigheten kan macOS bara ge bakgrundsbilden, inte innehållet i dina appfönster."
                 : "Memento takes screenshots every 2 seconds to build a searchable history. Without this permission, macOS can only provide your wallpaper, not app window content.")
                .foregroundColor(.secondary)
        }
    }
    
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(isSwedish ? "Så här aktiverar du" : "How to enable", systemImage: "list.number")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 16) {
                stepRow(1, isSwedish 
                        ? "Klicka på \"Öppna Inställningar\""
                        : "Click \"Open Settings\"")
                
                stepRow(2, isSwedish
                        ? "Aktivera \"Memento Capture\" i listan"
                        : "Enable \"Memento Capture\" in the list")
                
                stepRow(3, isSwedish
                        ? "Om appen saknas: klicka + och välj /Applications/Memento Capture.app"
                        : "If it's missing: click + and select /Applications/Memento Capture.app")
                
                stepRow(4, isSwedish
                        ? "Starta om Memento Capture"
                        : "Restart Memento Capture")
            }
            .padding(.leading, 4)
        }
    }
    
    private var troubleshootingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(isSwedish ? "Felsökning" : "Troubleshooting", systemImage: "wrench.and.screwdriver")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                troubleItem(
                    isSwedish ? "Appen syns inte i listan" : "App not in the list",
                    isSwedish 
                        ? "Klicka + och välj /Applications/Memento Capture.app"
                        : "Click + and select /Applications/Memento Capture.app"
                )
                
                troubleItem(
                    isSwedish ? "Behörighet försvinner efter uppdatering" : "Permission disappears after update",
                    isSwedish
                        ? "Det kan hända efter vissa uppdateringar. Ta bort appen i listan, lägg till den igen och starta om."
                        : "This can happen after some updates. Remove the app in the list, add it again, then restart."
                )
                
                troubleItem(
                    isSwedish ? "Fortfarande svart/bakgrund" : "Still black/wallpaper only",
                    isSwedish
                        ? "Kör reset-kommandot nedan, lägg till appen igen i listan och starta om."
                        : "Run the reset command below, add the app in the list again, then restart."
                )
            }
        }
    }
    
    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: openSystemSettings) {
                    Label(isSwedish ? "Öppna Inställningar" : "Open Settings", systemImage: "gear")
                }
                .buttonStyle(.borderedProminent)

                Button(action: repairPermissionsAfterUpdate) {
                    if repairingPermission {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 120)
                    } else {
                        Label(
                            isSwedish ? "Fixa efter uppdatering" : "Fix after update",
                            systemImage: "arrow.clockwise.circle"
                        )
                    }
                }
                .buttonStyle(.bordered)
                .disabled(repairingPermission)

                Spacer()

                Button(isSwedish ? "Stäng" : "Close") {
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Button(action: copyTerminalCommand) {
                    Label(isSwedish ? "Kopiera reset-kommando" : "Copy reset command", systemImage: "terminal")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
    }
    
    // MARK: - Helpers
    
    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            
            Text(text)
                .foregroundColor(.secondary)
        }
    }
    
    private func troubleItem(_ title: String, _ solution: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("• " + title)
                .font(.subheadline.bold())
            Text(solution)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 12)
        }
    }
    
    private func checkPermission() {
        checkingPermission = true
        // Use preflight only to avoid triggering the system permission dialog automatically.
        hasPermission = CGPreflightScreenCaptureAccess()
        checkingPermission = false
    }
    
    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func repairPermissionsAfterUpdate() {
        guard !repairingPermission else { return }
        repairingPermission = true
        repairStatusMessage = nil
        repairStatusIsError = false

        DispatchQueue.global(qos: .userInitiated).async {
            let success = resetScreenCapturePermission()

            DispatchQueue.main.async {
                repairingPermission = false
                openSystemSettings()
                CGRequestScreenCaptureAccess()
                checkPermission()

                if success {
                    repairStatusMessage = isSwedish
                        ? "Klart. Aktivera Memento Capture i listan och starta om appen."
                        : "Done. Enable Memento Capture in the list and restart the app."
                    repairStatusIsError = false
                } else {
                    repairStatusMessage = isSwedish
                        ? "Kunde inte köra reset automatiskt. Använd knappen för terminalkommandot."
                        : "Could not run reset automatically. Use the terminal command button."
                    repairStatusIsError = true
                }
            }
        }
    }

    private func resetScreenCapturePermission() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", "com.memento.capture"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    private func copyTerminalCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("tccutil reset ScreenCapture com.memento.capture", forType: .string)
        
        // Show feedback
        let alert = NSAlert()
        alert.messageText = isSwedish ? "Kopierat!" : "Copied!"
        alert.informativeText = isSwedish 
            ? "Klistra in i Terminal och tryck Enter.\nLägg sedan till/aktivera Memento Capture i Screen Recording och starta om appen."
            : "Paste in Terminal and press Enter.\nThen add/enable Memento Capture in Screen Recording and restart the app."
        alert.alertStyle = .informational
        alert.runModal()
    }
}
