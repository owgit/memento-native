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

    static var distributionChannel: String {
        (infoDictionary["MementoDistributionChannel"] as? String ?? "direct").lowercased()
    }

    static var appGroupIdentifier: String? {
        guard let rawValue = infoDictionary["MementoAppGroupIdentifier"] as? String else {
            return nil
        }
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    static var isAppStoreDistribution: Bool {
        if distributionChannel == "app-store" {
            return true
        }

        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            return false
        }

        return receiptURL.lastPathComponent == "receipt"
            && FileManager.default.fileExists(atPath: receiptURL.path)
    }

    static var sharedDefaults: UserDefaults {
        if let appGroupIdentifier,
           let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            return defaults
        }

        return UserDefaults.standard
    }

    static var defaultStoragePath: String {
        if let appGroupIdentifier,
           let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
           ) {
            return containerURL.appendingPathComponent("MementoData", isDirectory: true).path
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/memento").path
    }
}

enum StorageMetrics {
    private struct CacheEntry {
        let bytes: Int64
        let computedAt: Date
    }

    @MainActor private static var cache: [String: CacheEntry] = [:]
    private static let cacheTTL: TimeInterval = 5 * 60

    /// Cached, off-main-thread directory size. Safe to call from UI code.
    @MainActor
    static func totalBytes(in directoryURL: URL, bypassCache: Bool = false) async -> Int64? {
        let key = directoryURL.standardizedFileURL.path
        if !bypassCache,
           let entry = cache[key],
           Date().timeIntervalSince(entry.computedAt) < cacheTTL {
            return entry.bytes
        }

        let measured = await Task.detached(priority: .utility) {
            walkTotalBytes(in: directoryURL)
        }.value

        if let measured {
            cache[key] = CacheEntry(bytes: measured, computedAt: Date())
        }
        return measured
    }

    @MainActor
    static func invalidateCache() {
        cache.removeAll()
    }

    /// Synchronous full directory walk. NEVER call on the main thread for real
    /// storage directories — 100k+ files take 10+ seconds (measured).
    nonisolated static func walkTotalBytes(in directoryURL: URL) -> Int64? {
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
