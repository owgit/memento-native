import SwiftUI
import AppKit

/// Onboarding window shown on first launch
class OnboardingWindow {
    private var window: NSWindow?
    
    func showIfNeeded() {
        let defaults = UserDefaults.standard
        let hasSeenOnboarding = defaults.bool(forKey: "hasSeenOnboarding")
        
        if !hasSeenOnboarding {
            show()
        }
    }
    
    func show() {
        let contentView = OnboardingView {
            self.close()
        }
        
        let hostingController = NSHostingController(rootView: contentView)
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window?.title = "Välkommen till Memento"
        window?.contentViewController = hostingController
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.level = .floating
        
        // Activate app to show window
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func close() {
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        window?.close()
        window = nil
    }
}

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var hasPermission = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 64))
                .foregroundColor(.blue)
                .padding(.top, 20)
            
            // Title
            Text("Memento")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Din visuella tidsmaskin")
                .font(.title3)
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.horizontal, 40)
            
            // Features
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "camera.fill",
                    title: "Skärminspelning",
                    description: "Tar skärmbilder var 2:a sekund"
                )
                
                FeatureRow(
                    icon: "text.viewfinder",
                    title: "OCR-sökning",
                    description: "Sök i all text du sett på skärmen"
                )
                
                FeatureRow(
                    icon: "lock.shield.fill",
                    title: "100% Lokalt",
                    description: "All data stannar på din Mac"
                )
                
                FeatureRow(
                    icon: "leaf.fill",
                    title: "Låg resursanvändning",
                    description: "Endast ~1% RAM, minimal CPU"
                )
            }
            .padding(.horizontal, 30)
            
            Divider()
                .padding(.horizontal, 40)
            
            // Permission section
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: hasPermission ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(hasPermission ? .green : .orange)
                    Text("Skärminspelning krävs")
                        .fontWeight(.medium)
                }
                
                if !hasPermission {
                    Button("Öppna Systeminställningar") {
                        openScreenRecordingSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            Spacer()
            
            // Start button
            Button(action: onComplete) {
                Text("Starta Memento")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
        }
        .frame(width: 480, height: 580)
        .onAppear {
            checkPermission()
        }
    }
    
    private func checkPermission() {
        // Check screen recording permission
        hasPermission = CGPreflightScreenCaptureAccess()
    }
    
    private func openScreenRecordingSettings() {
        // Request permission (triggers system dialog)
        CGRequestScreenCaptureAccess()
        
        // Also open System Preferences
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        
        // Check again after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            checkPermission()
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
