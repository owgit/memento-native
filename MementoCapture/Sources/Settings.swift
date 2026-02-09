import Foundation

/// App settings stored in UserDefaults
@MainActor
class Settings: ObservableObject {
    static let shared = Settings()
    
    private let defaults = UserDefaults.standard
    
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
            defaults.set(autoStart, forKey: Key.autoStart.rawValue)
            updateLaunchAgent()
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
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/memento").path
        
        // Load from UserDefaults with defaults
        self.captureInterval = defaults.object(forKey: Key.captureInterval.rawValue) as? Double ?? 2.0
        self.pauseWhenIdle = defaults.object(forKey: Key.pauseWhenIdle.rawValue) as? Bool ?? true
        self.idleThresholdSeconds = defaults.object(forKey: Key.idleThresholdSeconds.rawValue) as? Double ?? 90.0
        self.pauseDuringVideo = defaults.object(forKey: Key.pauseDuringVideo.rawValue) as? Bool ?? true
        self.pauseDuringPrivateBrowsing = defaults.object(forKey: Key.pauseDuringPrivateBrowsing.rawValue) as? Bool ?? true
        self.clipboardMonitoring = defaults.bool(forKey: Key.clipboardMonitoring.rawValue)
        self.autoStart = defaults.bool(forKey: Key.autoStart.rawValue)
        self.retentionDays = defaults.object(forKey: Key.retentionDays.rawValue) as? Int ?? 7
        self.excludedApps = defaults.stringArray(forKey: Key.excludedApps.rawValue) ?? ["Memento Timeline", "MementoTimeline"]
        self.storagePath = defaults.string(forKey: Key.storagePath.rawValue) ?? defaultPath

        // Ensure clipboard capture state is restored on app launch.
        ClipboardCapture.shared.isEnabled = self.clipboardMonitoring
    }
    
    // MARK: - LaunchAgent
    
    private func updateLaunchAgent() {
        let launchAgentPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.memento.capture.plist")
        
        if autoStart {
            // Create LaunchAgent plist
            let plist: [String: Any] = [
                "Label": "com.memento.capture",
                "ProgramArguments": ["/Applications/Memento Capture.app/Contents/MacOS/memento-capture"],
                "RunAtLoad": true,
                "KeepAlive": false
            ]
            
            try? FileManager.default.createDirectory(
                at: launchAgentPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            (plist as NSDictionary).write(to: launchAgentPath, atomically: true)
            print("✅ LaunchAgent created")
        } else {
            // Remove LaunchAgent
            try? FileManager.default.removeItem(at: launchAgentPath)
            print("✅ LaunchAgent removed")
        }
    }
    
    // MARK: - Helpers
    
    func isAppExcluded(_ appName: String) -> Bool {
        excludedApps.contains { appName.localizedCaseInsensitiveContains($0) }
    }
    
    func addExcludedApp(_ app: String) {
        if !excludedApps.contains(app) {
            excludedApps.append(app)
        }
    }
    
    func removeExcludedApp(_ app: String) {
        excludedApps.removeAll { $0 == app }
    }

    func updateStoragePath(_ newPath: String) throws -> StorageMigrator.Result {
        let normalized = URL(fileURLWithPath: newPath).standardizedFileURL.path
        guard !normalized.isEmpty else { return StorageMigrator.Result() }
        guard normalized != storagePath else { return StorageMigrator.Result() }

        let result = try CaptureService.shared.switchStoragePath(to: URL(fileURLWithPath: normalized))
        storagePath = normalized
        return result
    }
    
    var storageURL: URL {
        URL(fileURLWithPath: storagePath)
    }
}
