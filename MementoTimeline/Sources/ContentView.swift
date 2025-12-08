import SwiftUI
import VisionKit

struct ContentView: View {
    @EnvironmentObject var manager: TimelineManager
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    @State private var isHoveringTimeline = false
    @State private var mouseLocation: CGPoint = .zero
    @State private var previewFrame: NSImage?
    @State private var previewTime: String = ""
    @State private var zoomLevel: CGFloat = 1.0
    @State private var hasInitializedZoom = false
    
    var body: some View {
        ZStack {
            // Full-screen frame display
            frameView
                .ignoresSafeArea()
            
            // Gradient overlays for controls visibility
            if showControls {
                VStack {
                    // Top gradient
                    LinearGradient(
                        colors: [Color.black.opacity(0.7), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    
                    Spacer()
                    
                    // Bottom gradient
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 200)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            
            // Controls overlay
            VStack {
                // Top bar - app info
                if showControls {
                    topBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Spacer()
                
                // Bottom floating controls
                if showControls {
                    floatingControls
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.3), value: showControls)
            
            // Search overlay
            if manager.isSearching {
                searchOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            
            // Text overlay panel
            if manager.showTextOverlay {
                textOverlay
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            
            // Loading indicator
            if manager.isLoading {
                loadingView
            }
            
            // Copied notification
            if manager.copiedNotification {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "doc.on.clipboard.fill")
                        Text("Kopierat!")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.9))
                    )
                    .padding(.bottom, 140)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3), value: manager.copiedNotification)
            }
        }
        .background(Color.black)
        .onAppear { 
            setupKeyHandling()
        }
        .onHover { hovering in
            if hovering {
                showControlsTemporarily()
            }
        }
        .gesture(
            TapGesture(count: 2).onEnded {
                toggleFullscreen()
            }
        )
    }
    
    // MARK: - Frame View
    private var frameView: some View {
        GeometryReader { geometry in
            if let image = manager.currentFrame {
                if zoomLevel <= 1.0 {
                    // Fit-to-window mode - enkel SwiftUI Image
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Zoom mode - använd ScrollView för pan/zoom med Live Text
                    LiveTextImageView(image: image, zoomLevel: $zoomLevel)
                }
            } else {
                Color.black
            }
        }
    }
    
    // MARK: - Top Bar
    private var topBar: some View {
        HStack(spacing: 16) {
            // App icon placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.1))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.8))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    // App color indicator
                    Circle()
                        .fill(manager.getColorForCurrentFrame())
                        .frame(width: 8, height: 8)
                    
                    Text(manager.currentApp.isEmpty ? "Memento Timeline" : manager.currentApp)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                
                Text(manager.currentTime.isEmpty ? "Laddar..." : formatTime(manager.currentTime))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Copy ALL text button (no keyboard shortcut - let native ⌘C work for selection)
            Button(action: { 
                withAnimation(.spring(response: 0.3)) { 
                    manager.copyAllText()
                }
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Kopiera ALL text")
            
            // Show text panel button
            Button(action: { 
                withAnimation(.spring(response: 0.3)) { 
                    manager.showTextOverlay.toggle()
                    if manager.showTextOverlay {
                        manager.loadTextForCurrentFrame()
                    }
                }
            }) {
                Image(systemName: manager.showTextOverlay ? "text.bubble.fill" : "text.bubble")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(manager.showTextOverlay ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("t", modifiers: .command)
            .help("Visa text (⌘T)")
            
            // Search button
            Button(action: { withAnimation { manager.isSearching = true } }) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 20, y: 5)
        )
    }
    
    // MARK: - Floating Controls
    private var floatingControls: some View {
        VStack(spacing: 16) {
            // Timeline scrubber
            timelineScrubber
            
            // Playback controls
            HStack(spacing: 32) {
                // Skip to start
                Button(action: { manager.jumpToFrame(0) }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(ControlButtonStyle())
                
                // Previous frame
                Button(action: { manager.previousFrame() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 24, weight: .semibold))
                }
                .buttonStyle(ControlButtonStyle(size: 50))
                .keyboardShortcut(.leftArrow, modifiers: [])
                
                // Time display
                VStack(spacing: 2) {
                    if let segment = manager.getSegmentForIndex(manager.currentFrameIndex) {
                        Text(formatTime(segment.timeString))
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Text(segment.appName)
                            .font(.system(size: 11))
                            .foregroundColor(segment.color)
                    } else {
                        Text("\(manager.currentFrameIndex + 1)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("av \(manager.totalFrames)")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .frame(width: 100)
                
                // Next frame
                Button(action: { manager.nextFrame() }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 24, weight: .semibold))
                }
                .buttonStyle(ControlButtonStyle(size: 50))
                .keyboardShortcut(.rightArrow, modifiers: [])
                
                // Skip to end
                Button(action: { manager.jumpToFrame(manager.totalFrames - 1) }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(ControlButtonStyle())
                
                Divider()
                    .frame(height: 30)
                    .background(Color.white.opacity(0.2))
                
                // Zoom controls
                Button(action: { zoomLevel = max(0.5, zoomLevel - 0.25) }) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 16))
                }
                .buttonStyle(ControlButtonStyle())
                
                Text("\(Int(zoomLevel * 100))%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 45)
                
                Button(action: { zoomLevel = min(5.0, zoomLevel + 0.25) }) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 16))
                }
                .buttonStyle(ControlButtonStyle())
                
                // Reset zoom to 100%
                Button(action: { zoomLevel = 1.0 }) {
                    Image(systemName: "1.magnifyingglass")
                        .font(.system(size: 16))
                }
                .buttonStyle(ControlButtonStyle())
                
                // Fit to screen
                Button(action: { fitToScreen() }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 16))
                }
                .buttonStyle(ControlButtonStyle())
                .help("Anpassa till fönster")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        )
    }
    
    // MARK: - Timeline Scrubber with App Colors
    private var timelineScrubber: some View {
        GeometryReader { geometry in
            let progress = manager.totalFrames > 0
                ? CGFloat(manager.currentFrameIndex) / CGFloat(max(1, manager.totalFrames - 1))
                : 0
            
            ZStack(alignment: .leading) {
                // Background with app-colored segments
                HStack(spacing: 0) {
                    ForEach(manager.timelineSegments) { segment in
                        let segmentWidth = geometry.size.width / CGFloat(max(1, manager.timelineSegments.count))
                        Rectangle()
                            .fill(segment.color.opacity(0.4))
                            .frame(width: segmentWidth, height: 12)
                    }
                }
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                
                // Progress overlay (darker)
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: max(6, geometry.size.width * progress), height: 12)
                
                // Hover preview with time
                if isHoveringTimeline {
                    let hoverProgress = mouseLocation.x / geometry.size.width
                    let hoverIndex = Int(hoverProgress * CGFloat(manager.totalFrames - 1))
                    
                    VStack(spacing: 4) {
                        // Time tooltip
                        if let segment = manager.getSegmentForIndex(hoverIndex) {
                            Text(segment.timeString.isEmpty ? "--:--" : formatTime(segment.timeString))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(segment.color.opacity(0.9))
                                )
                            
                            Text(segment.appName)
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .offset(x: geometry.size.width * hoverProgress - 40, y: -45)
                    
                    // Hover indicator
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(width: 3, height: 20)
                        .offset(x: geometry.size.width * hoverProgress - 1.5, y: 0)
                }
                
                // Current position handle
                ZStack {
                    Circle()
                        .fill(manager.getColorForCurrentFrame())
                        .frame(width: 18, height: 18)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                }
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                .offset(x: geometry.size.width * progress - 9)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    isHoveringTimeline = true
                    mouseLocation = location
                case .ended:
                    isHoveringTimeline = false
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        let frameIndex = Int(progress * CGFloat(manager.totalFrames - 1))
                        manager.jumpToFrame(frameIndex)
                    }
            )
        }
        .frame(height: 20)
    }
    
    private func formatTime(_ timeString: String) -> String {
        // Extract just HH:mm from "2024-01-15 14:30:25"
        let parts = timeString.split(separator: " ")
        if parts.count >= 2 {
            let timePart = String(parts[1])
            let timeComponents = timePart.split(separator: ":")
            if timeComponents.count >= 2 {
                return "\(timeComponents[0]):\(timeComponents[1])"
            }
        }
        return timeString
    }
    
    // MARK: - Search Overlay
    private var searchOverlay: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        manager.isSearching = false
                    }
                }
            
            // Search panel
            VStack(spacing: 0) {
                // Search input
                HStack(spacing: 14) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.4))
                    
                    TextField("Sök i din tidslinje...", text: $manager.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                        .onSubmit {
                            manager.search(manager.searchQuery)
                        }
                        .onChange(of: manager.searchQuery) { _, newValue in
                            if newValue.count >= 2 {
                                manager.search(newValue)
                            }
                        }
                    
                    if !manager.searchQuery.isEmpty {
                        Button(action: {
                            manager.searchQuery = ""
                            manager.searchResults = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Result count
                    if !manager.searchResults.isEmpty {
                        Text("\(manager.searchResults.count)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.2))
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Results
                if !manager.searchResults.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(manager.searchResults) { result in
                                SearchResultRow(result: result)
                                    .onTapGesture {
                                        manager.jumpToFrame(result.frameId)
                                        withAnimation {
                                            manager.isSearching = false
                                        }
                                    }
                            }
                        }
                    }
                    .frame(maxHeight: 400)
                } else if !manager.searchQuery.isEmpty && manager.searchQuery.count >= 2 {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.2))
                        Text("Inga resultat för \"\(manager.searchQuery)\"")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .frame(height: 150)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.2))
                        Text("Skriv för att söka")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .frame(height: 150)
                }
            }
            .frame(width: 580)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 0.98)))
                    .shadow(color: .black.opacity(0.5), radius: 40, y: 15)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
            Text("Laddar...")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
    
    // MARK: - Text Overlay
    private var textOverlay: some View {
        HStack {
            Spacer()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "text.quote")
                        .font(.system(size: 14))
                    Text("Text från skärmbild")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Spacer()
                    
                    // Copy all button
                    Button(action: { manager.copyAllText() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc")
                            Text("Kopiera allt")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.8))
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // Close button
                    Button(action: { 
                        withAnimation { manager.showTextOverlay = false }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.05))
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Text content
                if manager.currentFrameText.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.2))
                        Text("Ingen text hittad")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(manager.currentFrameText) { block in
                                TextBlockRow(block: block) {
                                    manager.copyText(block.text)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .frame(width: 380)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 0.95)))
                    .shadow(color: .black.opacity(0.4), radius: 20, x: -5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.trailing, 20)
            .padding(.vertical, 80)
        }
    }
    
    // MARK: - Helpers
    private func showControlsTemporarily() {
        showControls = true
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            if !isHoveringTimeline {
                withAnimation { showControls = false }
            }
        }
    }
    
    private func setupKeyHandling() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyEvent(event)
            return event
        }
        
        // Also handle mouse movement to show controls
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            showControlsTemporarily()
            return event
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        switch event.keyCode {
        case 123: // Left arrow
            manager.previousFrame()
            showControlsTemporarily()
        case 124: // Right arrow
            manager.nextFrame()
            showControlsTemporarily()
        case 53: // Escape
            if manager.isSearching {
                withAnimation { manager.isSearching = false }
            }
        case 49: // Space
            showControls.toggle()
        default:
            break
        }
    }
    
    private func toggleFullscreen() {
        if let window = NSApplication.shared.windows.first {
            window.toggleFullScreen(nil)
        }
    }
    
    private func fitToScreen() {
        // Reset to fit mode (zoomLevel <= 1.0 triggers SwiftUI scaledToFit)
        zoomLevel = 1.0
    }
}

// MARK: - Control Button Style
struct ControlButtonStyle: ButtonStyle {
    var size: CGFloat = 40
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white.opacity(configuration.isPressed ? 0.5 : 0.9))
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.05 : 0.1))
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Search Result Row
struct SearchResultRow: View {
    let result: TimelineManager.SearchResult
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Frame indicator
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.1))
                .frame(width: 50, height: 36)
                .overlay(
                    Text("#\(result.frameId)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                )
            
            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(result.text)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                if !result.timestamp.isEmpty || !result.appName.isEmpty {
                    HStack(spacing: 8) {
                        if !result.appName.isEmpty {
                            Text(result.appName)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        if !result.timestamp.isEmpty {
                            Text(result.timestamp)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                }
            }
            
            Spacer()
            
            // Arrow
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(isHovered ? 0.6 : 0.2))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isHovered ? Color.white.opacity(0.08) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Live Text Image View with Zoom
struct LiveTextImageView: NSViewRepresentable {
    let image: NSImage
    @Binding var zoomLevel: CGFloat
    
    init(image: NSImage, zoomLevel: Binding<CGFloat> = .constant(1.0)) {
        self.image = image
        self._zoomLevel = zoomLevel
    }
    
    @MainActor
    class Coordinator: NSObject {
        var analyzer: ImageAnalyzer?
        var overlayView: ImageAnalysisOverlayView?
        var currentImageHash: Int = 0
        var scrollView: NSScrollView?
        
        override init() {
            super.init()
            if ImageAnalyzer.isSupported {
                analyzer = ImageAnalyzer()
                overlayView = ImageAnalysisOverlayView()
                overlayView?.preferredInteractionTypes = .textSelection
                overlayView?.selectableItemsHighlighted = true
            }
        }
        
        func analyzeImage(_ image: NSImage, imageView: NSImageView) {
            guard let analyzer = analyzer,
                  let overlayView = overlayView else { return }
            
            let newHash = image.hashValue
            guard currentImageHash != newHash else { return }
            currentImageHash = newHash
            
            Task {
                if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    let configuration = ImageAnalyzer.Configuration([.text])
                    do {
                        let analysis = try await analyzer.analyze(cgImage, orientation: .up, configuration: configuration)
                        await MainActor.run {
                            overlayView.analysis = analysis
                            overlayView.trackingImageView = imageView
                        }
                    } catch {
                        print("⚠️ Live Text analysis failed: \(error)")
                    }
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        // Scroll view for zoom/pan
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .black
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05  // Allow zooming out to fit large images
        scrollView.maxMagnification = 5.0
        context.coordinator.scrollView = scrollView
        
        // Clip view
        let clipView = NSClipView()
        clipView.backgroundColor = .black
        scrollView.contentView = clipView
        
        // Container for image + overlay
        let containerView = FlippedView()
        containerView.wantsLayer = true
        
        // Image view at native size - magnification handles scaling
        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleNone
        imageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(imageView)
        
        // Container = image native size, magnification will scale to fit
        let imageSize = image.size
        containerView.frame = NSRect(origin: .zero, size: imageSize)
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])
        
        // Add Live Text overlay
        if let overlayView = context.coordinator.overlayView {
            overlayView.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(overlayView)
            
            NSLayoutConstraint.activate([
                overlayView.topAnchor.constraint(equalTo: containerView.topAnchor),
                overlayView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                overlayView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                overlayView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
            ])
            
            context.coordinator.analyzeImage(image, imageView: imageView)
        }
        
        scrollView.documentView = containerView
        
        // Fit image to window on initial load
        DispatchQueue.main.async {
            self.fitImageToWindow(scrollView: scrollView, imageSize: imageSize)
        }
        
        return scrollView
    }
    
    private func fitImageToWindow(scrollView: NSScrollView, imageSize: NSSize) {
        let clipViewSize = scrollView.contentView.bounds.size
        guard clipViewSize.width > 0, clipViewSize.height > 0 else { return }
        
        // Calculate zoom to fit
        let widthRatio = clipViewSize.width / imageSize.width
        let heightRatio = clipViewSize.height / imageSize.height
        let fitZoom = min(widthRatio, heightRatio) * 0.95  // 95% to leave some margin
        
        scrollView.magnification = fitZoom
        centerContent(in: scrollView)
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let containerView = scrollView.documentView,
              let imageView = containerView.subviews.first as? NSImageView else { return }
        
        imageView.image = image
        
        // Update container size for new image (1:1 with image pixels)
        let imageSize = image.size
        containerView.frame = NSRect(origin: .zero, size: imageSize)
        
        // Always update magnification to match zoomLevel
        if abs(scrollView.magnification - zoomLevel) > 0.001 {
            scrollView.animator().magnification = zoomLevel
            print("🔍 Setting magnification to \(zoomLevel)")
        }
        
        context.coordinator.analyzeImage(image, imageView: imageView)
        
        // Re-center after zoom change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.centerContent(in: scrollView)
        }
    }
    
    private func centerContent(in scrollView: NSScrollView) {
        guard let documentView = scrollView.documentView else { return }
        let documentSize = documentView.frame.size
        let clipViewSize = scrollView.contentView.bounds.size
        
        let x = max(0, (documentSize.width - clipViewSize.width) / 2)
        let y = max(0, (documentSize.height - clipViewSize.height) / 2)
        
        scrollView.contentView.scroll(to: NSPoint(x: x, y: y))
    }
}

// Helper view that doesn't flip coordinates
class FlippedView: NSView {
    override var isFlipped: Bool { false }
}

// MARK: - Text Block Row
struct TextBlockRow: View {
    let block: TimelineManager.TextBlock
    let onCopy: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(block.text)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.9))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if isHovered {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(TimelineManager())
        .frame(width: 1200, height: 800)
}
