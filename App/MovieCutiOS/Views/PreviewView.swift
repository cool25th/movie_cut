import SwiftUI
import AVFoundation
import AVKit
import MovieCutCore

struct PreviewView: View {
    @Bindable var viewModel: IOSEditorViewModel
    @State private var player = AVPlayer()
    @State private var playerItem: AVPlayerItem?
    @State private var timeObserverToken: Any?
    @State private var hasPlayableMedia = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                AVPlayerViewControllerRepresentable(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

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

    private func rebuildComposition() {
        removeTimeObserver()
        player.pause()

        let composition = AVMutableComposition()
        hasPlayableMedia = buildComposition(composition)

        guard hasPlayableMedia else {
            playerItem = nil
            player.replaceCurrentItem(with: nil)
            viewModel.isPlaying = false
            return
        }

        let item = AVPlayerItem(asset: composition)
        playerItem = item
        player.replaceCurrentItem(with: item)
        seekPlayerIfNeeded(to: viewModel.playheadTime)
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
                insertedPlayableMedia = insertVideoTrack(
                    timelineTrack,
                    from: project,
                    into: composition
                ) || insertedPlayableMedia
            case .audio:
                insertedPlayableMedia = insertAudioTrack(
                    timelineTrack,
                    from: project,
                    into: composition
                ) || insertedPlayableMedia
            case .text:
                continue
            }
        }

        return insertedPlayableMedia
    }

    private func insertVideoTrack(
        _ timelineTrack: Track,
        from project: Project,
        into composition: AVMutableComposition
    ) -> Bool {
        let playableClips = timelineTrack.clips
            .filter { $0.kind == .video }
            .sorted { $0.timelineRange.start < $1.timelineRange.start }

        guard !playableClips.isEmpty else { return false }

        let compositionVideoTrack = timelineTrack.isHidden ? nil : composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let compositionAudioTrack = timelineTrack.isMuted ? nil : composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var videoCursor = CMTime.zero
        var audioCursor = CMTime.zero
        var insertedPlayableMedia = false

        for clip in playableClips {
            guard
                let assetId = clip.assetId,
                let mediaAsset = project.mediaLibrary.assets[assetId]
            else { continue }

            let asset = AVURLAsset(url: mediaAsset.originalURL)

            if let compositionVideoTrack, !timelineTrack.isHidden {
                insertedPlayableMedia = insertClip(
                    clip,
                    mediaType: .video,
                    from: asset,
                    into: compositionVideoTrack,
                    cursor: &videoCursor
                ) || insertedPlayableMedia
            }

            if let compositionAudioTrack, !timelineTrack.isMuted {
                _ = insertClip(
                    clip,
                    mediaType: .audio,
                    from: asset,
                    into: compositionAudioTrack,
                    cursor: &audioCursor
                )
            }
        }

        return insertedPlayableMedia
    }

    private func insertAudioTrack(
        _ timelineTrack: Track,
        from project: Project,
        into composition: AVMutableComposition
    ) -> Bool {
        guard !timelineTrack.isMuted else { return false }

        let playableClips = timelineTrack.clips
            .filter { $0.kind == .audio || $0.kind == .video }
            .sorted { $0.timelineRange.start < $1.timelineRange.start }

        guard
            !playableClips.isEmpty,
            let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else { return false }

        var audioCursor = CMTime.zero
        var insertedPlayableMedia = false

        for clip in playableClips {
            guard
                let assetId = clip.assetId,
                let mediaAsset = project.mediaLibrary.assets[assetId]
            else { continue }

            let asset = AVURLAsset(url: mediaAsset.originalURL)
            insertedPlayableMedia = insertClip(
                clip,
                mediaType: .audio,
                from: asset,
                into: compositionAudioTrack,
                cursor: &audioCursor
            ) || insertedPlayableMedia
        }

        return insertedPlayableMedia
    }

    @discardableResult
    private func insertClip(
        _ clip: Clip,
        mediaType: AVMediaType,
        from asset: AVURLAsset,
        into compositionTrack: AVMutableCompositionTrack,
        cursor: inout CMTime
    ) -> Bool {
        guard
            let sourceTrack = asset.tracks(withMediaType: mediaType).first,
            let sourceTimeRange = sourceTimeRange(for: clip)
        else { return false }

        let timelineStart = cmTime(clip.timelineRange.start)
        guard CMTimeCompare(timelineStart, cursor) >= 0 else { return false }

        if CMTimeCompare(cursor, timelineStart) < 0 {
            let gap = CMTimeSubtract(timelineStart, cursor)
            compositionTrack.insertEmptyTimeRange(CMTimeRange(start: cursor, duration: gap))
            cursor = timelineStart
        }

        do {
            try compositionTrack.insertTimeRange(sourceTimeRange, of: sourceTrack, at: cursor)
            cursor = CMTimeAdd(cursor, sourceTimeRange.duration)
            return true
        } catch {
            return false
        }
    }

    private func sourceTimeRange(for clip: Clip) -> CMTimeRange? {
        let sourceDuration = min(
            max(clip.sourceRange.duration, 0),
            max(clip.timelineRange.duration, 0)
        )

        guard sourceDuration > 0 else { return nil }

        return CMTimeRange(
            start: cmTime(clip.sourceRange.start),
            duration: cmTime(sourceDuration)
        )
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }

            viewModel.playheadTime = min(
                max(0, seconds),
                max(viewModel.currentProject.timeline.duration, 0)
            )

            if
                viewModel.isPlaying,
                viewModel.currentProject.timeline.duration > 0,
                seconds >= viewModel.currentProject.timeline.duration
            {
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

        if isPlaying {
            player.play()
        } else {
            player.pause()
        }
    }

    private func seekPlayerIfNeeded(to time: TimeInterval) {
        guard hasPlayableMedia else { return }

        let clampedTime = min(max(0, time), max(viewModel.currentProject.timeline.duration, 0))
        let currentSeconds = player.currentTime().seconds

        if currentSeconds.isFinite, abs(currentSeconds - clampedTime) < 0.25 {
            return
        }

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
        let clampedTime = max(0, time.isFinite ? time : 0)
        let totalSeconds = Int(clampedTime.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct AVPlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }
}
