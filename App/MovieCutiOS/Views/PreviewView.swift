#if os(iOS)
import AVFoundation
import CoreImage
import Metal
import MovieCutCore
import SwiftUI

struct PreviewView: View {
    @Bindable var viewModel: IOSEditorViewModel
    @State private var player = AVPlayer()
    @State private var playerItem: AVPlayerItem?
    @State private var imageGenerator: AVAssetImageGenerator?
    @State private var timeObserverToken: Any?
    @State private var hasPlayableMedia = false
    @State private var ciContext = CIContext()
    @State private var filteredFrame: UIImage?
    @State private var lastRenderedFrameTime: TimeInterval?
    @State private var frameRequestID = 0
    @State private var isRenderingFilteredFrame = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                PlayerLayerRepresentable(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if let filteredFrame {
                    Image(uiImage: filteredFrame)
                        .resizable()
                        .scaledToFit()
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .allowsHitTesting(false)
                }

                if !hasPlayableMedia {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.black)

                    Text("No media loaded")
                        .font(.callout)
                        .foregroundStyle(.white.secondary)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)

            HStack(spacing: 16) {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 40, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(!hasPlayableMedia)
                .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")

                Text("\(timeString(viewModel.playheadTime)) / \(timeString(viewModel.currentProject.timeline.duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onAppear {
            configureCIContext()
            rebuildComposition()
        }
        .onDisappear {
            removeTimeObserver()
            player.pause()
            imageGenerator?.cancelAllCGImageGeneration()
        }
        .onChange(of: viewModel.currentProject.timeline) { _, _ in
            rebuildComposition()
        }
        .onChange(of: viewModel.selectedClipId) { _, _ in
            refreshFilteredFrame(at: viewModel.playheadTime, force: true)
        }
        .onChange(of: viewModel.isPlaying) { _, isPlaying in
            syncPlayback(isPlaying: isPlaying)
        }
        .onChange(of: viewModel.playheadTime) { _, newTime in
            seekPlayerIfNeeded(to: newTime)
        }
    }

    private func configureCIContext() {
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device)
        }
    }

    private func rebuildComposition() {
        removeTimeObserver()
        player.pause()
        imageGenerator?.cancelAllCGImageGeneration()
        clearFilteredFrame()

        let composition = AVMutableComposition()
        hasPlayableMedia = buildComposition(composition)

        guard hasPlayableMedia else {
            playerItem = nil
            imageGenerator = nil
            player.replaceCurrentItem(with: nil)
            viewModel.isPlaying = false
            return
        }

        let item = AVPlayerItem(asset: composition)
        let generator = AVAssetImageGenerator(asset: composition)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        generator.maximumSize = CGSize(width: 1280, height: 720)

        playerItem = item
        imageGenerator = generator
        player.replaceCurrentItem(with: item)
        seekPlayerIfNeeded(to: viewModel.playheadTime)
        refreshFilteredFrame(at: viewModel.playheadTime, force: true)
        addTimeObserver()
        syncPlayback(isPlaying: viewModel.isPlaying)
    }

    @discardableResult
    private func buildComposition(_ composition: AVMutableComposition) -> Bool {
        var insertedPlayableMedia = false
        let project = viewModel.currentProject

        for timelineTrack in project.timeline.tracks.sorted(by: { $0.zIndex < $1.zIndex }) {
            switch timelineTrack.kind {
            case .video:
                insertedPlayableMedia = insertVideoTrack(timelineTrack, from: project, into: composition) || insertedPlayableMedia
            case .audio:
                insertedPlayableMedia = insertAudioTrack(timelineTrack, from: project, into: composition) || insertedPlayableMedia
            case .text:
                continue
            }
        }

        return insertedPlayableMedia
    }

    private func insertVideoTrack(_ timelineTrack: Track, from project: Project, into composition: AVMutableComposition) -> Bool {
        let clips = timelineTrack.clips
            .filter { $0.kind == .video }
            .sorted { $0.timelineRange.start < $1.timelineRange.start }
        guard !clips.isEmpty else { return false }

        let videoTrack = timelineTrack.isHidden ? nil : composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let audioTrack = timelineTrack.isMuted ? nil : composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var videoCursor = CMTime.zero
        var audioCursor = CMTime.zero
        var inserted = false

        for clip in clips {
            guard let asset = asset(for: clip, in: project) else { continue }
            if let videoTrack {
                inserted = insertClip(clip, mediaType: .video, from: asset, into: videoTrack, cursor: &videoCursor) || inserted
            }
            if let audioTrack {
                _ = insertClip(clip, mediaType: .audio, from: asset, into: audioTrack, cursor: &audioCursor)
            }
        }

        return inserted
    }

    private func insertAudioTrack(_ timelineTrack: Track, from project: Project, into composition: AVMutableComposition) -> Bool {
        guard !timelineTrack.isMuted else { return false }
        let clips = timelineTrack.clips
            .filter { $0.kind == .audio || $0.kind == .video }
            .sorted { $0.timelineRange.start < $1.timelineRange.start }
        guard !clips.isEmpty, let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return false }

        var cursor = CMTime.zero
        var inserted = false
        for clip in clips {
            guard let asset = asset(for: clip, in: project) else { continue }
            inserted = insertClip(clip, mediaType: .audio, from: asset, into: audioTrack, cursor: &cursor) || inserted
        }
        return inserted
    }

    private func asset(for clip: Clip, in project: Project) -> AVURLAsset? {
        guard let assetId = clip.assetId, let mediaAsset = project.mediaLibrary.assets[assetId] else { return nil }
        return AVURLAsset(url: mediaAsset.originalURL)
    }

    @discardableResult
    private func insertClip(
        _ clip: Clip,
        mediaType: AVMediaType,
        from asset: AVURLAsset,
        into compositionTrack: AVMutableCompositionTrack,
        cursor: inout CMTime
    ) -> Bool {
        guard let sourceTrack = asset.tracks(withMediaType: mediaType).first,
              let sourceRange = sourceTimeRange(for: clip) else { return false }

        let timelineStart = cmTime(clip.timelineRange.start)
        guard CMTimeCompare(timelineStart, cursor) >= 0 else { return false }

        if CMTimeCompare(cursor, timelineStart) < 0 {
            let gap = CMTimeSubtract(timelineStart, cursor)
            compositionTrack.insertEmptyTimeRange(CMTimeRange(start: cursor, duration: gap))
            cursor = timelineStart
        }

        do {
            try compositionTrack.insertTimeRange(sourceRange, of: sourceTrack, at: cursor)
            cursor = CMTimeAdd(cursor, sourceRange.duration)
            return true
        } catch {
            return false
        }
    }

    private func sourceTimeRange(for clip: Clip) -> CMTimeRange? {
        let duration = min(max(clip.sourceRange.duration, 0), max(clip.timelineRange.duration, 0))
        guard duration > 0 else { return nil }
        return CMTimeRange(start: cmTime(clip.sourceRange.start), duration: cmTime(duration))
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 1.0 / 15.0, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }

            viewModel.playheadTime = min(max(0, seconds), max(viewModel.currentProject.timeline.duration, 0))
            refreshFilteredFrame(at: seconds)

            if viewModel.isPlaying,
               viewModel.currentProject.timeline.duration > 0,
               seconds >= viewModel.currentProject.timeline.duration {
                player.pause()
                viewModel.isPlaying = false
            }
        }
    }

    private func removeTimeObserver() {
        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
    }

    private func togglePlayback() {
        if viewModel.isPlaying {
            player.pause()
        } else if hasPlayableMedia {
            if viewModel.currentProject.timeline.duration > 0,
               viewModel.playheadTime >= viewModel.currentProject.timeline.duration {
                viewModel.playheadTime = 0
                seekPlayerIfNeeded(to: 0)
            }
            player.play()
        }
        viewModel.togglePlayPause()
    }

    private func syncPlayback(isPlaying: Bool) {
        guard hasPlayableMedia else {
            player.pause()
            return
        }
        isPlaying ? player.play() : player.pause()
    }

    private func seekPlayerIfNeeded(to time: TimeInterval) {
        guard hasPlayableMedia else { return }
        let clampedTime = min(max(0, time), max(viewModel.currentProject.timeline.duration, 0))
        let currentSeconds = player.currentTime().seconds

        if currentSeconds.isFinite, abs(currentSeconds - clampedTime) < 0.25 {
            refreshFilteredFrame(at: clampedTime)
            return
        }

        player.seek(to: cmTime(clampedTime), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            DispatchQueue.main.async {
                refreshFilteredFrame(at: clampedTime, force: true)
            }
        }
    }

    private func refreshFilteredFrame(at time: TimeInterval, force: Bool = false) {
        guard let generator = imageGenerator,
              let clip = filteredClip(at: time) else {
            clearFilteredFrame()
            return
        }

        if !force, let lastRenderedFrameTime, abs(lastRenderedFrameTime - time) < 1.0 / 15.0 {
            return
        }
        guard force || !isRenderingFilteredFrame else { return }

        frameRequestID += 1
        let requestID = frameRequestID
        let context = ciContext
        let frameTime = cmTime(time)
        isRenderingFilteredFrame = true

        DispatchQueue.global(qos: .userInteractive).async {
            let uiImage = Self.makeFilteredFrame(generator: generator, time: frameTime, clip: clip, context: context)
            DispatchQueue.main.async {
                guard requestID == frameRequestID else { return }
                filteredFrame = uiImage
                lastRenderedFrameTime = time
                isRenderingFilteredFrame = false
            }
        }
    }

    private func clearFilteredFrame() {
        frameRequestID += 1
        filteredFrame = nil
        lastRenderedFrameTime = nil
        isRenderingFilteredFrame = false
    }

    private func filteredClip(at time: TimeInterval) -> Clip? {
        if let selected = viewModel.selectedClip,
           selected.kind == .video,
           selected.timelineRange.contains(time),
           selected.requiresFilteredPreview {
            return selected
        }

        return viewModel.currentProject.timeline.tracks
            .filter { $0.kind == .video && !$0.isHidden }
            .sorted { $0.zIndex > $1.zIndex }
            .flatMap(\.clips)
            .first { $0.kind == .video && $0.timelineRange.contains(time) && $0.requiresFilteredPreview }
    }

    private func cmTime(_ seconds: TimeInterval) -> CMTime {
        CMTime(seconds: max(0, seconds.isFinite ? seconds : 0), preferredTimescale: 600)
    }

    private func timeString(_ time: TimeInterval) -> String {
        let totalSeconds = Int(max(0, time.isFinite ? time : 0).rounded(.down))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private extension PreviewView {
    static func makeFilteredFrame(
        generator: AVAssetImageGenerator,
        time: CMTime,
        clip: Clip,
        context: CIContext
    ) -> UIImage? {
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        let input = CIImage(cgImage: cgImage)
        let output = applyFilterPipeline(to: input, clip: clip).cropped(to: input.extent)
        guard let rendered = context.createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: rendered)
    }

    static func applyFilterPipeline(to image: CIImage, clip: Clip) -> CIImage {
        var result = image
        if let correction = clip.colorCorrection {
            result = apply(colorCorrection: correction, to: result)
        }
        for effect in clip.effects {
            result = apply(effect: effect, to: result)
        }
        return result
    }

    static func apply(colorCorrection: ColorCorrection, to image: CIImage) -> CIImage {
        // Delegate to the shared Core processor so the preview matches export and
        // Mac. The previous inline warmth used the opposite sign (6500 + warmth)
        // from the Core processor (6500 - warmth), so the slider ran backwards.
        ColorCorrectionPixelProcessor.apply(colorCorrection, to: image)
    }

    static func apply(effect: Effect, to image: CIImage) -> CIImage {
        switch effect.type {
        case .brightness:
            return colorControls(image, brightness: effect.parameters["amount"] ?? 0.1, contrast: 1, saturation: 1)
        case .contrast:
            return colorControls(image, brightness: 0, contrast: effect.parameters["amount"] ?? 1.1, saturation: 1)
        case .saturation:
            return colorControls(image, brightness: 0, contrast: 1, saturation: effect.parameters["amount"] ?? 1.2)
        case .temperature:
            let neutral = CIVector(x: effect.parameters["neutralX"] ?? 6500, y: effect.parameters["neutralY"] ?? 0)
            let target = CIVector(x: effect.parameters["targetX"] ?? 7000, y: effect.parameters["targetY"] ?? 0)
            return applyFilter("CITemperatureAndTint", to: image, parameters: ["inputNeutral": neutral, "inputTargetNeutral": target])
        case .exposure:
            return applyFilter("CIExposureAdjust", to: image, parameters: [kCIInputEVKey: effect.parameters["ev"] ?? 0.5])
        case .grayscale:
            return applyFilter("CIPhotoEffectMono", to: image)
        case .sepia:
            return applyFilter("CISepiaTone", to: image, parameters: [kCIInputIntensityKey: effect.parameters["intensity"] ?? 0.9])
        case .blur:
            return applyFilter("CIGaussianBlur", to: image, parameters: [kCIInputRadiusKey: effect.parameters["radius"] ?? 5])
                .cropped(to: image.extent)
        case .styleTransfer:
            return applyFilter("CIPhotoEffectTransfer", to: image)
        case .cinematicLUT, .vintageLUT, .noirLUT, .vividLUT, .coolLUT:
            return VisualEffectPixelProcessor.apply([effect], to: image)
        case .fadeIn, .fadeOut, .crossDissolve:
            return image
        }
    }

    static func colorControls(_ image: CIImage, brightness: Double, contrast: Double, saturation: Double) -> CIImage {
        applyFilter(
            "CIColorControls",
            to: image,
            parameters: [
                kCIInputBrightnessKey: brightness,
                kCIInputContrastKey: contrast,
                kCIInputSaturationKey: saturation
            ]
        )
    }

    static func applyFilter(_ name: String, to image: CIImage, parameters: [String: Any] = [:]) -> CIImage {
        guard let filter = CIFilter(name: name) else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        parameters.forEach { filter.setValue($0.value, forKey: $0.key) }
        return filter.outputImage ?? image
    }
}

private extension Clip {
    var requiresFilteredPreview: Bool {
        colorCorrection != nil || !effects.isEmpty
    }
}

struct PlayerLayerRepresentable: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        view.playerLayer.player = player
    }
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = UIColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif
