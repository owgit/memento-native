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

    /// Value the custom-days field should start from when entering custom
    /// mode, given the currently stored retention. Never widens data loss:
    /// presets seed themselves, ∞ seeds the maximum custom horizon.
    static func seededCustomValue(from stored: Int) -> Int {
        stored == forever ? customRange.upperBound : clampedCustom(stored)
    }
}
