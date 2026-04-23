import AppKit
import Foundation

@MainActor
enum LegacyTimelineMigration {
    private static var legacyAppCandidateURLs: [URL] {
        let fileManager = FileManager.default
        return [
            URL(fileURLWithPath: "/Applications/Memento Timeline.app"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Memento Timeline.app")
        ]
    }

    private static var existingLegacyAppURLs: [URL] {
        legacyAppCandidateURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static var hasLegacyTimelineApp: Bool {
        !existingLegacyAppURLs.isEmpty
    }

    static var existingLegacyAppDisplayPaths: [String] {
        existingLegacyAppURLs.map { ($0.path as NSString).abbreviatingWithTildeInPath }
    }

    static var shouldPrompt: Bool {
        hasLegacyTimelineApp
    }

    static func showPromptIfNeeded() {
        let legacyAppURLs = existingLegacyAppURLs
        guard !legacyAppURLs.isEmpty else { return }

        guard shouldPrompt else { return }

        AppLog.info("ℹ️ Found legacy standalone Timeline app: \(legacyAppURLs.map { $0.path }.joined(separator: ", "))")
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L.legacyTimelineMigrationTitle
        alert.informativeText = L.legacyTimelineMigrationMessage(legacyAppURLs.map { ($0.path as NSString).abbreviatingWithTildeInPath })
        alert.addButton(withTitle: L.removeOldTimelineApp)
        alert.addButton(withTitle: L.openTimelineNow)
        alert.addButton(withTitle: L.keepForNow)

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            _ = moveLegacyAppsToTrash(legacyAppURLs)
        case .alertSecondButtonReturn:
            AppLog.info("ℹ️ User opened Timeline from legacy cleanup prompt")
            TimelineWindowController.shared.show()
        case .alertThirdButtonReturn:
            AppLog.info("ℹ️ User kept legacy Timeline app for now")
        default:
            AppLog.info("ℹ️ User dismissed legacy Timeline cleanup prompt")
        }
    }

    @discardableResult
    static func moveExistingLegacyAppsToTrash() -> Bool {
        moveLegacyAppsToTrash(existingLegacyAppURLs)
    }

    static func revealExistingLegacyApps() {
        revealLegacyApps(existingLegacyAppURLs)
    }

    @discardableResult
    private static func moveLegacyAppsToTrash(_ urls: [URL]) -> Bool {
        let fileManager = FileManager.default
        var failedURLs: [URL] = []
        var lastError: Error?

        for url in urls {
            do {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
            } catch {
                failedURLs.append(url)
                lastError = error
            }
        }

        guard failedURLs.isEmpty else {
            AppLog.warning("⚠️ Could not move legacy Timeline app to Trash: \(lastError?.localizedDescription ?? "Unknown error")")
            showCleanupFailedAlert(urls: failedURLs, error: lastError ?? NSError(domain: "LegacyTimelineMigration", code: 1))
            return false
        }

        if !urls.isEmpty {
            AppLog.info("✅ Moved legacy Timeline app to Trash")
        }

        return true
    }

    private static func revealLegacyApps(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private static func showCleanupFailedAlert(urls: [URL], error: Error) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L.legacyTimelineCleanupFailedTitle
        alert.informativeText = L.legacyTimelineCleanupFailedMessage(
            urls.map { ($0.path as NSString).abbreviatingWithTildeInPath },
            error.localizedDescription
        )
        alert.addButton(withTitle: L.showInFinder)
        alert.addButton(withTitle: L.ok)

        if alert.runModal() == .alertFirstButtonReturn {
            revealLegacyApps(urls)
        }
    }

}
