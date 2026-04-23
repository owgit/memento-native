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

        if let existingWindow = window {
            if timelineManager === manager {
                activate(existingWindow)
                return
            }

            let rootView = TimelineHostView(manager: manager)
            if let hostingController = existingWindow.contentViewController as? NSHostingController<TimelineHostView> {
                hostingController.rootView = rootView
            } else {
                existingWindow.contentViewController = NSHostingController(rootView: rootView)
            }

            activate(existingWindow)
            return
        }

        let rootView = TimelineHostView(manager: manager)
        let hostingController = NSHostingController(rootView: rootView)
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = isSwedish ? "Tidslinje" : "Timeline"
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.titleVisibility = .hidden
        newWindow.titlebarAppearsTransparent = true
        newWindow.tabbingMode = .disallowed
        newWindow.isReleasedWhenClosed = false
        newWindow.minSize = NSSize(width: 800, height: 500)
        newWindow.setContentSize(NSSize(width: 1400, height: 900))
        newWindow.setFrameAutosaveName("TimelineWindow")
        newWindow.center()

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
