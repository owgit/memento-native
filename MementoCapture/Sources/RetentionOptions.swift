import Foundation

/// Maps between the retention presets and the custom-days field in Settings.
/// `Settings.retentionDays` stays a plain Int; 9999 is the legacy ∞ sentinel.
enum RetentionOptions {
    static let presets: [Int] = [1, 3, 7, 14, 30]
    static let forever = 9999
    static let customRange = 1...365

    /// The sentinel used by the picker UI for the "Custom…" row.
    static let customPickerTag = -1

    static func isPreset(_ days: Int) -> Bool {
        presets.contains(days) || days == forever
    }

    static func clampedCustom(_ days: Int) -> Int {
        min(max(days, customRange.lowerBound), customRange.upperBound)
    }
}
