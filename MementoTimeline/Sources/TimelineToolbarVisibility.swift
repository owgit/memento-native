struct TimelineToolbarVisibility {
    private(set) var isToolbarVisible: Bool
    private(set) var isManuallyHidden: Bool

    init(isToolbarVisible: Bool = true, isManuallyHidden: Bool = false) {
        self.isToolbarVisible = isManuallyHidden ? false : isToolbarVisible
        self.isManuallyHidden = isManuallyHidden
    }

    var shouldShowRevealButton: Bool {
        isManuallyHidden && !isToolbarVisible
    }

    mutating func hideManually() {
        isToolbarVisible = false
        isManuallyHidden = true
    }

    mutating func showManually() {
        isToolbarVisible = true
        isManuallyHidden = false
    }

    mutating func showTemporarily() {
        guard !isManuallyHidden else { return }
        isToolbarVisible = true
    }

    mutating func hideAutomatically() {
        guard !isManuallyHidden else { return }
        isToolbarVisible = false
    }
}
