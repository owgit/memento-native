import SwiftUI
import AppKit
import ScreenCaptureKit

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
        window?.setContentSize(NSSize(width: 500, height: 600))
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
                        Text(isSwedish ? "Memento behöver denna behörighet för att fungera" : "Memento needs this permission to work")
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
                
                Spacer(minLength: 20)
                
                // Actions
                actionButtons

                if let repairStatusMessage {
                    Label(repairStatusMessage, systemImage: repairStatusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(repairStatusIsError ? .orange : .green)
                        .padding(.top, 2)
                }
            }
            .padding(24)
        }
        .frame(width: 500, height: 600)
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
                 ? "Memento tar skärmbilder var 2:a sekund för att skapa en sökbar historik av allt du sett. Utan Screen Recording-behörighet kan appen endast fånga din bakgrundsbild – inte appfönster eller innehåll."
                 : "Memento takes screenshots every 2 seconds to create a searchable history of everything you've seen. Without Screen Recording permission, the app can only capture your wallpaper – not app windows or content.")
                .foregroundColor(.secondary)
        }
    }
    
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(isSwedish ? "Så här aktiverar du" : "How to enable", systemImage: "list.number")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 16) {
                stepRow(1, isSwedish 
                        ? "Klicka \"Öppna Inställningar\" nedan"
                        : "Click \"Open Settings\" below")
                
                stepRow(2, isSwedish
                        ? "Hitta \"Memento Capture\" i listan"
                        : "Find \"Memento Capture\" in the list")
                
                stepRow(3, isSwedish
                        ? "Aktivera reglaget bredvid appen"
                        : "Toggle the switch next to the app")
                
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
                        ? "Klicka + och navigera till /Applications/Memento Capture.app"
                        : "Click + and navigate to /Applications/Memento Capture.app"
                )
                
                troubleItem(
                    isSwedish ? "Behörighet försvinner efter uppdatering" : "Permission disappears after update",
                    isSwedish
                        ? "Detta är normalt för osignerade appar. Ta bort appen från listan, lägg till den igen, och starta om."
                        : "This is normal for unsigned apps. Remove from list, add again, and restart."
                )
                
                troubleItem(
                    isSwedish ? "Fortfarande svart/bakgrund" : "Still black/wallpaper only",
                    isSwedish
                        ? "Prova: Terminal → tccutil reset ScreenCapture → lägg till appen igen"
                        : "Try: Terminal → tccutil reset ScreenCapture → add app again"
                )
            }
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: repairPermissionsAfterUpdate) {
                if repairingPermission {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: 120)
                } else {
                    Label(
                        isSwedish ? "Fixa efter uppdatering" : "Fix after update",
                        systemImage: "wand.and.stars"
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(repairingPermission)

            Button(action: openSystemSettings) {
                Label(isSwedish ? "Öppna Inställningar" : "Open Settings", systemImage: "gear")
            }
            
            Button(action: copyTerminalCommand) {
                Label(isSwedish ? "Kopiera reset-kommando" : "Copy reset command", systemImage: "terminal")
            }
            
            Spacer()
            
            if hasPermission {
                Button(isSwedish ? "Stäng" : "Close") {
                    NSApp.keyWindow?.close()
                }
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
        hasPermission = CGPreflightScreenCaptureAccess()
        
        // Also try to get shareable content to verify
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                await MainActor.run {
                    hasPermission = !content.displays.isEmpty
                    checkingPermission = false
                }
            } catch {
                await MainActor.run {
                    hasPermission = false
                    checkingPermission = false
                }
            }
        }
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
                        ? "Reset klart. Aktivera Memento Capture i listan."
                        : "Reset complete. Enable Memento Capture in the list."
                    repairStatusIsError = false
                } else {
                    repairStatusMessage = isSwedish
                        ? "Kunde inte köra reset automatiskt. Använd terminal-knappen."
                        : "Could not run reset automatically. Use the terminal button."
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
        NSPasteboard.general.setString("tccutil reset ScreenCapture", forType: .string)
        
        // Show feedback
        let alert = NSAlert()
        alert.messageText = isSwedish ? "Kopierat!" : "Copied!"
        alert.informativeText = isSwedish 
            ? "Klistra in i Terminal och tryck Enter. Lägg sedan till appen i Screen Recording igen."
            : "Paste in Terminal and press Enter. Then add the app to Screen Recording again."
        alert.alertStyle = .informational
        alert.runModal()
    }
}

