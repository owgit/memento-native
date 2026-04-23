import Foundation

/// Simple localization - detects system language
enum L {
    static let isSwedish: Bool = {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return lang == "sv"
    }()
    
    // MARK: - Menu
    static var openTimeline: String { isSwedish ? "Öppna Timeline" : "Open Timeline" }
    static var permissionMissingStatus: String { isSwedish ? "⚠ Behörighet för skärminspelning saknas" : "⚠ Screen Recording permission missing" }
    static var statistics: String { isSwedish ? "Statistik..." : "Statistics..." }
    static var cleanOldFrames: String { isSwedish ? "Rensa gamla frames..." : "Clean Old Frames..." }
    static var saveDebugScreenshot: String { isSwedish ? "Spara debug-skärmdump" : "Save Debug Screenshot" }
    static var advancedMenu: String { isSwedish ? "Avancerat" : "Advanced" }
    static var quitMemento: String { isSwedish ? "Avsluta Memento" : "Quit Memento" }
    static var settingsMenu: String { isSwedish ? "Inställningar..." : "Settings..." }
    static var chipRecording: String { isSwedish ? "Spelar in" : "Recording" }
    static var chipPaused: String { isSwedish ? "Pausad" : "Paused" }
    static var chipRecordingTiny: String { isSwedish ? "Rec" : "Rec" }
    static var chipPausedTiny: String { isSwedish ? "Paus" : "Pause" }
    static var chipPermissionMissingShort: String { isSwedish ? "Saknas" : "Missing" }
    static var chipPermissionOkTiny: String { "OK" }
    static var chipLastCaptureNoneShort: String { isSwedish ? "Ingen" : "None" }
    static var chipLastCaptureNowShort: String { isSwedish ? "Nu" : "Now" }
    static func chipLastCaptureMinutesShort(_ minutes: Int) -> String { "\(minutes)m" }
    static func chipLastCaptureHoursShort(_ hours: Int) -> String { "\(hours)h" }
    static func chipLastCaptureDaysShort(_ days: Int) -> String { "\(days)d" }
    static var checkForUpdates: String { isSwedish ? "Sök uppdatering..." : "Check for Updates..." }
    static var checkingForUpdates: String { isSwedish ? "Söker uppdatering..." : "Checking for updates..." }
    static func updateAvailableMenu(_ version: String) -> String {
        isSwedish ? "Uppdatering tillgänglig: \(version)" : "Update available: \(version)"
    }
    static var updateAvailableTitle: String { isSwedish ? "Ny version finns" : "New version available" }
    static func updateAvailableMessage(_ local: String, _ remote: String) -> String {
        if isSwedish {
            return "Nuvarande version: \(local)\nNy version: \(remote)"
        }
        return "Current version: \(local)\nNew version: \(remote)"
    }
    static var upToDateTitle: String { isSwedish ? "Du har senaste versionen" : "You're up to date" }
    static func upToDateMessage(_ local: String) -> String {
        isSwedish ? "Du kör redan senaste versionen (\(local))." : "You're already running the latest version (\(local))."
    }
    static var updateCheckFailedTitle: String { isSwedish ? "Kunde inte kontrollera uppdatering" : "Could not check for updates" }
    static var updateCheckFailedMessage: String {
        isSwedish ? "Kontrollera internetanslutningen och försök igen." : "Check your internet connection and try again."
    }
    static var installUpdateNow: String { isSwedish ? "Installera nu" : "Install now" }
    static var installingUpdate: String { isSwedish ? "Installerar uppdatering..." : "Installing update..." }
    static var updateInstallCompleteTitle: String { isSwedish ? "Uppdatering installerad" : "Update installed" }
    static var updateInstallCompleteMessage: String {
        isSwedish
            ? "Den nya versionen är installerad i Applications. Starta om appen för att börja använda den."
            : "The new version is installed in Applications. Restart the app to start using it."
    }
    static var restartNow: String { isSwedish ? "Starta om nu" : "Restart now" }
    static var updateInstallFailedTitle: String { isSwedish ? "Kunde inte installera uppdateringen" : "Could not install update" }
    static var updateInstallFailedMessage: String {
        isSwedish
            ? "Automatisk installation misslyckades. Du kan öppna release-sidan, läsa FAQ och installera manuellt."
            : "Automatic install failed. You can open the release page, check the FAQ, and install manually."
    }
    static var openReleasePage: String { isSwedish ? "Öppna release-sida" : "Open release page" }
    static var openFAQ: String { isSwedish ? "Öppna FAQ" : "Open FAQ" }
    static var later: String { isSwedish ? "Senare" : "Later" }
    static var updateNotificationTitle: String { isSwedish ? "Memento-uppdatering finns" : "Memento update available" }
    static func updateNotificationBody(_ version: String) -> String {
        isSwedish ? "Version \(version) finns att ladda ner." : "Version \(version) is ready to download."
    }
    static var legacyTimelineMigrationTitle: String {
        isSwedish ? "Ta bort gamla Timeline-appen?" : "Remove old Timeline app?"
    }
    static func legacyTimelineMigrationMessage(_ paths: [String]) -> String {
        _ = paths
        if isSwedish {
            return """
            Timeline finns nu i Memento Capture.
            Du kan ta bort den gamla appen utan risk.
            Öppna Timeline via menyradsikonen eller med ⌘T.
            """
        }
        return """
        Timeline now lives inside Memento Capture.
        You can safely remove the old app.
        Open Timeline from the menu bar icon or with ⌘T.
        """
    }
    static var legacyTimelineCleanupFailedTitle: String {
        isSwedish ? "Kunde inte flytta gamla Timeline-appen" : "Could not move old Timeline app"
    }
    static func legacyTimelineCleanupFailedMessage(_ paths: [String], _ reason: String) -> String {
        let joinedPaths = paths.joined(separator: "\n")
        if isSwedish {
            return """
            Memento kunde inte flytta den gamla appen automatiskt.

            \(joinedPaths)

            Orsak: \(reason)
            """
        }
        return """
        Memento could not move the old app automatically.

        \(joinedPaths)

        Reason: \(reason)
        """
    }
    
    // MARK: - Permissions
    // MARK: - Statistics
    static var statisticsTitle: String { isSwedish ? "Memento Statistik" : "Memento Statistics" }
    static var frames: String { isSwedish ? "Frames" : "Frames" }
    static var embeddings: String { isSwedish ? "Embeddings" : "Embeddings" }
    static var disk: String { isSwedish ? "Disk" : "Disk" }
    static var location: String { isSwedish ? "Plats" : "Location" }
    static var openFolder: String { isSwedish ? "Öppna mapp" : "Open Folder" }
    
    // MARK: - Clean
    static var cleanTitle: String { isSwedish ? "Rensa gamla frames" : "Clean Old Frames" }
    static var cleanMessage: String { isSwedish ? "Välj hur gamla frames du vill ta bort:" : "Choose how old frames to remove:" }
    static var olderThan7Days: String { isSwedish ? "Äldre än 7 dagar" : "Older than 7 days" }
    static var olderThan30Days: String { isSwedish ? "Äldre än 30 dagar" : "Older than 30 days" }
    static var deleteAll: String { isSwedish ? "Radera ALLT" : "Delete ALL" }
    static var cleanDone: String { isSwedish ? "Rensning klar" : "Cleanup Complete" }
    static func cleanResult(_ frames: Int, _ videos: Int) -> String {
        isSwedish 
            ? "Raderade \(frames) frames och \(videos) video-filer."
            : "Deleted \(frames) frames and \(videos) video files."
    }
    
    // MARK: - Debug Screenshot
    static var errorTitle: String { isSwedish ? "Fel" : "Error" }
    static var screenshotError: String { isSwedish ? "Kunde inte ta skärmdump. Kontrollera behörigheter." : "Could not take screenshot. Check permissions." }
    static var debugScreenshotSaved: String { isSwedish ? "Debug-skärmdump sparad" : "Debug Screenshot Saved" }
    static func screenshotSavedMessage(_ filePath: String, _ width: Int, _ height: Int) -> String {
        isSwedish
            ? "Bild sparad här:\n\(filePath)\n\nStorlek: \(width)x\(height)"
            : "Image saved here:\n\(filePath)\n\nSize: \(width)x\(height)"
    }
    
    // MARK: - Buttons
    static var ok: String { "OK" }
    static var cancel: String { isSwedish ? "Avbryt" : "Cancel" }
    static var open: String { isSwedish ? "Öppna" : "Open" }
    static var showInFinder: String { isSwedish ? "Visa i Finder" : "Show in Finder" }
    static var moveToTrash: String { isSwedish ? "Flytta till Papperskorgen" : "Move to Trash" }
    static var removeOldTimelineApp: String {
        isSwedish ? "Ta bort gamla appen (Rekommenderas)" : "Remove old app (Recommended)"
    }
    static var openTimelineNow: String { isSwedish ? "Öppna Timeline nu" : "Open Timeline now" }
    static var keepForNow: String { isSwedish ? "Behåll tills vidare" : "Keep for now" }
    static var notNow: String { isSwedish ? "Inte nu" : "Not Now" }
    
    // MARK: - Community
    static var buyMeACoffee: String { isSwedish ? "Bjud på en kaffe" : "Buy me a coffee" }
}
