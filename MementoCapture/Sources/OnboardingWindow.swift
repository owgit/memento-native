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
        
        window?.title = L.welcomeTitle
        window?.contentViewController = hostingController
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.level = .floating
        
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
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 64))
                .foregroundColor(.blue)
                .padding(.top, 20)
            
            Text(L.memento)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text(L.tagline)
                .font(.title3)
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.horizontal, 40)
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "camera.fill",
                    title: L.featureRecording,
                    description: L.featureRecordingDesc
                )
                
                FeatureRow(
                    icon: "text.viewfinder",
                    title: L.featureOCR,
                    description: L.featureOCRDesc
                )
                
                FeatureRow(
                    icon: "lock.shield.fill",
                    title: L.featurePrivacy,
                    description: L.featurePrivacyDesc
                )
                
                FeatureRow(
                    icon: "leaf.fill",
                    title: L.featureLowResource,
                    description: L.featureLowResourceDesc
                )
            }
            .padding(.horizontal, 30)
            
            Divider()
                .padding(.horizontal, 40)
            
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: hasPermission ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(hasPermission ? .green : .orange)
                    Text(L.screenRecordingRequired)
                        .fontWeight(.medium)
                }
                
                if !hasPermission {
                    Button(L.openSystemSettings) {
                        openScreenRecordingSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            Spacer()
            
            Button(action: onComplete) {
                Text(L.startMemento)
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
        hasPermission = CGPreflightScreenCaptureAccess()
    }
    
    private func openScreenRecordingSettings() {
        CGRequestScreenCaptureAccess()
        
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        
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
