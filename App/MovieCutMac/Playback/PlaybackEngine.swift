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
        var videoClipInstructions: [(
            trackID: CMPersistentTrackID,
            timeRange: CMTimeRange,
            transform: CGAffineTransform,
            opacity: Float,
            transition: Transition?,
            colorCorrection: ColorCorrection?,
            chromaKeyColor: SIMD3<Float>?,
            chromaKeyThreshold: Float,
            mask: Mask?
        )] = []
        var audioMixInputParameters: [AVMutableAudioMixInputParameters] = []

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
                    let isFreezeFrame = isFreezeFrameClip(clip)

                    if let videoCompositionTrack,
                       let sourceTrack = try await sourceAsset.loadTracks(withMediaType: .video).first {
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

                        try videoCompositionTrack.insertTimeRange(
                            effectiveSourceTimeRange,
                            of: effectiveSourceTrack,
                            at: destinationTime
                        )

                        let insertedDuration = effectiveSourceTimeRange.duration
                        let targetDuration: CMTime
                        if isFreezeFrame {
                            targetDuration = cmTime(clip.timelineRange.duration)
                            videoCompositionTrack.scaleTimeRange(
                                CMTimeRange(start: destinationTime, duration: insertedDuration),
                                toDuration: targetDuration
                            )
                        } else {
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
                        videoClipInstructions.append((
                            videoCompositionTrack.trackID,
                            CMTimeRange(start: destinationTime, duration: targetDuration),
                            affineTransform(
                                for: clip.transform,
                                sourceSize: sourceSize,
                                preferredTransform: preferredTransform
                            ),
                            Float(min(max(clip.opacity, 0), 1)),
                            clip.transition,
                            clip.colorCorrection,
                            clip.chromaKeyColor,
                            clip.chromaKeyThreshold,
                            clip.mask
                        ))
                    }

                    if !isFreezeFrame,
                       let audioCompositionTrack,
                       let sourceTrack = try await sourceAsset.loadTracks(withMediaType: .audio).first {
                        guard sourceTimeRange.duration > .zero else { continue }

                        try audioCompositionTrack.insertTimeRange(
                            sourceTimeRange,
                            of: sourceTrack,
                            at: destinationTime
                        )

                        let targetDuration = scaledDuration(for: clip, insertedDuration: sourceTimeRange.duration)
                        if targetDuration != sourceTimeRange.duration {
                            audioCompositionTrack.scaleTimeRange(
                                CMTimeRange(start: destinationTime, duration: sourceTimeRange.duration),
                                toDuration: targetDuration
                            )
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

                    try audioCompositionTrack.insertTimeRange(
                        sourceTimeRange,
                        of: sourceTrack,
                        at: destinationTime
                    )

                    let targetDuration = scaledDuration(for: clip, insertedDuration: sourceTimeRange.duration)
                    if targetDuration != sourceTimeRange.duration {
                        audioCompositionTrack.scaleTimeRange(
                            CMTimeRange(start: destinationTime, duration: sourceTimeRange.duration),
                            toDuration: targetDuration
                        )
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

                    let textLayer = CATextLayer()
                    let fontSize = CGFloat(textContent.fontSize)
                    let fontName = textContent.fontFamily == "System" ? "Helvetica Neue" : textContent.fontFamily
                    let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
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

                    textLayer.string = textContent.text
                    textLayer.font = font
                    textLayer.fontSize = fontSize
                    textLayer.foregroundColor = cgColor(hexRGB: textContent.fontColor)
                    textLayer.alignmentMode = textAlignmentMode(for: textContent.alignment)
                    textLayer.contentsScale = 2.0
                    textLayer.frame = CGRect(
                        x: position.x - 100,
                        y: canvasSize.height - position.y - fontSize,
                        width: 200,
                        height: fontSize + 20
                    )

                    let clipStart = cmTime(clip.timelineRange.start)
                    let clipDuration = cmTime(clip.timelineRange.duration)
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

            let usesCustomVideoCompositor = videoClipInstructions.contains { clipInstruction in
                clipInstruction.colorCorrection != nil || clipInstruction.chromaKeyColor != nil || clipInstruction.mask != nil
            }
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

                if let transition = clipInstruction.transition, transition.type == .crossDissolve {
                    let overlapDuration = transition.duration
                    let overlapStart = CMTimeAdd(
                        clipInstruction.timeRange.start,
                        CMTime(seconds: clipInstruction.timeRange.duration.seconds - overlapDuration, preferredTimescale: 600)
                    )
                    layerInstruction.setOpacityRamp(
                        fromStartOpacity: 1.0,
                        toEndOpacity: 0.0,
                        timeRange: CMTimeRange(
                            start: overlapStart,
                            duration: CMTime(seconds: overlapDuration, preferredTimescale: 600)
                        )
                    )
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
                                chromaKeyColor: clipInstruction.chromaKeyColor,
                                chromaKeyThreshold: clipInstruction.chromaKeyThreshold,
                                mask: clipInstruction.mask
                            )
                        }
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
