import SwiftUI
import AppKit
import TimelineFeature

@MainActor
final class TimelineWindowController {
    static let shared = TimelineWindowController()

    private var window: NSWindow?
    private var timelineManager: TimelineManager?
    private var configuredStoragePath: String?
    private var windowCloseObserver: NSObjectProtocol?
    private let isSwedish = Locale.preferredLanguages.first?.hasPrefix("sv") == true
    private let preferredContentSize = NSSize(width: 1280, height: 800)
    private let contentAspectRatio: CGFloat = 16.0 / 10.0

    private func activate(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async { [weak window] in
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func resetWindowState() {
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
            self.windowCloseObserver = nil
        }

        window = nil
        timelineManager = nil
        configuredStoragePath = nil
    }

    func show() {
        TimelineFeatureRuntime.configure {
            TimelineFeatureConfiguration(
                storagePath: Settings.shared.storagePath,
                captureInterval: Settings.shared.captureInterval
            )
        }

        let manager = resolveTimelineManager()
        seedLatestCaptureIfAvailable(into: manager)

        if let existingWindow = window {
            if timelineManager === manager {
                configureTimelineChrome(for: existingWindow, shouldCenter: false)
                activate(existingWindow)
                return
            }

            let rootView = TimelineHostView(manager: manager)
            if let hostingController = existingWindow.contentViewController as? NSHostingController<TimelineHostView> {
                hostingController.rootView = rootView
            } else {
                existingWindow.contentViewController = NSHostingController(rootView: rootView)
            }

            configureTimelineChrome(for: existingWindow, shouldCenter: false)
            activate(existingWindow)
            return
        }

        let rootView = TimelineHostView(manager: manager)
        let hostingController = NSHostingController(rootView: rootView)
        let newWindow = NSWindow(contentViewController: hostingController)
        configureTimelineChrome(for: newWindow, shouldCenter: true)

        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
            self.windowCloseObserver = nil
        }
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resetWindowState()
            }
        }

        window = newWindow
        activate(newWindow)
    }

    private func seedLatestCaptureIfAvailable(into manager: TimelineManager) {
        guard let image = CaptureService.shared.lastCapturedImage else { return }

        manager.seedStartupFrame(
            NSImage(
                cgImage: image,
                size: NSSize(width: image.width, height: image.height)
            )
        )
    }

    private func configureTimelineChrome(for window: NSWindow, shouldCenter: Bool) {
        let contentSize = timelineContentSize(for: window.screen)

        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.title = isSwedish ? "Tidslinje" : "Timeline"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.fullScreenNone]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.minSize = contentSize
        window.maxSize = contentSize
        window.setContentSize(contentSize)

        if shouldCenter {
            window.center()
        }

        hideStandardChrome(for: window)
    }

    private func timelineContentSize(for screen: NSScreen?) -> NSSize {
        let visibleFrame = (screen ?? NSScreen.main)?.visibleFrame
        let widthLimit = visibleFrame.map { $0.width * 0.90 } ?? preferredContentSize.width
        let heightLimit = visibleFrame.map { $0.height * 0.84 } ?? preferredContentSize.height
        let maxWidth = min(preferredContentSize.width, widthLimit)
        let maxHeight = min(preferredContentSize.height, heightLimit)
        let fittedWidth = min(maxWidth, maxHeight * contentAspectRatio)

        return NSSize(
            width: floor(fittedWidth),
            height: floor(fittedWidth / contentAspectRatio)
        )
    }

    private func hideStandardChrome(for window: NSWindow) {
        let buttonTypes: [NSWindow.ButtonType] = [
            .closeButton,
            .miniaturizeButton,
            .zoomButton
        ]

        for type in buttonTypes {
            window.standardWindowButton(type)?.isHidden = true
        }
    }

    private func resolveTimelineManager() -> TimelineManager {
        let currentStoragePath = Settings.shared.storagePath

        if let timelineManager,
           configuredStoragePath == currentStoragePath {
            return timelineManager
        }

        let manager = TimelineManager()
        timelineManager = manager
        configuredStoragePath = currentStoragePath
        return manager
    }
}

private struct TimelineHostView: View {
    @ObservedObject var manager: TimelineManager

    var body: some View {
        ContentView()
            .environmentObject(manager)
            .frame(minWidth: 800, minHeight: 500)
    }
}
