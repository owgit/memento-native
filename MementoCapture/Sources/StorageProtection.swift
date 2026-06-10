import Foundation

/// Hardens the storage directory: restrictive permissions and optional
/// Time Machine backup exclusion. All functions log-and-continue on failure
/// (e.g. exFAT volumes without POSIX permission support).
enum StorageProtection {
    /// Restrict the storage directory to the current user (rwx------).
    static func applyDirectoryPermissions(to url: URL) {
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: url.path
            )
        } catch {
            AppLog.warning("⚠️ Could not restrict storage permissions: \(error.localizedDescription)")
        }
    }

    /// Include or exclude the storage directory from Time Machine backups.
    static func setExcludedFromBackup(_ excluded: Bool, on url: URL) {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = excluded
        do {
            try mutableURL.setResourceValues(values)
        } catch {
            AppLog.warning("⚠️ Could not update backup exclusion: \(error.localizedDescription)")
        }
    }
}
