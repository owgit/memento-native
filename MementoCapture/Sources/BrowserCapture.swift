import Foundation
import AppKit

/// Captures URL and tab title from browsers using AppleScript
class BrowserCapture {
    private static let delimiter = "|||"
    private static let privateKeywords = [
        "incognito",
        "inprivate",
        "private browsing",
        "private window",
        "private mode",
        "privat surfning",
        "privat fonster",
        "privat lage",
        "about:privatebrowsing"
    ]
    private static let privateURLMarkers = [
        "about:privatebrowsing",
        "about:incognito",
        "chrome://incognito",
        "edge://inprivate",
        "brave://incognito"
    ]
    
    struct BrowserInfo {
        let url: String?
        let title: String?
        let browserName: String
        let isPrivateBrowsing: Bool
    }
    
    /// Get current URL and title from the frontmost browser
    static func getCurrentBrowserInfo() -> BrowserInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let appName = app.localizedName else { return nil }
        
        switch appName {
        case "Safari":
            return getSafariInfo()
        case "Google Chrome", "Chrome":
            return getChromiumInfo(appName: "Google Chrome", browserName: "Chrome")
        case "Arc":
            return getChromiumInfo(appName: "Arc", browserName: "Arc")
        case "Firefox":
            return getFirefoxInfo()
        case "Brave Browser":
            return getChromiumInfo(appName: "Brave Browser", browserName: "Brave")
        case "Microsoft Edge":
            return getChromiumInfo(appName: "Microsoft Edge", browserName: "Edge")
        default:
            return nil
        }
    }
    
    // MARK: - Safari
    private static func getSafariInfo() -> BrowserInfo? {
        let script = """
        tell application "Safari"
            if (count of windows) > 0 then
                set frontWin to front window
                set currentTab to current tab of frontWin
                set tabURL to URL of currentTab
                set tabTitle to name of currentTab
                set winTitle to name of frontWin
                return tabURL & "\(delimiter)" & tabTitle & "\(delimiter)" & winTitle
            end if
        end tell
        """
        guard let result = runAppleScript(script) else { return nil }
        return parseBrowserInfo(result, browserName: "Safari")
    }

    // MARK: - Chromium-based browsers
    private static func getChromiumInfo(appName: String, browserName: String) -> BrowserInfo? {
        let scriptWithMode = """
        tell application "\(appName)"
            if (count of windows) > 0 then
                set frontWin to front window
                set activeTab to active tab of frontWin
                set tabURL to URL of activeTab
                set tabTitle to title of activeTab
                set tabMode to ""
                try
                    set tabMode to mode of frontWin as text
                end try
                return tabURL & "\(delimiter)" & tabTitle & "\(delimiter)" & tabMode
            end if
        end tell
        """

        if let result = runAppleScript(scriptWithMode) {
            return parseBrowserInfo(result, browserName: browserName)
        }

        // Fallback if browser dictionary differs and `mode` is unavailable.
        let fallbackScript = """
        tell application "\(appName)"
            if (count of windows) > 0 then
                set activeTab to active tab of front window
                set tabURL to URL of activeTab
                set tabTitle to title of activeTab
                return tabURL & "\(delimiter)" & tabTitle
            end if
        end tell
        """

        guard let result = runAppleScript(fallbackScript) else { return nil }
        return parseBrowserInfo(result, browserName: browserName)
    }
    
    // MARK: - Firefox (limited AppleScript support)
    private static func getFirefoxInfo() -> BrowserInfo? {
        // Firefox has limited AppleScript support - can only get window title
        let script = """
        tell application "Firefox"
            if (count of windows) > 0 then
                return name of front window
            end if
        end tell
        """
        guard let title = runAppleScript(script) else { return nil }
        return BrowserInfo(
            url: nil,
            title: normalize(title),
            browserName: "Firefox",
            isPrivateBrowsing: matchesPrivateKeyword(title)
        )
    }
    
    // MARK: - AppleScript Runner
    private static func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return result.stringValue
    }

    private static func parseBrowserInfo(_ result: String, browserName: String) -> BrowserInfo {
        let parts = result.components(separatedBy: delimiter)
        let url = normalize(parts.indices.contains(0) ? parts[0] : nil)
        let title = normalize(parts.indices.contains(1) ? parts[1] : nil)
        let extraContext = normalize(parts.indices.contains(2) ? parts[2] : nil)

        let isPrivate = matchesPrivateKeyword(extraContext)
            || matchesPrivateKeyword(title)
            || matchesPrivateURL(url)

        return BrowserInfo(
            url: url,
            title: title,
            browserName: browserName,
            isPrivateBrowsing: isPrivate
        )
    }

    private static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func matchesPrivateKeyword(_ value: String?) -> Bool {
        guard let normalizedValue = value?
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased() else {
            return false
        }
        return privateKeywords.contains { normalizedValue.contains($0) }
    }

    private static func matchesPrivateURL(_ url: String?) -> Bool {
        guard let url = url?.lowercased() else { return false }
        return privateURLMarkers.contains { url.contains($0) }
    }
}

