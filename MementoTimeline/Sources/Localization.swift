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
    static var of: String { isSwedish ? "av" : "of" }
    
    // MARK: - Top Bar
    static var copyAllText: String { isSwedish ? "Kopiera ALL text" : "Copy ALL text" }
    static var showText: String { isSwedish ? "Visa text" : "Show text" }
    
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
    static func noResults(_ query: String) -> String {
        isSwedish ? "Inga resultat för \"\(query)\"" : "No results for \"\(query)\""
    }
    static var typeToSearch: String { isSwedish ? "Skriv för att söka" : "Type to search" }
    
    // MARK: - Text Overlay
    static var textFromScreenshot: String { isSwedish ? "Text från skärmbild" : "Text from screenshot" }
    static var copyAll: String { isSwedish ? "Kopiera allt" : "Copy all" }
    static var noTextFound: String { isSwedish ? "Ingen text hittad" : "No text found" }
    
    // MARK: - Months (for date formatting)
    static var months: [String] {
        isSwedish 
            ? ["", "jan", "feb", "mar", "apr", "maj", "jun", "jul", "aug", "sep", "okt", "nov", "dec"]
            : ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    }
}


