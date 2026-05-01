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

            if let hostingController = existingWindow.contentViewController as? NSHostingController<TimelineHostView> {
                hostingController.rootView = TimelineHostView(manager: manager)
                Self.configureTimelineHostingController(hostingController)
            } else {
                existingWindow.contentViewController = Self.makeTimelineHostingController(manager: manager)
            }

            configureTimelineChrome(for: existingWindow, shouldCenter: false)
            activate(existingWindow)
            return
        }

        let hostingController = Self.makeTimelineHostingController(manager: manager)
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

    static func makeTimelineHostingController(manager: TimelineManager) -> NSHostingController<TimelineHostView> {
        let hostingController = NSHostingController(rootView: TimelineHostView(manager: manager))
        configureTimelineHostingController(hostingController)
        return hostingController
    }

    private static func configureTimelineHostingController(_ hostingController: NSHostingController<TimelineHostView>) {
        hostingController.sizingOptions = [.minSize]
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

        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = isSwedish ? "Tidslinje" : "Timeline"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.fullScreenPrimary]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 800, height: 500)
        window.contentAspectRatio = contentSize
        window.setContentSize(contentSize)

        if shouldCenter {
            window.center()
        }

        placeStandardWindowButtons(in: window)
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

    private func placeStandardWindowButtons(in window: NSWindow) {
        guard let contentView = window.contentView else { return }

        let constraintPrefix = "memento.timeline.windowButton."
        let existingConstraints = contentView.constraints.filter {
            $0.identifier?.hasPrefix(constraintPrefix) == true
        }
        contentView.removeConstraints(existingConstraints)

        let buttonTypes: [NSWindow.ButtonType] = [
            .closeButton,
            .miniaturizeButton,
            .zoomButton
        ]
        let leadingInset: CGFloat = 22
        let topInset: CGFloat = 16
        let spacing: CGFloat = 20

        for (index, type) in buttonTypes.enumerated() {
            guard let button = window.standardWindowButton(type) else { continue }

            button.isHidden = false
            button.alphaValue = 1
            button.translatesAutoresizingMaskIntoConstraints = false

            if button.superview !== contentView {
                button.removeFromSuperview()
                contentView.addSubview(button)
            }

            let leading = button.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: leadingInset + CGFloat(index) * spacing
            )
            leading.identifier = "\(constraintPrefix)\(index).leading"

            let top = button.topAnchor.constraint(equalTo: contentView.topAnchor, constant: topInset)
            top.identifier = "\(constraintPrefix)\(index).top"

            NSLayoutConstraint.activate([leading, top])
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

struct TimelineHostView: View {
    @ObservedObject var manager: TimelineManager

    var body: some View {
        ContentView()
            .environmentObject(manager)
            .frame(minWidth: 800, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
    }
}
