import AVFoundation
import Foundation
import MovieCutCore
import Observation

@MainActor
@Observable
final class PlaybackEngine {
    var player: AVPlayer
    var isPlaying: Bool
    var currentTime: TimeInterval
    var duration: TimeInterval
    var playerItem: AVPlayerItem?
    var playbackRate: Float

    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var playbackTimerTask: Task<Void, Never>?

    init() {
        self.player = AVPlayer()
        self.isPlaying = false
        self.currentTime = 0
        self.duration = 0
        self.playerItem = nil
        self.playbackRate = 1
    }

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
                item.videoComposition = videoComposition
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

    func clear() {
        pause()
        statusObservation?.invalidate()
        statusObservation = nil
        player.replaceCurrentItem(with: nil)
        playerItem = nil
        currentTime = 0
        duration = 0
        playbackRate = 1
    }

    func play() {
        guard playerItem != nil else { return }
        if duration > 0, currentTime >= duration {
            seek(to: 0)
        }
        player.rate = playbackRate
        isPlaying = true
        startPlaybackTimer()
    }

    func pause() {
        player.pause()
        isPlaying = false
        stopPlaybackTimer()
        updateCurrentTimeFromPlayer()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func setRate(_ rate: Float) {
        playbackRate = min(max(rate, 0.25), 4.0)
        if isPlaying {
            player.rate = playbackRate
        }
    }

    func seek(to time: TimeInterval) {
        let targetTime: TimeInterval
        if duration > 0 {
            targetTime = min(max(0, time), duration)
        } else {
            targetTime = max(0, time)
        }

        currentTime = targetTime
        let cmTime = CMTime(seconds: targetTime, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func startPlaybackTimer() {
        guard playbackTimerTask == nil else { return }

        playbackTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.updateCurrentTimeFromPlayer()
                try? await Task.sleep(nanoseconds: 33_333_333)
            }
        }
    }

    func stopPlaybackTimer() {
        playbackTimerTask?.cancel()
        playbackTimerTask = nil
    }

    private func observeStatus(for item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handlePlayerItemStatusChanged()
            }
        }
    }

    private func buildComposition(from project: Project) async throws -> (
        AVMutableComposition,
        AVMutableVideoComposition?,
        AVMutableAudioMix?
    ) {
        func cmTime(_ seconds: TimeInterval) -> CMTime {
            CMTime(seconds: seconds, preferredTimescale: 600)
        }

        func cmTimeRange(_ range: TimeRange) -> CMTimeRange {
            CMTimeRange(start: cmTime(range.start), duration: cmTime(range.duration))
        }

        func scaledDuration(for clip: Clip, insertedDuration: CMTime) -> CMTime {
            let playbackRate = min(max(clip.playbackRate, 0.25), 4.0)
            guard playbackRate != 1 else { return insertedDuration }

            return CMTime(seconds: insertedDuration.seconds / playbackRate, preferredTimescale: 600)
        }

        func affineTransform(
            for transform: ClipTransform,
            sourceSize: CGSize,
            preferredTransform: CGAffineTransform
        ) -> CGAffineTransform {
            let anchorPoint = CGPoint(
                x: sourceSize.width * transform.anchorPoint.x,
                y: sourceSize.height * transform.anchorPoint.y
            )
            let radians = CGFloat(transform.rotation * .pi / 180)

            var affineTransform = preferredTransform
            affineTransform = affineTransform.translatedBy(
                x: transform.position.x + transform.offset.x,
                y: transform.position.y + transform.offset.y
            )
            affineTransform = affineTransform.translatedBy(x: anchorPoint.x, y: anchorPoint.y)
            affineTransform = affineTransform.rotated(by: radians)
            affineTransform = affineTransform.scaledBy(
                x: transform.scale.width,
                y: transform.scale.height
            )
            affineTransform = affineTransform.translatedBy(x: -anchorPoint.x, y: -anchorPoint.y)
            return affineTransform
        }

        func makeCompositionTrack(
            in composition: AVMutableComposition,
            mediaType: AVMediaType
        ) throws -> AVMutableCompositionTrack {
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: mediaType,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw NSError(
                    domain: "MovieCutMac.PlaybackEngine",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Could not create a playback composition track."]
                )
            }

            return compositionTrack
        }

        let composition = AVMutableComposition()
        var videoCompositionTracks: [(track: AVMutableCompositionTrack, zIndex: Int)] = []
        var videoClipInstructions: [(
            trackID: CMPersistentTrackID,
            timeRange: CMTimeRange,
            transform: CGAffineTransform,
            opacity: Float
        )] = []
        var audioMixInputParameters: [AVAudioMixInputParameters] = []

        for track in project.timeline.tracks.sorted(by: { $0.zIndex < $1.zIndex }) {
            switch track.kind {
            case .video:
                let videoCompositionTrack = track.isHidden ? nil : try makeCompositionTrack(
                    in: composition,
                    mediaType: .video
                )
                let audioCompositionTrack = track.isMuted ? nil : try makeCompositionTrack(
                    in: composition,
                    mediaType: .audio
                )
                let audioParameters = AVMutableAudioMixInputParameters()

                if let videoCompositionTrack {
                    videoCompositionTracks.append((videoCompositionTrack, track.zIndex))
                }

                if let audioCompositionTrack {
                    audioParameters.trackID = audioCompositionTrack.trackID
                }

                for clip in track.clips.sorted(by: { $0.timelineRange.start < $1.timelineRange.start }) {
                    guard let assetId = clip.assetId,
                          let mediaAsset = project.mediaLibrary.assets[assetId] else {
                        continue
                    }

                    let sourceAsset = AVURLAsset(url: mediaAsset.originalURL)
                    let destinationTime = cmTime(clip.timelineRange.start)
                    let sourceTimeRange = cmTimeRange(clip.sourceRange)

                    if let videoCompositionTrack,
                       let sourceTrack = try await sourceAsset.loadTracks(withMediaType: .video).first {
                        if videoCompositionTrack.segments.isEmpty {
                            videoCompositionTrack.preferredTransform = try await sourceTrack.load(.preferredTransform)
                        }

                        try videoCompositionTrack.insertTimeRange(
                            sourceTimeRange,
                            of: sourceTrack,
                            at: destinationTime
                        )

                        let scaledDuration = scaledDuration(for: clip, insertedDuration: sourceTimeRange.duration)
                        if scaledDuration != sourceTimeRange.duration {
                            videoCompositionTrack.scaleTimeRange(
                                CMTimeRange(start: destinationTime, duration: sourceTimeRange.duration),
                                toDuration: scaledDuration
                            )
                        }

                        let preferredTransform = try await sourceTrack.load(.preferredTransform)
                        let sourceSize = try await sourceTrack.load(.naturalSize)
                        videoClipInstructions.append((
                            videoCompositionTrack.trackID,
                            CMTimeRange(start: destinationTime, duration: scaledDuration),
                            affineTransform(
                                for: clip.transform,
                                sourceSize: sourceSize,
                                preferredTransform: preferredTransform
                            ),
                            Float(min(max(clip.opacity, 0), 1))
                        ))
                    }

                    if let audioCompositionTrack,
                       let sourceTrack = try await sourceAsset.loadTracks(withMediaType: .audio).first {
                        try audioCompositionTrack.insertTimeRange(
                            sourceTimeRange,
                            of: sourceTrack,
                            at: destinationTime
                        )

                        let scaledDuration = scaledDuration(for: clip, insertedDuration: sourceTimeRange.duration)
                        if scaledDuration != sourceTimeRange.duration {
                            audioCompositionTrack.scaleTimeRange(
                                CMTimeRange(start: destinationTime, duration: sourceTimeRange.duration),
                                toDuration: scaledDuration
                            )
                        }

                        audioParameters.setVolume(Float(clip.volume), at: destinationTime)
                    }
                }

                if audioCompositionTrack != nil {
                    audioMixInputParameters.append(audioParameters)
                }
            case .audio:
                guard !track.isMuted else { continue }

                let audioCompositionTrack = try makeCompositionTrack(in: composition, mediaType: .audio)
                let audioParameters = AVMutableAudioMixInputParameters()
                audioParameters.trackID = audioCompositionTrack.trackID

                for clip in track.clips.sorted(by: { $0.timelineRange.start < $1.timelineRange.start }) {
                    guard let assetId = clip.assetId,
                          let mediaAsset = project.mediaLibrary.assets[assetId] else {
                        continue
                    }

                    let sourceAsset = AVURLAsset(url: mediaAsset.originalURL)
                    guard let sourceTrack = try await sourceAsset.loadTracks(withMediaType: .audio).first else {
                        continue
                    }

                    let destinationTime = cmTime(clip.timelineRange.start)
                    let sourceTimeRange = cmTimeRange(clip.sourceRange)
                    try audioCompositionTrack.insertTimeRange(
                        sourceTimeRange,
                        of: sourceTrack,
                        at: destinationTime
                    )

                    let scaledDuration = scaledDuration(for: clip, insertedDuration: sourceTimeRange.duration)
                    if scaledDuration != sourceTimeRange.duration {
                        audioCompositionTrack.scaleTimeRange(
                            CMTimeRange(start: destinationTime, duration: sourceTimeRange.duration),
                            toDuration: scaledDuration
                        )
                    }

                    audioParameters.setVolume(Float(clip.volume), at: destinationTime)
                }

                audioMixInputParameters.append(audioParameters)
            case .text:
                continue
            }
        }

        let sortedVideoCompositionTracks = videoCompositionTracks.sorted { $0.zIndex > $1.zIndex }
        let videoComposition: AVMutableVideoComposition?
        if sortedVideoCompositionTracks.isEmpty {
            videoComposition = nil
        } else {
            let mutableVideoComposition = AVMutableVideoComposition()
            mutableVideoComposition.renderSize = project.timeline.canvasSize
            mutableVideoComposition.frameDuration = CMTime(
                seconds: 1 / max(project.timeline.frameRate.doubleValue, 1),
                preferredTimescale: 600
            )

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)

            let layerInstructions = sortedVideoCompositionTracks.map {
                AVMutableVideoCompositionLayerInstruction(assetTrack: $0.track)
            }
            instruction.layerInstructions = layerInstructions

            let layerInstructionsByTrackID = Dictionary(
                uniqueKeysWithValues: zip(sortedVideoCompositionTracks.map { $0.track.trackID }, layerInstructions)
            )

            for clipInstruction in videoClipInstructions {
                guard let layerInstruction = layerInstructionsByTrackID[clipInstruction.trackID] else {
                    continue
                }

                layerInstruction.setTransform(clipInstruction.transform, at: clipInstruction.timeRange.start)
                layerInstruction.setTransform(
                    .identity,
                    at: CMTimeAdd(clipInstruction.timeRange.start, clipInstruction.timeRange.duration)
                )

                if clipInstruction.opacity < 1 {
                    layerInstruction.setOpacityRamp(
                        fromStartOpacity: clipInstruction.opacity,
                        toEndOpacity: clipInstruction.opacity,
                        timeRange: clipInstruction.timeRange
                    )
                    layerInstruction.setOpacity(
                        1,
                        at: CMTimeAdd(clipInstruction.timeRange.start, clipInstruction.timeRange.duration)
                    )
                }
            }

            mutableVideoComposition.instructions = [instruction]
            videoComposition = mutableVideoComposition
        }

        let audioMix: AVMutableAudioMix?
        if audioMixInputParameters.isEmpty {
            audioMix = nil
        } else {
            let mutableAudioMix = AVMutableAudioMix()
            mutableAudioMix.inputParameters = audioMixInputParameters
            audioMix = mutableAudioMix
        }

        return (composition, videoComposition, audioMix)
    }

    private func handlePlayerItemStatusChanged() {
        guard let playerItem else {
            duration = 0
            return
        }

        switch playerItem.status {
        case .readyToPlay:
            updateDuration(from: playerItem)
        case .failed, .unknown:
            break
        @unknown default:
            break
        }
    }

    private func updateDuration(from item: AVPlayerItem) {
        let seconds = item.duration.seconds
        if seconds.isFinite, seconds > 0 {
            duration = seconds
        }
    }

    private func updateCurrentTimeFromPlayer() {
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return }

        currentTime = seconds
        if isPlaying, duration > 0, seconds >= duration {
            pause()
        }
    }
}
