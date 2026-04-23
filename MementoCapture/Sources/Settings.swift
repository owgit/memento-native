import Foundation
import ServiceManagement

/// App settings stored in UserDefaults
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()
    
    private let defaults = AppVersionInfo.sharedDefaults
    private var isSynchronizingAutoStart = false
    // Preserve legacy exclusion defaults for users who still run the standalone timeline host.
    private static let legacyStandaloneTimelineNames = ["Memento Timeline", "MementoTimeline"]
    
    // Keys
    private enum Key: String {
        case captureInterval = "captureInterval"
        case clipboardMonitoring = "clipboardMonitoring"
        case autoStart = "autoStart"
        case retentionDays = "retentionDays"
        case excludedApps = "excludedApps"
        case storagePath = "storagePath"
        case pauseWhenIdle = "pauseWhenIdle"
        case idleThresholdSeconds = "idleThresholdSeconds"
        case pauseDuringVideo = "pauseDuringVideo"
        case pauseDuringPrivateBrowsing = "pauseDuringPrivateBrowsing"
    }
    
    // MARK: - Published Properties
    
    @Published var captureInterval: Double {
        didSet { defaults.set(captureInterval, forKey: Key.captureInterval.rawValue) }
    }

    @Published var pauseWhenIdle: Bool {
        didSet { defaults.set(pauseWhenIdle, forKey: Key.pauseWhenIdle.rawValue) }
    }

    @Published var idleThresholdSeconds: Double {
        didSet { defaults.set(idleThresholdSeconds, forKey: Key.idleThresholdSeconds.rawValue) }
    }

    @Published var pauseDuringVideo: Bool {
        didSet { defaults.set(pauseDuringVideo, forKey: Key.pauseDuringVideo.rawValue) }
    }

    @Published var pauseDuringPrivateBrowsing: Bool {
        didSet { defaults.set(pauseDuringPrivateBrowsing, forKey: Key.pauseDuringPrivateBrowsing.rawValue) }
    }
    
    @Published var clipboardMonitoring: Bool {
        didSet { 
            defaults.set(clipboardMonitoring, forKey: Key.clipboardMonitoring.rawValue)
            ClipboardCapture.shared.isEnabled = clipboardMonitoring
        }
    }
    
    @Published var autoStart: Bool {
        didSet { 
            guard !isSynchronizingAutoStart else {
                return
            }

            persistAutoStartPreference(autoStart)
        }
    }
    
    @Published var retentionDays: Int {
        didSet { defaults.set(retentionDays, forKey: Key.retentionDays.rawValue) }
    }
    
    @Published var excludedApps: [String] {
        didSet { defaults.set(excludedApps, forKey: Key.excludedApps.rawValue) }
    }
    
    @Published var storagePath: String {
        didSet { defaults.set(storagePath, forKey: Key.storagePath.rawValue) }
    }
    
    // MARK: - Init
    
    private init() {
        let defaultPath = AppVersionInfo.defaultStoragePath
        let storedAutoStart = defaults.bool(forKey: Key.autoStart.rawValue)
        
        // Load from UserDefaults with defaults
        self.captureInterval = defaults.object(forKey: Key.captureInterval.rawValue) as? Double ?? 2.0
        self.pauseWhenIdle = defaults.object(forKey: Key.pauseWhenIdle.rawValue) as? Bool ?? true
        self.idleThresholdSeconds = defaults.object(forKey: Key.idleThresholdSeconds.rawValue) as? Double ?? 90.0
        self.pauseDuringVideo = defaults.object(forKey: Key.pauseDuringVideo.rawValue) as? Bool ?? true
        self.pauseDuringPrivateBrowsing = defaults.object(forKey: Key.pauseDuringPrivateBrowsing.rawValue) as? Bool ?? true
        self.clipboardMonitoring = defaults.bool(forKey: Key.clipboardMonitoring.rawValue)
        self.autoStart = Self.resolveAutoStartPreference(defaultsValue: storedAutoStart)
        self.retentionDays = defaults.object(forKey: Key.retentionDays.rawValue) as? Int ?? 7
        self.excludedApps = defaults.stringArray(forKey: Key.excludedApps.rawValue) ?? Self.legacyStandaloneTimelineNames
        if AppVersionInfo.isAppStoreDistribution {
            self.storagePath = defaultPath
            defaults.set(defaultPath, forKey: Key.storagePath.rawValue)
        } else {
            self.storagePath = defaults.string(forKey: Key.storagePath.rawValue) ?? defaultPath
        }

        // Ensure clipboard capture state is restored on app launch.
        ClipboardCapture.shared.isEnabled = self.clipboardMonitoring

        reconcileAutoStartRegistrationIfNeeded()
    }

    var usesSystemManagedAutoStart: Bool { true }

    var supportsCustomStorageLocation: Bool {
        !AppVersionInfo.isAppStoreDistribution
    }
    
    // MARK: - Legacy LaunchAgent cleanup

    private func cleanupLegacyLaunchAgent() {
        let plistURL = DirectAutoStartRegistration.launchAgentURL()
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return }
        try? FileManager.default.removeItem(at: plistURL)
        AppLog.info("🧹 Removed legacy LaunchAgent plist")
    }

    private func persistAutoStartPreference(_ enabled: Bool) {
        do {
            try updateAutoStartRegistration(enabled: enabled)
            defaults.set(enabled, forKey: Key.autoStart.rawValue)
        } catch {
            AppLog.error("❌ Could not update auto-start preference: \(error.localizedDescription)")
            revertAutoStartPreference(to: !enabled)
        }
    }

    private func updateAutoStartRegistration(enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
        AppLog.info("ℹ️ Main app login-item status: \(String(describing: service.status))")

        cleanupLegacyLaunchAgent()
    }

    private func reconcileAutoStartRegistrationIfNeeded() {
        guard autoStart else {
            return
        }

        do {
            try updateAutoStartRegistration(enabled: true)
        } catch {
            AppLog.error("❌ Could not reconcile auto-start registration: \(error.localizedDescription)")
        }
    }

    private func revertAutoStartPreference(to value: Bool) {
        isSynchronizingAutoStart = true
        autoStart = value
        defaults.set(value, forKey: Key.autoStart.rawValue)
        isSynchronizingAutoStart = false
    }

    private static func resolveAutoStartPreference(defaultsValue: Bool) -> Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return defaultsValue
        }
    }
    
    // MARK: - Helpers
    
    func isAppExcluded(_ appName: String) -> Bool {
        excludedApps.contains { appName.localizedCaseInsensitiveContains($0) }
    }

    private static func normalizedExcludedAppName(_ app: String) -> String {
        app
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
    
    func addExcludedApp(_ app: String) {
        let trimmed = app.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalizedCandidate = Self.normalizedExcludedAppName(trimmed)
        guard !excludedApps.contains(where: { Self.normalizedExcludedAppName($0) == normalizedCandidate }) else {
            return
        }

        excludedApps.append(trimmed)
    }
    
    func removeExcludedApp(_ app: String) {
        excludedApps.removeAll { $0 == app }
    }

    func updateStoragePath(_ newPath: String) async throws -> StorageMigrator.Result {
        guard supportsCustomStorageLocation else {
            throw NSError(
                domain: "Settings",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Custom storage locations are disabled for the App Store build."]
            )
        }

        let normalized = URL(fileURLWithPath: newPath).standardizedFileURL.path
        guard !normalized.isEmpty else { return StorageMigrator.Result() }
        guard normalized != storagePath else { return StorageMigrator.Result() }

        let result = try await CaptureService.shared.switchStoragePath(to: URL(fileURLWithPath: normalized))
        storagePath = normalized
        return result
    }
    
    var storageURL: URL {
        URL(fileURLWithPath: storagePath)
    }
}
