import SwiftUI
import TimelineFeature

@main
struct MementoTimelineApp: App {
    @StateObject private var timelineManager = TimelineManager()

    init() {
        TimelineFeatureRuntime.configure {
            TimelineFeatureConfiguration(
                storagePath: Self.resolveLegacyStoragePath(),
                captureInterval: Self.resolveLegacyCaptureInterval()
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(timelineManager)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1400, height: 900)
    }

    private static func resolveLegacyStoragePath() -> String {
        if let captureDefaults = UserDefaults(suiteName: "com.memento.capture"),
           let path = captureDefaults.string(forKey: "storagePath"),
           !path.isEmpty {
            return path
        }

        if let captureDomain = UserDefaults.standard.persistentDomain(forName: "com.memento.capture"),
           let path = captureDomain["storagePath"] as? String,
           !path.isEmpty {
            return path
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/memento").path
    }

    private static func resolveLegacyCaptureInterval() -> TimeInterval {
        if let captureDefaults = UserDefaults(suiteName: "com.memento.capture"),
           let value = captureDefaults.object(forKey: "captureInterval") as? Double,
           value > 0 {
            return value
        }

        if let captureDomain = UserDefaults.standard.persistentDomain(forName: "com.memento.capture"),
           let value = captureDomain["captureInterval"] as? Double,
           value > 0 {
            return value
        }

        return 2.0
    }
}
