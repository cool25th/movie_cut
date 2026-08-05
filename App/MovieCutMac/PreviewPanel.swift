import AppKit
import SwiftUI
import MovieCutCore
import UniformTypeIdentifiers

struct PreviewPanel: View {
    var viewModel: EditorViewModel
    @State private var playbackEngine: PlaybackEngine
    @State private var previewVolume: Double = 1
    @State private var previewZoom: Double = 1
    @State private var isPreviewZoomFit = true
    @State private var showsSafeZoneGuides = false

    private let previewZoomRange: ClosedRange<Double> = 0.5...2
    private let previewZoomStep: Double = 0.25

    init(viewModel: EditorViewModel) {
        self.viewModel = viewModel
        _playbackEngine = State(initialValue: viewModel.playbackEngine)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                MovieCutTheme.previewWellBackground

                if projectHasVisualContent || playbackEngine.playerItem != nil {
                    previewCanvasWell {
                        previewSurface
                    }
                } else {
                    previewCanvasWell {
                        previewEmptyState
                    }
                }

                if let compositionError = playbackEngine.lastCompositionError {
                    previewCompositionErrorBanner(compositionError)
                }

                // IA/menu-position contract: preview transport is bottom-docked
                // near the timeline boundary, not top-docked above the canvas.
                // P1 preview polish contract: compact bottom transport retained
                // with a quiet empty matte and secondary preview import CTA.
                VStack {
                    Spacer(minLength: 0)
                    previewTransportBar
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MovieCutTheme.previewWellBackground)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(NSLocalizedString("Preview", comment: ""))
            .accessibilityValue(previewAccessibilityValue)
            .task {
                loadProjectComposition()
            }
            .onChange(of: playbackEngine.currentTime) { _, currentTime in
                // Composition playback time is already the project timeline
                // domain; no per-clip source→timeline conversion needed.
                viewModel.playheadTime = min(max(0, currentTime), max(0, viewModel.currentProject.timeline.duration))
            }

        }
    }

    /// Whether the project has any visual track (video/image/text) worth
    /// showing the composition surface for. Drives the empty-state vs.
    /// surface decision independently of selection.
    private var projectHasVisualContent: Bool {
        let timeline = viewModel.currentProject.timeline
        return timeline.tracks.contains { track in
            track.kind != .audio && !track.clips.isEmpty
        }
    }

    private func previewCompositionErrorBanner(_ message: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                    .fill(MovieCutTheme.inspectorSelectedControlSurface.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                    .stroke(MovieCutTheme.border.opacity(0.4), lineWidth: 0.5)
            )
            .padding(.top, 12)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(NSLocalizedString("Preview composition failed", comment: ""))
        .accessibilityValue(message)
    }

    private func previewCanvasWell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: MovieCutRadius.medium, style: .continuous)
                .fill(MovieCutTheme.previewLoop4WellSurface)

            PreviewLoop4WellTexture(intensity: 0.28)

            content()
                .padding(MovieCutSpacing.large + MovieCutSpacing.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: MovieCutRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MovieCutRadius.medium, style: .continuous)
                .stroke(MovieCutTheme.inspectorSelectedBorder.opacity(0.80), lineWidth: 0.5)
        )
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 64)
    }

    private var previewTransportBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                previewTimeBadge(
                    title: NSLocalizedString("Current", comment: ""),
                    value: timecodeString(playbackEngine.currentTime),
                    accessibilityLabel: NSLocalizedString("Current Time", comment: "")
                )

                Spacer(minLength: 8)

                playbackTransportCapsule

                Spacer(minLength: 8)

                previewTimeBadge(
                    title: NSLocalizedString("Duration", comment: ""),
                    value: timecodeString(playbackEngine.duration),
                    accessibilityLabel: NSLocalizedString("Duration", comment: "")
                )

                Divider()
                    .overlay(MovieCutTheme.divider.opacity(0.55))
                    .frame(height: 20)

                previewCanvasResolutionBadge
                previewSafeZoneToggle
                previewZoomControls
                previewVolumeControl
            }

            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    previewTimeBadge(
                        title: NSLocalizedString("Current", comment: ""),
                        value: timecodeString(playbackEngine.currentTime),
                        accessibilityLabel: NSLocalizedString("Current Time", comment: "")
                    )

                    Spacer(minLength: 12)

                    playbackTransportCapsule

                    Spacer(minLength: 12)

                    previewTimeBadge(
                        title: NSLocalizedString("Duration", comment: ""),
                        value: timecodeString(playbackEngine.duration),
                        accessibilityLabel: NSLocalizedString("Duration", comment: "")
                    )
                }

                HStack(spacing: 8) {
                    previewCanvasResolutionBadge
                    previewSafeZoneToggle

                    Spacer(minLength: 8)

                    previewZoomControls

                    Spacer(minLength: 8)

                    previewVolumeControl
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(MovieCutTheme.previewControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                .stroke(MovieCutTheme.inspectorSelectedBorder.opacity(0.42), lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NSLocalizedString("Preview transport controls", comment: ""))
    }

    private var playbackTransportCapsule: some View {
        HStack(spacing: 7) {
            Button(action: {
                seekByFrames(-1)
            }) {
                Image(systemName: "backward.frame")
            }
            .buttonStyle(.borderless)
            .disabled(playbackEngine.playerItem == nil)
            .accessibilityLabel(NSLocalizedString("Seek Back One Frame", comment: ""))
            .accessibilityHint(NSLocalizedString("Moves the playhead back by one frame.", comment: ""))

            Button(action: { playbackEngine.togglePlayPause() }) {
                Image(systemName: playbackEngine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .disabled(playbackEngine.playerItem == nil)
            .accessibilityLabel(playbackEngine.isPlaying ? NSLocalizedString("Pause", comment: "") : NSLocalizedString("Play", comment: ""))
            .accessibilityHint(NSLocalizedString("Starts or pauses preview playback.", comment: ""))

            Button(action: {
                seekByFrames(1)
            }) {
                Image(systemName: "forward.frame")
            }
            .buttonStyle(.borderless)
            .disabled(playbackEngine.playerItem == nil)
            .accessibilityLabel(NSLocalizedString("Seek Forward One Frame", comment: ""))
            .accessibilityHint(NSLocalizedString("Moves the playhead forward by one frame.", comment: ""))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(MovieCutTheme.inspectorSelectedControlSurface)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NSLocalizedString("Playback transport", comment: ""))
    }

    private var previewVolumeControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.wave.2")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Slider(value: Binding(
                get: { previewVolume },
                set: { newValue in
                    previewVolume = newValue
                    playbackEngine.player.volume = Float(newValue)
                }
            ), in: 0 ... 1)
            .frame(width: 72)
            .accessibilityLabel(NSLocalizedString("Volume", comment: ""))
            .accessibilityValue(String(format: NSLocalizedString("%.0f%%", comment: ""), previewVolume * 100))
            .accessibilityHint(NSLocalizedString("Adjusts preview playback volume.", comment: ""))
        }
    }

    private var previewZoomControls: some View {
        HStack(spacing: 6) {
            Button(action: resetPreviewZoomToFit) {
                Label(NSLocalizedString("Fit", comment: ""), systemImage: "arrow.up.left.and.down.right")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .help("Fit Preview")
            .accessibilityLabel(NSLocalizedString("Fit Preview", comment: ""))
            .accessibilityValue(previewZoomAccessibilityValue)
            .accessibilityHint(NSLocalizedString("Resets preview zoom to fit the canvas in the preview.", comment: ""))

            Button(action: { adjustPreviewZoom(by: -previewZoomStep) }) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .disabled(previewZoom <= previewZoomRange.lowerBound)
            .help("Zoom Preview Out")
            .accessibilityLabel(NSLocalizedString("Zoom Preview Out", comment: ""))
            .accessibilityHint(NSLocalizedString("Decreases the preview zoom.", comment: ""))

            Text(previewZoomDisplay)
                .font(.caption.monospacedDigit().weight(.medium))
                .frame(width: 42, alignment: .trailing)
                .accessibilityLabel(NSLocalizedString("Preview zoom", comment: ""))
                .accessibilityValue(previewZoomDisplay)

            Slider(value: Binding(
                get: { previewZoom },
                set: { newValue in
                    setManualPreviewZoom(newValue)
                }
            ), in: previewZoomRange, step: 0.05)
            .frame(width: 68)
            .accessibilityLabel(NSLocalizedString("Preview zoom slider", comment: ""))
            .accessibilityValue(previewZoomDisplay)
            .accessibilityHint(NSLocalizedString("Adjusts preview zoom without changing export or canvas settings.", comment: ""))

            Button(action: { adjustPreviewZoom(by: previewZoomStep) }) {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .disabled(previewZoom >= previewZoomRange.upperBound)
            .help("Zoom Preview In")
            .accessibilityLabel(NSLocalizedString("Zoom Preview In", comment: ""))
            .accessibilityHint(NSLocalizedString("Increases the preview zoom.", comment: ""))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(MovieCutTheme.inspectorSelectedControlSurface.opacity(0.88))
        )
        .overlay(
            Capsule()
                .stroke(MovieCutTheme.inspectorSelectedBorder.opacity(0.40), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NSLocalizedString("Preview zoom controls", comment: ""))
    }

    private var previewSafeZoneToggle: some View {
        Button(action: { showsSafeZoneGuides.toggle() }) {
            Image(systemName: showsSafeZoneGuides ? "rectangle.inset.filled" : "rectangle.dashed")
                .font(.caption.weight(.semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(showsSafeZoneGuides ? MovieCutTheme.accentCyan : Color.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(showsSafeZoneGuides ? MovieCutTheme.accentCyan.opacity(0.16) : MovieCutTheme.inspectorSelectedControlSurface.opacity(0.88))
        )
        .overlay(
            Capsule()
                .stroke(
                    showsSafeZoneGuides ? MovieCutTheme.accentCyan.opacity(0.42) : MovieCutTheme.inspectorSelectedBorder.opacity(0.40),
                    lineWidth: 0.5
                )
        )
        .help(showsSafeZoneGuides ? "Hide Safe Zones" : "Show Safe Zones")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NSLocalizedString("Safe zone guides", comment: ""))
        .accessibilityValue(showsSafeZoneGuides ? NSLocalizedString("On", comment: "") : NSLocalizedString("Off", comment: ""))
        .accessibilityHint(NSLocalizedString("Shows or hides non-exporting title and action safe guides on the preview canvas.", comment: ""))
    }

    private var previewZoomDisplay: String {
        String(format: NSLocalizedString("%.0f%%", comment: ""), clampedPreviewZoom(previewZoom) * 100)
    }

    private var previewZoomAccessibilityValue: String {
        if isPreviewZoomFit {
            return String(format: NSLocalizedString("%@, fit", comment: ""), previewZoomDisplay)
        }
        return previewZoomDisplay
    }

    private func resetPreviewZoomToFit() {
        previewZoom = 1
        isPreviewZoomFit = true
    }

    private func setManualPreviewZoom(_ zoom: Double) {
        previewZoom = clampedPreviewZoom(zoom)
        isPreviewZoomFit = false
    }

    private func adjustPreviewZoom(by delta: Double) {
        setManualPreviewZoom(previewZoom + delta)
    }

    private func clampedPreviewZoom(_ zoom: Double) -> Double {
        min(previewZoomRange.upperBound, max(previewZoomRange.lowerBound, zoom))
    }

    private var previewSurface: some View {
        ZStack {
            // The project composition is the source of truth for the rendered
            // video frame (multi-track, transitions, effects, masks, audio
            // mix). Canvas editing overlays (text/sticker transform, mask,
            // chroma eyedropper, motion tracking) are layered on top for
            // interaction but do not re-render the underlying pixels — the
            // composition already bakes them in via Core Animation.
            //
            // When the selected clip is text/audio (no visual source) and the
            // project has no rendered video track behind it, fall back to the
            // editorial matte so the preview never shows an empty void while
            // the user edits a text or audio-only clip.
            if projectHasRenderedVideoTrack {
                VideoPreviewView(player: playbackEngine.player)
            } else if let clip = viewModel.selectedClip, usesLoop4PreviewEditorialMatte(for: clip) {
                PreviewLoop4EditorialMatte(
                    clipKind: clip.kind,
                    textContent: clip.textContent
                )
            } else {
                VideoPreviewView(player: playbackEngine.player)
            }
        }
        .aspectRatio(canvasAspectRatio, contentMode: .fit)
        .overlay {
            if let clip = viewModel.selectedClip {
                previewOverlay(for: clip)
            }
        }
        .scaleEffect(previewZoom)
        .accessibilityValue(previewZoomAccessibilityValue)
    }

    /// Whether any non-text/non-audio clip exists that the composition can
    /// render real pixels for. Text-only or audio-only selections still get
    /// the editorial matte so the canvas isn't a black void.
    private var projectHasRenderedVideoTrack: Bool {
        let timeline = viewModel.currentProject.timeline
        // Video tracks carry both video and image clips (image clips are
        // promoted onto video tracks and rendered via ImageVideoRenderService).
        return timeline.tracks.contains { track in
            track.kind == .video && track.clips.contains { $0.assetId != nil }
        }
    }

    private var canvasAspectRatio: CGFloat {
        let size = viewModel.currentProject.canvas.size
        return size.width / max(size.height, 1)
    }

    private var hasImportedMedia: Bool {
        !viewModel.currentProject.mediaLibrary.assets.isEmpty
    }

    private func usesLoop4PreviewEditorialMatte(for clip: Clip) -> Bool {
        switch clip.kind {
        case .audio, .text:
            return true
        case .video, .image:
            return clip.assetId == nil
        }
    }

    private var emptyStateTitle: String {
        hasImportedMedia
            ? NSLocalizedString("Select a clip", comment: "")
            : NSLocalizedString("Import media", comment: "")
    }

    private var emptyStateMessage: String {
        hasImportedMedia
            ? NSLocalizedString("Choose a timeline clip to preview it.", comment: "")
            : NSLocalizedString("Import media, then drag it to the timeline.", comment: "")
    }

    private var previewEmptyState: some View {
        VStack(spacing: MovieCutSpacing.xSmall) {
            Image(systemName: hasImportedMedia ? "play.rectangle" : "plus.rectangle.on.rectangle")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.white.opacity(0.44))
                .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text(emptyStateTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))
                Text(emptyStateMessage)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.50))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 220)
            }

            Button {
                openImportPanel()
            } label: {
                Label(NSLocalizedString("Import Media", comment: ""), systemImage: "square.and.arrow.down")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(NSLocalizedString("Import media", comment: ""))
            .accessibilityHint(NSLocalizedString("Opens a file picker for video, audio, or image assets.", comment: ""))
        }
        .frame(maxWidth: 250)
        .movieCutCard(
            padding: MovieCutSpacing.small,
            cornerRadius: MovieCutRadius.small,
            background: MovieCutTheme.previewEmptyStateBackground.opacity(0.74),
            border: MovieCutTheme.border.opacity(0.18)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(emptyStateTitle)
        .accessibilityHint(emptyStateMessage)
    }

    private func previewTimeBadge(title: String, value: String, accessibilityLabel: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(.primary)
        }
        .frame(width: 104, alignment: .leading)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(value)
    }

    private var previewCanvasResolutionBadge: some View {
        Label {
            Text(viewModel.canvasResolutionBadgeText)
                .lineLimit(1)
                .monospacedDigit()
        } icon: {
            Image(systemName: "rectangle.ratio")
                .accessibilityHidden(true)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(MovieCutTheme.inspectorSelectedControlSurface.opacity(0.88))
        )
        .overlay(
            Capsule()
                .stroke(MovieCutTheme.inspectorSelectedBorder.opacity(0.40), lineWidth: 0.5)
        )
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NSLocalizedString("Preview canvas and export resolution", comment: ""))
        .accessibilityValue(viewModel.canvasResolutionBadgeText)
        .accessibilityHint(NSLocalizedString("Shows the preview canvas ratio and computed export render size.", comment: ""))
    }

    @ViewBuilder
    private func previewOverlay(for clip: Clip) -> some View {
        ZStack {
            if clip.assetId == nil {
                clipPlaceholder(for: clip)
            }

            if showsSafeZoneGuides {
                safeZoneGuideOverlay(guides: SafeZoneGuide.standard)
            }

            if viewModel.hasReframePreview, viewModel.reframePreviewClipId == clip.id {
                ReframeCropPathOverlay(frames: viewModel.reframePreviewFrames)
            }

            if let trackingRect = viewModel.motionTrackingOverlayRect,
               viewModel.motionTrackingClipId == clip.id {
                MotionTrackingBoxOverlay(
                    rect: trackingRect,
                    isEditable: viewModel.isMotionTrackingOverlayEditable,
                    isTracking: viewModel.isMotionTrackingRunning
                ) { updatedRect in
                    viewModel.updateMotionTrackingInitialRect(updatedRect)
                }
            }

            if viewModel.isChromaKeyEyedropperActive, clip.kind == .video {
                ChromaKeyEyedropperOverlay { normalizedPoint in
                    Task { await viewModel.pickChromaKeyColor(atNormalizedPoint: normalizedPoint) }
                }
            }

            if viewModel.isMaskEditorActive {
                MaskCanvasView(
                    mask: maskBinding(for: clip.id),
                    canvasSize: viewModel.currentProject.canvas.size
                )
            }

            if viewModel.hasMultipleSelectedCanvasOverlays {
                CanvasMultiSelectionOverlay(
                    clips: viewModel.selectedCanvasOverlayClips,
                    canvasSize: viewModel.currentProject.canvas.size,
                    onNudge: { dx, dy in
                        Task { await viewModel.nudgeSelectedCanvasOverlays(dx: dx, dy: dy) }
                    },
                    onAlign: { alignment in
                        Task { await viewModel.alignSelectedCanvasOverlays(alignment) }
                    },
                    onCenter: {
                        Task { await viewModel.centerSelectedCanvasOverlays() }
                    }
                )
            } else if clip.kind == .text, let textContent = clip.textContent {
                CanvasTransformOverlay(
                    clip: clip,
                    textContent: textContent,
                    canvasSize: viewModel.currentProject.canvas.size,
                    isSticker: viewModel.selectedClipIsSticker,
                    clipZIndex: clip.zIndex,
                    onLayerBackward: {
                        Task { await viewModel.moveSelectedClipLayerBackward() }
                    },
                    onLayerForward: {
                        Task { await viewModel.moveSelectedClipLayerForward() }
                    },
                    onLayerFront: {
                        Task { await viewModel.bringSelectedClipLayerToFront() }
                    },
                    onLayerBackmost: {
                        Task { await viewModel.sendSelectedClipLayerToBack() }
                    }
                ) { updatedTransform in
                    commitCanvasTransform(
                        updatedTransform,
                        for: clip,
                        textContent: textContent,
                        isSticker: viewModel.selectedClipIsSticker
                    )
                }
            }
        }
    }

    private func safeZoneGuideOverlay(guides: [SafeZoneGuide]) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(Array(guides.enumerated()), id: \.offset) { index, guide in
                    let rect = safeZoneRect(for: guide, in: proxy.size)
                    let color = safeZoneColor(for: guide)

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(
                            color.opacity(0.78),
                            style: StrokeStyle(lineWidth: 1, dash: index == 0 ? [5, 4] : [3, 3])
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    Text(guide.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(color.opacity(0.86))
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.34))
                        )
                        .overlay(
                            Capsule()
                                .stroke(color.opacity(0.34), lineWidth: 0.5)
                        )
                        .fixedSize()
                        .offset(x: rect.minX + 7, y: rect.minY + 7)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func safeZoneRect(for guide: SafeZoneGuide, in size: CGSize) -> CGRect {
        let insets = guide.insets
        let minX = size.width * CGFloat(insets.leading)
        let minY = size.height * CGFloat(insets.top)
        let maxX = size.width * (1 - CGFloat(insets.trailing))
        let maxY = size.height * (1 - CGFloat(insets.bottom))

        return CGRect(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }

    private func safeZoneColor(for guide: SafeZoneGuide) -> Color {
        Color(hex: guide.colorHex)
    }

    private func maskBinding(for clipId: UUID) -> Binding<Mask?> {
        Binding(
            get: {
                guard viewModel.selectedClip?.id == clipId else { return nil }
                return viewModel.selectedClip?.mask
            },
            set: { newMask in
                Task {
                    guard viewModel.selectedClipId == clipId else { return }
                    await viewModel.updateSelectedMask(newMask)
                }
            }
        )
    }

    private func commitCanvasTransform(
        _ transform: ClipTransform,
        for clip: Clip,
        textContent: TextClipContent,
        isSticker: Bool
    ) {
        Task {
            guard viewModel.selectedClipId == clip.id else { return }

            if isSticker {
                await viewModel.updateSelectedStickerTransform(transform)
                return
            }

            await viewModel.updateSelectedTransform(transform)

            guard viewModel.selectedClipId == clip.id else { return }
            guard !pointsEqual(textContent.position, transform.position) else { return }

            var updatedContent = textContent
            updatedContent.position = transform.position
            await viewModel.updateSelectedTextContent(updatedContent)
        }
    }

    private func pointsEqual(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) <= 1.0e-9 && abs(lhs.y - rhs.y) <= 1.0e-9
    }

    private func clipPlaceholder(for clip: Clip) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "play.rectangle")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.5))
            Text(String(describing: clip.kind))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var previewAccessibilityValue: String {
        if let clip = viewModel.selectedClip {
            return String(format: NSLocalizedString("Selected clip %@", comment: ""), String(describing: clip.kind))
        }
        return emptyStateTitle
    }

    private func openImportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .audio, .image]
        if panel.runModal() == .OK {
            let urls = panel.urls
            Task { @MainActor in
                await viewModel.importMedia(urls)
            }
        }
    }

    private func loadProjectComposition() {
        viewModel.rebuildPreviewComposition()
    }

    private func seekByFrames(_ frameCount: Int) {
        let frameRate = viewModel.currentProject.timeline.frameRate.doubleValue
        guard frameRate > 0 else { return }
        let frameDuration = 1.0 / frameRate
        let nextTime = playbackEngine.currentTime + (Double(frameCount) * frameDuration)
        playbackEngine.seek(to: nextTime)
        viewModel.playheadTime = min(max(0, nextTime), max(0, viewModel.currentProject.timeline.duration))
    }

    private func timecodeString(_ time: TimeInterval) -> String {
        let t = max(0, time)
        let totalSeconds = Int(t)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let frames = Int((t - Double(totalSeconds)) * 30)
        return String(format: "%02d:%02d:%02d", minutes, seconds, abs(frames))
    }
}

private extension Color {
    init(hex: String) {
        if let rgb = HexColorMath.rgb(fromHex: hex) {
            self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
        } else {
            self.init(.sRGB, red: 1, green: 1, blue: 1, opacity: 1)
        }
    }
}

private struct PreviewLoop4WellTexture: View {
    var intensity: Double = 1

    var body: some View {
        Canvas { context, size in
            for index in 0..<5 {
                let x = size.width * (0.08 + CGFloat(index) * 0.17)
                let y = size.height * (0.18 + CGFloat(index % 2) * 0.08)
                let rect = CGRect(
                    x: x,
                    y: y,
                    width: size.width * 0.13,
                    height: size.height * 0.08
                )
                context.fill(
                    Self.roundedRectPath(rect, radius: 5),
                    with: .color(MovieCutTheme.previewLoop4MatteBlock.opacity((index.isMultiple(of: 2) ? 0.42 : 0.30) * intensity))
                )
            }

            for index in 0..<6 {
                let x = size.width * (0.14 + CGFloat(index) * 0.10)
                var line = Path()
                line.move(to: CGPoint(x: x, y: size.height * 0.10))
                line.addLine(to: CGPoint(x: x + size.width * 0.10, y: size.height * 0.90))
                context.stroke(line, with: .color(MovieCutTheme.previewLoop4MatteLine.opacity(0.34 * intensity)), lineWidth: 0.7)
            }

            for index in 0..<4 {
                let y = size.height * (0.22 + CGFloat(index) * 0.10)
                var line = Path()
                line.move(to: CGPoint(x: size.width * 0.08, y: y))
                line.addLine(to: CGPoint(x: size.width * 0.92, y: y))
                context.stroke(line, with: .color(MovieCutTheme.previewLoop4MatteLine.opacity(0.24 * intensity)), lineWidth: 0.7)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> Path {
        var path = Path()
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius))
        return path
    }
}

private struct PreviewLoop4EditorialMatte: View {
    var clipKind: ClipKind
    var textContent: TextClipContent?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    MovieCutTheme.previewLoop4MatteBase,
                    MovieCutTheme.previewLoop4WellSurface,
                    MovieCutTheme.previewLoop4MatteBase
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            PreviewLoop4MattePattern()

            VStack(spacing: 0) {
                statusChips
                Spacer(minLength: 12)
                centerScaffold
                Spacer(minLength: 12)
                bottomStrip
            }
            .padding(18)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(MovieCutTheme.previewLoop4MatteLine.opacity(0.42), lineWidth: 0.8)
        )
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var statusChips: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(MovieCutTheme.previewLoop4MatteBlock.opacity(index == 0 ? 0.95 : 0.55))
                    .frame(width: index == 0 ? 54 : 32, height: 7)
            }

            Spacer(minLength: 12)

            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(MovieCutTheme.previewLoop4MatteLine.opacity(index == 1 ? 0.72 : 0.38))
                    .frame(width: 7, height: 7)
            }
        }
    }

    @ViewBuilder
    private var centerScaffold: some View {
        if let textContent {
            PreviewLoop4TextSelectionScaffold(textContent: textContent)
        } else {
            PreviewLoop4LowContentScaffold(clipKind: clipKind)
        }
    }

    private var bottomStrip: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<24, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(MovieCutTheme.previewLoop4MatteLine.opacity(0.38 + Double(index % 4) * 0.08))
                    .frame(width: CGFloat(5 + (index % 5) * 2), height: CGFloat(5 + (index % 6)))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(MovieCutTheme.previewLoop4MatteBlock.opacity(0.40))
        )
    }
}

private struct PreviewLoop4MattePattern: View {
    var body: some View {
        Canvas { context, size in
            let posterRect = CGRect(
                x: size.width * 0.37,
                y: size.height * 0.12,
                width: size.width * 0.30,
                height: size.height * 0.64
            )
            context.fill(Self.roundedRectPath(posterRect, radius: 7), with: .color(MovieCutTheme.previewLoop4MatteBlock.opacity(0.95)))

            for index in 0..<6 {
                let rect = CGRect(
                    x: posterRect.minX + posterRect.width * 0.10,
                    y: posterRect.minY + posterRect.height * (0.12 + CGFloat(index) * 0.11),
                    width: posterRect.width * (index.isMultiple(of: 2) ? 0.78 : 0.56),
                    height: posterRect.height * 0.045
                )
                context.fill(Self.roundedRectPath(rect, radius: 3), with: .color(MovieCutTheme.previewLoop4MatteBase.opacity(0.42)))
            }

            let sideRects = [
                CGRect(x: size.width * 0.08, y: size.height * 0.16, width: size.width * 0.20, height: size.height * 0.15),
                CGRect(x: size.width * 0.12, y: size.height * 0.38, width: size.width * 0.18, height: size.height * 0.14),
                CGRect(x: size.width * 0.68, y: size.height * 0.18, width: size.width * 0.20, height: size.height * 0.14),
                CGRect(x: size.width * 0.66, y: size.height * 0.42, width: size.width * 0.22, height: size.height * 0.17),
                CGRect(x: size.width * 0.23, y: size.height * 0.72, width: size.width * 0.54, height: size.height * 0.08),
            ]

            for (index, rect) in sideRects.enumerated() {
                context.fill(
                    Self.roundedRectPath(rect, radius: 6),
                    with: .color(MovieCutTheme.previewLoop4MatteBlock.opacity(index.isMultiple(of: 2) ? 0.76 : 0.58))
                )
            }

            for index in 0..<9 {
                let x = size.width * (0.10 + CGFloat(index) * 0.09)
                var line = Path()
                line.move(to: CGPoint(x: x, y: size.height * 0.09))
                line.addLine(to: CGPoint(x: x + size.width * 0.16, y: size.height * 0.88))
                context.stroke(line, with: .color(MovieCutTheme.previewLoop4MatteLine.opacity(0.94)), lineWidth: 1.0)
            }

            for index in 0..<5 {
                let y = size.height * (0.18 + CGFloat(index) * 0.13)
                var line = Path()
                line.move(to: CGPoint(x: size.width * 0.08, y: y))
                line.addLine(to: CGPoint(x: size.width * 0.92, y: y))
                context.stroke(line, with: .color(MovieCutTheme.previewLoop4MatteLine.opacity(0.72)), lineWidth: 0.9)
            }
        }
        .accessibilityHidden(true)
    }

    private static func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> Path {
        var path = Path()
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius))
        return path
    }
}

private struct PreviewLoop4TextSelectionScaffold: View {
    var textContent: TextClipContent

    private var displayText: String {
        textContent.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.28))

                if displayText.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(MovieCutTheme.previewLoop4MatteLine.opacity(0.58))
                                .frame(width: CGFloat(130 - index * 18), height: 8)
                        }
                    }
                } else {
                    Text(displayText)
                        .font(.system(size: displayFontSize, weight: textContent.isBold ? .bold : .semibold))
                        .foregroundStyle(Color.white.opacity(0.76))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.62)
                        .padding(.horizontal, 18)
                }
            }
            .frame(width: 260, height: 96)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        MovieCutTheme.previewLoop4MatteLine.opacity(0.86),
                        style: StrokeStyle(lineWidth: 1.2, dash: [7, 5])
                    )
            )

            HStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(MovieCutTheme.previewLoop4MatteBlock.opacity(index == 2 ? 0.92 : 0.48))
                        .frame(width: index == 2 ? 46 : 28, height: 7)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(MovieCutTheme.previewLoop4MatteBase.opacity(0.44))
        )
    }

    private var displayFontSize: CGFloat {
        min(max(CGFloat(textContent.fontSize) * 0.26, 17), 30)
    }
}

private struct PreviewLoop4LowContentScaffold: View {
    var clipKind: ClipKind

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<38, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(MovieCutTheme.previewLoop4MatteLine.opacity(0.44 + Double(index % 5) * 0.07))
                        .frame(width: 4, height: CGFloat(12 + ((index * 7) % 34)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MovieCutTheme.previewLoop4MatteBlock.opacity(0.50))
            )

            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(MovieCutTheme.previewLoop4MatteBlock.opacity(index.isMultiple(of: 2) ? 0.76 : 0.42))
                        .frame(width: index == 0 ? 42 : 28, height: 8)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(MovieCutTheme.previewLoop4MatteBase.opacity(0.34))
        )
    }
}

private struct CanvasTransformOverlay: View {
    var clip: Clip
    var textContent: TextClipContent
    var canvasSize: CGSize
    var isSticker: Bool
    var clipZIndex: Int?
    var onLayerBackward: () -> Void
    var onLayerForward: () -> Void
    var onLayerFront: () -> Void
    var onLayerBackmost: () -> Void
    var onCommit: (ClipTransform) -> Void

    @State private var draftTransform: ClipTransform?
    @State private var gestureStartTransform: ClipTransform?
    @State private var activeSnapGuides: [CanvasSnapGuide] = []

    private static let coordinateSpaceName = "CanvasTransformOverlayCoordinateSpace"
    private static let snapThresholdViewPoints: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            overlayContent(in: proxy.size)
        }
        .onChange(of: clip.id) { _, _ in
            draftTransform = nil
            gestureStartTransform = nil
            activeSnapGuides = []
        }
        .onChange(of: clip.transform) { _, _ in
            guard gestureStartTransform == nil else { return }
            draftTransform = nil
            activeSnapGuides = []
        }
    }

    @ViewBuilder
    private func overlayContent(in viewSize: CGSize) -> some View {
        let metrics = CanvasTransformMetrics(viewSize: viewSize, canvasSize: canvasSize)

        if metrics.isUsable {
            let transform = displayTransform
            let baseSize = estimatedContentSize
            let center = centerPoint(for: transform, metrics: metrics)
            let size = metrics.viewSize(for: scaled(baseSize, by: uniformScale(for: transform)))
            let corners = rotatedCorners(center: center, size: size, rotation: transform.rotation)
            let resizePoint = corners.bottomRight
            let rotatePoint = rotatedPoint(
                center: center,
                offset: CGPoint(x: 0, y: -(size.height * 0.5 + 34)),
                rotation: transform.rotation
            )
            let topCenter = rotatedPoint(
                center: center,
                offset: CGPoint(x: 0, y: -size.height * 0.5),
                rotation: transform.rotation
            )

            ZStack(alignment: .topLeading) {
                CanvasSnapGuidesView(guides: activeSnapGuides, metrics: metrics)

                selectionRectangle(center: center, size: size, rotation: transform.rotation)
                    .gesture(moveGesture(metrics: metrics))

                connector(from: topCenter, to: rotatePoint)

                CanvasTransformHandle(systemImage: "arrow.up.and.down.and.arrow.left.and.right", shape: .circle)
                    .position(center)
                    .gesture(moveGesture(metrics: metrics))
                    .accessibilityLabel("Canvas transform overlay")
                    .accessibilityHint("Drag to move selected sticker/text")

                CanvasTransformHandle(systemImage: "arrow.down.right.and.arrow.up.left", shape: .square)
                    .position(resizePoint)
                    .gesture(resizeGesture(metrics: metrics))
                    .accessibilityLabel("Resize handle")
                    .accessibilityHint("Drag to resize the selected sticker or text uniformly.")

                CanvasTransformHandle(systemImage: "rotate.right", shape: .circle)
                    .position(rotatePoint)
                    .gesture(rotateGesture(metrics: metrics))
                    .accessibilityLabel("Rotate handle")
                    .accessibilityHint("Drag to rotate the selected sticker or text.")

                CanvasTransformControlStack(
                    transform: transform,
                    clipZIndex: clipZIndex,
                    onCenter: centerOverlay,
                    onNudgeLeft: { nudgeOverlay(dx: -8, dy: 0) },
                    onNudgeRight: { nudgeOverlay(dx: 8, dy: 0) },
                    onNudgeUp: { nudgeOverlay(dx: 0, dy: 8) },
                    onNudgeDown: { nudgeOverlay(dx: 0, dy: -8) },
                    onLayerBackward: onLayerBackward,
                    onLayerForward: onLayerForward,
                    onLayerFront: onLayerFront,
                    onLayerBackmost: onLayerBackmost
                )
                .position(controlStackPosition(center: center, size: size, viewSize: viewSize))
            }
            .coordinateSpace(name: Self.coordinateSpaceName)
            .frame(width: viewSize.width, height: viewSize.height)
            .clipped()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Canvas transform overlay")
        }
    }

    private var displayTransform: ClipTransform {
        draftTransform ?? resolvedBaseTransform
    }

    private var resolvedBaseTransform: ClipTransform {
        var transform = clip.transform
        if isZeroPoint(transform.position) {
            if !isZeroPoint(textContent.position) {
                transform.position = textContent.position
            } else {
                transform.position = CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
            }
        }
        return transform
    }

    private var estimatedContentSize: CGSize {
        let fontSize = CGFloat(max(textContent.fontSize, 1))
        let shorterCanvasEdge = max(min(canvasSize.width, canvasSize.height), 1)

        if textContent.stickerImageURL != nil {
            let width = min(max(fontSize * 2.8, 96), shorterCanvasEdge * 0.45)
            return CGSize(width: width, height: width * 0.72)
        }

        if isSticker {
            let size = min(max(fontSize * 1.2, 72), shorterCanvasEdge * 0.35)
            return CGSize(width: size, height: size)
        }

        let characterEstimate = CGFloat(max(textContent.text.count, 1))
        let width = min(max(characterEstimate * fontSize * 0.48 + 40, 160), canvasSize.width * 0.78)
        let height = min(max(fontSize + 28, 56), canvasSize.height * 0.32)
        return CGSize(width: width, height: height)
    }

    private func selectionRectangle(center: CGPoint, size: CGSize, rotation: Double) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(
                Color.white.opacity(0.92),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [7, 5])
            )
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.08))
            )
            .frame(width: max(size.width, 36), height: max(size.height, 36))
            .rotationEffect(.degrees(rotation))
            .position(center)
            .contentShape(Rectangle())
            .accessibilityLabel("Canvas transform overlay")
            .accessibilityHint("Drag to move selected sticker/text")
    }

    private func connector(from start: CGPoint, to end: CGPoint) -> some View {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func moveGesture(metrics: CanvasTransformMetrics) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                let start = startInteraction()
                let vector = metrics.canvasVector(for: value.translation)
                var updated = start
                let proposedPosition = metrics.clampedCanvasPoint(CGPoint(
                    x: start.position.x + vector.dx,
                    y: start.position.y + vector.dy
                ))
                let snapped = snappedPosition(proposedPosition, offset: start.offset, metrics: metrics)
                updated.position = snapped.position
                activeSnapGuides = snapped.guides
                draftTransform = updated
            }
            .onEnded { _ in
                commitInteraction()
            }
    }

    private func resizeGesture(metrics: CanvasTransformMetrics) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                let start = startInteraction()
                let startScale = uniformScale(for: start)
                let center = centerPoint(for: start, metrics: metrics)
                let startSize = metrics.viewSize(for: scaled(estimatedContentSize, by: startScale))
                let startHandle = rotatedPoint(
                    center: center,
                    offset: CGPoint(x: startSize.width * 0.5, y: startSize.height * 0.5),
                    rotation: start.rotation
                )
                let baseDistance = max(distance(from: center, to: startHandle), 1)
                let nextDistance = max(distance(from: center, to: value.location), 1)
                let scale = min(max(startScale * (nextDistance / baseDistance), 0.25), 3.0)

                var updated = start
                updated.scale = CGSize(width: scale, height: scale)
                draftTransform = updated
            }
            .onEnded { _ in
                commitInteraction()
            }
    }

    private func rotateGesture(metrics: CanvasTransformMetrics) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                let start = startInteraction()
                let center = centerPoint(for: start, metrics: metrics)
                let initialAngle = angle(from: center, to: value.startLocation)
                let currentAngle = angle(from: center, to: value.location)
                var updated = start
                updated.rotation = normalizedDegrees(start.rotation + Double((currentAngle - initialAngle) * 180 / .pi))
                draftTransform = updated
            }
            .onEnded { _ in
                commitInteraction()
            }
    }

    private func startInteraction() -> ClipTransform {
        if let gestureStartTransform {
            return gestureStartTransform
        }

        let transform = displayTransform
        gestureStartTransform = transform
        return transform
    }

    private func commitInteraction() {
        if let draftTransform {
            onCommit(draftTransform)
        }
        gestureStartTransform = nil
        activeSnapGuides = []
    }

    private func centerOverlay() {
        let transform = displayTransform
        let centeredPosition = canvasPosition(forCenter: CGPoint(
            x: canvasSize.width * 0.5,
            y: canvasSize.height * 0.5
        ), offset: transform.offset)
        commitControlTransform(transform, position: centeredPosition)
    }

    private func nudgeOverlay(dx: CGFloat, dy: CGFloat) {
        let transform = displayTransform
        let nudgedPosition = CGPoint(
            x: transform.position.x + dx,
            y: transform.position.y + dy
        )
        commitControlTransform(transform, position: clampedCanvasPoint(nudgedPosition))
    }

    private func commitControlTransform(_ transform: ClipTransform, position: CGPoint) {
        var updated = transform
        updated.position = position
        draftTransform = updated
        activeSnapGuides = []
        onCommit(updated)
    }

    private func snappedPosition(
        _ position: CGPoint,
        offset: CGPoint,
        metrics: CanvasTransformMetrics
    ) -> CanvasSnapResult {
        var center = CGPoint(
            x: position.x + offset.x,
            y: position.y + offset.y
        )
        var guides: [CanvasSnapGuide] = []

        if let verticalGuide = nearestVerticalGuide(to: center.x, metrics: metrics) {
            center.x = verticalGuide.position
            guides.append(verticalGuide)
        }

        if let horizontalGuide = nearestHorizontalGuide(to: center.y, metrics: metrics) {
            center.y = horizontalGuide.position
            guides.append(horizontalGuide)
        }

        return CanvasSnapResult(
            position: canvasPosition(forCenter: center, offset: offset),
            guides: guides
        )
    }

    private func nearestVerticalGuide(to canvasX: CGFloat, metrics: CanvasTransformMetrics) -> CanvasSnapGuide? {
        nearestGuide(
            to: canvasX,
            scale: metrics.scaleX,
            candidates: [
                CanvasSnapGuide(kind: .verticalCenter, position: canvasSize.width * 0.5),
                CanvasSnapGuide(kind: .safeLeft, position: safeAreaRect.minX),
                CanvasSnapGuide(kind: .safeRight, position: safeAreaRect.maxX),
            ]
        )
    }

    private func nearestHorizontalGuide(to canvasY: CGFloat, metrics: CanvasTransformMetrics) -> CanvasSnapGuide? {
        nearestGuide(
            to: canvasY,
            scale: metrics.scaleY,
            candidates: [
                CanvasSnapGuide(kind: .horizontalCenter, position: canvasSize.height * 0.5),
                CanvasSnapGuide(kind: .safeBottom, position: safeAreaRect.minY),
                CanvasSnapGuide(kind: .safeTop, position: safeAreaRect.maxY),
            ]
        )
    }

    private func nearestGuide(
        to value: CGFloat,
        scale: CGFloat,
        candidates: [CanvasSnapGuide]
    ) -> CanvasSnapGuide? {
        let usableScale = max(scale, .leastNonzeroMagnitude)
        let nearest = candidates.min {
            abs($0.position - value) * usableScale < abs($1.position - value) * usableScale
        }
        guard let nearest, abs(nearest.position - value) * usableScale <= Self.snapThresholdViewPoints else {
            return nil
        }
        return nearest
    }

    private var safeAreaRect: CGRect {
        CGRect(
            x: canvasSize.width * 0.1,
            y: canvasSize.height * 0.1,
            width: canvasSize.width * 0.8,
            height: canvasSize.height * 0.8
        )
    }

    private func canvasPosition(forCenter center: CGPoint, offset: CGPoint) -> CGPoint {
        clampedCanvasPoint(CGPoint(
            x: center.x - offset.x,
            y: center.y - offset.y
        ))
    }

    private func clampedCanvasPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), canvasSize.width),
            y: min(max(point.y, 0), canvasSize.height)
        )
    }

    private func centerPoint(for transform: ClipTransform, metrics: CanvasTransformMetrics) -> CGPoint {
        metrics.viewPoint(for: CGPoint(
            x: transform.position.x + transform.offset.x,
            y: transform.position.y + transform.offset.y
        ))
    }

    private func rotatedCorners(
        center: CGPoint,
        size: CGSize,
        rotation: Double
    ) -> (topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
        (
            topLeft: rotatedPoint(center: center, offset: CGPoint(x: -size.width * 0.5, y: -size.height * 0.5), rotation: rotation),
            topRight: rotatedPoint(center: center, offset: CGPoint(x: size.width * 0.5, y: -size.height * 0.5), rotation: rotation),
            bottomRight: rotatedPoint(center: center, offset: CGPoint(x: size.width * 0.5, y: size.height * 0.5), rotation: rotation),
            bottomLeft: rotatedPoint(center: center, offset: CGPoint(x: -size.width * 0.5, y: size.height * 0.5), rotation: rotation)
        )
    }

    private func rotatedPoint(center: CGPoint, offset: CGPoint, rotation: Double) -> CGPoint {
        let radians = CGFloat(rotation * .pi / 180)
        let cosValue = cos(radians)
        let sinValue = sin(radians)
        return CGPoint(
            x: center.x + offset.x * cosValue - offset.y * sinValue,
            y: center.y + offset.x * sinValue + offset.y * cosValue
        )
    }

    private func controlStackPosition(center: CGPoint, size: CGSize, viewSize: CGSize) -> CGPoint {
        let x = min(max(center.x, 160), max(viewSize.width - 160, 160))
        let preferredY = center.y - size.height * 0.5 - 72
        let y = min(max(preferredY, 58), max(viewSize.height - 58, 58))
        return CGPoint(x: x, y: y)
    }

    private func uniformScale(for transform: ClipTransform) -> CGFloat {
        let scale = (transform.scale.width + transform.scale.height) * 0.5
        guard scale.isFinite, scale > 0 else { return 1 }
        return scale
    }

    private func scaled(_ size: CGSize, by scale: CGFloat) -> CGSize {
        CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func angle(from start: CGPoint, to end: CGPoint) -> CGFloat {
        atan2(end.y - start.y, end.x - start.x)
    }

    private func normalizedDegrees(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 {
            value -= 360
        } else if value < -180 {
            value += 360
        }
        return value
    }

    private func isZeroPoint(_ point: CGPoint) -> Bool {
        abs(point.x) <= 1.0e-9 && abs(point.y) <= 1.0e-9
    }
}

private struct CanvasMultiSelectionOverlay: View {
    var clips: [Clip]
    var canvasSize: CGSize
    var onNudge: (CGFloat, CGFloat) -> Void
    var onAlign: (CanvasOverlayAlignment) -> Void
    var onCenter: () -> Void

    var body: some View {
        GeometryReader { proxy in
            overlayContent(in: proxy.size)
        }
    }

    @ViewBuilder
    private func overlayContent(in viewSize: CGSize) -> some View {
        let metrics = CanvasTransformMetrics(viewSize: viewSize, canvasSize: canvasSize)

        if metrics.isUsable, let bounds = selectionBounds(metrics: metrics) {
            ZStack(alignment: .topLeading) {
                selectionBox(bounds: bounds)

                Text("\(clips.count) selected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .position(labelPosition(for: bounds))
                    .accessibilityLabel("\(clips.count) selected")

                CanvasGroupControlStack(
                    onCenter: onCenter,
                    onNudgeLeft: { onNudge(-8, 0) },
                    onNudgeRight: { onNudge(8, 0) },
                    onNudgeUp: { onNudge(0, 8) },
                    onNudgeDown: { onNudge(0, -8) },
                    onAlign: onAlign
                )
                .position(controlStackPosition(bounds: bounds, viewSize: viewSize))
            }
            .frame(width: viewSize.width, height: viewSize.height)
            .clipped()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Multi-selection transform box")
        }
    }

    private func selectionBox(bounds: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(
                Color.white.opacity(0.94),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [8, 5])
            )
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.06))
            )
            .frame(width: bounds.width, height: bounds.height)
            .position(CGPoint(x: bounds.midX, y: bounds.midY))
            .accessibilityLabel("Multi-selection transform box")
            .accessibilityValue("\(clips.count) selected")
    }

    private func selectionBounds(metrics: CanvasTransformMetrics) -> CGRect? {
        var canvasBounds: CGRect?

        for clip in clips {
            guard let textContent = clip.textContent else { continue }

            let transform = resolvedTransform(for: clip, textContent: textContent)
            let baseSize = estimatedContentSize(for: textContent)
            let displaySize = scaled(baseSize, by: uniformScale(for: transform))
            let center = CGPoint(
                x: transform.position.x + transform.offset.x,
                y: transform.position.y + transform.offset.y
            )
            let rect = CGRect(
                x: center.x - displaySize.width * 0.5,
                y: center.y - displaySize.height * 0.5,
                width: displaySize.width,
                height: displaySize.height
            )

            if let currentBounds = canvasBounds {
                canvasBounds = currentBounds.union(rect)
            } else {
                canvasBounds = rect
            }
        }

        guard let canvasBounds else { return nil }

        let center = metrics.viewPoint(for: CGPoint(x: canvasBounds.midX, y: canvasBounds.midY))
        let size = metrics.viewSize(for: canvasBounds.size)
        return CGRect(
            x: center.x - size.width * 0.5,
            y: center.y - size.height * 0.5,
            width: size.width,
            height: size.height
        )
    }

    private func resolvedTransform(for clip: Clip, textContent: TextClipContent) -> ClipTransform {
        var transform = clip.transform
        if isZeroPoint(transform.position) {
            if !isZeroPoint(textContent.position) {
                transform.position = textContent.position
            } else {
                transform.position = CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
            }
        }
        return transform
    }

    private func estimatedContentSize(for textContent: TextClipContent) -> CGSize {
        let fontSize = CGFloat(max(textContent.fontSize, 1))
        let shorterCanvasEdge = max(min(canvasSize.width, canvasSize.height), 1)

        if textContent.stickerImageURL != nil {
            let width = min(max(fontSize * 2.8, 96), shorterCanvasEdge * 0.45)
            return CGSize(width: width, height: width * 0.72)
        }

        if textContent.isSticker || textContent.fontFamily == "Apple Color Emoji" {
            let size = min(max(fontSize * 1.2, 72), shorterCanvasEdge * 0.35)
            return CGSize(width: size, height: size)
        }

        let characterEstimate = CGFloat(max(textContent.text.count, 1))
        let width = min(max(characterEstimate * fontSize * 0.48 + 40, 160), canvasSize.width * 0.78)
        let height = min(max(fontSize + 28, 56), canvasSize.height * 0.32)
        return CGSize(width: width, height: height)
    }

    private func uniformScale(for transform: ClipTransform) -> CGFloat {
        let scale = (transform.scale.width + transform.scale.height) * 0.5
        guard scale.isFinite, scale > 0 else { return 1 }
        return scale
    }

    private func scaled(_ size: CGSize, by scale: CGFloat) -> CGSize {
        CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func labelPosition(for bounds: CGRect) -> CGPoint {
        CGPoint(x: bounds.midX, y: max(bounds.minY - 16, 16))
    }

    private func controlStackPosition(bounds: CGRect, viewSize: CGSize) -> CGPoint {
        let x = min(max(bounds.midX, 170), max(viewSize.width - 170, 170))
        let preferredY = bounds.maxY + 74
        let y = min(max(preferredY, 74), max(viewSize.height - 74, 74))
        return CGPoint(x: x, y: y)
    }

    private func isZeroPoint(_ point: CGPoint) -> Bool {
        abs(point.x) <= 1.0e-9 && abs(point.y) <= 1.0e-9
    }
}

private struct CanvasTransformHandle: View {
    enum HandleShape {
        case circle
        case square
    }

    var systemImage: String
    var shape: HandleShape

    var body: some View {
        ZStack {
            handleBackground

            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.82))
                .accessibilityHidden(true)
        }
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var handleBackground: some View {
        switch shape {
        case .circle:
            Circle()
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 2)
        case .square:
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 2)
        }
    }
}

private struct CanvasSnapGuide: Identifiable, Hashable {
    enum Kind: String {
        case verticalCenter
        case horizontalCenter
        case safeLeft
        case safeRight
        case safeTop
        case safeBottom
    }

    enum Orientation {
        case vertical
        case horizontal
    }

    var kind: Kind
    var position: CGFloat

    var id: String {
        "\(kind.rawValue)-\(Int(position.rounded()))"
    }

    var orientation: Orientation {
        switch kind {
        case .verticalCenter, .safeLeft, .safeRight:
            return .vertical
        case .horizontalCenter, .safeTop, .safeBottom:
            return .horizontal
        }
    }

    var accessibilityValue: String {
        switch kind {
        case .verticalCenter:
            return "Vertical center"
        case .horizontalCenter:
            return "Horizontal center"
        case .safeLeft:
            return "Safe area left"
        case .safeRight:
            return "Safe area right"
        case .safeTop:
            return "Safe area top"
        case .safeBottom:
            return "Safe area bottom"
        }
    }
}

private struct CanvasSnapResult {
    var position: CGPoint
    var guides: [CanvasSnapGuide]
}

private struct CanvasSnapGuidesView: View {
    var guides: [CanvasSnapGuide]
    var metrics: CanvasTransformMetrics

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(guides) { guide in
                CanvasSnapGuideLine(guide: guide, metrics: metrics)
            }
        }
        .frame(width: metrics.viewSize.width, height: metrics.viewSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
    }
}

private struct CanvasSnapGuideLine: View {
    var guide: CanvasSnapGuide
    var metrics: CanvasTransformMetrics

    var body: some View {
        guidePath
            .stroke(Color.cyan.opacity(0.96), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 4]))
            .shadow(color: Color.black.opacity(0.45), radius: 2, x: 0, y: 1)
            .frame(width: metrics.viewSize.width, height: metrics.viewSize.height)
            .accessibilityLabel("Snap guide")
            .accessibilityValue(guide.accessibilityValue)
            .accessibilityHint("Shows the active alignment snap target.")
    }

    private var guidePath: Path {
        Path { path in
            switch guide.orientation {
            case .vertical:
                let x = metrics.viewPoint(for: CGPoint(x: guide.position, y: 0)).x
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: metrics.viewSize.height))
            case .horizontal:
                let y = metrics.viewPoint(for: CGPoint(x: 0, y: guide.position)).y
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: metrics.viewSize.width, y: y))
            }
        }
    }
}

private struct CanvasTransformControlStack: View {
    var transform: ClipTransform
    var clipZIndex: Int?
    var onCenter: () -> Void
    var onNudgeLeft: () -> Void
    var onNudgeRight: () -> Void
    var onNudgeUp: () -> Void
    var onNudgeDown: () -> Void
    var onLayerBackward: () -> Void
    var onLayerForward: () -> Void
    var onLayerFront: () -> Void
    var onLayerBackmost: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            CanvasTransformHUD(transform: transform, clipZIndex: clipZIndex)

            CanvasNudgeControls(
                onCenter: onCenter,
                onNudgeLeft: onNudgeLeft,
                onNudgeRight: onNudgeRight,
                onNudgeUp: onNudgeUp,
                onNudgeDown: onNudgeDown
            )

            CanvasLayerControls(
                onLayerBackward: onLayerBackward,
                onLayerForward: onLayerForward,
                onLayerFront: onLayerFront,
                onLayerBackmost: onLayerBackmost
            )
        }
        .accessibilityElement(children: .contain)
    }
}

private struct CanvasGroupControlStack: View {
    var onCenter: () -> Void
    var onNudgeLeft: () -> Void
    var onNudgeRight: () -> Void
    var onNudgeUp: () -> Void
    var onNudgeDown: () -> Void
    var onAlign: (CanvasOverlayAlignment) -> Void

    var body: some View {
        VStack(spacing: 6) {
            CanvasGroupNudgeControls(
                onCenter: onCenter,
                onNudgeLeft: onNudgeLeft,
                onNudgeRight: onNudgeRight,
                onNudgeUp: onNudgeUp,
                onNudgeDown: onNudgeDown
            )

            CanvasMultiAlignControls(
                onCenter: onCenter,
                onAlign: onAlign
            )
        }
        .accessibilityElement(children: .contain)
    }
}

private struct CanvasGroupNudgeControls: View {
    var onCenter: () -> Void
    var onNudgeLeft: () -> Void
    var onNudgeRight: () -> Void
    var onNudgeUp: () -> Void
    var onNudgeDown: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            CanvasOverlayIconButton(
                systemImage: "scope",
                accessibilityLabel: "Center selected group",
                accessibilityHint: "Moves the selected text and sticker group to the canvas center.",
                action: onCenter
            )

            CanvasOverlayIconButton(
                systemImage: "arrow.left",
                accessibilityLabel: "Nudge selected group left",
                accessibilityHint: "Moves the selected text and sticker group left by eight canvas points.",
                action: onNudgeLeft
            )

            CanvasOverlayIconButton(
                systemImage: "arrow.up",
                accessibilityLabel: "Nudge selected group up",
                accessibilityHint: "Moves the selected text and sticker group up by eight canvas points.",
                action: onNudgeUp
            )

            CanvasOverlayIconButton(
                systemImage: "arrow.down",
                accessibilityLabel: "Nudge selected group down",
                accessibilityHint: "Moves the selected text and sticker group down by eight canvas points.",
                action: onNudgeDown
            )

            CanvasOverlayIconButton(
                systemImage: "arrow.right",
                accessibilityLabel: "Nudge selected group right",
                accessibilityHint: "Moves the selected text and sticker group right by eight canvas points.",
                action: onNudgeRight
            )
        }
        .padding(4)
        .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct CanvasMultiAlignControls: View {
    var onCenter: () -> Void
    var onAlign: (CanvasOverlayAlignment) -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                CanvasOverlayTextButton(
                    title: "Left",
                    accessibilityLabel: "Align Left",
                    accessibilityHint: "Aligns selected overlays to the left edge of the group.",
                    action: { onAlign(.leading) }
                )

                CanvasOverlayTextButton(
                    title: "Center",
                    accessibilityLabel: "Align Center",
                    accessibilityHint: "Aligns selected overlays to the horizontal center of the group.",
                    action: { onAlign(.centerX) }
                )

                CanvasOverlayTextButton(
                    title: "Right",
                    accessibilityLabel: "Align Right",
                    accessibilityHint: "Aligns selected overlays to the right edge of the group.",
                    action: { onAlign(.trailing) }
                )
            }

            HStack(spacing: 4) {
                CanvasOverlayTextButton(
                    title: "Top",
                    accessibilityLabel: "Align Top",
                    accessibilityHint: "Aligns selected overlays to the top edge of the group.",
                    action: { onAlign(.top) }
                )

                CanvasOverlayTextButton(
                    title: "Middle",
                    accessibilityLabel: "Align Middle",
                    accessibilityHint: "Aligns selected overlays to the vertical middle of the group.",
                    action: { onAlign(.centerY) }
                )

                CanvasOverlayTextButton(
                    title: "Bottom",
                    accessibilityLabel: "Align Bottom",
                    accessibilityHint: "Aligns selected overlays to the bottom edge of the group.",
                    action: { onAlign(.bottom) }
                )
            }

            CanvasOverlayTextButton(
                title: "Center Group",
                accessibilityLabel: "Center Group",
                accessibilityHint: "Moves the selected overlay group to the canvas center while preserving relative offsets.",
                width: 172,
                action: onCenter
            )
        }
        .padding(4)
        .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct CanvasNudgeControls: View {
    var onCenter: () -> Void
    var onNudgeLeft: () -> Void
    var onNudgeRight: () -> Void
    var onNudgeUp: () -> Void
    var onNudgeDown: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            CanvasOverlayIconButton(
                systemImage: "scope",
                accessibilityLabel: "Center selected overlay",
                accessibilityHint: "Moves the selected text or sticker to the canvas center.",
                action: onCenter
            )

            CanvasOverlayIconButton(
                systemImage: "arrow.left",
                accessibilityLabel: "Nudge selected overlay left",
                accessibilityHint: "Moves the selected text or sticker left by eight canvas points.",
                action: onNudgeLeft
            )

            CanvasOverlayIconButton(
                systemImage: "arrow.up",
                accessibilityLabel: "Nudge selected overlay up",
                accessibilityHint: "Moves the selected text or sticker up by eight canvas points.",
                action: onNudgeUp
            )

            CanvasOverlayIconButton(
                systemImage: "arrow.down",
                accessibilityLabel: "Nudge selected overlay down",
                accessibilityHint: "Moves the selected text or sticker down by eight canvas points.",
                action: onNudgeDown
            )

            CanvasOverlayIconButton(
                systemImage: "arrow.right",
                accessibilityLabel: "Nudge selected overlay right",
                accessibilityHint: "Moves the selected text or sticker right by eight canvas points.",
                action: onNudgeRight
            )
        }
        .padding(4)
        .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct CanvasLayerControls: View {
    var onLayerBackward: () -> Void
    var onLayerForward: () -> Void
    var onLayerFront: () -> Void
    var onLayerBackmost: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            CanvasOverlayTextButton(
                title: "Backmost",
                accessibilityLabel: "Send selected layer to back",
                accessibilityHint: "Moves the selected clip track behind the other tracks.",
                action: onLayerBackmost
            )

            CanvasOverlayTextButton(
                title: "Back",
                accessibilityLabel: "Move selected layer backward",
                accessibilityHint: "Lowers the selected clip track by one layer step.",
                action: onLayerBackward
            )

            CanvasOverlayTextButton(
                title: "Forward",
                accessibilityLabel: "Move selected layer forward",
                accessibilityHint: "Raises the selected clip track by one layer step.",
                action: onLayerForward
            )

            CanvasOverlayTextButton(
                title: "Front",
                accessibilityLabel: "Bring selected layer to front",
                accessibilityHint: "Moves the selected clip track in front of the other tracks.",
                action: onLayerFront
            )
        }
        .padding(4)
        .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct CanvasOverlayIconButton: View {
    var systemImage: String
    var accessibilityLabel: String
    var accessibilityHint: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .frame(width: 26, height: 24)
        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .help(accessibilityLabel)
    }
}

private struct CanvasOverlayTextButton: View {
    var title: String
    var accessibilityLabel: String
    var accessibilityHint: String
    var width: CGFloat = 56
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .buttonStyle(.plain)
        .frame(width: width, height: 24)
        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .help(accessibilityLabel)
    }
}

private struct CanvasTransformHUD: View {
    var transform: ClipTransform
    var clipZIndex: Int?

    var body: some View {
        Text(hudText)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .accessibilityLabel("Transform values")
            .accessibilityValue(hudText)
    }

    private var hudText: String {
        let transformText = String(
            format: "X %.0f  Y %.0f  S %.2f  R %.0f deg",
            transform.position.x,
            transform.position.y,
            (transform.scale.width + transform.scale.height) * 0.5,
            transform.rotation
        )
        if let clipZIndex {
            return "\(transformText)  Z \(clipZIndex)"
        }
        return transformText
    }
}

private struct CanvasTransformMetrics {
    var viewSize: CGSize
    var canvasSize: CGSize

    var isUsable: Bool {
        viewSize.width > 0 &&
            viewSize.height > 0 &&
            canvasSize.width > 0 &&
            canvasSize.height > 0
    }

    var scaleX: CGFloat {
        viewSize.width / max(canvasSize.width, 1)
    }

    var scaleY: CGFloat {
        viewSize.height / max(canvasSize.height, 1)
    }

    func viewPoint(for canvasPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: canvasPoint.x * scaleX,
            y: viewSize.height - canvasPoint.y * scaleY
        )
    }

    func viewSize(for canvasSize: CGSize) -> CGSize {
        CGSize(
            width: max(canvasSize.width * scaleX, 36),
            height: max(canvasSize.height * scaleY, 36)
        )
    }

    func canvasVector(for translation: CGSize) -> CGVector {
        CGVector(
            dx: translation.width / max(scaleX, .leastNonzeroMagnitude),
            dy: -translation.height / max(scaleY, .leastNonzeroMagnitude)
        )
    }

    func clampedCanvasPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), canvasSize.width),
            y: min(max(point.y, 0), canvasSize.height)
        )
    }
}

/// Draws the smoothed auto-reframe crop path over the preview (F-19): each
/// crop rect outline plus a polyline through the centers. Read-only overlay.
private struct ReframeCropPathOverlay: View {
    var frames: [CropFrame]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                // Crop rectangles (normalized 0...1 → view space).
                ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                    let rect = viewRect(frame.rect, in: size)
                    Rectangle()
                        .strokeBorder(Color.yellow.opacity(0.35), lineWidth: 1)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }

                // Center path.
                Path { path in
                    let points = frames.map { center(of: $0.rect, in: size) }
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(Color.yellow.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }

    private func viewRect(_ normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalized.minX * size.width,
            y: normalized.minY * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }

    private func center(of normalized: CGRect, in size: CGSize) -> CGPoint {
        CGPoint(x: normalized.midX * size.width, y: normalized.midY * size.height)
    }
}

/// Editable initial box and read-only tracked box overlay for motion tracking.
private struct MotionTrackingBoxOverlay: View {
    var rect: CGRect
    var isEditable: Bool
    var isTracking: Bool
    var onChange: (CGRect) -> Void

    @State private var gestureStartRect: CGRect?

    private enum ResizeHandle: CaseIterable, Identifiable {
        case topLeft
        case topRight
        case bottomRight
        case bottomLeft

        var id: Self { self }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let viewRect = Self.viewRect(rect, in: size)

            ZStack(alignment: .topLeading) {
                if isEditable {
                    box(viewRect)
                        .gesture(moveGesture(in: size))
                } else {
                    box(viewRect)
                }

                if isEditable {
                    ForEach(ResizeHandle.allCases) { handle in
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 1))
                            .position(handlePosition(handle, in: viewRect))
                            .gesture(resizeGesture(handle: handle, in: size))
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .accessibilityLabel(isEditable ? "Motion tracking selection box" : "Tracked motion box")
    }

    private func box(_ viewRect: CGRect) -> some View {
        Rectangle()
            .fill(Color.cyan.opacity(isEditable ? 0.08 : 0.02))
            .overlay(
                Rectangle()
                    .stroke(
                        Color.cyan.opacity(isTracking ? 0.95 : 0.78),
                        style: StrokeStyle(
                            lineWidth: isTracking ? 2 : 1.5,
                            dash: isEditable ? [6, 4] : []
                        )
                    )
            )
            .overlay(alignment: .center) {
                Circle()
                    .fill(Color.cyan.opacity(0.95))
                    .frame(width: 5, height: 5)
            }
            .frame(width: viewRect.width, height: viewRect.height)
            .position(x: viewRect.midX, y: viewRect.midY)
            .contentShape(Rectangle())
    }

    private func moveGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = startedGestureRect()
                let dx = value.translation.width / max(size.width, 1)
                let dy = value.translation.height / max(size.height, 1)
                onChange(Self.clampedMovingRect(
                    CGRect(x: start.minX + dx, y: start.minY + dy, width: start.width, height: start.height)
                ))
            }
            .onEnded { _ in
                gestureStartRect = nil
            }
    }

    private func resizeGesture(handle: ResizeHandle, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = startedGestureRect()
                let dx = value.translation.width / max(size.width, 1)
                let dy = value.translation.height / max(size.height, 1)
                onChange(Self.resizedRect(start, handle: handle, dx: dx, dy: dy))
            }
            .onEnded { _ in
                gestureStartRect = nil
            }
    }

    private func startedGestureRect() -> CGRect {
        if let gestureStartRect {
            return gestureStartRect
        }

        gestureStartRect = rect
        return rect
    }

    private func handlePosition(_ handle: ResizeHandle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft:
            return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:
            return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomRight:
            return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottomLeft:
            return CGPoint(x: rect.minX, y: rect.maxY)
        }
    }

    private static func viewRect(_ normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalized.minX * size.width,
            y: normalized.minY * size.height,
            width: max(normalized.width * size.width, 1),
            height: max(normalized.height * size.height, 1)
        )
    }

    private static func clampedMovingRect(_ rect: CGRect) -> CGRect {
        let width = min(max(rect.width, 0.04), 1)
        let height = min(max(rect.height, 0.04), 1)
        return CGRect(
            x: min(max(rect.minX, 0), 1 - width),
            y: min(max(rect.minY, 0), 1 - height),
            width: width,
            height: height
        )
    }

    private static func resizedRect(_ rect: CGRect, handle: ResizeHandle, dx: CGFloat, dy: CGFloat) -> CGRect {
        let minSize: CGFloat = 0.04
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY

        switch handle {
        case .topLeft:
            minX += dx
            minY += dy
        case .topRight:
            maxX += dx
            minY += dy
        case .bottomRight:
            maxX += dx
            maxY += dy
        case .bottomLeft:
            minX += dx
            maxY += dy
        }

        minX = min(max(minX, 0), 1)
        minY = min(max(minY, 0), 1)
        maxX = min(max(maxX, 0), 1)
        maxY = min(max(maxY, 0), 1)

        if maxX - minX < minSize {
            switch handle {
            case .topLeft, .bottomLeft:
                minX = max(0, maxX - minSize)
            case .topRight, .bottomRight:
                maxX = min(1, minX + minSize)
            }
        }
        if maxY - minY < minSize {
            switch handle {
            case .topLeft, .topRight:
                minY = max(0, maxY - minSize)
            case .bottomRight, .bottomLeft:
                maxY = min(1, minY + minSize)
            }
        }

        return CGRect(x: minX, y: minY, width: max(maxX - minX, minSize), height: max(maxY - minY, minSize))
    }
}

/// A transparent click-capture layer for the chroma-key eyedropper (F-10).
/// Reports the click position as a normalized (0...1, top-left origin) point.
private struct ChromaKeyEyedropperOverlay: View {
    var onPick: (CGPoint) -> Void

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let size = proxy.size
                    guard size.width > 0, size.height > 0 else { return }
                    let normalized = CGPoint(
                        x: min(max(location.x / size.width, 0), 1),
                        y: min(max(location.y / size.height, 0), 1)
                    )
                    onPick(normalized)
                }
                .overlay(alignment: .topLeading) {
                    Label("Eyedropper — click to pick key color", systemImage: "eyedropper")
                        .font(.caption2)
                        .padding(4)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)
                        .padding(6)
                }
        }
        .accessibilityLabel("Chroma key eyedropper. Click the preview to pick the key color.")
    }
}
