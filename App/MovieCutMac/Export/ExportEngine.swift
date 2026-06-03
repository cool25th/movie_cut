import AVFoundation
import AppKit
import Foundation
import MovieCutCore
import Observation
import QuartzCore

@MainActor
@Observable
final class ExportEngine {
    var isExporting = false
    var exportProgress: Double = 0
    var exportError: String?

    @ObservationIgnored private var activeExportSession: AVAssetExportSession?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    func export(project: Project, to url: URL) async throws {
        isExporting = true
        exportProgress = 0
        exportError = nil

        do {
            let exportPackage = try await makeExportPackage(for: project)
            guard !exportPackage.composition.tracks.isEmpty else {
                throw ExportEngineError.noExportableMedia
            }

            let presetName = presetName(for: project.exportSettings)
            guard let exportSession = AVAssetExportSession(asset: exportPackage.composition, presetName: presetName) else {
                throw ExportEngineError.exportSessionCreationFailed
            }

            exportSession.videoComposition = exportPackage.videoComposition
            exportSession.audioMix = exportPackage.audioMix
            activeExportSession = exportSession
            startProgressPolling()

            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }

            let fileType = outputFileType(for: url, settings: project.exportSettings, supportedFileTypes: exportSession.supportedFileTypes)
            try await exportSession.export(to: url, as: fileType)
            exportProgress = 1
            finishExport()
        } catch {
            exportError = error.localizedDescription
            finishExport()
            throw error
        }
    }

    private func makeExportPackage(for project: Project) async throws -> ExportPackage {
        let composition = AVMutableComposition()
        var videoCompositionTracks: [AVCompositionTrack] = []
        var videoClipInstructions: [ExportClipInstructionMetadata] = []
        var audioMixInputParameters: [AVAudioMixInputParameters] = []

        for track in project.timeline.tracks where !track.isMuted {
            if track.kind == .text {
                for clip in track.clips {
                    guard let textContent = clip.textContent else {
                        continue
                    }

                    let destinationTime = CMTime(seconds: clip.timelineRange.start, preferredTimescale: 600)
                    let clipDuration = CMTime(seconds: clip.timelineRange.duration, preferredTimescale: 600)
                    videoClipInstructions.append(ExportClipInstructionMetadata(
                        clipID: clip.id,
                        trackID: kCMPersistentTrackID_Invalid,
                        timeRange: CMTimeRange(start: destinationTime, duration: clipDuration),
                        transform: clip.transform,
                        opacity: clip.opacity,
                        mask: clip.mask,
                        colorCorrection: clip.colorCorrection,
                        effects: clip.effects,
                        textContent: textContent
                    ))
                }

                continue
            }

            guard let mediaType = mediaType(for: track.kind) else { continue }

            var destinationTrack: AVMutableCompositionTrack?
            let audioParameters = AVMutableAudioMixInputParameters()

            for clip in track.clips {
                guard let assetId = clip.assetId,
                      let mediaAsset = project.mediaLibrary.assets[assetId] else {
                    continue
                }

                let sourceAsset = AVURLAsset(url: mediaAsset.originalURL)
                guard let sourceTrack = try await sourceAsset.loadTracks(withMediaType: mediaType).first else {
                    continue
                }

                let compositionTrack: AVMutableCompositionTrack
                if let destinationTrack {
                    compositionTrack = destinationTrack
                } else {
                    guard let createdTrack = composition.addMutableTrack(
                        withMediaType: mediaType,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    ) else {
                        throw ExportEngineError.compositionTrackCreationFailed
                    }
                    createdTrack.preferredTransform = try await sourceTrack.load(.preferredTransform)
                    destinationTrack = createdTrack
                    compositionTrack = createdTrack

                    if mediaType == .video {
                        videoCompositionTracks.append(createdTrack)
                    } else if mediaType == .audio {
                        audioParameters.trackID = createdTrack.trackID
                    }
                }

                let sourceTimeRange = CMTimeRange(
                    start: CMTime(seconds: clip.sourceRange.start, preferredTimescale: 600),
                    duration: CMTime(seconds: clip.sourceRange.duration, preferredTimescale: 600)
                )
                let destinationTime = CMTime(seconds: clip.timelineRange.start, preferredTimescale: 600)
                try compositionTrack.insertTimeRange(sourceTimeRange, of: sourceTrack, at: destinationTime)

                var effectiveSourceTrack = sourceTrack
                var effectiveSourceTimeRange = sourceTimeRange
                var clipCompositionDuration = sourceTimeRange.duration

                if clip.isReversed, mediaType == .video {
                    let reversedOutputURL = temporaryReverseRenderURL(for: clip)
                    try await ReverseRenderService().renderReversed(
                        clip: sourceAsset,
                        timeRange: sourceTimeRange,
                        outputURL: reversedOutputURL,
                        progress: { _ in }
                    )

                    let reversedAsset = AVURLAsset(url: reversedOutputURL)
                    guard let reversedTrack = try await reversedAsset.loadTracks(withMediaType: mediaType).first else {
                        continue
                    }

                    compositionTrack.removeTimeRange(CMTimeRange(start: destinationTime, duration: sourceTimeRange.duration))
                    effectiveSourceTrack = reversedTrack
                    effectiveSourceTimeRange = CMTimeRange(start: .zero, duration: sourceTimeRange.duration)
                    clipCompositionDuration = effectiveSourceTimeRange.duration
                    try compositionTrack.insertTimeRange(effectiveSourceTimeRange, of: effectiveSourceTrack, at: destinationTime)
                }

                var didApplySpeedRamp = false
                if clip.speedRampPoints.count >= 2 {
                    let curve = SpeedRampCurve(points: clip.speedRampPoints)
                    clipCompositionDuration = try applySpeedRamp(
                        curve,
                        sourceTrack: effectiveSourceTrack,
                        sourceTimeRange: effectiveSourceTimeRange,
                        destinationTime: destinationTime,
                        compositionTrack: compositionTrack
                    )
                    didApplySpeedRamp = true
                }

                let playbackRate = min(max(clip.playbackRate, 0.25), 4.0)
                if playbackRate != 1, !didApplySpeedRamp {
                    let scaledDuration = CMTime(seconds: clip.sourceRange.duration / playbackRate, preferredTimescale: 600)
                    let insertedRange = CMTimeRange(start: destinationTime, duration: clipCompositionDuration)
                    compositionTrack.scaleTimeRange(insertedRange, toDuration: scaledDuration)
                    clipCompositionDuration = scaledDuration
                }

                if mediaType == .video {
                    // Masked clips are carried into the video-composition metadata for future compositing.
                    videoClipInstructions.append(ExportClipInstructionMetadata(
                        clipID: clip.id,
                        trackID: compositionTrack.trackID,
                        timeRange: CMTimeRange(start: destinationTime, duration: clipCompositionDuration),
                        transform: clip.transform,
                        opacity: clip.opacity,
                        mask: clip.mask,
                        colorCorrection: clip.colorCorrection,
                        effects: clip.effects
                    ))
                }

                if mediaType == .audio {
                    audioParameters.setVolume(Float(clip.volume), at: destinationTime)
                }
            }

            if mediaType == .audio, destinationTrack != nil {
                audioMixInputParameters.append(audioParameters)
            }
        }

        let videoComposition = makeVideoComposition(
            tracks: videoCompositionTracks,
            clips: videoClipInstructions,
            duration: composition.duration,
            canvas: project.canvas
        )
        let audioMix = makeAudioMix(parameters: audioMixInputParameters)

        return ExportPackage(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix
        )
    }

    private func makeVideoComposition(
        tracks: [AVCompositionTrack],
        clips: [ExportClipInstructionMetadata],
        duration: CMTime,
        canvas: CanvasPreset
    ) -> AVMutableVideoComposition? {
        guard !tracks.isEmpty else { return nil }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = canvas.size
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(canvas.frameRate.framesPerSecond))

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstructions = tracks.map { AVMutableVideoCompositionLayerInstruction(assetTrack: $0) }
        instruction.layerInstructions = layerInstructions

        let layerInstructionsByTrackID = Dictionary(
            uniqueKeysWithValues: zip(tracks.map(\.trackID), layerInstructions)
        )
        var customCompositorClips: [ExportClipInstructionMetadata] = []

        for clip in clips {
            if clip.textContent != nil {
                customCompositorClips.append(clip)
                continue
            }

            guard let layerInstruction = layerInstructionsByTrackID[clip.trackID] else {
                continue
            }

            if !isIdentityTransform(clip.transform) {
                layerInstruction.setTransform(
                    affineTransform(for: clip.transform, canvasSize: canvas.size),
                    at: clip.timeRange.start
                )
                layerInstruction.setTransform(.identity, at: CMTimeAdd(clip.timeRange.start, clip.timeRange.duration))
            }

            let opacity = min(max(clip.opacity, 0), 1)
            if opacity < 1 {
                layerInstruction.setOpacityRamp(
                    fromStartOpacity: Float(opacity),
                    toEndOpacity: Float(opacity),
                    timeRange: clip.timeRange
                )
                layerInstruction.setOpacity(1, at: CMTimeAdd(clip.timeRange.start, clip.timeRange.duration))
            }

            if clip.requiresCustomVideoCompositorMetadata {
                // Color correction and analysis effects need a CIImage-backed custom compositor.
                customCompositorClips.append(clip)
            }
        }

        videoComposition.instructions = [instruction]
        videoComposition.animationTool = makeCustomVideoCompositorInstruction(
            tracks: tracks,
            clips: customCompositorClips,
            canvas: canvas
        )

        return videoComposition
    }

    private func makeCustomVideoCompositorInstruction(
        tracks: [AVCompositionTrack],
        clips: [ExportClipInstructionMetadata],
        canvas: CanvasPreset
    ) -> AVVideoCompositionCoreAnimationTool? {
        _ = tracks
        let parentLayer = CALayer()
        let videoLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: canvas.size)
        videoLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(videoLayer)

        var addedTextLayer = false
        for clipMeta in clips {
            guard let textContent = clipMeta.textContent else { continue }

            let textLayer = CATextLayer()
            let fontSize = CGFloat(textContent.fontSize)
            let fontName = textContent.fontFamily == "System" ? "Helvetica Neue" : textContent.fontFamily
            let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
            let position = textPosition(for: clipMeta, textContent: textContent, canvasSize: canvas.size)

            textLayer.string = textContent.text
            textLayer.font = font
            textLayer.fontSize = fontSize
            textLayer.foregroundColor = cgColor(hexRGB: textContent.fontColor)
            textLayer.backgroundColor = textContent.backgroundColor.map(cgColor(hexRGB:))
            textLayer.alignmentMode = textAlignmentMode(for: textContent.alignment)
            textLayer.contentsScale = 2.0
            textLayer.opacity = Float(min(max(clipMeta.opacity, 0), 1))
            textLayer.frame = CGRect(
                x: position.x - 100,
                y: canvas.size.height - position.y - fontSize,
                width: 200,
                height: fontSize + 20
            )

            let beginTime = clipMeta.timeRange.start.seconds
            let duration = clipMeta.timeRange.duration.seconds
            textLayer.beginTime = AVCoreAnimationBeginTimeAtZero + beginTime
            textLayer.duration = duration
            parentLayer.addSublayer(textLayer)
            addedTextLayer = true
        }

        guard addedTextLayer else { return nil }
        return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
    }

    private func temporaryReverseRenderURL(for clip: Clip) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutReverse-\(clip.id.uuidString)")
            .appendingPathExtension("mov")
    }

    private func applySpeedRamp(
        _ curve: SpeedRampCurve,
        sourceTrack: AVAssetTrack,
        sourceTimeRange: CMTimeRange,
        destinationTime: CMTime,
        compositionTrack: AVMutableCompositionTrack
    ) throws -> CMTime {
        _ = sourceTrack

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

            let segmentRange = CMTimeRange(
                start: CMTimeAdd(destinationTime, accumulatedOutputDuration),
                duration: CMTime(seconds: sourceSegmentDuration, preferredTimescale: 600)
            )
            let scaledDuration = CMTime(seconds: outputSegmentDuration, preferredTimescale: 600)
            compositionTrack.scaleTimeRange(segmentRange, toDuration: scaledDuration)
            accumulatedOutputDuration = CMTimeAdd(accumulatedOutputDuration, scaledDuration)
        }

        return accumulatedOutputDuration
    }

    private func isIdentityTransform(_ transform: ClipTransform) -> Bool {
        isZeroPoint(transform.position)
            && isZeroPoint(transform.offset)
            && abs(transform.scale.width - 1) <= 1.0e-9
            && abs(transform.scale.height - 1) <= 1.0e-9
            && abs(transform.rotation) <= 1.0e-9
    }

    private func affineTransform(for transform: ClipTransform, canvasSize: CGSize) -> CGAffineTransform {
        let anchorPoint = CGPoint(
            x: canvasSize.width * transform.anchorPoint.x,
            y: canvasSize.height * transform.anchorPoint.y
        )
        let radians = CGFloat(transform.rotation * .pi / 180)

        var affineTransform = CGAffineTransform.identity
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

    private func textPosition(
        for clipMeta: ExportClipInstructionMetadata,
        textContent: TextClipContent,
        canvasSize: CGSize
    ) -> CGPoint {
        if !isZeroPoint(textContent.position) {
            return textContent.position
        }

        if !isZeroPoint(clipMeta.transform.position) {
            return clipMeta.transform.position
        }

        return CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
    }

    private func isZeroPoint(_ point: CGPoint) -> Bool {
        abs(point.x) <= 1.0e-9 && abs(point.y) <= 1.0e-9
    }

    private func cgColor(hexRGB: String) -> CGColor {
        let hex = hexRGB.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else {
            return NSColor.white.cgColor
        }

        let red = CGFloat((value >> 16) & 0xFF) / 255.0
        let green = CGFloat((value >> 8) & 0xFF) / 255.0
        let blue = CGFloat(value & 0xFF) / 255.0
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1).cgColor
    }

    private func textAlignmentMode(for alignment: TextAlignment) -> CATextLayerAlignmentMode {
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

    private func makeAudioMix(parameters: [AVAudioMixInputParameters]) -> AVMutableAudioMix? {
        guard !parameters.isEmpty else { return nil }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = parameters
        return audioMix
    }

    private func mediaType(for trackKind: TrackKind) -> AVMediaType? {
        switch trackKind {
        case .video:
            return .video
        case .audio:
            return .audio
        case .text:
            return nil
        }
    }

    private func presetName(for settings: ExportSettings) -> String {
        switch (settings.codec, settings.resolution) {
        case (.hevc, .p1080):
            return AVAssetExportPresetHEVC1920x1080
        case (.hevc, .p4K):
            return AVAssetExportPresetHEVC3840x2160
        case (.hevc, .p720):
            return AVAssetExportPresetHEVCHighestQuality
        case (.h264, .p720):
            return AVAssetExportPreset1280x720
        case (.h264, .p1080):
            return AVAssetExportPreset1920x1080
        case (.h264, .p4K):
            return AVAssetExportPreset3840x2160
        }
    }

    private func outputFileType(
        for url: URL,
        settings: ExportSettings,
        supportedFileTypes: [AVFileType]
    ) -> AVFileType {
        let requested: AVFileType
        switch url.pathExtension.lowercased() {
        case "mov":
            requested = .mov
        case "m4v":
            requested = .m4v
        default:
            requested = settings.codec == .hevc ? .mov : .mp4
        }

        if supportedFileTypes.contains(requested) {
            return requested
        }

        if supportedFileTypes.contains(.mp4) {
            return .mp4
        }

        return supportedFileTypes.first ?? .mov
    }

    private func startProgressPolling() {
        progressTask?.cancel()
        progressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let activeExportSession {
                    exportProgress = Double(activeExportSession.progress)
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func finishExport() {
        progressTask?.cancel()
        progressTask = nil
        activeExportSession = nil
        isExporting = false
    }
}

private struct ExportPackage {
    var composition: AVMutableComposition
    var videoComposition: AVMutableVideoComposition?
    var audioMix: AVMutableAudioMix?
}

private struct ExportClipInstructionMetadata {
    var clipID: UUID
    var trackID: CMPersistentTrackID
    var timeRange: CMTimeRange
    var transform: ClipTransform
    var opacity: Double
    var mask: Mask?
    var colorCorrection: ColorCorrection?
    var effects: [Effect]
    var textContent: TextClipContent?

    var requiresCustomVideoCompositorMetadata: Bool {
        textContent != nil || mask != nil || colorCorrection != nil || !effects.isEmpty
    }
}

private enum ExportEngineError: LocalizedError {
    case compositionTrackCreationFailed
    case exportSessionCreationFailed
    case noExportableMedia

    var errorDescription: String? {
        switch self {
        case .compositionTrackCreationFailed:
            return "Could not create an export composition track."
        case .exportSessionCreationFailed:
            return "Could not create an AVAsset export session."
        case .noExportableMedia:
            return "The project does not contain exportable media."
        }
    }
}

private extension ExportResolution {
    var renderSize: CGSize {
        switch self {
        case .p720:
            return CGSize(width: 1280, height: 720)
        case .p1080:
            return CGSize(width: 1920, height: 1080)
        case .p4K:
            return CGSize(width: 3840, height: 2160)
        }
    }
}

private extension ExportFrameRate {
    var framesPerSecond: Int32 {
        switch self {
        case .fps24:
            return 24
        case .fps30:
            return 30
        case .fps60:
            return 60
        }
    }
}
