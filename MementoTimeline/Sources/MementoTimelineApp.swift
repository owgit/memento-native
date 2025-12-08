import SwiftUI

@main
struct MementoTimelineApp: App {
    @StateObject private var timelineManager = TimelineManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(timelineManager)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1400, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Timeline") {
                Button("Sök") {
                    timelineManager.isSearching = true
                }
                .keyboardShortcut("f", modifiers: .command)
                
                Button("Fullskärm") {
                    toggleFullscreen()
                }
                .keyboardShortcut("f", modifiers: [])
                
                Divider()
                
                Button("Föregående frame") {
                    timelineManager.previousFrame()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                
                Button("Nästa frame") {
                    timelineManager.nextFrame()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
        }
    }
    
    private func toggleFullscreen() {
        if let window = NSApplication.shared.windows.first {
            window.toggleFullScreen(nil)
        }
    }
}

