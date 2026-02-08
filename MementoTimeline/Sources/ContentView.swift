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

private enum SearchPanelState {
    case idle
    case loading
    case empty
    case error(String)
    case results
}

private struct CommandPaletteEntry: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let action: () -> Void
}

private enum TimelineVisualTokens {
    static let searchPanelWidth: CGFloat = 640
    static let searchPanelCornerRadius: CGFloat = 20
    static let searchRowCornerRadius: CGFloat = 8
    static let searchPreviewCornerRadius: CGFloat = 12
    static let commandPanelWidth: CGFloat = 620
    static let commandPanelCornerRadius: CGFloat = 18
    static let commandRowCornerRadius: CGFloat = 10
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
    @State private var commandPaletteQuery: String = ""
    @State private var selectedCommandIndex: Int = 0
    
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

            // Command palette overlay
            if manager.isCommandPaletteOpen {
                commandPaletteOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
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
        .focusable(!manager.isSearching && !manager.isCommandPaletteOpen)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            if !manager.isSearching && !manager.isCommandPaletteOpen {
                manager.previousFrame()
                showControlsTemporarily()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.rightArrow) {
            if !manager.isSearching && !manager.isCommandPaletteOpen {
                manager.nextFrame()
                showControlsTemporarily()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.space) {
            if !manager.isSearching && !manager.isCommandPaletteOpen {
                showControls.toggle()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if manager.isCommandPaletteOpen {
                closeCommandPalette()
                return .handled
            }
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
        .onChange(of: manager.isCommandPaletteOpen) { _, isOpen in
            if isOpen {
                commandPaletteQuery = ""
                selectedCommandIndex = 0
                manager.isSearching = false
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
                        // Command palette
                        Button(action: {
                            NSApplication.shared.activate(ignoringOtherApps: true)
                            NSApplication.shared.keyWindow?.makeKey()
                            openCommandPalette()
                        }) {
                            Image(systemName: "command")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(ControlButtonStyle(size: 30, isActive: manager.isCommandPaletteOpen))
                        .help(L.commandPaletteHelp)

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
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let maxIndex = max(0, manager.totalFrames - 1)
                let activeIndex = isDragging ? dragFrameIndex : manager.currentFrameIndex
                let clampedActiveIndex = min(max(0, activeIndex), maxIndex)
                let progress = manager.totalFrames > 1
                    ? CGFloat(clampedActiveIndex) / CGFloat(maxIndex)
                    : 0
                let currentX = geometry.size.width * progress

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.28), Color.blue.opacity(0.30), Color.cyan.opacity(0.28)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 14)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )

                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: max(7, geometry.size.width * progress), height: 14)

                    if (isHoveringTimeline || isDragging), manager.totalFrames > 0 {
                        let width = max(1, geometry.size.width)
                        let hoverProgress = max(0, min(1, mouseLocation.x / width))
                        let hoverIndex = isDragging
                            ? clampedActiveIndex
                            : Int(round(hoverProgress * CGFloat(maxIndex)))
                        let markerX = isDragging ? currentX : geometry.size.width * hoverProgress
                        let minX: CGFloat = 46
                        let maxX = max(minX, geometry.size.width - minX)
                        let clampedMarkerX = min(max(markerX, minX), maxX)

                        if let segment = manager.getSegmentForIndex(hoverIndex) {
                            VStack(spacing: 4) {
                                Text(segment.timeString.isEmpty ? "--:--" : formatTime(segment.timeString))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(segment.color.opacity(0.90))
                                    )

                                Text(segment.appName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                            .offset(x: clampedMarkerX - 40, y: -47)
                        }

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 3, height: 22)
                            .offset(x: clampedMarkerX - 1.5, y: -1)
                    }

                    ZStack {
                        Circle()
                            .fill(manager.getColorForCurrentFrame())
                            .frame(width: 18, height: 18)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                    }
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    .offset(x: currentX - 9)
                }
                .frame(height: 24)
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
                            mouseLocation = value.location
                            let width = max(1, geometry.size.width)
                            let prog = max(0, min(1, value.location.x / width))
                            dragFrameIndex = Int(prog * CGFloat(maxIndex))

                            // Throttle: only load frame every 150ms during drag
                            let now = Date()
                            if now.timeIntervalSince(lastFrameLoadTime) > 0.15 {
                                lastFrameLoadTime = now
                                manager.jumpToFrame(dragFrameIndex)
                            }
                        }
                        .onEnded { value in
                            isDragging = false
                            let width = max(1, geometry.size.width)
                            let prog = max(0, min(1, value.location.x / width))
                            let finalIndex = Int(prog * CGFloat(maxIndex))
                            manager.jumpToFrame(finalIndex)
                        }
                )
            }
            .frame(height: 24)

            HStack(spacing: 12) {
                Text(timelineStartLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(timelineProgressLabel)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(timelineEndLabel)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.55))

            HStack(spacing: 8) {
                if manager.isLoadingMore {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.8))
                } else {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                }

                Text(historyLoadStatusText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                if !manager.isLoadingMore {
                    Text(L.olderHistoryHintShort)
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white.opacity(0.6))
        }
    }
    
    private func formatTime(_ timeString: String) -> String {
        // Extract HH:mm from both ISO and SQL-like timestamp formats.
        let clean = timeString.replacingOccurrences(of: "\"", with: "")
        let parts = clean.contains("T") ? clean.split(separator: "T") : clean.split(separator: " ")
        if parts.count >= 2 {
            let timePart = String(parts[1]).replacingOccurrences(of: "Z", with: "")
            let timeComponents = timePart.split(separator: ":")
            if timeComponents.count >= 2 {
                return "\(timeComponents[0]):\(timeComponents[1])"
            }
            return timePart
        }
        return clean
    }

    private var timelineStartLabel: String {
        timelineLabelForIndex(0)
    }

    private var timelineEndLabel: String {
        guard manager.totalFrames > 0 else { return "—" }
        return timelineLabelForIndex(manager.totalFrames - 1)
    }

    private var timelineProgressLabel: String {
        guard manager.totalFrames > 0 else { return "0 / 0" }
        let position = min(max(1, manager.currentFrameIndex + 1), manager.totalFrames)
        let percent = Int((Double(position) / Double(max(1, manager.totalFrames))) * 100)
        return "\(position) / \(manager.totalFrames) (\(percent)%)"
    }

    private func timelineLabelForIndex(_ index: Int) -> String {
        guard manager.totalFrames > 0, let segment = manager.getSegmentForIndex(index) else { return "—" }
        return formatTimeDisplay(segment.timeString)
    }

    private var historyLoadStatusText: String {
        guard let first = manager.timelineSegments.first?.time,
              let last = manager.timelineSegments.last?.time else {
            return manager.isLoadingMore ? L.loadingOlderHistory : "\(L.loadedPrefix): —"
        }

        if manager.isLoadingMore {
            return L.loadingOlderHistory
        }

        let span = max(0, last.timeIntervalSince(first))
        return "\(L.loadedPrefix): \(formatLoadedSpan(span))"
    }

    private func formatLoadedSpan(_ interval: TimeInterval) -> String {
        let totalMinutes = max(1, Int(interval / 60))
        if totalMinutes < 120 {
            return "\(totalMinutes)m"
        }

        let totalHours = totalMinutes / 60
        if totalHours < 72 {
            return "\(totalHours)h"
        }

        let days = totalHours / 24
        return "\(days)d"
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
                    Button(action: { setSearchMode(semantic: false) }) {
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
                    .accessibilityLabel(L.text)
                    
                    Button(action: { setSearchMode(semantic: true) }) {
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
                    .accessibilityLabel(L.semantic)
                    
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
                    .accessibilityLabel(manager.useSemanticSearch ? L.semanticPlaceholder : L.searchPlaceholder)
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
                            manager.searchErrorMessage = nil
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
                            manager.searchErrorMessage = nil
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

                if let selectedResult = selectedSearchResult {
                    searchPreviewSection(result: selectedResult)
                    Divider()
                        .background(Color.white.opacity(0.08))
                }
                
                // Results
                switch searchPanelState {
                case .results:
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(manager.searchResults.enumerated()), id: \.element.id) { index, result in
                                SearchResultRow(
                                    result: result,
                                    query: manager.searchQuery,
                                    isSelected: index == selectedSearchResultIndex,
                                    isOpening: openingSearchResultFrameId == result.frameId
                                )
                                    .onHover { isHovering in
                                        if isHovering {
                                            selectedSearchResultIndex = index
                                        }
                                    }
                                    .onTapGesture {
                                        openSearchResult(result, selectedIndex: index)
                                    }
                            }
                        }
                    }
                    .frame(maxHeight: 400)
                case .loading:
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                        Text(manager.isPreparingSearchHistory ? L.loadingSearchHistory : L.searching)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .frame(height: 150)
                case .empty:
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.2))
                        Text(L.noResults(manager.searchQuery))
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.5))
                        Button(manager.useSemanticSearch ? L.searchTryText : L.searchTrySemantic) {
                            setSearchMode(semantic: !manager.useSemanticSearch)
                            retryCurrentSearch()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(height: 150)
                case .error(let message):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(.orange.opacity(0.9))
                        Text(L.searchErrorTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                        Button(L.searchRetry) {
                            retryCurrentSearch()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(height: 180)
                case .idle:
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
            .frame(width: TimelineVisualTokens.searchPanelWidth)
            .background(
                RoundedRectangle(cornerRadius: TimelineVisualTokens.searchPanelCornerRadius)
                    .fill(Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 0.98)))
                    .shadow(color: .black.opacity(0.5), radius: 40, y: 15)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TimelineVisualTokens.searchPanelCornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    // MARK: - Command Palette
    private var commandPaletteOverlay: some View {
        let entries = commandPaletteEntries

        return ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    closeCommandPalette()
                }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "command")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))

                    SearchTextField(
                        text: $commandPaletteQuery,
                        placeholder: L.commandPalettePlaceholder,
                        onSubmit: { runSelectedCommand() },
                        onMoveUp: { moveCommandSelection(-1) },
                        onMoveDown: { moveCommandSelection(1) }
                    )
                    .frame(height: 28)
                    .accessibilityLabel(L.commandPalettePlaceholder)
                    .onChange(of: commandPaletteQuery) { _, _ in
                        selectedCommandIndex = 0
                    }

                    Text(L.commandPaletteHint)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))

                    Button(action: { closeCommandPalette() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()
                    .background(Color.white.opacity(0.1))

                if commandPaletteQuery.isEmpty, !manager.recentSearchSelections.isEmpty {
                    HStack {
                        Text(L.commandRecentMatches)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.55))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                }

                if entries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "terminal")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.2))
                        Text(L.commandNoActions)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    .frame(height: 180)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                CommandPaletteRow(
                                    title: entry.title,
                                    subtitle: entry.subtitle,
                                    icon: entry.icon,
                                    tint: entry.tint,
                                    isSelected: index == selectedCommandIndex
                                )
                                .onHover { hovering in
                                    if hovering {
                                        selectedCommandIndex = index
                                    }
                                }
                                .onTapGesture {
                                    selectedCommandIndex = index
                                    entry.action()
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                    }
                    .frame(maxHeight: 300)
                }
            }
            .frame(width: TimelineVisualTokens.commandPanelWidth)
            .background(
                RoundedRectangle(cornerRadius: TimelineVisualTokens.commandPanelCornerRadius)
                    .fill(Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 0.98)))
                    .shadow(color: .black.opacity(0.5), radius: 35, y: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TimelineVisualTokens.commandPanelCornerRadius)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
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
        manager.searchErrorMessage = nil
        manager.isCommandPaletteOpen = false
        withAnimation { manager.isSearching = true }
    }

    private func closeSearchOverlay() {
        searchDebounceTask?.cancel()
        openingSearchResultFrameId = nil
        withAnimation(.easeOut(duration: 0.2)) {
            manager.isSearching = false
        }
    }

    private func openCommandPalette() {
        manager.isSearching = false
        manager.searchErrorMessage = nil
        commandPaletteQuery = ""
        selectedCommandIndex = 0
        withAnimation(.easeOut(duration: 0.15)) {
            manager.isCommandPaletteOpen = true
        }
    }

    private func closeCommandPalette() {
        withAnimation(.easeOut(duration: 0.15)) {
            manager.isCommandPaletteOpen = false
        }
    }

    private var commandPaletteEntries: [CommandPaletteEntry] {
        let query = commandPaletteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        var entries: [CommandPaletteEntry] = []

        if !query.isEmpty {
            entries.append(
                CommandPaletteEntry(
                    id: "search:\(query)",
                    title: L.searchFor(query),
                    subtitle: manager.useSemanticSearch ? L.semantic : L.text,
                    icon: manager.useSemanticSearch ? "brain" : "magnifyingglass",
                    tint: .blue
                ) {
                    runSearchFromPalette(query: query)
                }
            )

            if let parsed = parseTimeQuery(query) {
                entries.append(
                    CommandPaletteEntry(
                        id: "time:\(parsed.display)",
                        title: L.jumpToTime(parsed.display),
                        subtitle: L.commandJumpToTimeSubtitle,
                        icon: "clock.arrow.circlepath",
                        tint: .mint
                    ) {
                        let opened = manager.jumpToClosestTime(hour: parsed.hour, minute: parsed.minute)
                        if opened {
                            closeCommandPalette()
                        }
                    }
                )
            }
        }

        let baseEntries: [CommandPaletteEntry] = [
            CommandPaletteEntry(
                id: "open-search",
                title: L.commandOpenSearch,
                subtitle: L.commandOpenSearchSubtitle,
                icon: "magnifyingglass",
                tint: .blue
            ) {
                openSearchOverlay()
            },
            CommandPaletteEntry(
                id: "toggle-text",
                title: manager.showTextOverlay ? L.commandHideTextPanel : L.commandShowTextPanel,
                subtitle: L.commandTextPanelSubtitle,
                icon: manager.showTextOverlay ? "text.bubble.fill" : "text.bubble",
                tint: .purple
            ) {
                withAnimation(.spring(response: 0.3)) {
                    manager.showTextOverlay.toggle()
                    if manager.showTextOverlay {
                        manager.loadTextForCurrentFrame()
                    }
                }
                closeCommandPalette()
            },
            CommandPaletteEntry(
                id: "toggle-mode",
                title: manager.useSemanticSearch ? L.commandUseTextSearch : L.commandUseSemantic,
                subtitle: L.commandSearchModeSubtitle,
                icon: manager.useSemanticSearch ? "text.magnifyingglass" : "brain",
                tint: .orange
            ) {
                setSearchMode(semantic: !manager.useSemanticSearch)
                closeCommandPalette()
            }
        ]

        let recent = manager.recentSearchSelections.prefix(5).map { selection in
            CommandPaletteEntry(
                id: "recent:\(selection.frameId)",
                title: selection.text,
                subtitle: selection.appName.isEmpty
                    ? "\(selection.matchType.label) · \(formatTimeDisplay(selection.timestamp))"
                    : "\(selection.matchType.label) · \(selection.appName) · \(formatTimeDisplay(selection.timestamp))",
                icon: "clock",
                tint: .green
            ) {
                manager.jumpToFrameId(selection.frameId) { success in
                    if success {
                        closeCommandPalette()
                    }
                }
            }
        }

        let filterableEntries = baseEntries + recent
        if query.isEmpty {
            entries.append(contentsOf: filterableEntries)
        } else {
            let filtered = filterableEntries.filter { entry in
                entry.title.localizedCaseInsensitiveContains(query) ||
                entry.subtitle.localizedCaseInsensitiveContains(query)
            }
            entries.append(contentsOf: filtered)
        }

        return entries
    }

    private func moveCommandSelection(_ delta: Int) {
        let entries = commandPaletteEntries
        guard !entries.isEmpty else { return }
        let next = selectedCommandIndex + delta
        selectedCommandIndex = min(max(0, next), entries.count - 1)
    }

    private func runSelectedCommand() {
        let entries = commandPaletteEntries
        guard !entries.isEmpty else { return }
        let index = min(max(0, selectedCommandIndex), entries.count - 1)
        entries[index].action()
    }

    private func runSearchFromPalette(query: String) {
        openSearchOverlay()
        manager.searchQuery = query
        if query.count >= 2 {
            if manager.useSemanticSearch {
                manager.semanticSearch(query)
            } else {
                manager.search(query)
            }
        }
    }

    private func parseTimeQuery(_ query: String) -> (display: String, hour: Int, minute: Int)? {
        let cleaned = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: ":")
        let parts = cleaned.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        let display = String(format: "%02d:%02d", hour, minute)
        return (display, hour, minute)
    }

    private func moveSearchSelection(_ delta: Int) {
        guard !manager.searchResults.isEmpty else { return }
        let next = selectedSearchResultIndex + delta
        selectedSearchResultIndex = min(max(0, next), manager.searchResults.count - 1)
    }

    private var selectedSearchResult: TimelineManager.SearchResult? {
        guard selectedSearchResultIndex >= 0, selectedSearchResultIndex < manager.searchResults.count else {
            return nil
        }
        return manager.searchResults[selectedSearchResultIndex]
    }

    private var searchPanelState: SearchPanelState {
        if let error = manager.searchErrorMessage, !error.isEmpty {
            return .error(error)
        }
        if !manager.searchResults.isEmpty {
            return .results
        }
        if manager.isPreparingSearchHistory || (manager.isSearchRunning && manager.searchQuery.count >= 2) {
            return .loading
        }
        if manager.searchQuery.count >= 2 {
            return .empty
        }
        return .idle
    }

    private func setSearchMode(semantic: Bool) {
        guard manager.useSemanticSearch != semantic else { return }
        manager.useSemanticSearch = semantic
        manager.searchResults = []
        manager.searchErrorMessage = nil
        selectedSearchResultIndex = 0
    }

    private func retryCurrentSearch() {
        guard manager.searchQuery.count >= 2 else { return }
        if manager.useSemanticSearch {
            manager.semanticSearch(manager.searchQuery)
        } else {
            manager.search(manager.searchQuery)
        }
    }

    @ViewBuilder
    private func searchPreviewSection(result: TimelineManager.SearchResult) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(L.searchPreviewTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.82))
                    Text(result.matchType.label)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(result.matchType.badgeColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(result.matchType.badgeColor.opacity(0.18))
                        )
                }

                Text(result.appName.isEmpty ? L.searchPreviewHint : "\(result.appName) · \(formatTimeDisplay(result.timestamp))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.58))
                    .lineLimit(1)

                Text(result.text)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
            }

            Spacer()

            Button(L.searchOpenSelected) {
                openSearchResult(result, selectedIndex: selectedSearchResultIndex)
            }
            .buttonStyle(.borderedProminent)
            .disabled(openingSearchResultFrameId != nil)
            .accessibilityLabel(L.searchOpenSelected)
            .accessibilityHint(L.searchPreviewHint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: TimelineVisualTokens.searchPreviewCornerRadius)
                .fill(Color.white.opacity(0.04))
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
                manager.rememberRecentSearch(result)
                closeSearchOverlay()
            } else {
                manager.searchErrorMessage = L.searchOpenError
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

// MARK: - Command Palette Row
struct CommandPaletteRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 20, height: 20)
                .background(tint.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: TimelineVisualTokens.commandRowCornerRadius)
                .fill(isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: TimelineVisualTokens.commandRowCornerRadius)
                .stroke(isSelected ? Color.white.opacity(0.28) : Color.clear, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Search Result Row
struct SearchResultRow: View {
    let result: TimelineManager.SearchResult
    var query: String = ""
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
                    Text(result.matchType.label)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(result.matchType.badgeColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(result.matchType.badgeColor.opacity(0.18))
                        )
                    
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
                    highlightedText(formatURL(url), query: query)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.7))
                        .lineLimit(1)
                }
                
                highlightedText(cleanupText(result.text), query: query)
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
            RoundedRectangle(cornerRadius: TimelineVisualTokens.searchRowCornerRadius)
                .stroke(isSelected ? Color.blue.opacity(0.55) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: TimelineVisualTokens.searchRowCornerRadius))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(L.searchOpenSelected)
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

    private func highlightedText(_ source: String, query: String) -> Text {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Text(source)
        }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return Text(source)
        }

        var cursor = source.startIndex
        var combined = Text("")

        while cursor < source.endIndex,
              let range = source.range(
                  of: normalizedQuery,
                  options: [.caseInsensitive, .diacriticInsensitive],
                  range: cursor..<source.endIndex
              ) {
            if cursor < range.lowerBound {
                combined = combined + Text(String(source[cursor..<range.lowerBound]))
            }
            combined = combined + Text(String(source[range]))
                .fontWeight(.semibold)
                .foregroundColor(.yellow.opacity(0.95))
            cursor = range.upperBound
        }

        if cursor < source.endIndex {
            combined = combined + Text(String(source[cursor..<source.endIndex]))
        }
        return combined
    }

    private var accessibilitySummary: String {
        let date = formatDate(result.timestamp)
        let time = formatTime(result.timestamp)
        let app = result.appName.isEmpty ? "" : "\(result.appName), "
        return "\(result.matchType.label), \(date) \(time), \(app)\(cleanupText(result.text))"
    }
}

private extension TimelineManager.SearchResult.MatchType {
    var label: String {
        switch self {
        case .ocr: return "OCR"
        case .url: return "URL"
        case .title: return "TITLE"
        case .clipboard: return "CLIP"
        }
    }

    var badgeColor: Color {
        switch self {
        case .url: return .cyan
        case .title: return .orange
        case .clipboard: return .green
        case .ocr: return .white.opacity(0.75)
        }
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
