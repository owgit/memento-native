import Foundation

enum StorageMigrationError: LocalizedError {
    case destinationInsideSource

    var errorDescription: String? {
        switch self {
        case .destinationInsideSource:
            return "Destination folder cannot be inside the current storage folder."
        }
    }
}

/// Moves existing storage data to a new folder while preserving all files.
enum StorageMigrator {
    struct Result {
        var movedItems: Int = 0
        var copiedItems: Int = 0
        var conflictRenames: Int = 0
        var skippedItems: Int = 0
    }

    static func migrateDirectory(from source: URL, to destination: URL) throws -> Result {
        let sourceURL = source.standardizedFileURL
        let destinationURL = destination.standardizedFileURL

        guard sourceURL.path != destinationURL.path else { return Result() }

        if isSubpath(destinationURL, of: sourceURL) {
            throw StorageMigrationError.destinationInsideSource
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return Result()
        }

        var result = Result()
        try migrateContents(from: sourceURL, to: destinationURL, result: &result)

        // Remove empty source directory after migration.
        if let remaining = try? fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil),
           remaining.isEmpty {
            try? fileManager.removeItem(at: sourceURL)
        }

        return result
    }

    private static func migrateContents(from sourceDir: URL, to destinationDir: URL, result: inout Result) throws {
        let fileManager = FileManager.default
        let items = try fileManager.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])

        for sourceItem in items {
            let destinationItem = destinationDir.appendingPathComponent(sourceItem.lastPathComponent)

            if !fileManager.fileExists(atPath: destinationItem.path) {
                try moveOrCopyAndRemove(source: sourceItem, destination: destinationItem, result: &result)
                continue
            }

            var sourceIsDirectory: ObjCBool = false
            var destinationIsDirectory: ObjCBool = false
            fileManager.fileExists(atPath: sourceItem.path, isDirectory: &sourceIsDirectory)
            fileManager.fileExists(atPath: destinationItem.path, isDirectory: &destinationIsDirectory)

            if sourceIsDirectory.boolValue && destinationIsDirectory.boolValue {
                try migrateContents(from: sourceItem, to: destinationItem, result: &result)
                if let remaining = try? fileManager.contentsOfDirectory(at: sourceItem, includingPropertiesForKeys: nil),
                   remaining.isEmpty {
                    try? fileManager.removeItem(at: sourceItem)
                }
                continue
            }

            if !sourceIsDirectory.boolValue && !destinationIsDirectory.boolValue && filesLikelyEqual(sourceItem, destinationItem) {
                result.skippedItems += 1
                try? fileManager.removeItem(at: sourceItem)
                continue
            }

            let renamedTarget = uniqueConflictURL(for: sourceItem.lastPathComponent, in: destinationDir)
            result.conflictRenames += 1
            try moveOrCopyAndRemove(source: sourceItem, destination: renamedTarget, result: &result)
        }
    }

    private static func moveOrCopyAndRemove(source: URL, destination: URL, result: inout Result) throws {
        let fileManager = FileManager.default
        do {
            try fileManager.moveItem(at: source, to: destination)
            result.movedItems += 1
        } catch {
            try fileManager.copyItem(at: source, to: destination)
            try? fileManager.removeItem(at: source)
            result.copiedItems += 1
        }
    }

    private static func filesLikelyEqual(_ lhs: URL, _ rhs: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.fileSizeKey]
        let lhsSize = try? lhs.resourceValues(forKeys: keys).fileSize
        let rhsSize = try? rhs.resourceValues(forKeys: keys).fileSize
        return lhsSize != nil && lhsSize == rhsSize
    }

    private static func uniqueConflictURL(for filename: String, in directory: URL) -> URL {
        let fileManager = FileManager.default
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var index = 1

        while true {
            let candidateName: String
            if ext.isEmpty {
                candidateName = "\(base)-migrated-\(index)"
            } else {
                candidateName = "\(base)-migrated-\(index).\(ext)"
            }
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private static func isSubpath(_ child: URL, of parent: URL) -> Bool {
        let childComponents = child.standardizedFileURL.pathComponents
        let parentComponents = parent.standardizedFileURL.pathComponents
        guard childComponents.count >= parentComponents.count else { return false }
        return Array(childComponents.prefix(parentComponents.count)) == parentComponents
    }
}

