import SwiftUI
import AppKit

@MainActor
enum SetupHubReason {
    case manual
    case firstLaunch
    case permissionMissing
    case updated(previous: String, current: String)

    func bannerMessage(isSwedish: Bool) -> String? {
        switch self {
        case .manual:
            return nil
        case .firstLaunch:
            return isSwedish
                ? "Välkommen! Setup Hub guidar dig genom behörighet och första start."
                : "Welcome! Setup Hub guides permission and first-time setup."
        case .permissionMissing:
            return isSwedish
                ? "Skärminspelningsbehörighet saknas. Åtgärda det här för att inspelningen ska fungera."
                : "Screen Recording permission is missing. Fix it here to enable capture."
        case let .updated(previous, current):
            return isSwedish
                ? "Appen uppdaterades: \(previous) → \(current). Kontrollera behörighet om inspelning inte fungerar."
                : "App updated: \(previous) → \(current). Check permission if capture is not working."
        }
    }
}

/// Unified setup hub for first launch, updates and permission recovery.
@MainActor
class PermissionGuideController {
    static let shared = PermissionGuideController()
    private var window: NSWindow?

    func show(reason: SetupHubReason = .manual) {
        let root = SetupHubView(reason: reason)

        if let existing = window {
            if let host = existing.contentViewController as? NSHostingController<SetupHubView> {
                host.rootView = root
            } else {
                existing.contentViewController = NSHostingController(rootView: root)
            }
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: root)
        window = NSWindow(contentViewController: hostingController)
        window?.title = isSwedish ? "Setup Hub" : "Setup Hub"
        window?.styleMask = [.titled, .closable]
        window?.setContentSize(NSSize(width: 620, height: 700))
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var isSwedish: Bool {
        Locale.current.language.languageCode?.identifier == "sv"
    }
}

// MARK: - View

struct SetupHubView: View {
    let reason: SetupHubReason

    @State private var hasPermission = false
    @State private var checkingPermission = false
    @State private var repairingPermission = false
    @State private var permissionPollTimer: Timer?
    @State private var repairStatusMessage: String?
    @State private var repairStatusIsError = false

    private var isSwedish: Bool {
        Locale.current.language.languageCode?.identifier == "sv"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection

                    if let banner = reason.bannerMessage(isSwedish: isSwedish) {
                        Label(banner, systemImage: "info.circle.fill")
                            .font(.subheadline)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    statusCards

                    Divider()

                    primaryActionsSection

                    Divider()

                    instructionsSection

                    Divider()

                    troubleshootingSection
                }
                .padding(24)
            }

            Divider()

            footerSection
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 620, height: 700)
        .onAppear { checkPermission() }
        .onDisappear {
            permissionPollTimer?.invalidate()
            permissionPollTimer = nil
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "checklist")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 46, height: 46)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(isSwedish ? "Setup Hub" : "Setup Hub")
                    .font(.title2.bold())
                Text(isSwedish ? "Allt för första start, uppdatering och behörigheter" : "Everything for first launch, updates and permissions")
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: checkPermission) {
                if checkingPermission {
                    ProgressView().controlSize(.small)
                } else {
                    Label(isSwedish ? "Uppdatera" : "Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(checkingPermission)
        }
    }

    private var statusCards: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    hasPermission
                        ? (isSwedish ? "Skärminspelning: OK" : "Screen Recording: OK")
                        : (isSwedish ? "Skärminspelning: Saknas" : "Screen Recording: Missing"),
                    systemImage: hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundColor(hasPermission ? .green : .orange)

                Text(
                    hasPermission
                        ? (isSwedish ? "Memento kan spela in skärmens innehåll." : "Memento can capture screen content.")
                        : (isSwedish ? "Behörighet krävs för att fånga appfönster." : "Permission is required to capture app windows.")
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "\(isSwedish ? "Version" : "Version"): \(appVersionLabel)",
                    systemImage: "shippingbox"
                )
                Text(isSwedish ? "Om capture strular efter uppdatering: kör reparera här." : "If capture breaks after update: run repair here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var primaryActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(isSwedish ? "Snabbåtgärder" : "Quick Actions", systemImage: "bolt.fill")
                .font(.headline)

            HStack(spacing: 10) {
                Button(action: repairPermissionsAfterUpdate) {
                    if repairingPermission {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 130)
                    } else {
                        Label(
                            hasPermission
                                ? (isSwedish ? "Kontrollera status" : "Check Status")
                                : (isSwedish ? "Fixa automatiskt" : "Fix Automatically"),
                            systemImage: hasPermission ? "arrow.clockwise" : "wand.and.stars"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(repairingPermission)

                Button(action: openSystemSettings) {
                    Label(isSwedish ? "Öppna Inställningar" : "Open Settings", systemImage: "gear")
                }
                .buttonStyle(.bordered)
            }

            if let repairStatusMessage {
                Label(repairStatusMessage, systemImage: repairStatusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(repairStatusIsError ? .orange : .green)
                    .padding(.top, 2)
            }

            Button(action: copyTerminalCommand) {
                Text(isSwedish ? "Avancerat: Kopiera Terminal-kommando" : "Advanced: Copy terminal command")
                    .font(.caption)
            }
            .buttonStyle(.link)
        }
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(isSwedish ? "Steg för steg" : "Step by Step", systemImage: "list.number")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                stepRow(1, isSwedish ? "Öppna Systeminställningar för Skärminspelning" : "Open Screen Recording settings")
                stepRow(2, isSwedish ? "Aktivera \"Memento Capture\" i listan" : "Enable \"Memento Capture\" in the list")
                stepRow(3, isSwedish ? "Om appen saknas: lägg till /Applications/Memento Capture.app" : "If missing: add /Applications/Memento Capture.app")
                stepRow(4, isSwedish ? "Starta om Memento Capture" : "Restart Memento Capture")
            }
            .padding(.leading, 2)
        }
    }

    private var troubleshootingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(isSwedish ? "Felsökning" : "Troubleshooting", systemImage: "wrench.and.screwdriver")
                .font(.headline)

            troubleItem(
                isSwedish ? "Dialogen fortsätter komma" : "Prompt keeps appearing",
                isSwedish
                    ? "Kör reparera-knappen, aktivera appen i listan och starta om appen." 
                    : "Run repair, enable the app in the list, and restart the app."
            )

            troubleItem(
                isSwedish ? "Bara bakgrund syns" : "Only wallpaper is captured",
                isSwedish
                    ? "Behörigheten är inte aktiv. Kontrollera att togglen är på för Memento Capture."
                    : "Permission is not active. Verify toggle is enabled for Memento Capture."
            )
        }
    }

    private var footerSection: some View {
        HStack {
            Spacer()
            Button(isSwedish ? "Stäng" : "Close") {
                NSApp.keyWindow?.close()
            }
            .buttonStyle(.bordered)
        }
    }

    private var appVersionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
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
        VStack(alignment: .leading, spacing: 3) {
            Text("• \(title)")
                .font(.subheadline.bold())
            Text(solution)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 10)
        }
    }

    private func checkPermission() {
        checkingPermission = true
        hasPermission = CGPreflightScreenCaptureAccess()
        checkingPermission = false
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func repairPermissionsAfterUpdate() {
        if hasPermission {
            checkPermission()
            repairStatusIsError = false
            repairStatusMessage = isSwedish
                ? "Behörighet är redan aktiv."
                : "Permission is already active."
            return
        }

        guard !repairingPermission else { return }
        repairingPermission = true
        repairStatusMessage = nil
        repairStatusIsError = false

        DispatchQueue.global(qos: .userInitiated).async {
            let success = resetScreenCapturePermission()

            DispatchQueue.main.async {
                repairingPermission = false
                if success {
                    requestPermissionFromSystem(afterReset: true)
                } else {
                    repairStatusMessage = isSwedish
                        ? "Kunde inte köra reset automatiskt. Använd kommandoknappen."
                        : "Could not run reset automatically. Use the command button."
                    repairStatusIsError = true
                }
            }
        }
    }

    private func requestPermissionFromSystem(afterReset: Bool = false) {
        repairStatusIsError = false

        if hasPermission {
            repairStatusMessage = isSwedish
                ? "Behörighet är redan aktiv."
                : "Permission is already active."
            return
        }

        let grantedImmediately = CGRequestScreenCaptureAccess()
        checkPermission()

        if grantedImmediately || hasPermission {
            repairStatusMessage = isSwedish
                ? "Behörighet aktiverad."
                : "Permission enabled."
            return
        }

        openSystemSettings()
        startPermissionPolling()
        repairStatusMessage = isSwedish
            ? (afterReset
                ? "Förfrågan skickad. Aktivera Memento Capture i listan i Systeminställningar."
                : "Förfrågan skickad. Godkänn och aktivera Memento Capture i Systeminställningar.")
            : (afterReset
                ? "Request sent. Enable Memento Capture in the list in System Settings."
                : "Request sent. Approve and enable Memento Capture in System Settings.")
    }

    private func startPermissionPolling() {
        permissionPollTimer?.invalidate()

        var attempts = 0
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            attempts += 1
            checkPermission()
            if hasPermission || attempts >= 30 {
                timer.invalidate()
                permissionPollTimer = nil
                if hasPermission {
                    repairStatusIsError = false
                    repairStatusMessage = isSwedish
                        ? "Behörighet registrerad. Starta om appen en gång."
                        : "Permission detected. Restart the app once."
                }
            }
        }

        if let permissionPollTimer {
            RunLoop.main.add(permissionPollTimer, forMode: .common)
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

        let alert = NSAlert()
        alert.messageText = isSwedish ? "Kopierat!" : "Copied!"
        alert.informativeText = isSwedish
            ? "Klistra in i Terminal och tryck Enter. Aktivera sedan Memento Capture i Screen Recording och starta om appen."
            : "Paste in Terminal and press Enter. Then enable Memento Capture in Screen Recording and restart the app."
        alert.alertStyle = .informational
        alert.runModal()
    }
}
