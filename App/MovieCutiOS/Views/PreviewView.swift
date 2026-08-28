#if os(iOS)
import AVFoundation
import MovieCutCore
import SwiftUI

struct PreviewView: View {
    @Bindable var viewModel: IOSEditorViewModel
    @State private var player = AVPlayer()
    @State private var playerItem: AVPlayerItem?
    @State private var timeObserverToken: Any?
    @State private var hasPlayableMedia = false
    // RACE-01 (리뷰 2026-08-26): 재생성 경합 방지 — 빌드 Task를 추적·취소하고
    // 세대 토큰으로 stale 설치를 차단한다. 느린 이전 빌드(reverse·대형
    // asset 로딩)가 나중에 끝나 최신 AVPlayerItem을 덮어쓰던 결함(Mac
    // PlaybackEngine 164-168·216-236 패리티).
    @State private var compositionBuildTask: Task<Void, Never>?
    @State private var compositionGeneration = 0

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                PlayerLayerRepresentable(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // RACE-01: the up-to-15fps copyCGImage overlay is REMOVED —
                // the player already renders the plan's videoComposition
                // (every clip, effect, mask, transition, sticker) through the
                // custom compositor; the overlay duplicated that work on the
                // CPU and cost playback frame rate and power.

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
                // Phase-1 (review #3): frame stepping at the project rate.
                Button {
                    viewModel.stepFrame(forward: false)
                } label: {
                    Image(systemName: "backward.frame")
                        .font(.body)
                        .frame(width: 34, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(!hasPlayableMedia)
                .accessibilityLabel("Previous frame")

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

                Button {
                    viewModel.stepFrame(forward: true)
                } label: {
                    Image(systemName: "forward.frame")
                        .font(.body)
                        .frame(width: 34, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(!hasPlayableMedia)
                .accessibilityLabel("Next frame")

                // Phase-1 (review #3): loop playback toggle.
                Button {
                    viewModel.isLooping.toggle()
                } label: {
                    Image(systemName: viewModel.isLooping ? "repeat" : "repeat")
                        .font(.body)
                        .frame(width: 34, height: 36)
                        .foregroundStyle(viewModel.isLooping ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!hasPlayableMedia)
                .accessibilityLabel("Loop playback")
                .accessibilityValue(viewModel.isLooping ? "On" : "Off")

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
            rebuildComposition()
        }
        .onDisappear {
            removeTimeObserver()
            player.pause()
        }
        .onChange(of: viewModel.currentProject.timeline) { _, _ in
            rebuildComposition()
        }
        .onChange(of: viewModel.isPlaying) { _, isPlaying in
            syncPlayback(isPlaying: isPlaying)
        }
        .onChange(of: viewModel.playheadTime) { _, newTime in
            seekPlayerIfNeeded(to: newTime)
        }
    }

    /// RENDER-01: the preview consumes the SAME render plan as the export
    /// (one composition for durations/speed/ramps/freeze/reverse, one
    /// videoComposition for per-clip effects through the custom compositor,
    /// one audioMix for volume/fades). The previous preview built its own
    /// simpler composition and post-filtered single-clip frames, so ramps,
    /// reverse, masks, blend modes, multi-track compositing, text, and
    /// stickers never matched the export.
    private func rebuildComposition() {
        removeTimeObserver()
        player.pause()

        compositionBuildTask?.cancel()
        compositionGeneration &+= 1
        let requestedGeneration = compositionGeneration
        compositionBuildTask = Task { @MainActor in
            let project = viewModel.currentProject
            let plan = try? await renderPlanEngine.makeRenderPlan(for: project)

            // A newer rebuild superseded this one — never install stale
            // state, on EITHER the success or the empty-media path.
            guard !Task.isCancelled, requestedGeneration == compositionGeneration else {
                return
            }

            guard let plan, !plan.composition.tracks.isEmpty else {
                hasPlayableMedia = false
                playerItem = nil
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

            playerItem = item
            player.replaceCurrentItem(with: item)
            seekPlayerIfNeeded(to: viewModel.playheadTime)
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

            if viewModel.isPlaying,
               viewModel.currentProject.timeline.duration > 0,
               seconds >= viewModel.currentProject.timeline.duration {
                if viewModel.isLooping {
                    // Phase-1 (review #3): loop playback restarts at zero.
                    player.seek(to: .zero)
                    viewModel.playheadTime = 0
                    player.play()
                } else {
                    player.pause()
                    viewModel.isPlaying = false
                }
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
            return
        }

        // The player layer renders the composited frame at the seek target —
        // the scrub preview needs no separate frame copy (RACE-01 cleanup).
        player.seek(
            to: cmTime(clampedTime),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func cmTime(_ seconds: TimeInterval) -> CMTime {
        CMTime(seconds: max(0, seconds.isFinite ? seconds : 0), preferredTimescale: 600)
    }

    private func timeString(_ time: TimeInterval) -> String {
        let totalSeconds = Int(max(0, time.isFinite ? time : 0).rounded(.down))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
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
