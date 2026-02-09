import Foundation

/// Simple localization - detects system language
enum L {
    static let isSwedish: Bool = {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return lang == "sv"
    }()
    
    // MARK: - Menu
    static var recording: String { isSwedish ? "● Spelar in" : "● Recording" }
    static var paused: String { isSwedish ? "○ Pausad" : "○ Paused" }
    static var pauseRecording: String { isSwedish ? "Pausa inspelning" : "Pause Recording" }
    static var resumeRecording: String { isSwedish ? "Fortsätt inspelning" : "Resume Recording" }
    static var openTimeline: String { isSwedish ? "Öppna Timeline" : "Open Timeline" }
    static var permissions: String { isSwedish ? "Setup Hub..." : "Setup Hub..." }
    static var permissionMissingStatus: String { isSwedish ? "⚠ Behörighet för skärminspelning saknas" : "⚠ Screen Recording permission missing" }
    static var statistics: String { isSwedish ? "Statistik..." : "Statistics..." }
    static var cleanOldFrames: String { isSwedish ? "Rensa gamla frames..." : "Clean Old Frames..." }
    static var saveDebugScreenshot: String { isSwedish ? "Spara debug-skärmdump" : "Save Debug Screenshot" }
    static var quitMemento: String { isSwedish ? "Avsluta Memento" : "Quit Memento" }
    static var settingsMenu: String { isSwedish ? "Inställningar..." : "Settings..." }
    static var controlCenterTitle: String { isSwedish ? "Control Center" : "Control Center" }
    static var chipRecording: String { isSwedish ? "Spelar in" : "Recording" }
    static var chipPaused: String { isSwedish ? "Pausad" : "Paused" }
    static var chipRecordingShort: String { isSwedish ? "Inspelning" : "Recording" }
    static var chipPausedShort: String { isSwedish ? "Paus" : "Paused" }
    static var chipRecordingTiny: String { isSwedish ? "Rec" : "Rec" }
    static var chipPausedTiny: String { isSwedish ? "Paus" : "Pause" }
    static var chipPermissionShort: String { isSwedish ? "Behörighet" : "Permission" }
    static var chipPermissionMissingShort: String { isSwedish ? "Saknas" : "Missing" }
    static var chipPermissionOkTiny: String { "OK" }
    static var chipPermissionMissing: String { isSwedish ? "Behörighet saknas" : "Permission missing" }
    static var chipPermissionOK: String { isSwedish ? "Behörighet OK" : "Permission OK" }
    static var chipLastCaptureNever: String { isSwedish ? "Senaste: ingen" : "Last: none" }
    static var chipLastCaptureNow: String { isSwedish ? "Senaste: nu" : "Last: now" }
    static var chipLastCaptureNoneShort: String { isSwedish ? "Ingen" : "None" }
    static var chipLastCaptureNowShort: String { isSwedish ? "Nu" : "Now" }
    static func chipLastCaptureMinutesShort(_ minutes: Int) -> String { "\(minutes)m" }
    static func chipLastCaptureHoursShort(_ hours: Int) -> String { "\(hours)h" }
    static func chipLastCaptureDaysShort(_ days: Int) -> String { "\(days)d" }
    static func chipLastCaptureMinutes(_ minutes: Int) -> String {
        isSwedish ? "Senaste: \(minutes)m" : "Last: \(minutes)m"
    }
    static func chipLastCaptureHours(_ hours: Int) -> String {
        isSwedish ? "Senaste: \(hours)h" : "Last: \(hours)h"
    }
    static func chipLastCaptureDays(_ days: Int) -> String {
        isSwedish ? "Senaste: \(days)d" : "Last: \(days)d"
    }
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
            ? "Automatisk installation misslyckades. Du kan öppna release-sidan och installera manuellt."
            : "Automatic install failed. You can open the release page and install manually."
    }
    static var openReleasePage: String { isSwedish ? "Öppna release-sida" : "Open release page" }
    static var later: String { isSwedish ? "Senare" : "Later" }
    static var updateNotificationTitle: String { isSwedish ? "Memento-uppdatering finns" : "Memento update available" }
    static func updateNotificationBody(_ version: String) -> String {
        isSwedish ? "Version \(version) finns att ladda ner." : "Version \(version) is ready to download."
    }
    
    // MARK: - Permissions
    static var permissionsOk: String { isSwedish ? "✓ Behörigheter OK" : "✓ Permissions OK" }
    static var permissionsMissing: String { isSwedish ? "⚠ Behörigheter saknas" : "⚠ Permissions Missing" }
    static var permissionsOkTitle: String { isSwedish ? "Behörigheter OK" : "Permissions OK" }
    static var permissionsOkMessage: String { 
        isSwedish 
            ? "Screen Recording-behörighet är beviljad. Appen kan fånga hela skärmen." 
            : "Screen Recording permission granted. App can capture full screen."
    }
    static var permissionsMissingTitle: String { isSwedish ? "Behörighet saknas" : "Permission Missing" }
    static var permissionsMissingMessage: String {
        isSwedish
            ? "Screen Recording-behörighet krävs för att fånga hela skärmen med appar. Utan den fångas bara bakgrundsbilden.\n\nGå till: Systeminställningar > Integritet och säkerhet > Skärminspelning"
            : "Screen Recording permission required to capture full screen with apps. Without it, only the wallpaper is captured.\n\nGo to: System Settings > Privacy & Security > Screen Recording"
    }
    static var openSettings: String { isSwedish ? "Öppna Inställningar" : "Open Settings" }
    
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
    static var clipboardCapture: String { isSwedish ? "Fånga urklipp" : "Capture Clipboard" }
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
    static func screenshotSavedMessage(_ filename: String, _ width: Int, _ height: Int) -> String {
        isSwedish
            ? "Bild sparad på skrivbordet:\n\(filename)\n\nStorlek: \(width)x\(height)"
            : "Image saved to Desktop:\n\(filename)\n\nSize: \(width)x\(height)"
    }
    
    // MARK: - Buttons
    static var ok: String { "OK" }
    static var cancel: String { isSwedish ? "Avbryt" : "Cancel" }
    static var open: String { isSwedish ? "Öppna" : "Open" }
    
    // MARK: - Onboarding
    static var welcomeTitle: String { isSwedish ? "Välkommen till Memento" : "Welcome to Memento" }
    static var memento: String { "Memento" }
    static var tagline: String { isSwedish ? "Din visuella tidsmaskin" : "Your visual time machine" }
    static var featureRecording: String { isSwedish ? "Skärminspelning" : "Screen Recording" }
    static var featureRecordingDesc: String { isSwedish ? "Tar skärmbilder var 2:a sekund" : "Captures screen every 2 seconds" }
    static var featureOCR: String { isSwedish ? "OCR-sökning" : "OCR Search" }
    static var featureOCRDesc: String { isSwedish ? "Sök i all text du sett på skärmen" : "Search all text you've seen on screen" }
    static var featurePrivacy: String { isSwedish ? "100% Lokalt" : "100% Local" }
    static var featurePrivacyDesc: String { isSwedish ? "All data stannar på din Mac" : "All data stays on your Mac" }
    static var featureLowResource: String { isSwedish ? "Låg resursanvändning" : "Low Resource Usage" }
    static var featureLowResourceDesc: String { isSwedish ? "Endast ~1% RAM, minimal CPU" : "Only ~1% RAM, minimal CPU" }
    static var screenRecordingRequired: String { isSwedish ? "Skärminspelning krävs" : "Screen Recording Required" }
    static var openSystemSettings: String { isSwedish ? "Öppna Systeminställningar" : "Open System Settings" }
    static var startMemento: String { isSwedish ? "Starta Memento" : "Start Memento" }
    static var buyMeACoffee: String { isSwedish ? "Bjud på en kaffe" : "Buy me a coffee" }
    
    // MARK: - Onboarding Steps
    static var onboardingWelcome: String { isSwedish ? "Välkommen till Memento" : "Welcome to Memento" }
    static var onboardingFeatures: String { isSwedish ? "Vad kan du göra?" : "What can you do?" }
    static var onboardingHowItWorks: String { isSwedish ? "Så fungerar det" : "How it works" }
    static var onboardingPermission: String { isSwedish ? "En sak till..." : "One more thing..." }
    
    static var onboardingTagline: String { isSwedish ? "Din personliga skärmhistorik" : "Your personal screen history" }
    static var onboardingSubtitle: String { 
        isSwedish 
            ? "Glöm aldrig vad du såg på skärmen.\nSök i text, bilder och webbsidor."
            : "Never forget what you saw on screen.\nSearch text, images and web pages."
    }
    
    // Features
    static var featureSearchAll: String { isSwedish ? "Sök i allt" : "Search everything" }
    static var featureSearchAllDesc: String { isSwedish ? "Hitta text från vilken skärmdump som helst" : "Find text from any screenshot" }
    static var featureClipboard: String { isSwedish ? "Clipboard-historik" : "Clipboard history" }
    static var featureClipboardDesc: String { isSwedish ? "Allt du kopierat sparas sökbart" : "Everything you copy is searchable" }
    static var featureWeb: String { isSwedish ? "Webb-historik" : "Web history" }
    static var featureWebDesc: String { isSwedish ? "Hitta webbsidor du besökt med URL & titel" : "Find web pages you visited with URL & title" }
    static var featureLiveText: String { isSwedish ? "Live Text" : "Live Text" }
    static var featureLiveTextDesc: String { isSwedish ? "Markera och kopiera text direkt från bilder" : "Select and copy text directly from images" }
    static var featurePrivate: String { isSwedish ? "100% Privat" : "100% Private" }
    static var featurePrivateDesc: String { isSwedish ? "Allt sparas lokalt - ingen moln, ingen telemetri" : "Everything stored locally - no cloud, no telemetry" }
    
    // How it works
    static var howCapture: String { isSwedish ? "Starta Capture först!" : "Start Capture first!" }
    static var howCaptureDesc: String { isSwedish ? "Denna app körs i menyraden och måste vara igång" : "This app runs in menu bar and must be running" }
    static var howOCR: String { isSwedish ? "Automatisk OCR" : "Automatic OCR" }
    static var howOCRDesc: String { isSwedish ? "All text på skärmen extraheras och indexeras" : "All text on screen is extracted and indexed" }
    static var howTimeline: String { isSwedish ? "Memento Timeline" : "Memento Timeline" }
    static var howTimelineDesc: String { isSwedish ? "Öppna Timeline-appen för att söka och bläddra" : "Open Timeline app to search and browse" }
    static var howTip: String { isSwedish ? "Tips!" : "Tip!" }
    static var howTipDesc: String { isSwedish ? "⌘F = sök, ←→ = navigera, markera text direkt i bilden för att kopiera!" : "⌘F = search, ←→ = navigate, select text directly in image to copy!" }
    
    // Permission
    static var permissionReady: String { isSwedish ? "Redo att köra!" : "Ready to go!" }
    static var permissionReadyDesc: String { 
        isSwedish 
            ? "Du har gett tillåtelse.\nMemento börjar spela in när du stänger detta fönster."
            : "Permission granted.\nMemento starts recording when you close this window."
    }
    static var permissionNeeded: String { isSwedish ? "Skärminspelning krävs" : "Screen Recording Required" }
    static var permissionNeededDesc: String { 
        isSwedish 
            ? "Memento behöver tillgång till skärminspelning för att fungera."
            : "Memento needs screen recording access to work."
    }
    static var permissionAdd: String { isSwedish ? "Lägg till \"Memento Capture\" i listan" : "Add \"Memento Capture\" to the list" }
    
    // Navigation
    static var back: String { isSwedish ? "Tillbaka" : "Back" }
    static var next: String { isSwedish ? "Nästa" : "Next" }
}
