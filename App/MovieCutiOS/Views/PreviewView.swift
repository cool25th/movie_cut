#if os(iOS)
import AVFoundation
import MovieCutCore
import SwiftUI

struct PreviewView: View {
    @Bindable var viewModel: IOSEditorViewModel
    @State private var player = AVPlayer()
    @State private var playerItem: AVPlayerItem?
    @State private var timeObserverToken: Any?
    // STAB-03②: end-of-playback comes from the deterministic
    // AVPlayerItemDidPlayToEndTime notification, not the periodic observer.
    @State private var endTimeObserver: NSObjectProtocol?
    @State private var hasPlayableMedia = false
    // RACE-01 (리뷰 2026-08-26): 재생성 경합 방지 — 빌드 Task를 추적·취소하고
    // 세대 토큰으로 stale 설치를 차단한다. 느린 이전 빌드(reverse·대형
    // asset 로딩)가 나중에 끝나 최신 AVPlayerItem을 덮어쓰던 결함(Mac
    // PlaybackEngine 164-168·216-236 패리티).
    @State private var compositionBuildTask: Task<Void, Never>?
    @State private var compositionGeneration = 0
    /// Stage-4: the proxy policy the CURRENT installed plan was built with.
    /// Thermal notifications only matter when they flip this value (Mac's
    /// ThermalStateObserver skips redundant rebuilds the same way) — a
    /// nominal↔fair transition that keeps the policy unchanged must not pay
    /// for a full plan rebuild (EQ'd clips derive media per build).
    @State private var lastResolvedProxyPolicy: Bool?

    /// The preview's source policy for the current project + thermal state
    /// (the caller-resolved half of the stage-4 policy; the engine applies
    /// it per asset).
    private func resolvedUseProxyPlayback(_ project: Project) -> Bool {
        project.playbackSettings.useProxyPlayback
            || ProxyDowngradePolicy.shouldAutoDowngrade(
                thermalState: ThermalState.current,
                autoProxyOnThermalPressure: project.playbackSettings.autoProxyOnThermalPressure
            )
    }

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
        // CODEX-07: relink swaps the asset backing existing clips without
        // touching the timeline — the plan built while the asset was
        // missing kept empty/partial tracks until an unrelated timeline
        // edit (or view recreation) rebuilt it. Any mediaLibrary change
        // now rebuilds too; the generation guard inside
        // rebuildComposition makes the double fire on import+timeline
        // changes harmless.
        .onChange(of: viewModel.currentProject.mediaLibrary) { _, _ in
            rebuildComposition()
        }
        // capcut-surpass stage-4: thermal transitions re-resolve the preview
        // source policy — serious/critical pressure drops to proxy playback
        // (when the user allows the safety net), cooling restores the
        // original. Same S7 ladder Mac's ThermalStateObserver drives; the
        // decision itself lives in the shared Core ProxyDowngradePolicy, so
        // this only needs to trigger a rebuild.
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            // Skip when the transition didn't change the resolved policy —
            // a full rebuild (incl. EQ media derivation) buys nothing.
            guard resolvedUseProxyPlayback(viewModel.currentProject) != lastResolvedProxyPolicy else { return }
            rebuildComposition()
        }
        .onChange(of: viewModel.isPlaying) { _, isPlaying in
            syncPlayback(isPlaying: isPlaying)
        }
        .onChange(of: viewModel.playheadTime) { _, newTime in
            seekPlayerIfNeeded(to: newTime)
        }
        // STAB-03①: an explicit frame step (~1/fps ≈ 0.033 s) is smaller
        // than the observer-coalescing threshold below — observe the step
        // tick and force a zero-tolerance seek so the rendered frame always
        // follows the playhead number.
        .onChange(of: viewModel.frameStepTick) { _, _ in
            seekPlayer(to: viewModel.playheadTime, coalescingSmallMoves: false)
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
            // Stage-4 preview-only source policy: proxy playback under the
            // user's explicit preference OR the thermal safety net (S7,
            // ProxyDowngradePolicy parity with Mac). The export always reads
            // originals — the plan-level policy is resolved HERE, never from
            // settings inside the engine.
            let useProxyPlayback = resolvedUseProxyPlayback(project)
            lastResolvedProxyPolicy = useProxyPlayback
            let plan = try? await renderPlanEngine.makeRenderPlan(
                for: project,
                sourcePolicy: useProxyPlayback ? .proxyWhenAvailable : .originalOnly
            )

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

            // STAB-03②: this observer only syncs the playhead number —
            // loop/stop at the end is handled by the end notification, which
            // is guaranteed to fire (a periodic observer can miss the exact
            // end instant).
            MainActor.assumeIsolated {
                viewModel.playheadTime = min(max(0, seconds), max(viewModel.currentProject.timeline.duration, 0))
            }
        }
        endTimeObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [viewModel] _ in
            Task { @MainActor in
                let wasLooping = viewModel.isLooping
                viewModel.handlePlaybackReachedEnd()
                if wasLooping {
                    player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                    player.play()
                }
            }
        }
    }

    private func removeTimeObserver() {
        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
        if let endTimeObserver {
            NotificationCenter.default.removeObserver(endTimeObserver)
            self.endTimeObserver = nil
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

    /// Observer-driven sync skips sub-threshold moves (the periodic
    /// playhead callback fires ~15×/s during playback — re-seeking each
    /// tick would stutter). STAB-03①: explicit frame steps bypass the
    /// threshold via `coalescingSmallMoves: false`.
    private func seekPlayerIfNeeded(to time: TimeInterval) {
        seekPlayer(to: time, coalescingSmallMoves: true)
    }

    private func seekPlayer(to time: TimeInterval, coalescingSmallMoves: Bool) {
        guard hasPlayableMedia else { return }
        let clampedTime = min(max(0, time), max(viewModel.currentProject.timeline.duration, 0))
        let currentSeconds = player.currentTime().seconds

        if coalescingSmallMoves, currentSeconds.isFinite, abs(currentSeconds - clampedTime) < 0.25 {
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
