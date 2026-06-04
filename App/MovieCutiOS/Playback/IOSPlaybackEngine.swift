#if os(iOS)
import AVFoundation
import MovieCutCore
import Observation
import SwiftUI

/// Audio processing options for the iOS playback engine.
struct IOSClipAudioProcessingOptions: Sendable {
    var eqPresets: [UUID: EqualizerPreset] = [:]
    var noiseReductionClipIds: Set<UUID> = []
    var duckLevel: Double = 0.0
    var voiceClipIds: Set<UUID> = []
}

@MainActor
@Observable
final class IOSPlaybackEngine {
    var player = AVPlayer()
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var playerItem: AVPlayerItem?
    var playbackRate: Float = 1.0

    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var playbackTimerTask: Task<Void, Never>?
    @ObservationIgnored private var timeObserverToken: Any?

    // MARK: - Load

    func load(asset: MediaAsset) {
        pause()
        statusObservation?.invalidate()
        statusObservation = nil

        let avAsset = AVURLAsset(url: asset.originalURL)
        let item = AVPlayerItem(asset: avAsset)

        playerItem = item
        currentTime = 0
        duration = asset.duration ?? 0
        player.replaceCurrentItem(with: item)
        observeStatus(for: item)
    }

    func loadProject(_ project: Project) {
        pause()
        statusObservation?.invalidate()
        statusObservation = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let (composition, videoComposition, audioMix) = try await buildComposition(from: project)
                let item = AVPlayerItem(asset: composition)
                if let videoComposition {
                    item.videoComposition = videoComposition
                }
                item.audioMix = audioMix

                playerItem = item
                currentTime = 0
                duration = composition.duration.seconds.isFinite ? composition.duration.seconds : 0
                player.replaceCurrentItem(with: item)
                observeStatus(for: item)
            } catch {
                clear()
            }
        }
    }

    // MARK: - Playback Controls

    func play() {
        player.play()
        player.rate = playbackRate
        isPlaying = true
        startPlaybackTimer()
    }

    func pause() {
        player.pause()
        isPlaying = false
        stopPlaybackTimer()
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: max(0, time), preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.currentTime = time
            }
        }
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player.rate = rate
        }
    }

    func clear() {
        pause()
        player.replaceCurrentItem(with: nil)
        playerItem = nil
        currentTime = 0
        duration = 0
    }

    // MARK: - Status Observation

    private func observeStatus(for item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            Task { @MainActor in
                guard let self else { return }
                if observedItem.status == .failed {
                    self.clear()
                }
            }
        }
        addPeriodicTimeObserver()
    }

    private func addPeriodicTimeObserver() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        let interval = CMTime(seconds: 0.033, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds
            }
        }
    }

    // MARK: - Playback Timer

    private func startPlaybackTimer() {
        stopPlaybackTimer()
        playbackTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self, self.isPlaying {
                self.currentTime = self.player.currentTime().seconds
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimerTask?.cancel()
        playbackTimerTask = nil
    }

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
    }

    // MARK: - Composition Building

    private func buildComposition(from project: Project) async throws -> (AVComposition, AVVideoComposition?, AVMutableAudioMix?) {
        let composition = AVMutableComposition()
        let videoComposition = AVMutableVideoComposition()

        var videoInstructions: [AVMutableVideoCompositionInstruction] = []
        var audioMixParameters: [AVMutableAudioMixInputParameters] = []

        let canvasSize = project.canvas.size

        videoComposition.frameDuration = CMTime(seconds: 1, preferredTimescale: 30)
        videoComposition.renderSize = CGSize(
            width: max(canvasSize.width, 1),
            height: max(canvasSize.height, 1)
        )

        var timelineTime = CMTime.zero

        for track in project.timeline.tracks {
            for clip in track.clips {
                let sourceURL = clip.sourceAsset?.originalURL
                guard let url = sourceURL else { continue }

                let asset = AVURLAsset(url: url)
                let duration = CMTime(seconds: clip.timelineRange.duration, preferredTimescale: 600)

                // Video track
                if clip.kind == .video || clip.kind == .image {
                    if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
                        let compositionTrack = composition.addMutableTrack(
                            withMediaType: .video,
                            preferredTrackID: kCMPersistentTrackID_Invalid
                        )
                        let sourceStart = CMTime(seconds: clip.sourceRange.start, preferredTimescale: 600)
                        try? compositionTrack?.insertTimeRange(
                            CMTimeRange(start: sourceStart, duration: duration),
                            of: videoTrack,
                            at: timelineTime
                        )

                        let instruction = AVMutableVideoCompositionInstruction()
                        instruction.timeRange = CMTimeRange(start: timelineTime, duration: duration)

                        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack!)
                        let transform = clip.transform
                        layerInstruction.setTransform(
                            CGAffineTransform(translationX: transform.position.x, y: transform.position.y)
                                .rotated(by: .init(transform.rotation))
                                .scaledBy(x: transform.scale.width, y: transform.scale.height),
                            at: timelineTime
                        )
                        layerInstruction.setOpacity(Float(clip.opacity), at: timelineTime)

                        instruction.layerInstructions = [layerInstruction]
                        videoInstructions.append(instruction)
                    }
                }

                // Audio track
                if clip.kind == .video || clip.kind == .audio {
                    if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
                        let compositionTrack = composition.addMutableTrack(
                            withMediaType: .audio,
                            preferredTrackID: kCMPersistentTrackID_Invalid
                        )
                        let sourceStart = CMTime(seconds: clip.sourceRange.start, preferredTimescale: 600)
                        try? compositionTrack?.insertTimeRange(
                            CMTimeRange(start: sourceStart, duration: duration),
                            of: audioTrack,
                            at: timelineTime
                        )

                        let params = AVMutableAudioMixInputParameters(track: compositionTrack)
                        params.setVolume(Float(clip.volume), at: timelineTime)
                        if clip.fadeInDuration > 0 {
                            params.setVolumeRamp(from: 0, to: Float(clip.volume), timeRange: CMTimeRange(
                                start: timelineTime,
                                duration: CMTime(seconds: clip.fadeInDuration, preferredTimescale: 600)
                            ))
                        }
                        audioMixParameters.append(params)
                    }
                }

                timelineTime = timelineTime + duration
            }
        }

        if !videoInstructions.isEmpty {
            videoComposition.instructions = videoInstructions
        }

        let audioMix = AVMutableAudioMix()
        if !audioMixParameters.isEmpty {
            audioMix.inputParameters = audioMixParameters
        }

        return (composition, videoInstructions.isEmpty ? nil : videoComposition, audioMixParameters.isEmpty ? nil : audioMix)
    }
}
#endif
