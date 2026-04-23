import Foundation

public struct TimelineFeatureConfiguration: Sendable {
    public let storagePath: String
    public let captureInterval: TimeInterval

    public init(storagePath: String, captureInterval: TimeInterval) {
        self.storagePath = storagePath
        self.captureInterval = captureInterval
    }
}

@MainActor
public enum TimelineFeatureRuntime {
    private static var configurationProvider: (@MainActor () -> TimelineFeatureConfiguration)?

    public static func configure(
        configurationProvider: @escaping @MainActor () -> TimelineFeatureConfiguration
    ) {
        self.configurationProvider = configurationProvider
    }

    public static func clearConfiguration() {
        configurationProvider = nil
    }

    static var currentConfiguration: TimelineFeatureConfiguration? {
        configurationProvider?()
    }
}
