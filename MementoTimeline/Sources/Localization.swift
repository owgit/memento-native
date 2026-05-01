import Foundation

/// Simple localization - detects system language
enum L {
    static let isSwedish: Bool = {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return lang == "sv"
    }()
    
    // MARK: - General
    static var loading: String { isSwedish ? "Laddar..." : "Loading..." }
    static var noCapturesYet: String { isSwedish ? "Inga inspelningar än" : "No captures yet" }
    static var readyToLoadFrame: String { isSwedish ? "Dra i tidslinjen eller sök för att ladda en frame" : "Drag the timeline or search to load a frame" }
    
    // MARK: - Top Bar
    static var firstFrameHelp: String { isSwedish ? "Första (Home)" : "First (Home)" }
    static var previousFrameHelp: String { isSwedish ? "Föregående (←)" : "Previous (←)" }
    static var nextFrameHelp: String { isSwedish ? "Nästa (→)" : "Next (→)" }
    static var lastFrameHelp: String { isSwedish ? "Sista (End)" : "Last (End)" }
    static var commandPaletteHelp: String { isSwedish ? "Kommandopalett (⌘F)" : "Command palette (⌘F)" }
    static var hideToolbar: String { isSwedish ? "Göm toolbar" : "Hide toolbar" }
    static var showToolbar: String { isSwedish ? "Visa toolbar" : "Show toolbar" }
    static var hideToolbarHelp: String {
        isSwedish
            ? "Göm scrubber och appfilter så texten bakom kan markeras och kopieras"
            : "Hide scrubber and app filters so text behind them can be selected and copied"
    }
    static var showToolbarHelp: String {
        isSwedish
            ? "Visa scrubber och appfilter igen"
            : "Show scrubber and app filters again"
    }
    
    // MARK: - Controls
    
    // MARK: - Search
    static var text: String { "Text" }
    static var semantic: String { isSwedish ? "Semantisk" : "Semantic" }
    static var searchPlaceholder: String { isSwedish ? "Sök i din tidslinje..." : "Search your timeline..." }
    static var semanticPlaceholder: String { isSwedish ? "Beskriv vad du letar efter..." : "Describe what you're looking for..." }
    static var searching: String { isSwedish ? "Söker..." : "Searching..." }
    static var searchHintShortcuts: String { isSwedish ? "↑↓ välj, Enter öppna, Esc stäng" : "↑↓ select, Enter open, Esc close" }
    static var searchOpenSelected: String { isSwedish ? "Öppna vald träff" : "Open selected match" }
    static var searchPreviewTitle: String { isSwedish ? "Förhandsvisning" : "Preview" }
    static var searchPreviewHint: String { isSwedish ? "Kontrollera träffen innan hopp" : "Check the match before jump" }
    static var searchRetry: String { isSwedish ? "Försök igen" : "Try again" }
    static var searchTrySemantic: String { isSwedish ? "Prova semantisk sökning" : "Try semantic search" }
    static var searchTryText: String { isSwedish ? "Prova textsökning" : "Try text search" }
    static var searchDatabaseError: String { isSwedish ? "Kunde inte läsa sökdatabasen. Prova igen." : "Could not read search database. Try again." }
    static var searchOpenError: String { isSwedish ? "Kunde inte öppna träffen. Ladda äldre historik och försök igen." : "Could not open this match. Load older history and try again." }
    static var searchErrorTitle: String { isSwedish ? "Sökningen misslyckades" : "Search failed" }
    static var timelinePreviewLoading: String { isSwedish ? "Laddar preview..." : "Loading preview..." }
    static var timelinePreviewUnavailable: String { isSwedish ? "Ingen preview" : "No preview" }
    static var loadedPrefix: String { isSwedish ? "Laddat" : "Loaded" }
    static var loadingOlderHistory: String { isSwedish ? "Laddar äldre historik..." : "Loading older history..." }
    static var olderHistoryHintShort: String { isSwedish ? "← för äldre" : "← for older" }
    static var allApps: String { isSwedish ? "Alla" : "All" }
    static var appFilterHelp: String { isSwedish ? "Filtrera timeline-markörer per app" : "Filter timeline markers by app" }
    static var previousAppMarkerHelp: String { isSwedish ? "Föregående markör för vald app" : "Previous marker for selected app" }
    static var nextAppMarkerHelp: String { isSwedish ? "Nästa markör för vald app" : "Next marker for selected app" }
    static func noResults(_ query: String) -> String {
        isSwedish ? "Inga resultat för \"\(query)\"" : "No results for \"\(query)\""
    }
    static func searchFor(_ query: String) -> String {
        isSwedish ? "Sök efter \"\(query)\"" : "Search for \"\(query)\""
    }
    static func jumpToTime(_ value: String) -> String {
        isSwedish ? "Hoppa till \(value)" : "Jump to \(value)"
    }
    static var typeToSearch: String { isSwedish ? "Skriv för att söka" : "Type to search" }
    static var loadingSearchHistory: String { isSwedish ? "Laddar hela historiken..." : "Loading full history..." }
    static var commandPalettePlaceholder: String { isSwedish ? "Skriv kommando eller tid (14:30)..." : "Type command or time (14:30)..." }
    static var commandPaletteHint: String { isSwedish ? "⌘F öppna · Esc stäng" : "⌘F open · Esc close" }
    static var commandRecentMatches: String { isSwedish ? "Senaste träffar" : "Recent matches" }
    static var commandNoActions: String { isSwedish ? "Inga kommandon för denna sökning" : "No commands for this query" }
    static var commandOpenSearch: String { isSwedish ? "Öppna sökpanelen" : "Open search panel" }
    static var commandOpenSearchSubtitle: String { isSwedish ? "Fokusera sök och börja skriva" : "Focus search and start typing" }
    static var commandUseSemantic: String { isSwedish ? "Använd semantisk sökning" : "Use semantic search" }
    static var commandUseTextSearch: String { isSwedish ? "Använd textsökning" : "Use text search" }
    static var commandSearchModeSubtitle: String { isSwedish ? "Byt standardsökning" : "Switch default search mode" }
    static var commandJumpToTimeSubtitle: String { isSwedish ? "Hoppar till närmaste tid i historiken" : "Jumps to the closest time in loaded history" }

    // MARK: - App Menu
    static var timelineMenu: String { isSwedish ? "Tidslinje" : "Timeline" }
    static var menuSearch: String { isSwedish ? "Sök" : "Search" }
    static var menuCommandPalette: String { isSwedish ? "Kommandopalett" : "Command Palette" }
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
