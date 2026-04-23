import Foundation

enum AppRuntimeInfo {
    private static var infoDictionary: [String: Any] {
        Bundle.main.infoDictionary ?? [:]
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

    static var sharedDefaults: UserDefaults {
        if let appGroupIdentifier,
           let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            return defaults
        }

        return UserDefaults.standard
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
