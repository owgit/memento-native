import Foundation

enum AppVersionInfo {
    private static var infoDictionary: [String: Any] {
        Bundle.main.infoDictionary ?? [:]
    }

    static var shortVersion: String {
        infoDictionary["CFBundleShortVersionString"] as? String ?? "?"
    }

    static var buildVersion: String {
        infoDictionary["CFBundleVersion"] as? String ?? "?"
    }

    static var displayVersion: String {
        "\(shortVersion) (\(buildVersion))"
    }
}

enum StorageMetrics {
    static func totalBytes(in directoryURL: URL) -> Int64? {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return nil
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }

        return totalSize
    }
}
