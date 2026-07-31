import AppKit
import SwiftUI
import MovieCutCore
import UniformTypeIdentifiers

extension UTType {
    static let movieCutMediaAssetID = UTType(exportedAs: "com.moviecut.media-asset-id")
}

struct TimelineView: View {
    var viewModel: EditorViewModel

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var draggedClipId: UUID? = nil
    @State private var dragInitialTimelineRange: TimeRange?
    @State private var dragInitialSourceRange: TimeRange?
    @State private var timelineViewportWidth: CGFloat = 900
    @State private var timelineScrollViewportWidth: CGFloat = 900
    @State private var filmstripStore = TimelineFilmstripStore()
    @State private var isRulerScrubbing = false
    @State private var isPlayheadScrubbing = false
    @State private var playheadDragStartTime: TimeInterval = 0

    private let trackHeight: CGFloat = 50
    private let rulerHeight: CGFloat = 24
    private let trimHandleWidth: CGFloat = 8
    /// Shares the view model's minimum so drag and keyboard trim agree (Step 5).
    private var minimumClipDuration: TimeInterval { EditorViewModel.minimumTimelineClipDuration }
    private let markerLabelWidth: CGFloat = 132
    private let minimumTimelineContentWidth: CGFloat = 900
    private let timelineZoomRange: ClosedRange<Double> = 20...300
    private let fitTimelineFallbackWidth: CGFloat = 900
    private let minimumFitDuration: TimeInterval = 0.1

    private var pixelsPerSecond: Double {
        viewModel.timelineZoom
    }

    private var sortedMarkers: [Marker] {
        viewModel.currentProject.markers.sorted { $0.time < $1.time }
    }

    private var mainVideoTrackId: Track.ID? {
        viewModel.currentProject.timeline.tracks.first { $0.kind == .video }?.id
    }

    private func isMainVideoTrack(_ track: Track) -> Bool {
        track.id == mainVideoTrackId
    }

    private var timelineContentWidth: CGFloat {
        let markerEnd = sortedMarkers.map(\.time).max() ?? 0
        let visibleSeconds = max(viewModel.visibleTimelineDuration, markerEnd + 2)
        return max(minimumTimelineContentWidth, CGFloat(visibleSeconds) * CGFloat(pixelsPerSecond) + markerLabelWidth)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: MovieCutSpacing.small) {
                MovieCutIconTitle(
                    title: NSLocalizedString("Timeline", comment: ""),
                    systemImage: "timeline.selection"
                )
                if !sortedMarkers.isEmpty {
                    Text("\(sortedMarkers.count) markers")
                        .font(MovieCutTypography.metadata)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 22)
                    .overlay(MovieCutTheme.divider)

                selectedClipToolbar

                Divider()
                    .frame(height: 22)
                    .overlay(MovieCutTheme.divider)

                timelineMarkerControls

                Divider()
                    .frame(height: 22)
                    .overlay(MovieCutTheme.divider)

                Spacer(minLength: MovieCutSpacing.small)

                zoomControls
            }
            .padding(.horizontal, MovieCutSpacing.medium)
            .padding(.vertical, MovieCutSpacing.xSmall)
            .background(MovieCutTheme.panelBackgroundRaised)

            Divider()
                .overlay(MovieCutTheme.divider)

            ScrollViewReader { scrollProxy in
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 0) {
                        timeRuler

                        ForEach(viewModel.currentProject.timeline.tracks) { track in
                            trackLane(track)
                        }
                    }
                    .background(MovieCutTheme.timelineBackground)
                }
                .coordinateSpace(name: TimelineFilmstripCoordinateSpace.viewport)
                .background(timelineScrollViewportWidthReader)
                .movieCutScrollBackground(MovieCutTheme.timelineBackground)
                // Blade tool cursor feedback (S9).
                .cursor(viewModel.timelineTool == .blade ? .crosshair : nil)
                // Cmd + scroll to zoom the timeline (S9). Without ⌘, the scroll
                // view pans normally.
                .background(TimelineScrollZoomReader { delta in
                    let next = viewModel.timelineZoom + delta * (viewModel.timelineZoom / 8)
                    viewModel.timelineZoom = clampedTimelineZoom(next)
                })
                #if DEBUG
                .onAppear {
                    TimelineFilmstripDebugProbe.shared.registerPerformanceDriver(
                        setZoom: { zoom in
                            viewModel.timelineZoom = clampedTimelineZoom(zoom)
                        },
                        scrollTo: { sourceTime in
                            let boundedSeconds = max(0, sourceTime.isFinite ? sourceTime : 0)
                            let anchorMilliseconds = Int(
                                ((boundedSeconds / 15).rounded() * 15 * 1_000).rounded()
                            )
                            Task { @MainActor in
                                await Task.yield()
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    scrollProxy.scrollTo(
                                        TimelineFilmstripDebugScrollAnchor(
                                            milliseconds: anchorMilliseconds
                                        ),
                                        anchor: UnitPoint(x: 0.5, y: 0)
                                    )
                                }
                            }
                        },
                        cacheMetrics: {
                            await filmstripStore.cacheMetrics()
                        }
                    )
                }
                .onDisappear {
                    TimelineFilmstripDebugProbe.shared.unregisterPerformanceDriver()
                }
                #endif
            }
        }
        // Header (~28) + ruler (24) + 3 default track lanes (3 x 50) must stay visible.
        .frame(minHeight: 210)
        .background(MovieCutTheme.timelineBackground)
        .background(timelineViewportWidthReader)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NSLocalizedString("Timeline", comment: ""))
        .accessibilityIdentifier("timeline.root")
        .onDisappear {
            filmstripStore.cancelAll()
        }
    }

    private var timelineViewportWidthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    timelineViewportWidth = proxy.size.width
                }
                .onChange(of: proxy.size.width) { _, newWidth in
                    timelineViewportWidth = newWidth
                }
        }
    }

    private var timelineScrollViewportWidthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    timelineScrollViewportWidth = proxy.size.width
                }
                .onChange(of: proxy.size.width) { _, newWidth in
                    timelineScrollViewportWidth = newWidth
                }
        }
    }

    @ViewBuilder
    private func timelineToolbarIconButton(
        systemImage: String,
        title: String,
        accessibilityLabel: String? = nil,
        hint: String,
        accessibilityValue: String? = nil,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let localizedTitle = NSLocalizedString(title, comment: "")
        let localizedAccessibilityLabel = accessibilityLabel.map { NSLocalizedString($0, comment: "") } ?? localizedTitle
        let localizedHint = NSLocalizedString(hint, comment: "")

        let button = Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(isDisabled)
        .foregroundStyle(isDisabled ? MovieCutTheme.mutedText.opacity(0.56) : Color.primary)
        .font(MovieCutTypography.toolbar)
        .contentShape(Rectangle())
        .help(localizedTitle)
        .accessibilityLabel(localizedAccessibilityLabel)
        .accessibilityHint(localizedHint)

        if let accessibilityValue {
            button.accessibilityValue(accessibilityValue)
        } else {
            button
        }
    }

    private func timelineToolbarGroupLabel(title: String, systemImage: String) -> some View {
        let localizedTitle = NSLocalizedString(title, comment: "")

        return HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(MovieCutTypography.micro.weight(.semibold))
                .accessibilityHidden(true)
            Text(localizedTitle)
                .font(MovieCutTypography.micro.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(MovieCutTheme.mutedText)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHidden(true)
    }

    private func timelineToolbarCluster<Content: View>(
        title: String,
        systemImage: String,
        accessibilityLabel: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        return HStack(spacing: MovieCutSpacing.xSmall) {
            timelineToolbarGroupLabel(title: title, systemImage: systemImage)
            content()
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                .fill(MovieCutTheme.controlSurface.opacity(0.52))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                .stroke(MovieCutTheme.border.opacity(0.24), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NSLocalizedString(accessibilityLabel, comment: ""))
    }

    private var selectedClipToolbar: some View {
        HStack(spacing: MovieCutSpacing.xSmall) {
            timelineToolbarCluster(
                title: "Edit",
                systemImage: "slider.horizontal.3",
                accessibilityLabel: "Timeline edit tools"
            ) {
                timelineToolbarIconButton(
                    systemImage: "scissors",
                    title: "Split at Playhead",
                    hint: "Splits the selected clip at the playhead.",
                    isDisabled: !viewModel.canSplitSelectedClip
                ) {
                    Task { await viewModel.splitClip() }
                }

                timelineToolbarIconButton(
                    systemImage: "trash",
                    title: "Delete Selected Clips",
                    hint: "Deletes the selected clips from the timeline.",
                    isDisabled: !viewModel.hasSelectedClips
                ) {
                    Task { await viewModel.deleteClip() }
                }

                timelineToolbarIconButton(
                    systemImage: "delete.left",
                    title: "Ripple Delete Selected Clip",
                    hint: "Deletes the selected clip and closes the resulting gap.",
                    isDisabled: viewModel.selectedClip == nil
                ) {
                    Task { await viewModel.rippleDeleteSelectedClip() }
                }

                timelineToolbarIconButton(
                    systemImage: "square.on.square",
                    title: "Duplicate Selected Clips",
                    hint: "Duplicates the selected clips on the timeline.",
                    isDisabled: !viewModel.hasSelectedClips
                ) {
                    Task { await viewModel.duplicateSelectedClips() }
                }

                timelineToolbarIconButton(
                    systemImage: "arrow.left.to.line.compact",
                    title: "Snap Playhead to Clip Start",
                    hint: "Moves the playhead to the selected clip start.",
                    isDisabled: viewModel.selectedClip == nil
                ) {
                    viewModel.snapPlayheadToSelectedClipStart()
                }

                timelineToolbarIconButton(
                    systemImage: "arrow.right.to.line.compact",
                    title: "Snap Playhead to Clip End",
                    hint: "Moves the playhead to the selected clip end.",
                    isDisabled: viewModel.selectedClip == nil
                ) {
                    viewModel.snapPlayheadToSelectedClipEnd()
                }
            }

            timelineToolbarCluster(
                title: "Quick Tools",
                systemImage: "bolt",
                accessibilityLabel: "Timeline quick tools"
            ) {
                timelineToolbarIconButton(
                    systemImage: "snowflake",
                    title: "Freeze Selected Frame",
                    hint: "Freeze Selected Frame inserts a still frame at the playhead for the selected visual clip.",
                    isDisabled: !selectedClipSupportsVisualTimelineEffect
                ) {
                    Task { await viewModel.freezeSelectedFrame() }
                }

                timelineToolbarIconButton(
                    systemImage: "backward.fill",
                    title: "Reverse Selected Clip",
                    hint: "Reverse Selected Clip toggles reverse playback for the selected visual clip.",
                    isDisabled: !selectedClipSupportsVisualTimelineEffect
                ) {
                    Task {
                        guard let selectedClip = viewModel.selectedClip else { return }
                        await viewModel.updateSelectedReversePlayback(!selectedClip.isReversed)
                    }
                }
            }
        }
        .font(MovieCutTypography.toolbar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NSLocalizedString("Timeline edit tools", comment: ""))
    }

    private var timelineMarkerControls: some View {
        timelineToolbarCluster(
            title: "Markers",
            systemImage: "flag",
            accessibilityLabel: "Timeline marker controls"
        ) {
            timelineToolbarIconButton(
                systemImage: "backward.end.fill",
                title: "Previous Marker",
                hint: "Moves the playhead to the previous marker.",
                isDisabled: viewModel.previousMarker == nil
            ) {
                viewModel.goToPreviousMarker()
            }

            timelineToolbarIconButton(
                systemImage: "flag.fill",
                title: "Add Marker at Playhead",
                hint: "Adds a marker at the current playhead time.",
                accessibilityValue: String(format: NSLocalizedString("%d markers", comment: ""), sortedMarkers.count)
            ) {
                viewModel.addMarkerAtPlayhead()
            }

            timelineToolbarIconButton(
                systemImage: "forward.end.fill",
                title: "Next Marker",
                hint: "Moves the playhead to the next marker.",
                isDisabled: viewModel.nextMarker == nil
            ) {
                viewModel.goToNextMarker()
            }
        }
        .font(MovieCutTypography.toolbar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NSLocalizedString("Timeline marker controls", comment: ""))
    }

    private var selectedClipSupportsVisualTimelineEffect: Bool {
        guard let selectedClip = viewModel.selectedClip else { return false }
        return selectedClip.kind == .video || selectedClip.kind == .image
    }

    private var zoomControls: some View {
        timelineToolbarCluster(
            title: "Zoom",
            systemImage: "magnifyingglass",
            accessibilityLabel: "Timeline zoom controls"
        ) {
            timelineToolbarIconButton(
                systemImage: "minus.magnifyingglass",
                title: "Zoom Timeline Out",
                accessibilityLabel: "Timeline zoom out",
                hint: "Zooms the timeline out."
            ) {
                viewModel.zoomTimelineOut()
            }
            // Locale-independent anchor for the accessibility-label regression
            // check in TimelineAccessibilityLabelUITests (task 1.3). The label
            // itself resolves through the catalog, so it cannot be used to
            // locate the button.
            .accessibilityIdentifier("timeline.zoomOut")

            Slider(value: Binding(
                    get: { viewModel.timelineZoom },
                    set: { viewModel.timelineZoom = clampedTimelineZoom($0) }
                ),
                in: timelineZoomRange
            )
            .frame(width: 120)
            .controlSize(.small)
            .accessibilityLabel(NSLocalizedString("Timeline zoom slider", comment: ""))
            .accessibilityHint(NSLocalizedString("Adjusts pixels per second in the timeline.", comment: ""))

            timelineToolbarIconButton(
                systemImage: "plus.magnifyingglass",
                title: "Zoom Timeline In",
                accessibilityLabel: "Timeline zoom in",
                hint: "Zooms the timeline in."
            ) {
                viewModel.zoomTimelineIn()
            }
            .accessibilityIdentifier("timeline.zoomIn")

            Text(timelineZoomDisplay)
                .font(MovieCutTypography.metadata.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
                .accessibilityLabel(NSLocalizedString("Timeline zoom", comment: ""))
                .accessibilityValue(timelineZoomDisplay)

            timelineToolbarIconButton(
                systemImage: "arrow.left.and.right",
                title: "Fit Timeline",
                hint: "Fits the visible timeline duration in the available timeline width."
            ) {
                fitTimelineToAvailableWidth(timelineViewportWidth)
            }
        }
        .font(MovieCutTypography.toolbar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NSLocalizedString("Timeline zoom controls", comment: ""))
    }

    private var timelineZoomDisplay: String {
        "\(Int(clampedTimelineZoom(viewModel.timelineZoom).rounded())) px/s"
    }

    private func fitTimelineToAvailableWidth(_ availableWidth: CGFloat) {
        viewModel.timelineZoom = fittedTimelineZoom(for: availableWidth)
    }

    private func fittedTimelineZoom(for availableWidth: CGFloat) -> Double {
        let safeAvailableWidth = availableWidth.isFinite && availableWidth > 0 ? availableWidth : fitTimelineFallbackWidth
        let trackHeaderWidth = 80 + MovieCutSpacing.small * 2
        let availableContentWidth = max(1, safeAvailableWidth - trackHeaderWidth)
        let targetContentWidth = max(minimumTimelineContentWidth, availableContentWidth)
        let timelinePixelsWidth = max(1, targetContentWidth - markerLabelWidth)
        let duration = max(viewModel.visibleTimelineDuration, minimumFitDuration)

        return clampedTimelineZoom(Double(timelinePixelsWidth / CGFloat(duration)))
    }

    private func clampedTimelineZoom(_ zoom: Double) -> Double {
        guard zoom.isFinite else { return timelineZoomRange.lowerBound }
        return min(timelineZoomRange.upperBound, max(timelineZoomRange.lowerBound, zoom))
    }

    private func scrubTimeline(atLocalX localX: CGFloat, phase: TimelineScrubPhase) {
        let time = TimelineScrubMath.time(
            forLocalX: Double(localX),
            pixelsPerSecond: pixelsPerSecond,
            duration: viewModel.currentProject.timeline.duration
        )
        // Blade tool (S9): instead of scrubbing, a tap/click splits the
        // topmost clip at the clicked time. Move the playhead there first so
        // the split point is visible, then dispatch the blade split on release.
        if viewModel.timelineTool == .blade {
            viewModel.scrubPlayhead(to: time, phase: phase)
            if phase == .ended {
                Task { await viewModel.bladeSplitAtPlayhead() }
            }
            return
        }
        viewModel.scrubPlayhead(to: time, phase: phase)
    }

    private func rulerScrubGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let phase: TimelineScrubPhase = isRulerScrubbing ? .changed : .began
                isRulerScrubbing = true
                scrubTimeline(atLocalX: value.location.x, phase: phase)
            }
            .onEnded { value in
                scrubTimeline(atLocalX: value.location.x, phase: .ended)
                isRulerScrubbing = false
            }
    }

    private func playheadScrubGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isPlayheadScrubbing {
                    isPlayheadScrubbing = true
                    playheadDragStartTime = viewModel.playheadTime
                    viewModel.scrubPlayhead(to: playheadDragStartTime, phase: .began)
                }
                let targetX = CGFloat(playheadDragStartTime) * CGFloat(pixelsPerSecond) + value.translation.width
                scrubTimeline(atLocalX: targetX, phase: .changed)
            }
            .onEnded { value in
                let targetX = CGFloat(playheadDragStartTime) * CGFloat(pixelsPerSecond) + value.translation.width
                scrubTimeline(atLocalX: targetX, phase: .ended)
                isPlayheadScrubbing = false
            }
    }

    private var playheadOverlay: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(MovieCutTheme.accentCyan)
                .frame(width: 2)
        }
        .frame(width: 14, height: trackHeight)
        .contentShape(Rectangle())
        .offset(x: CGFloat(viewModel.playheadTime) * CGFloat(pixelsPerSecond) - 7)
        .highPriorityGesture(playheadScrubGesture())
        .accessibilityElement()
        .accessibilityLabel(NSLocalizedString("Playhead", comment: ""))
        .accessibilityValue(timelineSecondsString(viewModel.playheadTime))
        .accessibilityHint(NSLocalizedString("Drag to scrub the timeline frame by frame.", comment: ""))
    }

    private var timeRuler: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(MovieCutTheme.rulerBackground)
                .frame(width: 80, height: rulerHeight)
                .overlay(alignment: .leading) {
                    Text(NSLocalizedString("Time", comment: ""))
                        .font(MovieCutTypography.micro)
                        .foregroundStyle(MovieCutTheme.mutedText)
                        .padding(.leading, MovieCutSpacing.xSmall)
                }

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    var x: CGFloat = 0
                    var time: TimeInterval = 0
                    let interval: TimeInterval = pixelsPerSecond >= 100 ? 1 : (pixelsPerSecond >= 50 ? 5 : 10)

                    while x < size.width {
                        let isMajor = Int(time) % 10 == 0
                        let tickH: CGFloat = isMajor ? rulerHeight : rulerHeight / 2

                        context.stroke(
                            Path { p in
                                p.move(to: CGPoint(x: x, y: rulerHeight))
                                p.addLine(to: CGPoint(x: x, y: rulerHeight - tickH))
                            },
                            with: .color(isMajor ? MovieCutTheme.timelineGrid.opacity(0.66) : MovieCutTheme.timelineGrid.opacity(0.34)),
                            lineWidth: isMajor ? 0.6 : 0.3
                        )

                        if isMajor {
                            let text = Text("\(Int(time))s")
                                .font(MovieCutTypography.micro)
                                .foregroundStyle(MovieCutTheme.mutedText)
                            context.draw(text, at: CGPoint(x: x + 4, y: 8))
                        }

                        time += interval
                        x = CGFloat(time) * CGFloat(pixelsPerSecond)
                    }
                }
                .frame(width: timelineContentWidth, height: rulerHeight)

                ForEach(sortedMarkers) { marker in
                    if marker.kind == .beat {
                        // Beat markers render as compact ticks: a full flag per
                        // beat would flood the ruler on real music tracks.
                        Rectangle()
                            .fill(Color.orange.opacity(0.85))
                            .frame(width: 2, height: rulerHeight / 3)
                            .offset(x: markerX(marker), y: rulerHeight * 2 / 3)
                            .onTapGesture {
                                viewModel.goToMarker(marker)
                            }
                            .help(markerHelp(marker))
                            .accessibilityLabel(NSLocalizedString("Beat marker", comment: ""))
                            .accessibilityValue(timelineSecondsString(marker.time))
                    } else {
                        TimelineMarkerFlag(marker: marker)
                            .frame(width: markerLabelWidth, height: rulerHeight, alignment: .leading)
                            .offset(x: markerX(marker), y: 0)
                            .onTapGesture {
                                viewModel.goToMarker(marker)
                            }
                            .help(markerHelp(marker))
                    }
                }

                #if DEBUG
                HStack(spacing: 0) {
                    ForEach(debugFilmstripScrollAnchors, id: \.self) { milliseconds in
                        Color.clear
                            .frame(
                                width: max(1, CGFloat(15 * pixelsPerSecond)),
                                height: 1
                            )
                            .id(TimelineFilmstripDebugScrollAnchor(milliseconds: milliseconds))
                    }
                }
                .frame(width: timelineContentWidth, height: 1, alignment: .leading)
                #endif
            }
            .frame(width: timelineContentWidth, height: rulerHeight, alignment: .leading)
            .background(MovieCutTheme.rulerBackground)
            .contentShape(Rectangle())
            .simultaneousGesture(rulerScrubGesture())
            .accessibilityElement(children: .contain)
            .accessibilityLabel(NSLocalizedString("Timeline ruler", comment: ""))
            .accessibilityHint(NSLocalizedString("Click or drag to scrub the preview.", comment: ""))
        }
    }

    private func timelineGridLines(height: CGFloat) -> some View {
        Canvas { context, size in
            var x: CGFloat = 0
            var time: TimeInterval = 0
            let interval: TimeInterval = pixelsPerSecond >= 100 ? 1 : (pixelsPerSecond >= 50 ? 5 : 10)

            while x < size.width {
                let isMajor = Int(time) % 10 == 0
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                    },
                    with: .color(isMajor ? MovieCutTheme.timelineGrid.opacity(0.44) : MovieCutTheme.timelineGrid.opacity(0.24)),
                    lineWidth: isMajor ? 0.4 : 0.25
                )

                time += interval
                x = CGFloat(time) * CGFloat(pixelsPerSecond)
            }
        }
        .frame(width: timelineContentWidth, height: height)
        .allowsHitTesting(false)
    }

    private var mainVideoTrackBadge: some View {
        Text(NSLocalizedString("Main", comment: ""))
            .font(MovieCutTypography.micro.weight(.semibold))
            .foregroundStyle(MovieCutTheme.accentCyan)
            .lineLimit(1)
            .padding(.horizontal, MovieCutSpacing.xSmall)
            .padding(.vertical, 1)
            .background {
                Capsule()
                    .fill(MovieCutTheme.accentCyan.opacity(0.12))
            }
            .overlay {
                Capsule()
                    .stroke(MovieCutTheme.accentCyan.opacity(0.32), lineWidth: 0.5)
            }
            .layoutPriority(1)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func mainVideoTrackHeaderAccent(isMainVideo: Bool) -> some View {
        if isMainVideo {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: MovieCutRadius.small)
                    .strokeBorder(MovieCutTheme.accentCyan.opacity(0.20), lineWidth: 1)
                Rectangle()
                    .fill(MovieCutTheme.accentCyan.opacity(0.60))
                    .frame(width: 2)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func mainVideoTrackLaneHighlight(isMainVideo: Bool) -> some View {
        if isMainVideo {
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(MovieCutTheme.accentCyan.opacity(0.035))
                Rectangle()
                    .strokeBorder(MovieCutTheme.accentCyan.opacity(0.14), lineWidth: 1)
                Rectangle()
                    .fill(MovieCutTheme.accentCyan.opacity(0.36))
                    .frame(width: 2)
            }
            .frame(width: timelineContentWidth, height: trackHeight, alignment: .leading)
            .allowsHitTesting(false)
        }
    }

    private func trackLane(_ track: Track) -> some View {
        let isMainVideo = isMainVideoTrack(track)

        return HStack(spacing: 0) {
            // Track header
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MovieCutSpacing.xSmall) {
                    Text(track.name)
                        .font(MovieCutTypography.cardTitle)
                        .lineLimit(1)
                    if isMainVideo {
                        mainVideoTrackBadge
                    }
                }
                trackHeaderControls(for: track)
            }
            .frame(width: 80, alignment: .leading)
            .padding(.horizontal, MovieCutSpacing.small)
            .background(MovieCutTheme.trackHeaderBackground.opacity(0.74))
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(MovieCutTheme.divider.opacity(0.42))
                    .frame(width: 0.5)
            }
            .overlay(alignment: .leading) {
                mainVideoTrackHeaderAccent(isMainVideo: isMainVideo)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(trackHeaderAccessibilityLabel(for: track))
            .accessibilityIdentifier("timeline.trackHeader.\(track.id.uuidString)")

            // Clips area
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(MovieCutTheme.trackBackground)
                mainVideoTrackLaneHighlight(isMainVideo: isMainVideo)
                timelineGridLines(height: trackHeight)

                ForEach(clipsForDisplay(track)) { clip in
                    clipView(clip, trackKind: track.kind)
                }

                // Auto-cut preview: ranges scheduled for removal (F-18).
                ForEach(Array(viewModel.autoCutPreviewRanges.enumerated()), id: \.offset) { _, range in
                    Rectangle()
                        .fill(Color.red.opacity(0.28))
                        .overlay(Rectangle().strokeBorder(Color.red.opacity(0.7), lineWidth: 1))
                        .frame(width: max(1, CGFloat(range.duration) * CGFloat(pixelsPerSecond)), height: trackHeight)
                        .offset(x: CGFloat(range.start) * CGFloat(pixelsPerSecond))
                        .allowsHitTesting(false)
                        .accessibilityLabel(NSLocalizedString("Auto cut removal span", comment: ""))
                }

                ForEach(sortedMarkers.filter { $0.kind != .beat }) { marker in
                    TimelineMarkerLine(marker: marker, height: trackHeight)
                        .offset(x: markerX(marker))
                        .onTapGesture {
                            viewModel.goToMarker(marker)
                        }
                        .help(markerHelp(marker))
                }

                // Playhead: a 2pt visual with a wider direct-drag target.
                playheadOverlay

            }
            .frame(width: timelineContentWidth, height: trackHeight, alignment: .leading)
            .onDrop(of: [.fileURL, .movie, .image, .movieCutMediaAssetID], isTargeted: nil) { providers, location in
                handleTrackDrop(providers: providers, location: location, trackId: track.id)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(format: NSLocalizedString("%@ clip add region", comment: ""), trackHeaderAccessibilityLabel(for: track)))
            .accessibilityHint(NSLocalizedString("Drop media files or library assets here to add clips at the drop position.", comment: ""))
            .accessibilityIdentifier("timeline.trackLane.\(track.id.uuidString)")
        }
        .frame(height: trackHeight)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(MovieCutTheme.divider)
        }
    }

    private func trackHeaderControls(for track: Track) -> some View {
        HStack(spacing: 2) {
            Button {
                Task { await viewModel.toggleTrackMute(track) }
            } label: {
                Image(systemName: track.isMuted ? "speaker.slash" : "speaker.wave.2")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .help(track.isMuted ? "Unmute Track" : "Mute Track")
            .accessibilityLabel(NSLocalizedString("Mute track", comment: ""))
            .accessibilityValue(track.isMuted ? NSLocalizedString("Muted", comment: "") : NSLocalizedString("Audible", comment: ""))
            .accessibilityHint(NSLocalizedString("Toggles audio playback for this track.", comment: ""))

            Button {
                Task { await viewModel.toggleTrackHidden(track) }
            } label: {
                Image(systemName: track.isHidden ? "eye.slash" : "eye")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .help(track.isHidden ? "Show Track" : "Hide Track")
            .accessibilityLabel(NSLocalizedString("Hide track", comment: ""))
            .accessibilityValue(track.isHidden ? NSLocalizedString("Hidden", comment: "") : NSLocalizedString("Visible", comment: ""))
            .accessibilityHint(NSLocalizedString("Toggles visual output for this track.", comment: ""))

            Button {
                Task { await viewModel.toggleTrackLock(track) }
            } label: {
                Image(systemName: track.isLocked ? "lock" : "lock.open")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .help(track.isLocked ? "Unlock Track" : "Lock Track")
            .accessibilityLabel(NSLocalizedString("Lock track", comment: ""))
            .accessibilityValue(track.isLocked ? NSLocalizedString("Locked", comment: "") : NSLocalizedString("Unlocked", comment: ""))
            .accessibilityHint(NSLocalizedString("Toggles editing protection for this track.", comment: ""))
        }
        .font(MovieCutTypography.metadata.weight(.medium))
        .foregroundStyle(MovieCutTheme.mutedText.opacity(0.86))
    }

    @MainActor
    private func clipView(_ clip: Clip, trackKind: TrackKind) -> some View {
        let x = CGFloat(clip.timelineRange.start) * CGFloat(pixelsPerSecond)
        let width = CGFloat(clip.timelineRange.duration) * CGFloat(pixelsPerSecond)
        let isSelected = viewModel.selectedClipIds.contains(clip.id)
        let isActiveDrag = isDragging && draggedClipId == clip.id
        let clipAccent = accentForClip(clip: clip, trackKind: trackKind)

        return ZStack {
            RoundedRectangle(cornerRadius: MovieCutRadius.small)
                .fill(colorForClip(clip: clip, trackKind: trackKind, selected: isSelected))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: MovieCutRadius.small)
                            .fill(MovieCutTheme.timelineSelectedClipFill)
                    }
                }
                .overlay {
                    clipMediaBackground(for: clip, trackKind: trackKind, selected: isSelected)
                        .clipShape(RoundedRectangle(cornerRadius: MovieCutRadius.small))
                }
                .overlay(alignment: .top) {
                    clipMediaTypeStripe(accent: clipAccent, selected: isSelected)
                }
                .overlay(alignment: .leading) {
                    Text(clipLabel(clip))
                        .font(MovieCutTypography.micro)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, MovieCutSpacing.xSmall)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(isSelected ? 0.34 : 0.22))
                        )
                        .padding(.leading, MovieCutSpacing.xSmall)
                }
                .overlay(alignment: .trailing) {
                    HStack(spacing: 2) {
                        if clip.groupId != nil {
                            Image(systemName: "link")
                                .font(MovieCutTypography.metadata)
                                .foregroundStyle(.white.opacity(0.85))
                        .accessibilityLabel(NSLocalizedString("Linked clip", comment: ""))
                        }
                        if isStickerClip(clip) {
                            Image(systemName: "face.smiling")
                                .font(MovieCutTypography.metadata)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        if let proxyState = proxyBadgeState(for: clip) {
                            clipProxyBadge(proxyState)
                        }
                    }
                    .padding(.trailing, MovieCutSpacing.xSmall)
                }
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(clipAccent.opacity(isSelected ? 0.92 : 0.42))
                        .frame(width: isSelected ? 4 : 2)
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: MovieCutRadius.small)
                            .strokeBorder(clipAccent.opacity(0.98), lineWidth: 1.6)
                        RoundedRectangle(cornerRadius: MovieCutRadius.small)
                            .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.5)
                    } else {
                        RoundedRectangle(cornerRadius: MovieCutRadius.small)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    }
                }
                .shadow(color: isSelected ? clipAccent.opacity(0.26) : Color.clear, radius: isSelected ? 3 : 0, x: 0, y: 0)
                .contentShape(Rectangle())
                .gesture(moveGesture(for: clip))
                .accessibilityElement()
                .accessibilityLabel(clipAccessibilityLabel(for: clip))
                .accessibilityValue(
                    [
                        String(
                            format: NSLocalizedString("Starts at %@, duration %@, layer %d", comment: ""),
                            timelineSecondsString(clip.timelineRange.start),
                            timelineSecondsString(clip.timelineRange.duration),
                            clip.zIndex
                        ),
                        proxyAccessibilityPhrase(for: clip)
                    ]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                )
                .accessibilityHint(NSLocalizedString("Selects the clip. Drag to move it on the timeline. Layer actions adjust its zIndex.", comment: ""))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    selectClip(clip.id, extendingSelection: false)
                }

            HStack(spacing: 0) {
                clipTrimHandle(selected: isSelected)
                    .contentShape(Rectangle())
                    .gesture(leftTrimGesture(for: clip))
                    .accessibilityElement()
                    .accessibilityLabel(String(format: NSLocalizedString("%@ left trim handle", comment: ""), clipAccessibilityLabel(for: clip)))
                    .accessibilityHint(NSLocalizedString("Drag to trim the clip start.", comment: ""))

                Spacer(minLength: 0)

                clipTrimHandle(selected: isSelected)
                    .contentShape(Rectangle())
                    .gesture(rightTrimGesture(for: clip))
                    .accessibilityElement()
                    .accessibilityLabel(String(format: NSLocalizedString("%@ right trim handle", comment: ""), clipAccessibilityLabel(for: clip)))
                    .accessibilityHint(NSLocalizedString("Drag to trim the clip end.", comment: ""))
            }
        }
            .frame(width: max(2, width), height: trackHeight - 8)
            .offset(x: x, y: 4)
            .zIndex(Double(clip.zIndex) + (isActiveDrag || isSelected ? 10_000 : 0))
            .contentShape(Rectangle())
            .modifier(
                TimelineFilmstripHoverModifier(
                    clip: clip,
                    clipWidth: max(2, width),
                    supportsFilmstrip: filmstripAsset(for: clip) != nil,
                    store: filmstripStore
                )
            )
            .accessibilityElement(children: .contain)
            .highPriorityGesture(
                TapGesture()
                    .modifiers(.command)
                    .onEnded {
                        selectClip(clip.id, extendingSelection: true)
                    }
            )
            .onTapGesture {
                selectClip(clip.id, extendingSelection: false)
            }
            .contextMenu {
                Button(NSLocalizedString("Split", comment: "")) {
                    selectClip(clip.id, extendingSelection: false)
                    Task { await viewModel.splitClip() }
                }
                Button(NSLocalizedString("Delete", comment: "")) {
                    let clipIds = contextMenuClipIds(anchor: clip.id)
                    Task { await viewModel.deleteClips(clipIds) }
                }
                Button(NSLocalizedString("Duplicate", comment: "")) {
                    let clipIds = contextMenuClipIds(anchor: clip.id)
                    Task { await viewModel.duplicateClips(clipIds) }
                }
                Button(NSLocalizedString("Copy", comment: "")) {
                    let clipIds = contextMenuClipIds(anchor: clip.id)
                    viewModel.copyClips(clipIds)
                }
                .disabled(!viewModel.canCopyClips(contextMenuCandidateClipIds(anchor: clip.id)))
                Button(NSLocalizedString("Cut", comment: "")) {
                    let clipIds = contextMenuClipIds(anchor: clip.id)
                    Task { await viewModel.cutClips(clipIds) }
                }
                .disabled(!viewModel.canCutClips(contextMenuCandidateClipIds(anchor: clip.id)))
                Button(NSLocalizedString("Paste", comment: "")) {
                    Task { await viewModel.pasteClipsAtPlayhead() }
                }
                .disabled(!viewModel.canPasteClips)
                Divider()
                Button(NSLocalizedString("Group Clips", comment: "")) {
                    _ = contextMenuClipIds(anchor: clip.id)
                    Task { await viewModel.groupSelectedClips() }
                }
                .disabled(!viewModel.canGroupSelectedClips && !viewModel.selectedClipIds.contains(clip.id))
                Button(NSLocalizedString("Ungroup Clips", comment: "")) {
                    _ = contextMenuClipIds(anchor: clip.id)
                    Task { await viewModel.ungroupSelectedClips() }
                }
                .disabled(clip.groupId == nil && !viewModel.hasGroupedSelection)
                Divider()
                Button("Snap Playhead to Start") {
                    selectClip(clip.id, extendingSelection: false)
                    viewModel.snapPlayheadToSelectedClipStart()
                }
                Button("Snap Playhead to End") {
                    selectClip(clip.id, extendingSelection: false)
                    viewModel.snapPlayheadToSelectedClipEnd()
                }
                Divider()
                Button("Bring to Front") {
                    selectClip(clip.id, extendingSelection: false)
                    Task { await viewModel.bringSelectedClipLayerToFront() }
                }
                Button("Send to Back") {
                    selectClip(clip.id, extendingSelection: false)
                    Task { await viewModel.sendSelectedClipLayerToBack() }
                }
                Divider()
                Button(NSLocalizedString("Ripple Delete", comment: "")) {
                    selectClip(clip.id, extendingSelection: false)
                    Task { await viewModel.rippleDeleteClip(clipId: clip.id) }
                }
            }
    }

    private func clipMediaTypeStripe(accent: Color, selected: Bool) -> some View {
        Rectangle()
            .fill(accent.opacity(selected ? 0.58 : 0.26))
            .frame(height: selected ? 3 : 2)
            .allowsHitTesting(false)
    }

    private func clipTrimHandle(selected: Bool) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
            if selected {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.42))
                    .frame(width: 2, height: 22)
            }
        }
        .frame(width: trimHandleWidth)
    }

    @ViewBuilder
    private func clipMediaBackground(for clip: Clip, trackKind: TrackKind, selected: Bool) -> some View {
        if let asset = filmstripAsset(for: clip) {
            let fallbackImage = thumbnailImage(for: clip)
            if let fallbackImage {
                // The original single-thumbnail strip remains underneath the
                // async layer as the non-blank loading/failure/cancel fallback.
                thumbnailStrip(fallbackImage)
            } else {
                clipPlaceholderRhythm(
                    accent: accentForClip(clip: clip, trackKind: trackKind),
                    selected: selected
                )
            }
            TimelineFilmstripLayer(
                clip: clip,
                asset: asset,
                pixelsPerSecond: pixelsPerSecond,
                viewportWidth: timelineScrollViewportWidth,
                fallbackThumbnailAvailable: fallbackImage != nil,
                store: filmstripStore
            )
            Color.black.opacity(selected ? 0.46 : 0.34)
                .allowsHitTesting(false)
        } else if let image = thumbnailImage(for: clip) {
            thumbnailStrip(image)
                #if DEBUG
                .onAppear {
                    if clip.kind == .image {
                        TimelineFilmstripDebugProbe.shared.recordPreservedSurface(.imageThumbnail)
                    }
                }
                #endif
            Color.black.opacity(selected ? 0.46 : 0.34)
                .allowsHitTesting(false)
        } else if shouldRenderWaveform(for: clip, trackKind: trackKind) {
            waveformCanvas(for: clip, selected: selected)
                #if DEBUG
                .onAppear {
                    if clip.kind == .audio {
                        TimelineFilmstripDebugProbe.shared.recordPreservedSurface(.audioWaveform)
                    }
                }
                #endif
            Color.black.opacity(selected ? 0.20 : 0.28)
                .allowsHitTesting(false)
        } else if trackKind == .text || clip.kind == .text {
            textClipRhythmStrip(for: clip, selected: selected)
                #if DEBUG
                .onAppear {
                    TimelineFilmstripDebugProbe.shared.recordPreservedSurface(.textRhythm)
                }
                #endif
        } else {
            clipPlaceholderRhythm(accent: accentForClip(clip: clip, trackKind: trackKind), selected: selected)
        }
    }

    /// Whether this clip shows the proxy badge. The decision itself lives in
    /// Core (`ProxyBadgeState.resolve`) so it is unit-testable and reusable by
    /// iOS; this only resolves the clip's asset.
    private func proxyBadgeState(for clip: Clip) -> ProxyBadgeState? {
        // Proxies are only generated for video assets, which `filmstripAsset`
        // already filters for.
        guard let asset = filmstripAsset(for: clip) else { return nil }
        return ProxyBadgeState.resolve(
            proxy: asset.proxy,
            useProxyPlayback: viewModel.currentProject.playbackSettings.useProxyPlayback,
            autoDowngraded: viewModel.playbackEngine.autoProxyDowngrade
        )
    }

    /// The proxy indicator drawn in the clip's trailing icon cluster.
    ///
    /// Deliberately not tinted with `accentCyan`: `UI_DESIGN_PRINCIPLES.md` §2
    /// reserves the single accent for selection, playhead, and primary actions,
    /// and a status indicator is none of those. State is carried by opacity and
    /// by filled vs outline glyph instead.
    private func clipProxyBadge(_ state: ProxyBadgeState) -> some View {
        // thermalActive uses a thermometer glyph so the *reason* for the quality
        // drop is visible — an unexplained drop reads as a bug. (S7)
        let isActive = state == .active || state == .thermalActive
        let systemName = state == .thermalActive ? "thermometer.medium" : (state == .active ? "bolt.fill" : "bolt")
        return Image(systemName: systemName)
            .font(MovieCutTypography.metadata)
            .foregroundStyle(.white.opacity(isActive ? 0.85 : 0.45))
            .help(
                state == .active
                    ? NSLocalizedString("Playing the proxy for smoother editing. Export uses the original.", comment: "")
                    : (state == .thermalActive
                        ? NSLocalizedString("Thermal pressure: preview is using the proxy. It restores when the device cools. Export uses the original.", comment: "")
                        : NSLocalizedString("A proxy is ready. Turn on proxy playback to use it.", comment: ""))
            )
    }

    /// Spoken description of the proxy state, appended to the clip's own
    /// accessibility value.
    ///
    /// It has to live on the clip element: `clipView` calls
    /// `.accessibilityElement()`, which ignores children, so a label attached to
    /// the badge glyph itself would never be read aloud.
    private func proxyAccessibilityPhrase(for clip: Clip) -> String? {
        switch proxyBadgeState(for: clip) {
        case .active:
            return NSLocalizedString("proxy playback on", comment: "")
        case .thermalActive:
            return NSLocalizedString("proxy playback on due to thermal pressure", comment: "")
        case .idle:
            return NSLocalizedString("proxy ready", comment: "")
        case nil:
            return nil
        }
    }

    private func filmstripAsset(for clip: Clip) -> MediaAsset? {
        guard clip.kind == .video,
              let assetID = clip.assetId,
              let asset = viewModel.currentProject.mediaLibrary.assets[assetID],
              asset.kind == .video else {
            return nil
        }
        return asset
    }

    #if DEBUG
    private var debugFilmstripScrollAnchors: [Int] {
        let duration = max(0, viewModel.currentProject.timeline.duration)
        let finalStep = Int(ceil(duration / 15))
        return (0...max(0, finalStep)).map { $0 * 15_000 }
    }
    #endif

    private func thumbnailImage(for clip: Clip) -> NSImage? {
        guard
            clip.kind == .video || clip.kind == .image,
            let thumbnailData = viewModel.thumbnailData(for: clip)
        else {
            return nil
        }

        return NSImage(data: thumbnailData)
    }

    private func thumbnailStrip(_ image: NSImage) -> some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            let tileWidth = min(max(height * 16 / 9, 44), 72)
            let tileCount = max(1, Int(ceil(max(proxy.size.width, tileWidth) / tileWidth)))

            HStack(spacing: 1) {
                ForEach(0..<tileCount, id: \.self) { _ in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: tileWidth, height: height)
                        .clipped()
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func shouldRenderWaveform(for clip: Clip, trackKind: TrackKind) -> Bool {
        trackKind != .text && (clip.kind == .audio || clip.kind == .video)
    }

    private func waveformCanvas(for clip: Clip, selected: Bool) -> some View {
        // Read the waveform in `body` (here) rather than inside the Canvas
        // render closure. The Canvas closure runs in a separate immediate-mode
        // render pass and does NOT establish an @Observable dependency, so a
        // read there would never be invalidated when waveformCache is filled
        // by the background decode. Reading here makes the observation tracker
        // register the waveformCache access, so the view rebuilds (and the
        // Canvas re-renders) once the real bins arrive.
        //
        // The read is PURE: waveform(for:) never writes to waveformCache, so it
        // cannot trip "modifying state during view update". The decode that
        // fills a miss is requested from the .task modifier below, which runs
        // outside body evaluation — mirroring TimelineFilmstripLayer's pattern
        // (read snapshot in body, request from .task).
        let samples = viewModel.waveform(for: clip)
        // Identity includes the asset, not just the clip id: when a clip's
        // source asset is swapped (noise reduction), the clip id is unchanged
        // but the audio content — and thus the waveform — changes. Keying the
        // decode-triggering .task on WaveformRequestKey(clip:) re-runs the task
        // on the asset swap so the new waveform is requested. (The asset-swap
        // site also re-requests directly; both paths cover the case.)
        let requestKey = WaveformRequestKey(clip: clip)
        return Canvas { context, size in
            let sampleCount = samples.isEmpty ? max(12, Int(size.width / 7)) : samples.count
            let barWidth = max(1, size.width / CGFloat(sampleCount))
            let midY = size.height / 2

            for index in 0..<sampleCount {
                let sample = samples.isEmpty ? fallbackWaveformLevel(index: index) : samples[index]
                let barHeight = CGFloat(sample) * size.height * 0.8
                let rect = CGRect(
                    x: CGFloat(index) * barWidth,
                    y: midY - barHeight / 2,
                    width: max(1, barWidth - 0.5),
                    height: barHeight
                )
                context.fill(Path(rect), with: .color(.white.opacity(selected ? 0.36 : 0.24)))
            }
        }
        .task(id: requestKey) {
            // Trigger the decode only when the sample array is empty AND a
            // decode has not already populated the cache. Kept out of body so
            // the cache write happens during the task, not during view update.
            // Re-runs when requestKey (clip + asset) changes — e.g. an asset
            // swap — so the new waveform is requested even though clip.id is
            // unchanged.
            if viewModel.waveform(for: clip).isEmpty {
                viewModel.requestWaveformDecode(for: clip)
            }
        }
        .allowsHitTesting(false)
    }

    private func fallbackWaveformLevel(index: Int) -> CGFloat {
        let pattern: [CGFloat] = [0.22, 0.46, 0.32, 0.64, 0.38, 0.54, 0.28, 0.42]
        return pattern[index % pattern.count]
    }

    private func textClipRhythmStrip(for clip: Clip, selected: Bool) -> some View {
        GeometryReader { proxy in
            let glyphCount = max(3, min(14, Int(proxy.size.width / 18)))
            HStack(spacing: 4) {
                ForEach(0..<glyphCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.white.opacity(index.isMultiple(of: 3) ? (selected ? 0.28 : 0.18) : (selected ? 0.18 : 0.12)))
                        .frame(width: index.isMultiple(of: 4) ? 12 : 8, height: 12 + CGFloat(index % 3) * 3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .allowsHitTesting(false)
    }

    private func clipPlaceholderRhythm(accent: Color, selected: Bool) -> some View {
        GeometryReader { proxy in
            let tileCount = max(2, min(10, Int(proxy.size.width / 36)))
            HStack(spacing: 3) {
                ForEach(0..<tileCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                        .fill(accent.opacity(index.isMultiple(of: 2) ? (selected ? 0.22 : 0.13) : (selected ? 0.14 : 0.08)))
                        .frame(width: 28, height: max(14, proxy.size.height - 14))
                }
            }
            .padding(.horizontal, MovieCutSpacing.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .allowsHitTesting(false)
    }

    @MainActor
    private func selectClip(_ clipId: UUID, extendingSelection: Bool) {
        viewModel.selectTimelineClip(clipId, extendSelection: extendingSelection)
    }

    @MainActor
    private func contextMenuClipIds(anchor clipId: UUID) -> Set<UUID> {
        let clipIds = contextMenuCandidateClipIds(anchor: clipId)
        guard !viewModel.selectedClipIds.contains(clipId) else { return clipIds }

        viewModel.selectedClipIds = [clipId]
        return clipIds
    }

    private func contextMenuCandidateClipIds(anchor clipId: UUID) -> Set<UUID> {
        viewModel.selectedClipIds.contains(clipId) ? viewModel.selectedClipIds : [clipId]
    }

    private func moveGesture(for clip: Clip) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                beginClipDrag(clip)
                dragOffset = value.translation.width

                guard let initialRange = dragInitialTimelineRange else { return }
                let rawStart = max(0, initialRange.start + Double(value.translation.width) / pixelsPerSecond)
                let newStart = max(0, snappedTime(rawStart, allClips: allClips(excluding: clip.id)))

                updateClip(
                    clip.id,
                    timelineRange: TimeRange(start: newStart, duration: initialRange.duration)
                )
            }
            .onEnded { _ in
                commitMove(for: clip.id)
                endClipDrag()
            }
    }

    private func leftTrimGesture(for clip: Clip) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                beginClipDrag(clip)
                dragOffset = value.translation.width

                guard let initialTimelineRange = dragInitialTimelineRange else { return }

                // Compute the candidate new timeline start from the drag, then
                // route it through the shared ClipTrimMath so the source range
                // stays in sync with the timeline at any speed/ramp, the
                // source is guarded against the asset end, and the preview
                // matches the committed value (Step 5 of the core-editing
                // repair). Previously this assumed timeline 1s == source 1s.
                let rawStart = initialTimelineRange.start + Double(value.translation.width) / pixelsPerSecond
                let snappedStart = snappedTime(rawStart, allClips: allClips(excluding: clip.id))
                // Build a working clip from the initial ranges so ClipTrimMath
                // sees the pre-drag state on every tick (the live mutation
                // below would otherwise feed it already-mutated ranges).
                var workingClip = clip
                workingClip.timelineRange = initialTimelineRange
                if let initialSourceRange = dragInitialSourceRange {
                    workingClip.sourceRange = initialSourceRange
                }

                guard let result = ClipTrimMath.compute(
                    clip: workingClip,
                    edge: .start,
                    targetTimelineTime: snappedStart,
                    assetDuration: viewModel.assetDuration(forClipID: clip.id),
                    minimumDuration: minimumClipDuration
                ) else { return }

                updateClip(
                    clip.id,
                    sourceRange: result.source,
                    timelineRange: result.timeline
                )
            }
            .onEnded { _ in
                commitTrim(for: clip.id)
                endClipDrag()
            }
    }

    private func rightTrimGesture(for clip: Clip) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                beginClipDrag(clip)
                dragOffset = value.translation.width

                guard let initialTimelineRange = dragInitialTimelineRange else { return }

                let rawEnd = initialTimelineRange.end + Double(value.translation.width) / pixelsPerSecond
                let snappedEnd = snappedTime(rawEnd, allClips: allClips(excluding: clip.id))

                var workingClip = clip
                workingClip.timelineRange = initialTimelineRange
                if let initialSourceRange = dragInitialSourceRange {
                    workingClip.sourceRange = initialSourceRange
                }

                guard let result = ClipTrimMath.compute(
                    clip: workingClip,
                    edge: .end,
                    targetTimelineTime: snappedEnd,
                    assetDuration: viewModel.assetDuration(forClipID: clip.id),
                    minimumDuration: minimumClipDuration
                ) else { return }

                updateClip(
                    clip.id,
                    sourceRange: result.source,
                    timelineRange: result.timeline
                )
            }
            .onEnded { _ in
                commitTrim(for: clip.id)
                endClipDrag()
            }
    }

    private func beginClipDrag(_ clip: Clip) {
        if draggedClipId != clip.id {
            dragInitialTimelineRange = clip.timelineRange
            dragInitialSourceRange = clip.sourceRange
        }
        isDragging = true
        draggedClipId = clip.id
        viewModel.selectedClipId = clip.id
    }

    private func endClipDrag() {
        dragOffset = 0
        isDragging = false
        draggedClipId = nil
        dragInitialTimelineRange = nil
        dragInitialSourceRange = nil
    }

    private func commitMove(for clipId: UUID) {
        guard let clip = clip(for: clipId) else { return }
        let trackId = trackId(containing: clipId)

        Task {
            await viewModel.moveClip(
                clipId: clipId,
                sourceTrackId: trackId,
                targetTrackId: trackId,
                timelineRange: clip.timelineRange
            )
        }
    }

    private func commitTrim(for clipId: UUID) {
        guard let clip = clip(for: clipId) else { return }
        let trackId = trackId(containing: clipId)

        Task {
            await viewModel.trimClip(
                clipId: clipId,
                trackId: trackId,
                sourceRange: clip.sourceRange,
                timelineRange: clip.timelineRange
            )
        }
    }

    private func updateClip(_ clipId: UUID, sourceRange: TimeRange? = nil, timelineRange: TimeRange) {
        for trackIndex in viewModel.currentProject.timeline.tracks.indices {
            guard let clipIndex = viewModel.currentProject.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipId }) else {
                continue
            }

            if let sourceRange {
                viewModel.currentProject.timeline.tracks[trackIndex].clips[clipIndex].sourceRange = sourceRange
            }
            viewModel.currentProject.timeline.tracks[trackIndex].clips[clipIndex].timelineRange = timelineRange
            return
        }
    }

    private func clip(for clipId: UUID) -> Clip? {
        viewModel.currentProject.timeline.tracks
            .flatMap(\.clips)
            .first { $0.id == clipId }
    }

    private func trackId(containing clipId: UUID) -> UUID? {
        viewModel.currentProject.timeline.tracks.first { track in
            track.clips.contains { $0.id == clipId }
        }?.id
    }

    private func allClips(excluding clipId: UUID) -> [Clip] {
        viewModel.currentProject.timeline.tracks
            .flatMap(\.clips)
            .filter { $0.id != clipId }
    }

    private func clipsForDisplay(_ track: Track) -> [Clip] {
        track.clipsForLayerDisplay
    }

    private func snappedTime(_ rawTime: Double, allClips: [Clip], threshold: Double = 5.0) -> Double {
        let snapPoints = allClips.flatMap { [$0.timelineRange.start, $0.timelineRange.start + $0.timelineRange.duration] }
            + sortedMarkers.map(\.time)
            + [viewModel.playheadTime, 0.0]
        let thresholdTime = threshold / pixelsPerSecond
        for point in snapPoints {
            if abs(rawTime - point) < thresholdTime {
                return point
            }
        }
        return rawTime
    }

    private func colorForClip(clip: Clip, trackKind: TrackKind, selected: Bool) -> Color {
        if isStickerClip(clip) {
            return MovieCutTheme.timelineStickerClip.opacity(selected ? 1 : 0.88)
        }

        switch trackKind {
        case .video: return MovieCutTheme.timelineVideoClip.opacity(selected ? 1 : 0.88)
        case .audio: return MovieCutTheme.timelineAudioClip.opacity(selected ? 1 : 0.88)
        case .text: return MovieCutTheme.timelineTextClip.opacity(selected ? 1 : 0.88)
        }
    }

    private func accentForClip(clip: Clip, trackKind: TrackKind) -> Color {
        if isStickerClip(clip) {
            return .pink
        }

        switch trackKind {
        case .video: return MovieCutTheme.accentCyan
        case .audio: return .green
        case .text: return .orange
        }
    }

    private func clipLabel(_ clip: Clip) -> String {
        if let textContent = clip.textContent {
            if isStickerClip(clip) {
                return "Sticker \(textContent.text)"
            }
            return String(textContent.text.prefix(20))
        }
        return String(describing: clip.kind)
    }

    private func isStickerClip(_ clip: Clip) -> Bool {
        guard clip.kind == .text, let textContent = clip.textContent else {
            return false
        }

        return textContent.isSticker || textContent.fontFamily == "Apple Color Emoji"
    }

    private func markerX(_ marker: Marker) -> CGFloat {
        CGFloat(marker.time) * CGFloat(pixelsPerSecond)
    }

    private func markerHelp(_ marker: Marker) -> String {
        "\(marker.name) at \(timelineSecondsString(marker.time))"
    }

    private func clipAccessibilityLabel(for clip: Clip) -> String {
        switch clip.kind {
        case .video, .image:
            return NSLocalizedString("Video clip", comment: "")
        case .audio:
            return NSLocalizedString("Audio clip", comment: "")
        case .text:
            if isStickerClip(clip) {
                return NSLocalizedString("Sticker clip", comment: "")
            }
            return NSLocalizedString("Text clip", comment: "")
        }
    }

    private func trackHeaderAccessibilityLabel(for track: Track) -> String {
        if isMainVideoTrack(track) {
            return String(format: NSLocalizedString("Main video track, %@", comment: ""), track.name)
        }

        switch track.kind {
        case .video:
            return NSLocalizedString("Video track header", comment: "")
        case .audio:
            return NSLocalizedString("Audio track header", comment: "")
        case .text:
            return NSLocalizedString("Text track header", comment: "")
        }
    }

    private func timelineSecondsString(_ time: TimeInterval) -> String {
        String(format: NSLocalizedString("%.2fs", comment: ""), time)
    }

    /// Closure-based drop handling. The previous DropDelegate-based registration
    /// silently rejected live Finder drags on macOS, so timeline drops share the
    /// same onDrop(of:isTargeted:perform:) path that the media library uses.
    private func handleTrackDrop(providers: [NSItemProvider], location: CGPoint, trackId: UUID) -> Bool {
        let startTime = max(0, Double(location.x) / max(pixelsPerSecond, 1))

        let assetProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.movieCutMediaAssetID.identifier)
        }
        if !assetProviders.isEmpty {
            TimelineDropPayloadLoader.loadAssetIDs(from: assetProviders) { assetIds in
                guard !assetIds.isEmpty else {
                    Task { @MainActor in
                        viewModel.reportInvalidTimelineLibraryAssetDrop()
                    }
                    return
                }
                Task { @MainActor in
                    await viewModel.addImportedAssetsToTimeline(
                        assetIds,
                        preferredTrackId: trackId,
                        startTime: startTime
                    )
                }
            }
            return true
        }

        let externalProviders = providers.filter {
            DragDropHandler.providesExternalMedia($0)
        }
        guard !externalProviders.isEmpty else {
            Task { @MainActor in
                viewModel.reportUnsupportedTimelineDrop()
            }
            return false
        }
        DragDropHandler.loadExternalMediaURLs(from: externalProviders) { urls in
            guard !urls.isEmpty else {
                Task { @MainActor in
                    viewModel.reportInvalidTimelineFileDrop()
                }
                return
            }
            Task { @MainActor in
                await viewModel.importMediaAndAddToTimeline(
                    urls,
                    preferredTrackId: trackId,
                    startTime: startTime
                )
            }
        }
        return true
    }
}

private enum TimelineDropPayloadLoader {
    static func loadAssetIDs(from providers: [NSItemProvider], completion: @escaping ([UUID]) -> Void) {
        guard !providers.isEmpty else {
            completion([])
            return
        }

        let accumulator = OrderedDropPayloadAccumulator<UUID>(count: providers.count, completion: completion)
        for (index, provider) in providers.enumerated() {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.movieCutMediaAssetID.identifier) { data, _ in
                let id = data
                    .flatMap { String(data: $0, encoding: .utf8) }
                    .flatMap { UUID(uuidString: $0) }
                accumulator.complete(index: index, value: id)
            }
        }
    }
}

private final class OrderedDropPayloadAccumulator<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Value?]
    private var remaining: Int
    private let completion: ([Value]) -> Void

    init(count: Int, completion: @escaping ([Value]) -> Void) {
        self.values = Array(repeating: nil, count: count)
        self.remaining = count
        self.completion = completion
    }

    func complete(index: Int, value: Value?) {
        let finishedValues: [Value]?
        lock.lock()
        values[index] = value
        remaining -= 1
        finishedValues = remaining == 0 ? values.compactMap { $0 } : nil
        lock.unlock()

        if let finishedValues {
            completion(finishedValues)
        }
    }
}

private struct TimelineMarkerFlag: View {
    var marker: Marker

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flag.fill")
                .font(MovieCutTypography.micro.weight(.semibold))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 0) {
                Text(marker.name)
                    .font(MovieCutTypography.micro.weight(.semibold))
                    .lineLimit(1)
                Text(String(format: "%.1fs", marker.time))
                    .font(MovieCutTypography.micro)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(marker.name), \(String(format: "%.1fs", marker.time))")
    }
}

private struct TimelineMarkerLine: View {
    var marker: Marker
    var height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(Color.yellow)
                .frame(width: 8, height: 6)
            Rectangle()
                .fill(Color.yellow.opacity(0.72))
                .frame(width: 2, height: max(0, height - 6))
        }
        .frame(width: 8, height: height)
        .offset(x: -4)
        .accessibilityElement()
        .accessibilityLabel("\(marker.name), \(String(format: "%.1fs", marker.time))")
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
