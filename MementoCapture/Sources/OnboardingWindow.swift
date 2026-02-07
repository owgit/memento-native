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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
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

// MARK: - Onboarding Steps
enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case features
    case howItWorks
    case permission
    
    var title: String {
        switch self {
        case .welcome: return L.onboardingWelcome
        case .features: return L.onboardingFeatures
        case .howItWorks: return L.onboardingHowItWorks
        case .permission: return L.onboardingPermission
        }
    }
}

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var currentStep: OnboardingStep = .welcome
    @State private var hasPermission = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step == currentStep ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: currentStep)
                }
            }
            .padding(.top, 20)
            
            // Content
            TabView(selection: $currentStep) {
                welcomeStep.tag(OnboardingStep.welcome)
                featuresStep.tag(OnboardingStep.features)
                howItWorksStep.tag(OnboardingStep.howItWorks)
                permissionStep.tag(OnboardingStep.permission)
            }
            .tabViewStyle(.automatic)
            .animation(.easeInOut(duration: 0.3), value: currentStep)
            
            // Navigation
            HStack {
                if currentStep != .welcome {
                    Button(L.back) {
                        withAnimation {
                            if let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) {
                                currentStep = prev
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if currentStep == .permission {
                    Button(action: onComplete) {
                        Text(L.startMemento)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button(action: nextStep) {
                        HStack {
                            Text(L.next)
                            Image(systemName: "arrow.right")
                        }
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .frame(width: 520, height: 620)
        .onAppear { checkPermission() }
    }
    
    private func nextStep() {
        withAnimation {
            if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
                currentStep = next
            }
        }
    }
    
    // MARK: - Step 1: Welcome
    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            
            Text("Memento")
                .font(.system(size: 42, weight: .bold, design: .rounded))
            
            Text(L.onboardingTagline)
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text(L.onboardingSubtitle)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            Spacer()
            Spacer()
        }
    }
    
    // MARK: - Step 2: Features
    private var featuresStep: some View {
        VStack(spacing: 20) {
            Text(L.onboardingFeatures)
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 30)
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureCard(
                    icon: "magnifyingglass",
                    iconColor: .blue,
                    title: L.featureSearchAll,
                    description: L.featureSearchAllDesc
                )
                
                FeatureCard(
                    icon: "doc.on.clipboard",
                    iconColor: .green,
                    title: L.featureClipboard,
                    description: L.featureClipboardDesc
                )
                
                FeatureCard(
                    icon: "globe",
                    iconColor: .orange,
                    title: L.featureWeb,
                    description: L.featureWebDesc
                )
                
                FeatureCard(
                    icon: "text.cursor",
                    iconColor: .purple,
                    title: L.featureLiveText,
                    description: L.featureLiveTextDesc
                )
                
                FeatureCard(
                    icon: "lock.shield.fill",
                    iconColor: .mint,
                    title: L.featurePrivate,
                    description: L.featurePrivateDesc
                )
            }
            .padding(.horizontal, 30)
            
            Spacer()
        }
    }
    
    // MARK: - Step 3: How it works
    private var howItWorksStep: some View {
        VStack(spacing: 24) {
            Text(L.onboardingHowItWorks)
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 30)
            
            VStack(spacing: 20) {
                StepCard(
                    number: "1",
                    icon: "menubar.arrow.up.rectangle",
                    title: L.howCapture,
                    description: L.howCaptureDesc
                )
                
                StepCard(
                    number: "2",
                    icon: "text.viewfinder",
                    title: L.howOCR,
                    description: L.howOCRDesc
                )
                
                StepCard(
                    number: "3",
                    icon: "timelapse",
                    title: L.howTimeline,
                    description: L.howTimelineDesc
                )
            }
            .padding(.horizontal, 30)
            
            // Tip box
            HStack(spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.howTip)
                        .fontWeight(.semibold)
                    Text(L.howTipDesc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal, 30)
            
            Spacer()
        }
    }
    
    // MARK: - Step 4: Permission
    private var permissionStep: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: hasPermission ? "checkmark.shield.fill" : "shield.fill")
                .font(.system(size: 64))
                .foregroundColor(hasPermission ? .green : .accentColor)
            
            Text(hasPermission ? L.permissionReady : L.permissionNeeded)
                .font(.title)
                .fontWeight(.bold)
            
            if hasPermission {
                Text(L.permissionReadyDesc)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 40)
            } else {
                Text(L.permissionNeededDesc)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 40)
                
                Button(action: openScreenRecordingSettings) {
                    HStack {
                        Image(systemName: "gear")
                        Text(L.openSystemSettings)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                
                Text(L.permissionAdd)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            Spacer()
        }
    }
    
    private func checkPermission() {
        hasPermission = CGPreflightScreenCaptureAccess()
    }
    
    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        
        // Poll for permission change
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if CGPreflightScreenCaptureAccess() {
                hasPermission = true
                timer.invalidate()
            }
        }
    }
}

// MARK: - Feature Card
struct FeatureCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.15))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Step Card
struct StepCard: View {
    let number: String
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 32, height: 32)
                Text(number)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.primary.opacity(0.03))
        .cornerRadius(12)
    }
}

// MARK: - Legacy FeatureRow (kept for compatibility)
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
