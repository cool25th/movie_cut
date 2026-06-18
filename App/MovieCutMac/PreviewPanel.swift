import AppKit
import SwiftUI
import MovieCutCore
import UniformTypeIdentifiers

struct PreviewPanel: View {
    var viewModel: EditorViewModel
    @State private var playbackEngine: PlaybackEngine
    @State private var loadedAssetId: UUID?
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

                if let clip = viewModel.selectedClip {
                    previewCanvasWell {
                        previewSurface(for: clip)
                    }
                } else {
                    previewCanvasWell {
                        previewEmptyState
                    }
                }

                VStack {
                    previewTransportBar
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MovieCutTheme.previewWellBackground)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(NSLocalizedString("Preview", comment: ""))
            .accessibilityValue(previewAccessibilityValue)
            .task {
                loadSelectedClipAsset()
            }
            .onChange(of: viewModel.selectedClipId) { _, _ in
                loadSelectedClipAsset()
            }
            .onChange(of: viewModel.selectedClip?.playbackRate) { _, playbackRate in
                playbackEngine.setRate(Float(playbackRate ?? 1))
            }
            .onChange(of: playbackEngine.currentTime) { _, currentTime in
                syncTimelinePlayhead(to: currentTime)
            }

        }
    }

    private func previewCanvasWell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            content()
                .padding(MovieCutSpacing.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: MovieCutRadius.large, style: .continuous)
                .fill(MovieCutTheme.previewBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MovieCutRadius.large, style: .continuous)
                .stroke(MovieCutTheme.border.opacity(0.62), lineWidth: 0.5)
        )
        .padding(.horizontal, 24)
        .padding(.top, 58)
        .padding(.bottom, 22)
    }

    private var previewTransportBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
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

                previewCanvasResolutionBadge
                previewSafeZoneToggle
                previewZoomControls
                previewVolumeControl
            }

            VStack(spacing: 8) {
                HStack(spacing: 14) {
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

                HStack(spacing: 10) {
                    previewCanvasResolutionBadge
                    previewSafeZoneToggle

                    Spacer(minLength: 8)

                    previewZoomControls

                    Spacer(minLength: 8)

                    previewVolumeControl
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(MovieCutTheme.controlSurface.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: MovieCutRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MovieCutRadius.medium, style: .continuous)
                .stroke(MovieCutTheme.border.opacity(0.70), lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NSLocalizedString("Preview transport controls", comment: ""))
    }

    private var playbackTransportCapsule: some View {
        HStack(spacing: 8) {
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
                    .font(.title3.weight(.semibold))
                    .frame(width: 30, height: 30)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(MovieCutTheme.elevatedCardBackground)
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
            .frame(width: 84)
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
            .frame(width: 78)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(MovieCutTheme.elevatedCardBackground)
        )
        .overlay(
            Capsule()
                .stroke(MovieCutTheme.border.opacity(0.70), lineWidth: 0.5)
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
                .fill(showsSafeZoneGuides ? MovieCutTheme.accentCyan.opacity(0.16) : MovieCutTheme.elevatedCardBackground)
        )
        .overlay(
            Capsule()
                .stroke(
                    showsSafeZoneGuides ? MovieCutTheme.accentCyan.opacity(0.42) : MovieCutTheme.border.opacity(0.70),
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

    private func previewSurface(for clip: Clip) -> some View {
        VideoPreviewView(player: playbackEngine.player)
            .aspectRatio(canvasAspectRatio, contentMode: .fit)
            .overlay {
                previewOverlay(for: clip)
            }
            .scaleEffect(previewZoom)
            .accessibilityValue(previewZoomAccessibilityValue)
    }

    private var canvasAspectRatio: CGFloat {
        let size = viewModel.currentProject.canvas.size
        return size.width / max(size.height, 1)
    }

    private var hasImportedMedia: Bool {
        !viewModel.currentProject.mediaLibrary.assets.isEmpty
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
        VStack(spacing: MovieCutSpacing.small) {
            Image(systemName: hasImportedMedia ? "play.rectangle" : "plus.rectangle.on.rectangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.white.opacity(0.55))
                .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text(emptyStateTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                Text(emptyStateMessage)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }

            Button {
                openImportPanel()
            } label: {
                Label(NSLocalizedString("Import Media", comment: ""), systemImage: "square.and.arrow.down")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .accessibilityLabel(NSLocalizedString("Import media", comment: ""))
            .accessibilityHint(NSLocalizedString("Opens a file picker for video, audio, or image assets.", comment: ""))
        }
        .frame(maxWidth: 300)
        .movieCutCard(
            padding: 14,
            cornerRadius: MovieCutRadius.medium,
            background: MovieCutTheme.previewEmptyStateBackground,
            border: MovieCutTheme.border.opacity(0.55)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(emptyStateTitle)
        .accessibilityHint(emptyStateMessage)
    }

    private func previewTimeBadge(title: String, value: String, accessibilityLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(.primary)
        }
        .frame(width: 86, alignment: .leading)
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
                .fill(MovieCutTheme.elevatedCardBackground)
        )
        .overlay(
            Capsule()
                .stroke(MovieCutTheme.border.opacity(0.70), lineWidth: 0.5)
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

    private func loadSelectedClipAsset() {
        guard
            let clip = viewModel.selectedClip,
            let assetId = clip.assetId,
            let asset = viewModel.currentProject.mediaLibrary.assets[assetId]
        else {
            loadedAssetId = nil
            playbackEngine.clear()
            return
        }

        if loadedAssetId != asset.id {
            playbackEngine.load(asset: asset)
            loadedAssetId = asset.id
        }

        playbackEngine.setRate(Float(clip.playbackRate))
        playbackEngine.seek(to: clip.sourceRange.start)
        syncTimelinePlayhead(to: clip.sourceRange.start)
    }

    private func seekByFrames(_ frameCount: Int) {
        let frameDuration = 1.0 / 30.0
        let nextTime = playbackEngine.currentTime + (Double(frameCount) * frameDuration)
        playbackEngine.seek(to: nextTime)
        syncTimelinePlayhead(to: nextTime)
    }

    private func syncTimelinePlayhead(to playbackTime: TimeInterval) {
        guard let clip = viewModel.selectedClip else {
            viewModel.playheadTime = playbackTime
            return
        }

        let sourceOffset = max(0, playbackTime - clip.sourceRange.start)
        let timelineOffset = sourceOffset / max(clip.playbackRate, 0.25)
        let timelineTime = clip.timelineRange.start + timelineOffset
        viewModel.playheadTime = min(timelineTime, clip.timelineRange.end)
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
        let cleanHex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(cleanHex, radix: 16) ?? 0xFFFFFF
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
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
