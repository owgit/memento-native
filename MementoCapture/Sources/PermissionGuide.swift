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

private enum SetupHubVisualTokens {
    static let windowWidth: CGFloat = 620
    static let windowHeight: CGFloat = 700
    static let cornerRadius: CGFloat = 10
    static let sectionSpacing: CGFloat = 18
    static let contentPadding: CGFloat = 24
}

private enum SetupHubState {
    case checking
    case ready
    case needsPermission
    case recovering
    case error(String)
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
        window?.setContentSize(NSSize(width: SetupHubVisualTokens.windowWidth, height: SetupHubVisualTokens.windowHeight))
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
                VStack(alignment: .leading, spacing: SetupHubVisualTokens.sectionSpacing) {
                    headerSection

                    if let banner = reason.bannerMessage(isSwedish: isSwedish) {
                        Label(banner, systemImage: "info.circle.fill")
                            .font(.body)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: SetupHubVisualTokens.cornerRadius))
                    }

                    statusBannerSection

                    statusCards

                    Divider()

                    primaryActionsSection

                    Divider()

                    whyWeAskSection

                    Divider()

                    instructionsSection

                    Divider()

                    troubleshootingSection
                }
                .padding(SetupHubVisualTokens.contentPadding)
            }

            Divider()

            footerSection
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: SetupHubVisualTokens.windowWidth, height: SetupHubVisualTokens.windowHeight)
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
            .accessibilityLabel(isSwedish ? "Uppdatera status" : "Refresh status")
        }
    }

    private var currentHubState: SetupHubState {
        if checkingPermission {
            return .checking
        }
        if repairingPermission {
            return .recovering
        }
        if repairStatusIsError, let repairStatusMessage, !repairStatusMessage.isEmpty {
            return .error(repairStatusMessage)
        }
        return hasPermission ? .ready : .needsPermission
    }

    private var statusBannerSection: some View {
        let config = stateBannerConfig
        return HStack(spacing: 10) {
            Image(systemName: config.icon)
                .foregroundColor(config.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(config.title)
                    .font(.subheadline.weight(.semibold))
                Text(config.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(config.color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: SetupHubVisualTokens.cornerRadius))
        .accessibilityElement(children: .combine)
    }

    private var stateBannerConfig: (icon: String, color: Color, title: String, message: String) {
        switch currentHubState {
        case .checking:
            return (
                icon: "hourglass",
                color: .blue,
                title: isSwedish ? "Kontrollerar status..." : "Checking status...",
                message: isSwedish ? "Vi läser aktuell behörighet." : "Reading current permission state."
            )
        case .ready:
            return (
                icon: "checkmark.seal.fill",
                color: .green,
                title: isSwedish ? "Redo att spela in" : "Ready to record",
                message: isSwedish ? "Allt ser bra ut. Capture kan köra normalt." : "Everything looks good. Capture can run normally."
            )
        case .needsPermission:
            return (
                icon: "shield.lefthalf.filled.badge.exclamationmark",
                color: .orange,
                title: isSwedish ? "Behörighet behövs" : "Permission needed",
                message: isSwedish ? "Klicka på Fixa automatiskt. Vi guidar dig klart." : "Click Fix automatically. We'll guide you through it."
            )
        case .recovering:
            return (
                icon: "arrow.triangle.2.circlepath",
                color: .blue,
                title: isSwedish ? "Återställer behörighet..." : "Recovering permission...",
                message: isSwedish ? "Detta kan ta några sekunder." : "This can take a few seconds."
            )
        case .error(let message):
            return (
                icon: "xmark.octagon.fill",
                color: .orange,
                title: isSwedish ? "Åtgärd krävs" : "Action required",
                message: message
            )
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
                .accessibilityLabel(hasPermission ? (isSwedish ? "Kontrollera status" : "Check status") : (isSwedish ? "Fixa behörighet automatiskt" : "Fix permission automatically"))
                .accessibilityHint(isSwedish ? "Kör återställning och guidar till rätt inställning." : "Runs recovery and guides to the right setting.")

                Button(action: openSystemSettings) {
                    Label(isSwedish ? "Öppna Inställningar" : "Open Settings", systemImage: "gear")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(isSwedish ? "Öppna systeminställningar" : "Open system settings")
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
            .accessibilityLabel(isSwedish ? "Kopiera avancerat kommando" : "Copy advanced command")
        }
    }

    private var whyWeAskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(isSwedish ? "Varför behövs detta?" : "Why this is needed", systemImage: "questionmark.circle")
                .font(.headline)

            trustRow(
                icon: "video.badge.checkmark",
                text: isSwedish
                    ? "För att spara dina skärmbilder måste macOS ge Memento tillgång till skärmen."
                    : "To save your screenshots, macOS must grant Memento access to your screen."
            )
            trustRow(
                icon: "lock.shield",
                text: isSwedish
                    ? "Inspelningen stannar på din Mac. Ingen uppladdning krävs."
                    : "Captures stay on your Mac. No upload is required."
            )
            trustRow(
                icon: "arrow.uturn.backward.circle",
                text: isSwedish
                    ? "Om något bryts efter uppdatering kan du reparera här med ett klick."
                    : "If updates break permission, you can repair it here in one click."
            )
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

    private func trustRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 16)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: SetupHubVisualTokens.cornerRadius))
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
            .accessibilityLabel(isSwedish ? "Stäng setup hub" : "Close setup hub")
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
