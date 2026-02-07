import Foundation

/// Simple localization - detects system language
enum L {
    static let isSwedish: Bool = {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return lang == "sv"
    }()
    
    // MARK: - General
    static var copied: String { isSwedish ? "Kopierat!" : "Copied!" }
    static var loading: String { isSwedish ? "Laddar..." : "Loading..." }
    static var noCapturesYet: String { isSwedish ? "Inga inspelningar än" : "No captures yet" }
    static var of: String { isSwedish ? "av" : "of" }
    
    // MARK: - Top Bar
    static var copyAllText: String { isSwedish ? "Kopiera ALL text" : "Copy ALL text" }
    static var showText: String { isSwedish ? "Visa text" : "Show text" }
    static var firstFrameHelp: String { isSwedish ? "Första (Home)" : "First (Home)" }
    static var previousFrameHelp: String { isSwedish ? "Föregående (←)" : "Previous (←)" }
    static var nextFrameHelp: String { isSwedish ? "Nästa (→)" : "Next (→)" }
    static var lastFrameHelp: String { isSwedish ? "Sista (End)" : "Last (End)" }
    static var searchHelp: String { isSwedish ? "Sök (⌘F)" : "Search (⌘F)" }
    static var showTextHelp: String { isSwedish ? "Visa OCR-text (⌘T)" : "Show OCR text (⌘T)" }
    static var copyTextHelp: String { isSwedish ? "Kopiera all text" : "Copy all text" }
    
    // MARK: - Controls
    static var fitToWindow: String { isSwedish ? "Anpassa till fönster" : "Fit to window" }
    static var zoomIn: String { isSwedish ? "Zooma in" : "Zoom in" }
    static var zoomOut: String { isSwedish ? "Zooma ut" : "Zoom out" }
    static var resetZoom: String { isSwedish ? "Återställ zoom (100%)" : "Reset zoom (100%)" }
    static var selectToCopy: String { isSwedish ? "Markera → Kopiera" : "Select → Copy" }
    static var selectToCopyHelp: String { isSwedish ? "Markera text i bilden för att kopiera" : "Select text in the image to copy" }
    static var zoomToSelect: String { isSwedish ? "Zooma för att markera" : "Zoom to select" }
    static var zoomToSelectHelp: String { isSwedish ? "Zooma in till 100% för att markera text" : "Zoom in to 100% to select text" }
    
    // MARK: - Search
    static var text: String { "Text" }
    static var semantic: String { isSwedish ? "Semantisk" : "Semantic" }
    static var searchPlaceholder: String { isSwedish ? "Sök i din tidslinje..." : "Search your timeline..." }
    static var semanticPlaceholder: String { isSwedish ? "Beskriv vad du letar efter..." : "Describe what you're looking for..." }
    static var searching: String { isSwedish ? "Söker..." : "Searching..." }
    static var searchHintShortcuts: String { isSwedish ? "↑↓ välj, Enter öppna, Esc stäng" : "↑↓ select, Enter open, Esc close" }
    static func noResults(_ query: String) -> String {
        isSwedish ? "Inga resultat för \"\(query)\"" : "No results for \"\(query)\""
    }
    static var typeToSearch: String { isSwedish ? "Skriv för att söka" : "Type to search" }
    static var loadingSearchHistory: String { isSwedish ? "Laddar hela historiken..." : "Loading full history..." }
    
    // MARK: - Text Overlay
    static var textFromScreenshot: String { isSwedish ? "Text från skärmbild" : "Text from screenshot" }
    static var copyAll: String { isSwedish ? "Kopiera allt" : "Copy all" }
    static var noTextFound: String { isSwedish ? "Ingen text hittad" : "No text found" }

    // MARK: - App Menu
    static var timelineMenu: String { isSwedish ? "Tidslinje" : "Timeline" }
    static var menuSearch: String { isSwedish ? "Sök" : "Search" }
    static var menuFullscreen: String { isSwedish ? "Fullskärm" : "Fullscreen" }
    static var menuPreviousFrame: String { isSwedish ? "Föregående frame" : "Previous frame" }
    static var menuNextFrame: String { isSwedish ? "Nästa frame" : "Next frame" }
    
    // MARK: - Months (for date formatting)
    static var months: [String] {
        isSwedish 
            ? ["", "jan", "feb", "mar", "apr", "maj", "jun", "jul", "aug", "sep", "okt", "nov", "dec"]
            : ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    }
}
