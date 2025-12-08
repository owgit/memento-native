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
    static var permissions: String { isSwedish ? "Behörigheter..." : "Permissions..." }
    static var statistics: String { isSwedish ? "Statistik..." : "Statistics..." }
    static var cleanOldFrames: String { isSwedish ? "Rensa gamla frames..." : "Clean Old Frames..." }
    static var saveDebugScreenshot: String { isSwedish ? "Spara debug-skärmdump" : "Save Debug Screenshot" }
    static var quitMemento: String { isSwedish ? "Avsluta Memento" : "Quit Memento" }
    
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
}

