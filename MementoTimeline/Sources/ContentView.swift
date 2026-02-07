import SwiftUI
import VisionKit

// MARK: - Time Formatting Helpers

/// Format timestamp nicely: "14:30" for today, "igår 14:30", or "8 dec 14:30"
func formatTimeDisplay(_ timestamp: String) -> String {
    let clean = timestamp.replacingOccurrences(of: "\"", with: "")
    let parts = clean.contains("T") ? clean.split(separator: "T") : clean.split(separator: " ")
    
    // Get time part
    var timeStr = ""
    if parts.count >= 2 {
        let timePart = String(parts[1]).replacingOccurrences(of: "Z", with: "")
        let timeComponents = timePart.split(separator: ":")
        if timeComponents.count >= 2 {
            timeStr = "\(timeComponents[0]):\(timeComponents[1])"
        }
    }
    
    // Get date part
    guard let datePart = parts.first else { return timeStr }
    let dateComponents = datePart.split(separator: "-")
    guard dateComponents.count >= 3 else { return timeStr }
    
    let year = Int(dateComponents[0]) ?? 0
    let month = Int(dateComponents[1]) ?? 0
    let day = Int(dateComponents[2]) ?? 0
    
    // Check if today
    let calendar = Calendar.current
    let today = calendar.component(.day, from: Date())
    let thisMonth = calendar.component(.month, from: Date())
    let thisYear = calendar.component(.year, from: Date())
    
    if day == today && month == thisMonth && year == thisYear {
        return timeStr  // Just show time for today
    }
    
    // Yesterday check
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) {
        let yDay = calendar.component(.day, from: yesterday)
        let yMonth = calendar.component(.month, from: yesterday)
        if day == yDay && month == yMonth && year == thisYear {
            let isSwedish = Locale.current.language.languageCode?.identifier == "sv"
            return "\(isSwedish ? "igår" : "yesterday") \(timeStr)"
        }
    }
    
    // Show date + time
    let months = L.months
    let monthName = month > 0 && month < months.count ? months[month] : ""
    return "\(day) \(monthName) \(timeStr)"
}

struct ContentView: View {
    @EnvironmentObject var manager: TimelineManager
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    @State private var isHoveringTimeline = false
    @State private var mouseLocation: CGPoint = .zero
    @State private var zoomLevel: CGFloat = 1.0
    @State private var isDragging = false
    @State private var dragFrameIndex: Int = 0
    @State private var lastFrameLoadTime: Date = .distantPast
    @State private var eventMonitors: [Any] = []  // Store event monitors to prevent leak
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var selectedSearchResultIndex: Int = 0
    @State private var openingSearchResultFrameId: Int?
    
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
            
            // Controls overlay - only bottom bar
            VStack {
                Spacer()
                
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
            if manager.isLoading || manager.isLoadingMore {
                loadingView
            }
            
            // Copied notification
            if manager.copiedNotification {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "doc.on.clipboard.fill")
                        Text(L.copied)
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
        .focusable(!manager.isSearching)  // Only focusable when not searching
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            if !manager.isSearching {
                manager.previousFrame()
                showControlsTemporarily()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.rightArrow) {
            if !manager.isSearching {
                manager.nextFrame()
                showControlsTemporarily()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.space) {
            if !manager.isSearching {
                showControls.toggle()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if manager.isSearching {
                closeSearchOverlay()
                return .handled
            }
            return .ignored
        }
        .onChange(of: manager.searchResults.count) { _, newCount in
            if newCount == 0 {
                selectedSearchResultIndex = 0
            } else {
                selectedSearchResultIndex = min(selectedSearchResultIndex, newCount - 1)
            }
        }
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
        ZStack {
            Color.black
            
            if let image = manager.currentFrame {
                // Use a single native image view for both rendering and Live Text
                // to avoid layout drift between highlight and visible pixels.
                LiveTextImageView(image: image, zoomLevel: $zoomLevel, isFitToScreen: true)
            } else {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text(manager.totalFrames > 0 ? L.loading : L.noCapturesYet)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
    }
    
    // MARK: - Floating Controls
    private var floatingControls: some View {
        VStack(spacing: 12) {
            // Timeline scrubber
            timelineScrubber
            
            // Main controls - simplified layout
            HStack(spacing: 0) {
                // Left: Navigation
                HStack(spacing: 16) {
                    Button(action: { manager.jumpToFrame(0) }) {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(ControlButtonStyle(size: 32))
                    .help(L.firstFrameHelp)
                    
                    Button(action: { manager.previousFrame() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .buttonStyle(ControlButtonStyle(size: 44))
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .help(L.previousFrameHelp)
                }
                
                Spacer()
                
                // Center: Time & App (prominent)
                if let segment = manager.getSegmentForIndex(manager.currentFrameIndex) {
                    HStack(spacing: 10) {
                        AppIconView(appName: segment.appName)
                            .frame(width: 36, height: 36)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(formatTimeDisplay(segment.timeString))
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                            Text(segment.appName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(segment.color)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                } else {
                    Text("\(manager.currentFrameIndex + 1) / \(manager.totalFrames)")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.6))
                }
                
                Spacer()
                
                // Right: Navigation + Zoom
                HStack(spacing: 16) {
                    Button(action: { manager.nextFrame() }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .buttonStyle(ControlButtonStyle(size: 44))
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .help(L.nextFrameHelp)
                    
                    Button(action: { manager.jumpToFrame(manager.totalFrames - 1) }) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(ControlButtonStyle(size: 32))
                    .help(L.lastFrameHelp)
                    
                    // Action buttons group
                    HStack(spacing: 8) {
                        // Search
                        Button(action: { 
                            // Ensure window is key and active
                            NSApplication.shared.activate(ignoringOtherApps: true)
                            NSApplication.shared.keyWindow?.makeKey()
                            openSearchOverlay()
                        }) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13))
                        }
                        .buttonStyle(ControlButtonStyle(size: 30))
                        .keyboardShortcut("f", modifiers: .command)
                        .help(L.searchHelp)
                        
                        // Text panel
                        Button(action: { 
                            withAnimation(.spring(response: 0.3)) { 
                                manager.showTextOverlay.toggle()
                                if manager.showTextOverlay {
                                    manager.loadTextForCurrentFrame()
                                }
                            }
                        }) {
                            Image(systemName: manager.showTextOverlay ? "text.bubble.fill" : "text.bubble")
                                .font(.system(size: 13))
                        }
                        .buttonStyle(ControlButtonStyle(size: 30, isActive: manager.showTextOverlay))
                        .keyboardShortcut("t", modifiers: .command)
                        .help(L.showTextHelp)
                        
                        // Copy all
                        Button(action: { manager.copyAllText() }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 13))
                        }
                        .buttonStyle(ControlButtonStyle(size: 30))
                        .help(L.copyTextHelp)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 720)
        .modifier(GlassBackgroundModifier(cornerRadius: 20))
    }
    
    // MARK: - Timeline Scrubber with App Colors
    private var timelineScrubber: some View {
        GeometryReader { geometry in
            let displayIndex = isDragging ? dragFrameIndex : manager.currentFrameIndex
            let progress = manager.totalFrames > 0
                ? CGFloat(displayIndex) / CGFloat(max(1, manager.totalFrames - 1))
                : 0
            
            ZStack(alignment: .leading) {
                // Simplified background - single gradient instead of many rectangles
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.3), Color.cyan.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 12)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                
                // Progress overlay
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: max(6, geometry.size.width * progress), height: 12)
                
                // Hover preview with time
                if isHoveringTimeline && !isDragging {
                    let hoverProgress = mouseLocation.x / geometry.size.width
                    let hoverIndex = Int(hoverProgress * CGFloat(manager.totalFrames - 1))
                    
                    VStack(spacing: 4) {
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
                        isDragging = true
                        let prog = max(0, min(1, value.location.x / geometry.size.width))
                        dragFrameIndex = Int(prog * CGFloat(max(1, manager.totalFrames - 1)))
                        
                        // Throttle: only load frame every 150ms during drag
                        let now = Date()
                        if now.timeIntervalSince(lastFrameLoadTime) > 0.15 {
                            lastFrameLoadTime = now
                            manager.jumpToFrame(dragFrameIndex)
                        }
                    }
                    .onEnded { value in
                        isDragging = false
                        let prog = max(0, min(1, value.location.x / geometry.size.width))
                        let finalIndex = Int(prog * CGFloat(max(1, manager.totalFrames - 1)))
                        manager.jumpToFrame(finalIndex)
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
                    closeSearchOverlay()
                }
            
            // Search panel
            VStack(spacing: 0) {
                // Search mode toggle
                HStack(spacing: 8) {
                    Button(action: { manager.useSemanticSearch = false }) {
                        HStack(spacing: 6) {
                            Image(systemName: "text.magnifyingglass")
                            Text(L.text)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(manager.useSemanticSearch ? .white.opacity(0.5) : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(manager.useSemanticSearch ? Color.white.opacity(0.1) : Color.blue.opacity(0.8))
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { manager.useSemanticSearch = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "brain")
                            Text(L.semantic)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(manager.useSemanticSearch ? .white : .white.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(manager.useSemanticSearch ? Color.purple.opacity(0.8) : Color.white.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()

                    Text(L.searchHintShortcuts)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                
                // Search input
                HStack(spacing: 14) {
                    Image(systemName: manager.useSemanticSearch ? "brain" : "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundColor(manager.useSemanticSearch ? .purple.opacity(0.6) : .white.opacity(0.4))
                    
                    SearchTextField(
                        text: $manager.searchQuery,
                        placeholder: manager.useSemanticSearch ? L.semanticPlaceholder : L.searchPlaceholder,
                        onSubmit: {
                            openSelectedSearchResult()
                        },
                        onMoveUp: {
                            moveSearchSelection(-1)
                        },
                        onMoveDown: {
                            moveSearchSelection(1)
                        }
                    )
                    .frame(height: 30)
                    .onChange(of: manager.searchQuery) { _, newValue in
                        searchDebounceTask?.cancel()
                        selectedSearchResultIndex = 0
                        
                        if newValue.count >= 2 {
                            searchDebounceTask = Task {
                                try? await Task.sleep(nanoseconds: 150_000_000)
                                guard !Task.isCancelled else { return }
                                
                                if manager.useSemanticSearch {
                                    manager.semanticSearch(newValue)
                                } else {
                                    manager.search(newValue)
                                }
                            }
                        } else {
                            manager.searchResults = []
                        }
                    }

                    if manager.isSearchRunning {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white.opacity(0.7))
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

                if manager.isPreparingSearchHistory || manager.isSearchRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(manager.isPreparingSearchHistory ? L.loadingSearchHistory : L.searching)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Results
                if !manager.searchResults.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(manager.searchResults.enumerated()), id: \.element.id) { index, result in
                                SearchResultRow(
                                    result: result,
                                    isSelected: index == selectedSearchResultIndex,
                                    isOpening: openingSearchResultFrameId == result.frameId
                                )
                                    .onTapGesture {
                                        openSearchResult(result, selectedIndex: index)
                                    }
                            }
                        }
                    }
                    .frame(maxHeight: 400)
                } else if manager.isPreparingSearchHistory || (manager.isSearchRunning && manager.searchQuery.count >= 2) {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                        Text(manager.isPreparingSearchHistory ? L.loadingSearchHistory : L.searching)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .frame(height: 150)
                } else if !manager.searchQuery.isEmpty && manager.searchQuery.count >= 2 {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.2))
                        Text(L.noResults(manager.searchQuery))
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .frame(height: 150)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.2))
                        Text(L.typeToSearch)
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .frame(height: 150)
                }
            }
            .frame(width: 620)
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
            Text(L.loading)
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
                    Text(L.textFromScreenshot)
                        .font(.system(size: 14, weight: .semibold))
                    
                    Spacer()
                    
                    // Copy all button
                    Button(action: { manager.copyAllText() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc")
                            Text(L.copyAll)
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
                        Text(L.noTextFound)
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

    private func openSearchOverlay() {
        openingSearchResultFrameId = nil
        selectedSearchResultIndex = 0
        withAnimation { manager.isSearching = true }
    }

    private func closeSearchOverlay() {
        searchDebounceTask?.cancel()
        openingSearchResultFrameId = nil
        withAnimation(.easeOut(duration: 0.2)) {
            manager.isSearching = false
        }
    }

    private func moveSearchSelection(_ delta: Int) {
        guard !manager.searchResults.isEmpty else { return }
        let next = selectedSearchResultIndex + delta
        selectedSearchResultIndex = min(max(0, next), manager.searchResults.count - 1)
    }

    private func openSelectedSearchResult() {
        guard selectedSearchResultIndex >= 0, selectedSearchResultIndex < manager.searchResults.count else {
            if manager.useSemanticSearch {
                manager.semanticSearch(manager.searchQuery)
            } else {
                manager.search(manager.searchQuery)
            }
            return
        }
        let result = manager.searchResults[selectedSearchResultIndex]
        openSearchResult(result, selectedIndex: selectedSearchResultIndex)
    }

    private func openSearchResult(_ result: TimelineManager.SearchResult, selectedIndex: Int) {
        selectedSearchResultIndex = selectedIndex
        openingSearchResultFrameId = result.frameId
        manager.jumpToFrameId(result.frameId) { success in
            openingSearchResultFrameId = nil
            if success {
                closeSearchOverlay()
            }
        }
    }
    
    private func setupKeyHandling() {
        // Only setup once - check if already setup
        guard eventMonitors.isEmpty else { return }
        
        // Only monitor mouse movement - keyboard is handled by SwiftUI
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { event in
            showControlsTemporarily()
            return event
        }) {
            eventMonitors.append(monitor)
        }
    }
    
    private func toggleFullscreen() {
        if let window = NSApplication.shared.windows.first {
            window.toggleFullScreen(nil)
        }
    }
}

// MARK: - Glass Background Modifier (Liquid Glass on macOS 26+, Material on older)
struct GlassBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        }
    }
}

// MARK: - Control Button Style
struct ControlButtonStyle: PrimitiveButtonStyle {
    var size: CGFloat = 40
    var isActive: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        ControlButtonView(configuration: configuration, size: size, isActive: isActive)
    }
}

struct ControlButtonView: View {
    let configuration: PrimitiveButtonStyle.Configuration
    let size: CGFloat
    let isActive: Bool
    @State private var isPressed = false
    
    var body: some View {
        configuration.label
            .foregroundColor(isActive ? .cyan : (isPressed ? .white : .white.opacity(0.85)))
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(isPressed ? Color.white.opacity(0.4) : (isActive ? Color.cyan.opacity(0.2) : Color.white.opacity(0.1)))
            )
            .overlay(
                Circle()
                    .stroke(isPressed ? Color.white.opacity(0.7) : Color.white.opacity(0.15), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isPressed)
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
                isPressed = pressing
            }, perform: {
                configuration.trigger()
            })
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        withAnimation(.spring(response: 0.1, dampingFraction: 0.5)) {
                            isPressed = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                                isPressed = false
                            }
                        }
                        configuration.trigger()
                    }
            )
    }
}

// MARK: - Search Result Row
struct SearchResultRow: View {
    let result: TimelineManager.SearchResult
    var isSelected: Bool = false
    var isOpening: Bool = false
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Date/time badge
            VStack(spacing: 2) {
                Text(formatDate(result.timestamp))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Text(formatTime(result.timestamp))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(width: 54)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.08))
            )
            
            // Text content
            VStack(alignment: .leading, spacing: 4) {
                // Match type indicator + app name
                HStack(spacing: 6) {
                    // Match type icon
                    Image(systemName: matchTypeIcon)
                        .font(.system(size: 10))
                        .foregroundColor(matchTypeColor)
                    
                    // Similarity score for semantic search
                    if result.score > 0 {
                        Text("[\(Int(result.score * 100))%]")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.purple.opacity(0.8))
                    }
                    
                    if !result.appName.isEmpty {
                        Text(result.appName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                
                // URL if available
                if let url = result.url, !url.isEmpty {
                    Text(formatURL(url))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.7))
                        .lineLimit(1)
                }
                
                Text(cleanupText(result.text))
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
            }
            
            Spacer()
            
            if isOpening {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.8))
            } else {
                // Arrow
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(isHovered || isSelected ? 0.6 : 0.2))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.blue.opacity(0.20) : (isHovered ? Color.white.opacity(0.06) : Color.clear))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue.opacity(0.55) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    // Match type icon
    private var matchTypeIcon: String {
        switch result.matchType {
        case .url: return "link"
        case .title: return "textformat"
        case .clipboard: return "doc.on.clipboard"
        case .ocr: return "text.viewfinder"
        }
    }
    
    // Match type color
    private var matchTypeColor: Color {
        switch result.matchType {
        case .url: return .cyan
        case .title: return .orange
        case .clipboard: return .green
        case .ocr: return .white.opacity(0.5)
        }
    }
    
    // Format URL to show domain
    private func formatURL(_ url: String) -> String {
        if let urlObj = URL(string: url), let host = urlObj.host {
            let path = urlObj.path
            if path.count > 1 && path.count < 40 {
                return "\(host)\(path)"
            }
            return host
        }
        return String(url.prefix(50))
    }
    
    // "8 dec" format - handles both "2025-12-07 20:42:17" and "2025-12-08T01:39:08Z"
    private func formatDate(_ timestamp: String) -> String {
        let clean = timestamp.replacingOccurrences(of: "\"", with: "")
        // Split by T or space
        let parts = clean.contains("T") ? clean.split(separator: "T") : clean.split(separator: " ")
        guard let datePart = parts.first else { return "?" }
        let dateComponents = datePart.split(separator: "-")
        guard dateComponents.count >= 3 else { return String(datePart) }
        
        let day = Int(dateComponents[2]) ?? 0
        let monthNum = Int(dateComponents[1]) ?? 0
        let months = L.months
        let month = monthNum > 0 && monthNum < months.count ? months[monthNum] : ""
        return day > 0 ? "\(day) \(month)" : "?"
    }
    
    // "14:30" format - handles both formats
    private func formatTime(_ timestamp: String) -> String {
        let clean = timestamp.replacingOccurrences(of: "\"", with: "")
        let parts = clean.contains("T") ? clean.split(separator: "T") : clean.split(separator: " ")
        guard parts.count >= 2 else { return "" }
        let timePart = String(parts[1]).replacingOccurrences(of: "Z", with: "")
        let timeComponents = timePart.split(separator: ":")
        guard timeComponents.count >= 2 else { return timePart }
        return "\(timeComponents[0]):\(timeComponents[1])"
    }
    
    // Filter out boring menu bar text, keep interesting content
    private func cleanupText(_ text: String) -> String {
        // Common menu items to filter
        let menuPatterns = [
            "File Edit Selection View Run Terminal Window Help",
            "Arkiv Redigera Innehall Fonster Hjalp",
            "Arkiv Redigera Innehåll Fönster Hjälp",
            "File Edit View Insert Format",
            "KBIS"
        ]
        
        let lines = text.components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return false }
                // Skip lines that are mostly menu text
                for pattern in menuPatterns {
                    if trimmed.contains(pattern) { return false }
                }
                // Skip very short lines (likely UI noise)
                if trimmed.count < 5 { return false }
                return true
            }
        
        // Return first meaningful lines
        let result = lines.prefix(3).joined(separator: " · ")
        return result.isEmpty ? text.prefix(80).description : result
    }
}

// MARK: - Live Text Image View with Zoom
struct LiveTextImageView: NSViewRepresentable {
    let image: NSImage
    @Binding var zoomLevel: CGFloat
    let isFitToScreen: Bool
    
    init(image: NSImage, zoomLevel: Binding<CGFloat>, isFitToScreen: Bool) {
        self.image = image
        self._zoomLevel = zoomLevel
        self.isFitToScreen = isFitToScreen
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
                overlayView?.preferredInteractionTypes = .automatic  // All interaction types
            }
        }
        
        func analyzeImage(_ image: NSImage, imageView: NSImageView) {
            guard let analyzer = analyzer,
                  let overlayView = overlayView else { return }
            
            // Always update trackingImageView 
            overlayView.trackingImageView = imageView
            
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
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 5.0
        context.coordinator.scrollView = scrollView
        
        let clipView = NSClipView()
        clipView.backgroundColor = .clear
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        
        // Container at native image size
        let containerView = FlippedView()
        containerView.wantsLayer = true
        
        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.frame = NSRect(origin: .zero, size: image.size)
        containerView.addSubview(imageView)
        containerView.frame = NSRect(origin: .zero, size: image.size)
        
        // Live Text overlay
        if let overlayView = context.coordinator.overlayView {
            overlayView.frame = imageView.frame
            containerView.addSubview(overlayView)
            overlayView.trackingImageView = imageView
            context.coordinator.analyzeImage(image, imageView: imageView)
        }
        
        scrollView.documentView = containerView

        if isFitToScreen {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            let clipSize = scrollView.contentView.bounds.size
            containerView.frame = NSRect(origin: .zero, size: clipSize)
            imageView.frame = aspectFitRect(for: image.size, in: containerView.bounds)
            if let overlayView = context.coordinator.overlayView {
                overlayView.frame = imageView.frame
                overlayView.trackingImageView = imageView
            }
            scrollView.magnification = 1.0
        } else {
            // Set initial magnification low, then fit
            scrollView.magnification = 0.1
            DispatchQueue.main.async {
                self.fitToWindow(scrollView)
            }
        }
        
        return scrollView
    }
    
    private func fitToWindow(_ scrollView: NSScrollView) {
        let clipSize = scrollView.contentView.bounds.size
        let imageSize = image.size
        guard clipSize.width > 10, clipSize.height > 10, imageSize.width > 10, imageSize.height > 10 else { 
            return 
        }
        
        // Calculate scale to fit
        let scaleW = clipSize.width / imageSize.width
        let scaleH = clipSize.height / imageSize.height
        let scale = min(scaleW, scaleH) * 0.95  // 95% to leave margin
        
        scrollView.magnification = scale
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.centerContent(scrollView)
        }
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let containerView = scrollView.documentView,
              let imageView = containerView.subviews.first as? NSImageView else { return }
        
        let size = image.size
        imageView.image = image
        
        // Update image scaling; in fit mode we set a precise aspect-fit frame.
        imageView.imageScaling = .scaleAxesIndependently
        
        let overlayView = context.coordinator.overlayView

        // Set container to clip view size if fit-to-screen, else native image size.
        if isFitToScreen {
            let clipSize = scrollView.contentView.bounds.size
            containerView.frame = NSRect(origin: .zero, size: clipSize)
            imageView.frame = aspectFitRect(for: size, in: containerView.bounds)
            scrollView.magnification = 1.0
            scrollView.contentView.scroll(to: .zero)
        } else {
            containerView.frame = NSRect(origin: .zero, size: size)
            imageView.frame = NSRect(origin: .zero, size: size)
            scrollView.magnification = zoomLevel
        }
        
        // Update overlay to match image frame exactly.
        if let overlayView {
            overlayView.frame = imageView.frame
            overlayView.trackingImageView = imageView
        }
        
        context.coordinator.analyzeImage(image, imageView: imageView)
    }

    private func aspectFitRect(for imageSize: NSSize, in bounds: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }

        let imageAspect = imageSize.width / imageSize.height
        let boundsAspect = bounds.width / bounds.height

        if imageAspect > boundsAspect {
            let width = bounds.width
            let height = width / imageAspect
            let y = bounds.minY + (bounds.height - height) / 2
            return NSRect(x: bounds.minX, y: y, width: width, height: height)
        } else {
            let height = bounds.height
            let width = height * imageAspect
            let x = bounds.minX + (bounds.width - width) / 2
            return NSRect(x: x, y: bounds.minY, width: width, height: height)
        }
    }
    
    private func centerContent(_ scrollView: NSScrollView) {
        guard let doc = scrollView.documentView else { return }
        let docSize = doc.frame.size
        let clipSize = scrollView.contentView.bounds.size
        let x = max(0, (docSize.width * scrollView.magnification - clipSize.width) / 2)
        let y = max(0, (docSize.height * scrollView.magnification - clipSize.height) / 2)
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

// MARK: - App Icon View
struct AppIconView: View {
    let appName: String
    @State private var appIcon: NSImage?
    
    // Known app bundle IDs
    private static let bundleIds: [String: String] = [
        "Safari": "com.apple.Safari",
        "Google Chrome": "com.google.Chrome",
        "Chrome": "com.google.Chrome",
        "Firefox": "org.mozilla.firefox",
        "Arc": "company.thebrowser.Browser",
        "Cursor": "com.todesktop.230313mzl4w4u92",
        "Visual Studio Code": "com.microsoft.VSCode",
        "Code": "com.microsoft.VSCode",
        "Terminal": "com.apple.Terminal",
        "iTerm": "com.googlecode.iterm2",
        "Finder": "com.apple.finder",
        "Mail": "com.apple.mail",
        "Messages": "com.apple.MobileSMS",
        "Slack": "com.tinyspeck.slackmacgap",
        "Discord": "com.hnc.Discord",
        "Spotify": "com.spotify.client",
        "Notes": "com.apple.Notes",
        "Preview": "com.apple.Preview",
        "Photos": "com.apple.Photos",
        "Xcode": "com.apple.dt.Xcode",
        "Figma": "com.figma.Desktop",
        "Notion": "notion.id",
        "Obsidian": "md.obsidian",
        "Brave Browser": "com.brave.Browser",
        "Microsoft Edge": "com.microsoft.edgemac"
    ]
    
    var body: some View {
        Group {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Fallback: colored circle with first letter
                ZStack {
                    Circle()
                        .fill(TimelineManager.colorForApp(appName))
                    Text(String(appName.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .onAppear { loadIcon() }
        .onChange(of: appName) { loadIcon() }
    }
    
    private func loadIcon() {
        // Try to get icon from bundle ID
        if let bundleId = Self.bundleIds[appName],
           let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            appIcon = NSWorkspace.shared.icon(forFile: appUrl.path)
            return
        }
        
        // Try to find app by name in /Applications
        let appPaths = [
            "/Applications/\(appName).app",
            "/Applications/\(appName.replacingOccurrences(of: " ", with: "")).app",
            "/System/Applications/\(appName).app"
        ]
        
        for path in appPaths {
            if FileManager.default.fileExists(atPath: path) {
                appIcon = NSWorkspace.shared.icon(forFile: path)
                return
            }
        }
        
        // No icon found, use fallback
        appIcon = nil
    }
}

// MARK: - Native Search TextField (NSViewRepresentable)
struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.font = NSFont.systemFont(ofSize: 20, weight: .medium)
        textField.textColor = .white
        textField.backgroundColor = .clear
        textField.isBordered = false
        textField.focusRingType = .none
        textField.drawsBackground = false
        textField.cell?.sendsActionOnEndEditing = false
        
        // Auto-focus when created
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            textField.window?.makeFirstResponder(textField)
        }
        
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchTextField
        
        init(_ parent: SearchTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ notification: Notification) {
            if let textField = notification.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onMoveUp()
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onMoveDown()
                return true
            }
            return false
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(TimelineManager())
        .frame(width: 1200, height: 800)
}
