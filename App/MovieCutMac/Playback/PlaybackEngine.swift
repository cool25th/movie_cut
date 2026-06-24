import AVFoundation
import AppKit
import Foundation
import MovieCutCore
import Observation
import QuartzCore

/// Audio processing options passed from EditorViewModel to the engine.
struct ClipAudioProcessingOptions: Sendable {
    var eqPresets: [UUID: EqualizerPreset] = [:]
    var noiseReductionClipIds: Set<UUID> = []
    var duckLevel: Double = 0.0
    var voiceClipIds: Set<UUID> = []
}

@MainActor
@Observable
final class PlaybackEngine {
    var player: AVPlayer
    var isPlaying: Bool
    var currentTime: TimeInterval
    var duration: TimeInterval
    var playerItem: AVPlayerItem?
    var playbackRate: Float

    @ObservationIgnored private var textLayers: [CALayer] = []
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var playbackTimerTask: Task<Void, Never>?
    @ObservationIgnored private var temporaryReverseRenderURLs: [URL] = []

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
        cleanupTemporaryReverseRenderURLs()
        observeStatus(for: item)
    }

    func loadProject(_ project: Project, audioProcessing: ClipAudioProcessingOptions = ClipAudioProcessingOptions()) {
        pause()
        statusObservation?.invalidate()
        statusObservation = nil

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let (composition, videoComposition, audioMix, temporaryReverseRenderURLs) = try await buildComposition(from: project, audioProcessing: audioProcessing)
                let item = AVPlayerItem(asset: composition)
                item.videoComposition = videoComposition
                item.audioMix = audioMix

                playerItem = item
                currentTime = 0
                duration = composition.duration.seconds.isFinite ? composition.duration.seconds : 0
                player.replaceCurrentItem(with: item)
                cleanupTemporaryReverseRenderURLs()
                self.temporaryReverseRenderURLs = temporaryReverseRenderURLs
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
        cleanupTemporaryReverseRenderURLs()
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

    private func buildComposition(from project: Project, audioProcessing: ClipAudioProcessingOptions = ClipAudioProcessingOptions()) async throws -> (
        AVMutableComposition,
        AVMutableVideoComposition?,
        AVMutableAudioMix?,
        [URL]
    ) {
        textLayers = []
        var temporaryReverseRenderURLs: [URL] = []
        var shouldKeepTemporaryReverseRenderURLs = false
        defer {
            if !shouldKeepTemporaryReverseRenderURLs {
                removeTemporaryReverseRenderURLs(temporaryReverseRenderURLs)
            }
        }

        func cmTime(_ seconds: TimeInterval) -> CMTime {
            CMTime(seconds: seconds, preferredTimescale: 600)
        }

        func cmTimeRange(_ range: TimeRange) -> CMTimeRange {
            CMTimeRange(start: cmTime(range.start), duration: cmTime(range.duration))
        }

        func isFreezeFrameClip(_ clip: Clip) -> Bool {
            clip.sourceRange.duration < 0.1 && clip.timelineRange.duration > 0.5
        }

        func freezeFrameSourceTimeRange(for clip: Clip) -> CMTimeRange {
            let sourceTime = CMTime(seconds: clip.sourceRange.start, preferredTimescale: 600)
            let sourceDuration = CMTime(seconds: 0.04, preferredTimescale: 600)
            return CMTimeRange(start: sourceTime, duration: sourceDuration)
        }

        func scaledDuration(for clip: Clip, insertedDuration: CMTime) -> CMTime {
            let playbackRate = min(max(clip.playbackRate, 0.25), 4.0)
            guard playbackRate != 1 else { return insertedDuration }

            return CMTime(seconds: insertedDuration.seconds / playbackRate, preferredTimescale: 600)
        }

        func insertSpeedRampSegments(
            _ curve: SpeedRampCurve,
            sourceTrack: AVAssetTrack,
            sourceTimeRange: CMTimeRange,
            destinationTime: CMTime,
            compositionTrack: AVMutableCompositionTrack
        ) throws -> CMTime {
            let sourceDuration = sourceTimeRange.duration.seconds
            guard sourceDuration.isFinite, sourceDuration > 0 else {
                return sourceTimeRange.duration
            }

            let boundaries = ([0.0, 1.0] + curve.points.map { min(max($0.time, 0), 1) })
                .sorted()
                .reduce(into: [Double]()) { result, value in
                    if result.last.map({ abs($0 - value) > 1.0e-9 }) ?? true {
                        result.append(value)
                    }
                }

            guard boundaries.count > 1 else {
                try compositionTrack.insertTimeRange(sourceTimeRange, of: sourceTrack, at: destinationTime)
                return sourceTimeRange.duration
            }

            var accumulatedOutputDuration = CMTime.zero
            for index in 0..<(boundaries.count - 1) {
                let sourceStart = boundaries[index]
                let sourceEnd = boundaries[index + 1]
                let sourceSegmentDuration = (sourceEnd - sourceStart) * sourceDuration
                guard sourceSegmentDuration > 0 else { continue }

                let outputSegmentStart = curve.timeMapping(sourceTime: sourceStart) * sourceDuration
                let outputSegmentEnd = curve.timeMapping(sourceTime: sourceEnd) * sourceDuration
                let outputSegmentDuration = max(outputSegmentEnd - outputSegmentStart, 1.0 / 600.0)

                let segmentSourceRange = CMTimeRange(
                    start: CMTimeAdd(
                        sourceTimeRange.start,
                        CMTime(seconds: sourceStart * sourceDuration, preferredTimescale: 600)
                    ),
                    duration: CMTime(seconds: sourceSegmentDuration, preferredTimescale: 600)
                )
                let segmentDestinationTime = CMTimeAdd(destinationTime, accumulatedOutputDuration)
                let scaledDuration = CMTime(seconds: outputSegmentDuration, preferredTimescale: 600)

                try compositionTrack.insertTimeRange(
                    segmentSourceRange,
                    of: sourceTrack,
                    at: segmentDestinationTime
                )

                if scaledDuration != segmentSourceRange.duration {
                    compositionTrack.scaleTimeRange(
                        CMTimeRange(start: segmentDestinationTime, duration: segmentSourceRange.duration),
                        toDuration: scaledDuration
                    )
                }

                accumulatedOutputDuration = CMTimeAdd(accumulatedOutputDuration, scaledDuration)
            }

            if accumulatedOutputDuration == .zero {
                try compositionTrack.insertTimeRange(sourceTimeRange, of: sourceTrack, at: destinationTime)
                return sourceTimeRange.duration
            }

            return accumulatedOutputDuration
        }

        func applyAudioVolumeAndFades(
            for clip: Clip,
            audioParameters: AVMutableAudioMixInputParameters,
            destinationTime: CMTime,
            clipDuration: CMTime
        ) {
            let volume = Float(clip.volume)
            audioParameters.setVolume(volume, at: destinationTime)

            guard clipDuration.seconds.isFinite, clipDuration.seconds > 0 else { return }

            if clip.fadeInDuration > 0 {
                let fadeInDuration = min(clip.fadeInDuration, clipDuration.seconds)
                audioParameters.setVolumeRamp(
                    fromStartVolume: 0,
                    toEndVolume: volume,
                    timeRange: CMTimeRange(
                        start: destinationTime,
                        duration: CMTime(seconds: fadeInDuration, preferredTimescale: 600)
                    )
                )
            }

            if clip.fadeOutDuration > 0 {
                let fadeOutDuration = min(clip.fadeOutDuration, clipDuration.seconds)
                let fadeOutStart = CMTimeAdd(
                    destinationTime,
                    CMTime(seconds: clipDuration.seconds - fadeOutDuration, preferredTimescale: 600)
                )
                audioParameters.setVolumeRamp(
                    fromStartVolume: volume,
                    toEndVolume: 0,
                    timeRange: CMTimeRange(
                        start: fadeOutStart,
                        duration: CMTime(seconds: fadeOutDuration, preferredTimescale: 600)
                    )
                )
            }
            applyDuckingRamps(
                for: clip,
                audioParameters: audioParameters,
                destinationTime: destinationTime,
                clipDuration: clipDuration,
                baseVolume: volume
            )
        }

        func applyDuckingRamps(
            for clip: Clip,
            audioParameters: AVMutableAudioMixInputParameters,
            destinationTime: CMTime,
            clipDuration: CMTime,
            baseVolume: Float
        ) {
            guard let duckingLevel = clip.duckingLevel,
                  duckingLevel < 1,
                  !clip.duckingRanges.isEmpty,
                  clipDuration.seconds.isFinite, clipDuration.seconds > 0
            else { return }

            let duckedVolume = baseVolume * Float(max(0, duckingLevel))
            let attack = AudioDuckingPlanner.attackDuration
            let release = AudioDuckingPlanner.releaseDuration
            // Keep ducking ramps clear of the fade windows so AVFoundation
            // never receives overlapping volume ramps on one clip.
            let lowerBound = clip.fadeInDuration > 0 ? min(clip.fadeInDuration, clipDuration.seconds) : 0
            let upperBound = clipDuration.seconds
                - (clip.fadeOutDuration > 0 ? min(clip.fadeOutDuration, clipDuration.seconds) : 0)
            guard upperBound > lowerBound else { return }

            for range in AudioDuckingPlanner.mergeOverlapping(clip.duckingRanges) {
                let start = max(range.start, lowerBound)
                let end = min(range.end, upperBound)
                guard end - start > attack + release else { continue }

                let attackStart = CMTimeAdd(
                    destinationTime,
                    CMTime(seconds: start, preferredTimescale: 600)
                )
                audioParameters.setVolumeRamp(
                    fromStartVolume: baseVolume,
                    toEndVolume: duckedVolume,
                    timeRange: CMTimeRange(
                        start: attackStart,
                        duration: CMTime(seconds: attack, preferredTimescale: 600)
                    )
                )

                let releaseStart = CMTimeAdd(
                    destinationTime,
                    CMTime(seconds: end - release, preferredTimescale: 600)
                )
                audioParameters.setVolumeRamp(
                    fromStartVolume: duckedVolume,
                    toEndVolume: baseVolume,
                    timeRange: CMTimeRange(
                        start: releaseStart,
                        duration: CMTime(seconds: release, preferredTimescale: 600)
                    )
                )
            }
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

        func cgColor(hexRGB: String) -> CGColor {
            let hex = hexRGB.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            guard hex.count == 6, let value = UInt64(hex, radix: 16) else {
                return NSColor.white.cgColor
            }

            let red = CGFloat((value >> 16) & 0xFF) / 255.0
            let green = CGFloat((value >> 8) & 0xFF) / 255.0
            let blue = CGFloat(value & 0xFF) / 255.0
            return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1).cgColor
        }

        func textAlignmentMode(for alignment: TextAlignment) -> CATextLayerAlignmentMode {
            switch alignment {
            case .leading:
                return .left
            case .center:
                return .center
            case .trailing:
                return .right
            case .justified:
                return .justified
            }
        }

        func isZeroPoint(_ point: CGPoint) -> Bool {
            point.x == 0 && point.y == 0
        }

        let composition = AVMutableComposition()
        var videoCompositionTracks: [(track: AVMutableCompositionTrack, zIndex: Int)] = []
        var videoClipInstructions: [PlaybackClipInstructionMetadata] = []
        var audioMixInputParameters: [AVMutableAudioMixInputParameters] = []

        for track in project.timeline.tracks.sorted(by: { $0.zIndex < $1.zIndex }) {
            switch track.kind {
            case .video:
                var videoCompositionTracksBySlot: [Int: AVMutableCompositionTrack] = [:]
                let audioCompositionTrack = track.isMuted ? nil : try makeCompositionTrack(
                    in: composition,
                    mediaType: .audio
                )
                let audioParameters = AVMutableAudioMixInputParameters()

                if let audioCompositionTrack {
                    audioParameters.trackID = audioCompositionTrack.trackID
                }

                let sortedClips = track.clips.sorted(by: { $0.timelineRange.start < $1.timelineRange.start })
                for (clipIndex, clip) in sortedClips.enumerated() {
                    guard let assetId = clip.assetId,
                          let mediaAsset = project.mediaLibrary.assets[assetId] else {
                        continue
                    }

                    let sourceAsset = AVURLAsset(url: mediaAsset.originalURL)
                    var adjustedTimelineStart = clip.timelineRange.start
                    if clipIndex > 0 {
                        let previousClip = sortedClips[clipIndex - 1]
                        if let transition = previousClip.transition, transition.duration > 0 {
                            adjustedTimelineStart = max(0, adjustedTimelineStart - transition.duration)
                        }
                    }

                    let destinationTime = cmTime(adjustedTimelineStart)
                    let sourceTimeRange = cmTimeRange(clip.sourceRange)
                    let isFreezeFrame = isFreezeFrameClip(clip)

                    if !track.isHidden,
                       let sourceTrack = try await sourceAsset.loadTracks(withMediaType: .video).first {
                        let videoCompositionTrack: AVMutableCompositionTrack
                        let trackSlot = clipIndex % 2
                        if let existingTrack = videoCompositionTracksBySlot[trackSlot] {
                            videoCompositionTrack = existingTrack
                        } else {
                            videoCompositionTrack = try makeCompositionTrack(
                                in: composition,
                                mediaType: .video
                            )
                            videoCompositionTracksBySlot[trackSlot] = videoCompositionTrack
                            videoCompositionTracks.append((videoCompositionTrack, track.zIndex))
                        }

                        if videoCompositionTrack.segments.isEmpty {
                            videoCompositionTrack.preferredTransform = try await sourceTrack.load(.preferredTransform)
                        }

                        var effectiveSourceTrack = sourceTrack
                        var effectiveSourceTimeRange = isFreezeFrame
                            ? freezeFrameSourceTimeRange(for: clip)
                            : sourceTimeRange
                        if clip.isReversed && !isFreezeFrame {
                            let reversedOutputURL = temporaryReverseRenderURL(for: clip)
                            temporaryReverseRenderURLs.append(reversedOutputURL)
                            try await ReverseRenderService().renderReversed(
                                clip: sourceAsset,
                                timeRange: sourceTimeRange,
                                outputURL: reversedOutputURL,
                                progress: { @Sendable _ in }
                            )

                            let reversedAsset = AVURLAsset(url: reversedOutputURL)
                            guard let reversedTrack = try await reversedAsset.loadTracks(withMediaType: .video).first else {
                                continue
                            }

                            effectiveSourceTrack = reversedTrack
                            effectiveSourceTimeRange = CMTimeRange(start: .zero, duration: sourceTimeRange.duration)
                        }

                        let targetDuration: CMTime
                        if isFreezeFrame {
                            try videoCompositionTrack.insertTimeRange(
                                effectiveSourceTimeRange,
                                of: effectiveSourceTrack,
                                at: destinationTime
                            )

                            let insertedDuration = effectiveSourceTimeRange.duration
                            targetDuration = cmTime(clip.timelineRange.duration)
                            videoCompositionTrack.scaleTimeRange(
                                CMTimeRange(start: destinationTime, duration: insertedDuration),
                                toDuration: targetDuration
                            )
                        } else if clip.speedRampPoints.count >= 2 {
                            targetDuration = try insertSpeedRampSegments(
                                SpeedRampCurve(points: clip.speedRampPoints),
                                sourceTrack: effectiveSourceTrack,
                                sourceTimeRange: effectiveSourceTimeRange,
                                destinationTime: destinationTime,
                                compositionTrack: videoCompositionTrack
                            )
                        } else {
                            try videoCompositionTrack.insertTimeRange(
                                effectiveSourceTimeRange,
                                of: effectiveSourceTrack,
                                at: destinationTime
                            )

                            let insertedDuration = effectiveSourceTimeRange.duration
                            targetDuration = scaledDuration(for: clip, insertedDuration: insertedDuration)
                            if targetDuration != insertedDuration {
                                videoCompositionTrack.scaleTimeRange(
                                    CMTimeRange(start: destinationTime, duration: insertedDuration),
                                    toDuration: targetDuration
                                )
                            }
                        }

                        let preferredTransform = try await sourceTrack.load(.preferredTransform)
                        let sourceSize = try await sourceTrack.load(.naturalSize)
                        videoClipInstructions.append(PlaybackClipInstructionMetadata(
                            timelineTrackID: track.id,
                            trackID: videoCompositionTrack.trackID,
                            timeRange: CMTimeRange(start: destinationTime, duration: targetDuration),
                            transform: affineTransform(
                                for: clip.transform,
                                sourceSize: sourceSize,
                                preferredTransform: preferredTransform
                            ),
                            opacity: Float(min(max(clip.opacity, 0), 1)),
                            transition: clip.transition,
                            colorCorrection: clip.colorCorrection,
                            colorGrade: clip.colorGrade,
                            chromaKey: clip.chromaKey,
                            chromaKeyColor: clip.chromaKeyColor,
                            chromaKeyThreshold: clip.chromaKeyThreshold,
                            mask: clip.mask,
                            effects: clip.effects,
                            isBackgroundRemoved: clip.isBackgroundRemoved
                        ))
                    }

                    if !isFreezeFrame,
                       let audioCompositionTrack,
                       let sourceTrack = try await sourceAsset.loadTracks(withMediaType: .audio).first {
                        guard sourceTimeRange.duration > .zero else { continue }

                        let targetDuration: CMTime
                        if clip.speedRampPoints.count >= 2 {
                            targetDuration = try insertSpeedRampSegments(
                                SpeedRampCurve(points: clip.speedRampPoints),
                                sourceTrack: sourceTrack,
                                sourceTimeRange: sourceTimeRange,
                                destinationTime: destinationTime,
                                compositionTrack: audioCompositionTrack
                            )
                        } else {
                            try audioCompositionTrack.insertTimeRange(
                                sourceTimeRange,
                                of: sourceTrack,
                                at: destinationTime
                            )

                            targetDuration = scaledDuration(for: clip, insertedDuration: sourceTimeRange.duration)
                            if targetDuration != sourceTimeRange.duration {
                                audioCompositionTrack.scaleTimeRange(
                                    CMTimeRange(start: destinationTime, duration: sourceTimeRange.duration),
                                    toDuration: targetDuration
                                )
                            }
                        }

                        applyAudioVolumeAndFades(
                            for: clip,
                            audioParameters: audioParameters,
                            destinationTime: destinationTime,
                            clipDuration: targetDuration
                        )
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
                    guard sourceTimeRange.duration > .zero else { continue }

                    let targetDuration: CMTime
                    if clip.speedRampPoints.count >= 2 {
                        targetDuration = try insertSpeedRampSegments(
                            SpeedRampCurve(points: clip.speedRampPoints),
                            sourceTrack: sourceTrack,
                            sourceTimeRange: sourceTimeRange,
                            destinationTime: destinationTime,
                            compositionTrack: audioCompositionTrack
                        )
                    } else {
                        try audioCompositionTrack.insertTimeRange(
                            sourceTimeRange,
                            of: sourceTrack,
                            at: destinationTime
                        )

                        targetDuration = scaledDuration(for: clip, insertedDuration: sourceTimeRange.duration)
                        if targetDuration != sourceTimeRange.duration {
                            audioCompositionTrack.scaleTimeRange(
                                CMTimeRange(start: destinationTime, duration: sourceTimeRange.duration),
                                toDuration: targetDuration
                            )
                        }
                    }

                    applyAudioVolumeAndFades(
                        for: clip,
                        audioParameters: audioParameters,
                        destinationTime: destinationTime,
                        clipDuration: targetDuration
                    )
                }

                audioMixInputParameters.append(audioParameters)
            case .text:
                guard !track.isHidden else { continue }

                for clip in track.clips.sorted(by: { $0.timelineRange.start < $1.timelineRange.start }) {
                    guard let textContent = clip.textContent else { continue }

                    let fontSize = CGFloat(textContent.fontSize)
                    let canvasSize = project.timeline.canvasSize
                    let fallbackPosition = CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
                    let position: CGPoint
                    if !isZeroPoint(textContent.position) {
                        position = textContent.position
                    } else if !isZeroPoint(clip.transform.position) {
                        position = clip.transform.position
                    } else {
                        position = fallbackPosition
                    }
                    let layerPosition = CGPoint(
                        x: position.x + clip.transform.offset.x,
                        y: position.y + clip.transform.offset.y
                    )
                    let clipStart = cmTime(clip.timelineRange.start)
                    let clipDuration = cmTime(clip.timelineRange.duration)

                    if let stickerImageURL = textContent.stickerImageURL,
                       let stickerImage = NSImage(contentsOf: stickerImageURL),
                       let stickerCGImage = stickerImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        let imageLayer = CALayer()
                        imageLayer.contents = stickerCGImage
                        imageLayer.contentsGravity = .resizeAspect
                        imageLayer.contentsScale = 2.0
                        imageLayer.opacity = Float(min(max(clip.opacity, 0), 1))

                        let sourceSize = CGSize(width: stickerCGImage.width, height: stickerCGImage.height)
                        let displaySize = stickerDisplaySize(
                            sourceSize: sourceSize,
                            fontSize: fontSize,
                            canvasSize: canvasSize
                        )
                        imageLayer.frame = CGRect(
                            x: layerPosition.x - displaySize.width * 0.5,
                            y: canvasSize.height - layerPosition.y - displaySize.height * 0.5,
                            width: displaySize.width,
                            height: displaySize.height
                        )
                        let layerTransform = CGAffineTransform(rotationAngle: CGFloat(clip.transform.rotation * .pi / 180))
                            .scaledBy(x: clip.transform.scale.width, y: clip.transform.scale.height)
                        imageLayer.setAffineTransform(layerTransform)
                        imageLayer.beginTime = AVCoreAnimationBeginTimeAtZero + clipStart.seconds
                        imageLayer.duration = clipDuration.seconds
                        if let animation = textContent.animation {
                            applyStickerLayerAnimation(
                                animation,
                                to: imageLayer,
                                canvasSize: canvasSize,
                                displaySize: displaySize
                            )
                        }
                        textLayers.append(imageLayer)
                        continue
                    }

                    let textLayer = CATextLayer()
                    let fontName = textContent.fontFamily == "System" ? "Helvetica Neue" : textContent.fontFamily
                    let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)

                    textLayer.string = textContent.text
                    textLayer.font = font
                    textLayer.fontSize = fontSize
                    textLayer.foregroundColor = cgColor(hexRGB: textContent.fontColor)
                    textLayer.alignmentMode = textAlignmentMode(for: textContent.alignment)
                    textLayer.contentsScale = 2.0
                    textLayer.opacity = Float(min(max(clip.opacity, 0), 1))
                    textLayer.frame = CGRect(
                        x: layerPosition.x - 100,
                        y: canvasSize.height - layerPosition.y - fontSize,
                        width: 200,
                        height: fontSize + 20
                    )
                    let layerTransform = CGAffineTransform(rotationAngle: CGFloat(clip.transform.rotation * .pi / 180))
                        .scaledBy(x: clip.transform.scale.width, y: clip.transform.scale.height)
                    textLayer.setAffineTransform(layerTransform)

                    textLayer.beginTime = AVCoreAnimationBeginTimeAtZero + clipStart.seconds
                    textLayer.duration = clipDuration.seconds
                    if let animation = textContent.animation {
                        TextAnimationRenderer.applyCoreAnimation(
                            animation,
                            to: textLayer,
                            canvasSize: canvasSize,
                            fontSize: fontSize,
                            text: textContent.text
                        )
                    }
                    textLayers.append(textLayer)
                }
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

            let transitionEffects = makeTransitionEffects(from: videoClipInstructions)
            let usesCustomVideoCompositor = videoClipInstructions.contains { clipInstruction in
                clipInstruction.colorCorrection != nil
                    || clipInstruction.colorGrade != nil
                    || clipInstruction.chromaKey != nil
                    || clipInstruction.chromaKeyColor != nil
                    || clipInstruction.mask != nil
                    || !clipInstruction.effects.isEmpty
            } || !transitionEffects.isEmpty
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

                if let transition = clipInstruction.transition, transition.duration > 0 {
                    guard !transition.type.requiresTwoSourcePixelProcessing else {
                        continue
                    }

                    let overlapDuration = transition.duration
                    let overlapStart = CMTimeAdd(
                        clipInstruction.timeRange.start,
                        CMTime(seconds: clipInstruction.timeRange.duration.seconds - overlapDuration, preferredTimescale: 600)
                    )

                    let overlapRange = CMTimeRange(
                        start: overlapStart,
                        duration: CMTime(seconds: overlapDuration, preferredTimescale: 600)
                    )

                    switch transition.type {
                    case .crossDissolve:
                        layerInstruction.setOpacityRamp(
                            fromStartOpacity: 1.0,
                            toEndOpacity: 0.0,
                            timeRange: overlapRange
                        )
                    case .fadeThroughBlack:
                        let halfDuration = overlapDuration / 2
                        layerInstruction.setOpacityRamp(
                            fromStartOpacity: 1.0,
                            toEndOpacity: 0.0,
                            timeRange: CMTimeRange(
                                start: overlapStart,
                                duration: CMTime(seconds: halfDuration, preferredTimescale: 600)
                            )
                        )
                    case .wipeRight:
                        let fromTransform = CGAffineTransform(
                            translationX: -CGFloat(clipInstruction.timeRange.duration.seconds) * 100,
                            y: 0
                        )
                        layerInstruction.setTransformRamp(
                            fromStart: fromTransform,
                            toEnd: .identity,
                            timeRange: overlapRange
                        )
                    case .wipeLeft,
                         .wipeUp,
                         .wipeDown,
                         .slideLeft,
                         .slideRight,
                         .zoomIn,
                         .zoomOut,
                         .glitch:
                        break
                    case .none:
                        break
                    }
                }
            }

            if usesCustomVideoCompositor {
                mutableVideoComposition.customVideoCompositorClass = CustomVideoCompositor.self
                mutableVideoComposition.instructions = [
                    CustomCompositionInstruction(
                        timeRange: CMTimeRange(start: .zero, duration: composition.duration),
                        trackIDs: sortedVideoCompositionTracks.map { $0.track.trackID },
                        clipEffects: videoClipInstructions.compactMap { clipInstruction in
                            CustomCompositionClipEffect(
                                trackID: clipInstruction.trackID,
                                timeRange: clipInstruction.timeRange,
                                colorCorrection: clipInstruction.colorCorrection,
                                colorGrade: clipInstruction.colorGrade,
                                chromaKey: clipInstruction.chromaKey,
                                chromaKeyColor: clipInstruction.chromaKeyColor,
                                chromaKeyThreshold: clipInstruction.chromaKeyThreshold,
                                mask: clipInstruction.mask,
                                effects: clipInstruction.effects,
                                isBackgroundRemoved: clipInstruction.isBackgroundRemoved
                            )
                        },
                        transitionEffects: transitionEffects,
                        canvasBackground: project.canvasBackground,
                        prefersFastSegmentation: true
                    )
                ]
            } else {
                mutableVideoComposition.instructions = [instruction]
            }
            if !textLayers.isEmpty {
                let parentLayer = CALayer()
                let videoLayer = CALayer()
                parentLayer.frame = CGRect(
                    origin: CGPoint(x: 0, y: 0),
                    size: project.timeline.canvasSize
                )
                videoLayer.frame = parentLayer.bounds
                parentLayer.addSublayer(videoLayer)
                for layer in textLayers {
                    parentLayer.addSublayer(layer)
                }
                mutableVideoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
                    postProcessingAsVideoLayer: videoLayer,
                    in: parentLayer
                )
            }
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


        // MARK: - EQ Processing
        if !audioProcessing.eqPresets.isEmpty {
            for mutableParams in audioMixInputParameters {
                for projTrack in project.timeline.tracks {
                    for clip in projTrack.clips {
                        if let eqPreset = audioProcessing.eqPresets[clip.id] {
                            applyEQBands(eqPreset, to: mutableParams)
                        }
                    }
                }
            }
        }

        // MARK: - Noise Reduction
        // High-pass (80Hz) + low-pass (12kHz) filtering is applied at the AVAudioEngine level
        // for real-time playback. For composition-based playback, clips marked for noise reduction
        // are tracked in audioProcessing.noiseReductionClipIds for offline processing.

        // MARK: - Audio Ducking
        if audioProcessing.duckLevel > 0, !audioProcessing.voiceClipIds.isEmpty {
            let duckMultiplier = 1.0 - audioProcessing.duckLevel
            var voiceTimeRanges: [(start: Double, end: Double)] = []
            for projTrack in project.timeline.tracks where projTrack.kind == .video {
                for clip in projTrack.clips where audioProcessing.voiceClipIds.contains(clip.id) {
                    voiceTimeRanges.append((clip.timelineRange.start, clip.timelineRange.end))
                }
            }
            // Lower volume of audio-track clips during voice ranges
            for mutableParams in audioMixInputParameters {
                for projTrack in project.timeline.tracks where projTrack.kind == .audio {
                    for clip in projTrack.clips {
                        let clipRange = clip.timelineRange
                        for voiceRange in voiceTimeRanges {
                            if clipRange.start < voiceRange.end && voiceRange.start < clipRange.end {
                                let duckedVolume = Float(clip.volume * duckMultiplier)
                                let overlapStart = max(clipRange.start, voiceRange.start)
                                let overlapEnd = min(clipRange.end, voiceRange.end)
                                mutableParams.setVolumeRamp(
                                    fromStartVolume: duckedVolume,
                                    toEndVolume: duckedVolume,
                                    timeRange: CMTimeRange(
                                        start: CMTime(seconds: overlapStart, preferredTimescale: 600),
                                        duration: CMTime(seconds: overlapEnd - overlapStart, preferredTimescale: 600)
                                    )
                                )
                            }
                        }
                    }
                }
            }
        }

        shouldKeepTemporaryReverseRenderURLs = true
        return (composition, videoComposition, audioMix, temporaryReverseRenderURLs)
    }

    private func makeTransitionEffects(
        from clips: [PlaybackClipInstructionMetadata]
    ) -> [CustomCompositionTransitionEffect] {
        let videoClipsByTimelineTrack = Dictionary(
            grouping: clips.filter { $0.trackID != kCMPersistentTrackID_Invalid },
            by: \.timelineTrackID
        )

        return videoClipsByTimelineTrack.values.flatMap { trackClips in
            let sortedClips = trackClips.sorted {
                if $0.timeRange.start == $1.timeRange.start {
                    return $0.timeRange.duration > $1.timeRange.duration
                }
                return $0.timeRange.start < $1.timeRange.start
            }

            guard sortedClips.count > 1 else {
                return [CustomCompositionTransitionEffect]()
            }

            return sortedClips.indices.dropLast().compactMap { index in
                let outgoingClip = sortedClips[index]
                let incomingClip = sortedClips[index + 1]

                guard let transition = outgoingClip.transition,
                      transition.duration > 0,
                      transition.type.requiresTwoSourcePixelProcessing
                else {
                    return nil
                }

                let requestedDuration = CMTime(seconds: transition.duration, preferredTimescale: 600)
                let transitionDuration = min(
                    requestedDuration,
                    min(outgoingClip.timeRange.duration, incomingClip.timeRange.duration)
                )
                guard transitionDuration > .zero else {
                    return nil
                }

                let outgoingEnd = CMTimeAdd(outgoingClip.timeRange.start, outgoingClip.timeRange.duration)
                let transitionStart = CMTimeSubtract(outgoingEnd, transitionDuration)

                return CustomCompositionTransitionEffect(
                    outgoingTrackID: outgoingClip.trackID,
                    incomingTrackID: incomingClip.trackID,
                    timeRange: CMTimeRange(start: transitionStart, duration: transitionDuration),
                    type: transition.type
                )
            }
        }
    }

    private func stickerDisplaySize(sourceSize: CGSize, fontSize: CGFloat, canvasSize: CGSize) -> CGSize {
        let aspectRatio: CGFloat
        if sourceSize.width > 0, sourceSize.height > 0 {
            aspectRatio = sourceSize.width / sourceSize.height
        } else {
            aspectRatio = 1
        }

        let shorterCanvasEdge = max(min(canvasSize.width, canvasSize.height), 1)
        let baseWidth = min(max(fontSize * 2.8, 96), shorterCanvasEdge * 0.45)
        let width = baseWidth
        let height = max(width / max(aspectRatio, 0.01), 1)
        return CGSize(width: width, height: height)
    }

    private func applyStickerLayerAnimation(
        _ textAnimation: TextAnimation,
        to layer: CALayer,
        canvasSize: CGSize,
        displaySize: CGSize
    ) {
        let duration = max(textAnimation.duration, 0)
        guard duration > 0 else { return }

        let delay = max(textAnimation.delay, 0)
        switch textAnimation.type {
        case .fadeIn:
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 0
            animation.toValue = layer.opacity
            configureStickerLayerAnimation(animation, duration: duration, delay: delay)
            layer.add(animation, forKey: "fadeIn")
        case .fadeOut:
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = layer.opacity
            animation.toValue = 0
            configureStickerLayerAnimation(animation, duration: duration, delay: delay)
            layer.add(animation, forKey: "fadeOut")
        case .slideUp:
            let animation = CABasicAnimation(keyPath: "position.y")
            animation.fromValue = canvasSize.height + displaySize.height
            animation.toValue = layer.position.y
            configureStickerLayerAnimation(animation, duration: duration, delay: delay)
            layer.add(animation, forKey: "slideUp")
        case .slideDown:
            let animation = CABasicAnimation(keyPath: "position.y")
            animation.fromValue = -displaySize.height
            animation.toValue = layer.position.y
            configureStickerLayerAnimation(animation, duration: duration, delay: delay)
            layer.add(animation, forKey: "slideDown")
        case .scale:
            let animation = CABasicAnimation(keyPath: "transform.scale")
            animation.fromValue = 0
            animation.toValue = 1
            configureStickerLayerAnimation(animation, duration: duration, delay: delay)
            layer.add(animation, forKey: "scale")
        case .bounce:
            let animation = CAKeyframeAnimation(keyPath: "position.y")
            animation.values = [
                NSNumber(value: Double(layer.position.y)),
                NSNumber(value: Double(layer.position.y + 20)),
                NSNumber(value: Double(layer.position.y - 8)),
                NSNumber(value: Double(layer.position.y + 3)),
                NSNumber(value: Double(layer.position.y))
            ]
            animation.keyTimes = [0, 0.35, 0.6, 0.8, 1].map(NSNumber.init(value:))
            configureStickerLayerAnimation(animation, duration: duration, delay: delay)
            layer.add(animation, forKey: "bounce")
        case .typewriter:
            break
        }
    }

    private func configureStickerLayerAnimation(
        _ animation: CAAnimation,
        duration: TimeInterval,
        delay: TimeInterval
    ) {
        animation.duration = duration
        animation.beginTime = delay
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
    }

    private func applyEQBands(_ preset: EqualizerPreset, to parameters: AVMutableAudioMixInputParameters) {
        // EQ is applied through AVAudioUnitEQ in the audio engine; for composition-based
        // playback we note that AVAudioMixInputParameters does not support parametric EQ directly.
        // The EQ bands are applied when using AVAudioEngine for real-time playback.
        // For composition playback, volume adjustments approximate the EQ effect per band.
        let totalGain = preset.bands.reduce(Float(0)) { $0 + $1.gain }
        let avgGain = totalGain / Float(preset.bands.count)
        if avgGain != 0 {
            let volumeAdjustment = pow(10.0, Double(avgGain) / 20.0)
            let adjustedVolume = Float(min(max(volumeAdjustment, 0.0), 2.0))
            parameters.setVolume(adjustedVolume, at: .zero)
        }
    }

    private func temporaryReverseRenderURL(for clip: Clip) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutPlaybackReverse-\(clip.id.uuidString)-\(UUID().uuidString)")
            .appendingPathExtension("mov")
    }

    private func cleanupTemporaryReverseRenderURLs() {
        removeTemporaryReverseRenderURLs(temporaryReverseRenderURLs)
        temporaryReverseRenderURLs = []
    }

    private func removeTemporaryReverseRenderURLs(_ urls: [URL]) {
        let fileManager = FileManager.default
        for url in urls where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
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

private struct PlaybackClipInstructionMetadata {
    var timelineTrackID: UUID
    var trackID: CMPersistentTrackID
    var timeRange: CMTimeRange
    var transform: CGAffineTransform
    var opacity: Float
    var transition: Transition?
    var colorCorrection: ColorCorrection?
    var colorGrade: ColorGrade?
    var chromaKey: ChromaKeySettings?
    var chromaKeyColor: SIMD3<Float>?
    var chromaKeyThreshold: Float
    var mask: Mask?
    var effects: [Effect]
    var isBackgroundRemoved: Bool
}
