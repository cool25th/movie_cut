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
    @State private var ciContext = CIContext(options: RenderColorConfiguration.contextOptions)
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
            refreshCompositedFrame(at: viewModel.playheadTime, force: true)
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
            ciContext = CIContext(mtlDevice: device, options: RenderColorConfiguration.contextOptions)
        }
    }

    /// RENDER-01: the preview consumes the SAME render plan as the export
    /// (one composition for durations/speed/ramps/freeze/reverse, one
    /// videoComposition for per-clip effects through the custom compositor).
    /// The previous preview built its own simpler composition and post-
    /// filtered single-clip frames, so ramps, reverse, masks, blend modes,
    /// multi-track compositing, text, and stickers never matched the export.
    private func rebuildComposition() {
        removeTimeObserver()
        player.pause()
        imageGenerator?.cancelAllCGImageGeneration()
        clearCompositedFrame()

        Task { @MainActor in
            let project = viewModel.currentProject
            let plan = try? await renderPlanEngine.makeRenderPlan(for: project)

            guard let plan, !plan.composition.tracks.isEmpty else {
                hasPlayableMedia = false
                playerItem = nil
                imageGenerator = nil
                player.replaceCurrentItem(with: nil)
                viewModel.isPlaying = false
                return
            }

            hasPlayableMedia = true
            let item = AVPlayerItem(asset: plan.composition)
            item.videoComposition = plan.videoComposition
            // BUG-IOS-10: volume/fade ramps apply to preview playback too —
            // the same audioMix the export session consumes.
            item.audioMix = plan.audioMix

            let generator = AVAssetImageGenerator(asset: plan.composition)
            generator.videoComposition = plan.videoComposition
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
            generator.maximumSize = CGSize(width: 1280, height: 720)

            playerItem = item
            imageGenerator = generator
            player.replaceCurrentItem(with: item)
            seekPlayerIfNeeded(to: viewModel.playheadTime)
            refreshCompositedFrame(at: viewModel.playheadTime, force: true)
            addTimeObserver()
            syncPlayback(isPlaying: viewModel.isPlaying)
        }
    }

    /// Plan-builder only — the engine is never started (no export state).
    private let renderPlanEngine = IOSExportEngine()

    @discardableResult

    private func addTimeObserver() {
        let interval = CMTime(seconds: 1.0 / 15.0, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }

            viewModel.playheadTime = min(max(0, seconds), max(viewModel.currentProject.timeline.duration, 0))
            refreshCompositedFrame(at: seconds)

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
            refreshCompositedFrame(at: clampedTime)
            return
        }

        player.seek(to: cmTime(clampedTime), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            DispatchQueue.main.async {
                refreshCompositedFrame(at: clampedTime, force: true)
            }
        }
    }

    /// The generator carries the render plan's videoComposition, so its
    /// output is the FULLY composited frame (every clip, effect, transform,
    /// text, sticker) — identical to what the export encodes.
    private func refreshCompositedFrame(at time: TimeInterval, force: Bool = false) {
        guard let generator = imageGenerator else {
            clearCompositedFrame()
            return
        }

        if !force, let lastRenderedFrameTime, abs(lastRenderedFrameTime - time) < 1.0 / 15.0 {
            return
        }
        guard force || !isRenderingFilteredFrame else { return }

        frameRequestID += 1
        let requestID = frameRequestID
        let frameTime = cmTime(time)
        isRenderingFilteredFrame = true

        // AVAssetImageGenerator is not Sendable; wrap it so the concurrent
        // closure compiles under Swift 6. Each render task is serialised by
        // isRenderingFilteredFrame and requestID guarding.
        struct UncheckedSendable<T>: @unchecked Sendable { let value: T }
        let genBox = UncheckedSendable(value: generator)

        DispatchQueue.global(qos: .userInteractive).async {
            let uiImage: UIImage?
            if let cgImage = try? genBox.value.copyCGImage(at: frameTime, actualTime: nil) {
                uiImage = UIImage(cgImage: cgImage)
            } else {
                uiImage = nil
            }
            DispatchQueue.main.async {
                guard requestID == frameRequestID else { return }
                filteredFrame = uiImage
                lastRenderedFrameTime = time
                isRenderingFilteredFrame = false
            }
        }
    }

    private func clearCompositedFrame() {
        frameRequestID += 1
        filteredFrame = nil
        lastRenderedFrameTime = nil
        isRenderingFilteredFrame = false
    }

    private func cmTime(_ seconds: TimeInterval) -> CMTime {
        CMTime(seconds: max(0, seconds.isFinite ? seconds : 0), preferredTimescale: 600)
    }

    private func timeString(_ time: TimeInterval) -> String {
        let totalSeconds = Int(max(0, time.isFinite ? time : 0).rounded(.down))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}


private extension Clip {
    var requiresFilteredPreview: Bool {
        colorCorrection != nil || colorGrade != nil || !effects.isEmpty
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
        guard let playerLayer = layer as? AVPlayerLayer else {
            // layerClass is overridden to AVPlayerLayer above, so this is
            // unreachable by construction; the guard documents that contract
            // without a force cast.
            fatalError("PlayerLayerView.layerClass must be AVPlayerLayer")
        }
        return playerLayer
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
