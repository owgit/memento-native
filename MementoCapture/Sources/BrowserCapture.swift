import Foundation
import AppKit

/// Captures URL and tab title from browsers using AppleScript
class BrowserCapture {
    
    struct BrowserInfo {
        let url: String?
        let title: String?
        let browserName: String
    }
    
    /// Get current URL and title from the frontmost browser
    static func getCurrentBrowserInfo() -> BrowserInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let appName = app.localizedName else { return nil }
        
        switch appName {
        case "Safari":
            return getSafariInfo()
        case "Google Chrome", "Chrome":
            return getChromeInfo()
        case "Arc":
            return getArcInfo()
        case "Firefox":
            return getFirefoxInfo()
        case "Brave Browser":
            return getBraveInfo()
        case "Microsoft Edge":
            return getEdgeInfo()
        default:
            return nil
        }
    }
    
    // MARK: - Safari
    private static func getSafariInfo() -> BrowserInfo? {
        let script = """
        tell application "Safari"
            if (count of windows) > 0 then
                set currentTab to current tab of front window
                set tabURL to URL of currentTab
                set tabTitle to name of currentTab
                return tabURL & "|||" & tabTitle
            end if
        end tell
        """
        guard let result = runAppleScript(script) else { return nil }
        let parts = result.components(separatedBy: "|||")
        return BrowserInfo(
            url: parts.first,
            title: parts.count > 1 ? parts[1] : nil,
            browserName: "Safari"
        )
    }
    
    // MARK: - Chrome
    private static func getChromeInfo() -> BrowserInfo? {
        let script = """
        tell application "Google Chrome"
            if (count of windows) > 0 then
                set activeTab to active tab of front window
                set tabURL to URL of activeTab
                set tabTitle to title of activeTab
                return tabURL & "|||" & tabTitle
            end if
        end tell
        """
        guard let result = runAppleScript(script) else { return nil }
        let parts = result.components(separatedBy: "|||")
        return BrowserInfo(
            url: parts.first,
            title: parts.count > 1 ? parts[1] : nil,
            browserName: "Chrome"
        )
    }
    
    // MARK: - Arc
    private static func getArcInfo() -> BrowserInfo? {
        let script = """
        tell application "Arc"
            if (count of windows) > 0 then
                set activeTab to active tab of front window
                set tabURL to URL of activeTab
                set tabTitle to title of activeTab
                return tabURL & "|||" & tabTitle
            end if
        end tell
        """
        guard let result = runAppleScript(script) else { return nil }
        let parts = result.components(separatedBy: "|||")
        return BrowserInfo(
            url: parts.first,
            title: parts.count > 1 ? parts[1] : nil,
            browserName: "Arc"
        )
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
        return BrowserInfo(url: nil, title: title, browserName: "Firefox")
    }
    
    // MARK: - Brave
    private static func getBraveInfo() -> BrowserInfo? {
        let script = """
        tell application "Brave Browser"
            if (count of windows) > 0 then
                set activeTab to active tab of front window
                set tabURL to URL of activeTab
                set tabTitle to title of activeTab
                return tabURL & "|||" & tabTitle
            end if
        end tell
        """
        guard let result = runAppleScript(script) else { return nil }
        let parts = result.components(separatedBy: "|||")
        return BrowserInfo(
            url: parts.first,
            title: parts.count > 1 ? parts[1] : nil,
            browserName: "Brave"
        )
    }
    
    // MARK: - Edge
    private static func getEdgeInfo() -> BrowserInfo? {
        let script = """
        tell application "Microsoft Edge"
            if (count of windows) > 0 then
                set activeTab to active tab of front window
                set tabURL to URL of activeTab
                set tabTitle to title of activeTab
                return tabURL & "|||" & tabTitle
            end if
        end tell
        """
        guard let result = runAppleScript(script) else { return nil }
        let parts = result.components(separatedBy: "|||")
        return BrowserInfo(
            url: parts.first,
            title: parts.count > 1 ? parts[1] : nil,
            browserName: "Edge"
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
}


