import AVFoundation
import AppKit
import Foundation
import ImageIO
import MovieCutCore
import Observation
import QuartzCore
import UniformTypeIdentifiers

@MainActor
@Observable
final class ExportEngine {
    var isExporting = false
    var exportProgress: Double = 0
    var exportError: String?
    var lastExportURL: URL?

    /// Legacy UI mirrors. Export behavior is driven by Project.exportSettings.
    var exportResolution: String = "1080p"
    var exportQuality: String = "high"
    var exportFormat: String = "mp4"
    var backgroundRemovedClipIds: Set<UUID> = []

    @ObservationIgnored private var activeExportSession: AVAssetExportSession?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    private static let maximumOpticalFlowFrameRate: Int32 = 120

    /// Centralized export decision engine: render size, explicit bitrate, codec
    /// profile, file type, and writer output settings (see `MovieCutCore.ExportPlanner`).
    @ObservationIgnored private let exportPlanner = ExportPlanner()

    @discardableResult
    func export(project: Project, to url: URL, audioProcessing: ClipAudioProcessingOptions = ClipAudioProcessingOptions()) async throws -> URL {
        if shouldWriteChapterMetadata(for: project) {
            return try await exportVideoWithExplicitBitrate(project: project, to: url, audioProcessing: audioProcessing)
        }

        isExporting = true
        exportProgress = 0
        exportError = nil
        lastExportURL = nil

        do {
            let exportPackage = try await makeExportPackage(for: project, audioProcessing: audioProcessing)
            defer { removeTemporaryRenderURLs(exportPackage.temporaryRenderURLs) }
            guard !exportPackage.composition.tracks.isEmpty else {
                throw ExportEngineError.noExportableMedia
            }

            let presetName = presetName(for: project.exportSettings)
            guard let exportSession = AVAssetExportSession(asset: exportPackage.composition, presetName: presetName) else {
                throw ExportEngineError.exportSessionCreationFailed
            }

            configureExportSession(exportSession, videoComposition: exportPackage.videoComposition, project: project)

            exportSession.videoComposition = exportPackage.videoComposition
            exportSession.audioMix = exportPackage.audioMix

            // Embed chapter metadata from timeline markers
            applyChapterMetadata(to: exportSession, project: project)

            activeExportSession = exportSession
            startProgressPolling()

            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }

            let fileType = outputFileType(for: url, settings: project.exportSettings, supportedFileTypes: exportSession.supportedFileTypes)
            try await exportSession.export(to: url, as: fileType)
            exportProgress = 1
            lastExportURL = url
            finishExport()
            return url
        } catch {
            exportError = error.localizedDescription
            finishExport()
            throw error
        }
    }

    private func configureExportSession(
        _ exportSession: AVAssetExportSession,
        videoComposition: AVMutableVideoComposition?,
        project: Project
    ) {
        if let videoComp = videoComposition {
            let resolvedSize = renderSize(for: project.exportSettings.resolution, canvas: project.canvas)
            videoComp.renderSize = resolvedSize
        }

        applyBitrateFileLengthLimit(exportSession, project: project)
    }

    /// Embeds timeline markers as QuickTime chapter metadata on the exported file.
    private func applyChapterMetadata(to exportSession: AVAssetExportSession, project: Project) {
        guard project.exportSettings.includeChapters else { return }
        let chapterGroups = chapterMetadataGroups(for: project)
        guard !chapterGroups.isEmpty else { return }
        exportSession.metadata = chapterGroups.flatMap { $0.items }
    }

    private func shouldWriteChapterMetadata(for project: Project) -> Bool {
        project.exportSettings.includeChapters && !chapterMetadataGroups(for: project).isEmpty
    }

    private func chapterMetadataGroups(for project: Project) -> [AVTimedMetadataGroup] {
        guard project.exportSettings.includeChapters else { return [] }

        var markers = project.markers.filter { $0.kind == .standard }
        if project.exportSettings.includeBeatChapters {
            markers += project.markers.filter { $0.kind == .beat }
        }

        let totalDuration = max(project.timeline.duration, 0.1)
        let sortedMarkers = markers
            .filter { $0.time.isFinite && $0.time >= 0 && $0.time < totalDuration }
            .sorted { $0.time < $1.time }
        guard !sortedMarkers.isEmpty else { return [] }

        return sortedMarkers.enumerated().map { index, marker in
            let start = marker.time
            let end = index + 1 < sortedMarkers.count ? sortedMarkers[index + 1].time : totalDuration
            let duration = max(end - start, 0.1)

            let item = AVMutableMetadataItem()
            item.identifier = .quickTimeMetadataTitle
            item.value = (marker.name.isEmpty ? "Chapter \(index + 1)" : marker.name) as NSString
            item.extendedLanguageTag = "en"
            item.dataType = kCMMetadataBaseDataType_UTF8 as String

            let timeRange = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                duration: CMTime(seconds: duration, preferredTimescale: 600)
            )
            return AVTimedMetadataGroup(items: [item], timeRange: timeRange)
        }
    }

    private func applyBitrateFileLengthLimit(_ exportSession: AVAssetExportSession, project: Project) {
        let duration = project.timeline.duration
        let targetVideoBitrate = bitrateForQuality(project.exportSettings)
        guard duration.isFinite, duration > 0, targetVideoBitrate > 0 else {
            return
        }

        let audioBitrate = estimatedAudioBitrateBitsPerSecond(for: project.exportSettings.audioCodec)
        let targetBits = Double(targetVideoBitrate + audioBitrate) * duration

        // AVAssetExportSession preset exports do not expose a direct averageVideoBitRate knob.
        // fileLengthLimit is the available AVFoundation constraint here, so this applies the
        // selected target bitrate approximately while the chosen preset still controls encoding.
        exportSession.fileLengthLimit = Int64((targetBits / 8.0 * 1.05).rounded(.up))
    }

    private func makeExportPackage(
        for project: Project,
        audioProcessing: ClipAudioProcessingOptions = ClipAudioProcessingOptions()
    ) async throws -> ExportPackage {
        let composition = AVMutableComposition()
        var videoCompositionTracks: [AVCompositionTrack] = []
        var videoClipInstructions: [ExportClipInstructionMetadata] = []
        var audioMixInputParameters: [AVMutableAudioMixInputParameters] = []
        var temporaryEqualizedAudioURLs: [URL] = []
        var temporaryOpticalFlowURLs: [URL] = []
        var temporaryImageRenderURLs: [URL] = []
        var shouldKeepTemporaryEqualizedAudioURLs = false
        defer {
            if !shouldKeepTemporaryEqualizedAudioURLs {
                removeTemporaryRenderURLs(temporaryEqualizedAudioURLs)
            }
        }

        func applyAudioVolumeAndFades(
            for clip: Clip,
            audioParameters: AVMutableAudioMixInputParameters,
            destinationTime: CMTime,
            clipDuration: CMTime
        ) {
            let volume = Float(min(max(clip.volume, 0), 2))
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

        for track in project.timeline.tracks where !track.isMuted {
            if track.kind == .text {
                for clip in track.clips {
                    guard let textContent = clip.textContent else {
                        continue
                    }

                    let stickerImageURL = stickerImageURL(from: textContent)
                    let stickerEmoji = stickerImageURL == nil ? stickerEmoji(from: textContent) : nil
                    let exportTextContent = stickerEmoji == nil && stickerImageURL == nil ? textContent : nil
                    let stickerFontSize = stickerEmoji == nil && stickerImageURL == nil ? nil : CGFloat(textContent.fontSize)
                    let destinationTime = CMTime(seconds: clip.timelineRange.start, preferredTimescale: 600)
                    let clipDuration = CMTime(seconds: clip.timelineRange.duration, preferredTimescale: 600)
                    videoClipInstructions.append(ExportClipInstructionMetadata(
                        clipID: clip.id,
                        timelineTrackID: track.id,
                        trackID: kCMPersistentTrackID_Invalid,
                        timeRange: CMTimeRange(start: destinationTime, duration: clipDuration),
                        transform: clip.transform,
                        opacity: clip.opacity,
                        transition: nil,
                        mask: clip.mask,
                        colorCorrection: clip.colorCorrection,
                        colorGrade: clip.colorGrade,
                        chromaKey: clip.chromaKey,
                        chromaKeyColor: clip.chromaKeyColor,
                        chromaKeyThreshold: clip.chromaKeyThreshold,
                        effects: clip.effects,
                        textContent: exportTextContent,
                        stickerEmoji: stickerEmoji,
                        stickerFallbackText: stickerImageURL == nil ? nil : textContent.text,
                        stickerImageURL: stickerImageURL,
                        stickerFontSize: stickerFontSize,
                        keyframes: clip.keyframes,
                        isBackgroundRemoved: clip.isBackgroundRemoved || backgroundRemovedClipIds.contains(clip.id)
                    ))
                }

                continue
            }

            guard let mediaType = mediaType(for: track.kind) else { continue }

            var destinationTrack: AVMutableCompositionTrack?
            var videoDestinationTracksBySlot: [Int: AVMutableCompositionTrack] = [:]
            let audioParameters = AVMutableAudioMixInputParameters()

            let sortedClips = track.clips.sorted { $0.timelineRange.start < $1.timelineRange.start }

            for (clipIndex, clip) in sortedClips.enumerated() {
                guard let assetId = clip.assetId,
                      let mediaAsset = project.mediaLibrary.assets[assetId] else {
                    continue
                }

                // Denoised video audio is imported as a new audio MediaAsset and added as
                // an audio-track clip, so using this clip's asset URL preserves that source.
                var sourceAsset = AVURLAsset(url: mediaAsset.originalURL)
                var sourceTrack: AVAssetTrack
                if mediaType == .video, mediaAsset.kind == .image {
                    let renderDuration = max(clip.sourceRange.duration, clip.timelineRange.duration, 5)
                    let imageVideoURL = temporaryImageRenderURL(for: clip)
                    try await ImageVideoRenderService().render(
                        imageURL: mediaAsset.originalURL,
                        duration: renderDuration,
                        renderSize: renderSize(for: project.exportSettings.resolution, canvas: project.canvas),
                        outputURL: imageVideoURL
                    )
                    temporaryImageRenderURLs.append(imageVideoURL)
                    sourceAsset = AVURLAsset(url: imageVideoURL)
                    guard let renderedTrack = try await sourceAsset.loadTracks(withMediaType: .video).first else {
                        throw ExportEngineError.exportSessionCreationFailed
                    }
                    sourceTrack = renderedTrack
                } else {
                    guard let loadedTrack = try await sourceAsset.loadTracks(withMediaType: mediaType).first else {
                        continue
                    }
                    sourceTrack = loadedTrack
                }
                if mediaType == .audio,
                   let preset = clip.resolvedEqualizerPreset(fallback: audioProcessing.eqPresets[clip.id]) {
                    let rendered = try await equalizedAudioAsset(
                        for: clip,
                        mediaAsset: mediaAsset,
                        preset: preset,
                        temporaryURLs: &temporaryEqualizedAudioURLs
                    )
                    sourceAsset = rendered.asset
                    sourceTrack = rendered.track
                }

                let compositionTrack: AVMutableCompositionTrack
                if mediaType == .video {
                    let trackSlot = clipIndex % 2
                    if let existingTrack = videoDestinationTracksBySlot[trackSlot] {
                        compositionTrack = existingTrack
                    } else {
                        guard let createdTrack = composition.addMutableTrack(
                            withMediaType: mediaType,
                            preferredTrackID: kCMPersistentTrackID_Invalid
                        ) else {
                            throw ExportEngineError.compositionTrackCreationFailed
                        }
                        createdTrack.preferredTransform = try await sourceTrack.load(.preferredTransform)
                        videoDestinationTracksBySlot[trackSlot] = createdTrack
                        videoCompositionTracks.append(createdTrack)
                        compositionTrack = createdTrack
                    }
                } else if let destinationTrack {
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

                    if mediaType == .audio {
                        audioParameters.trackID = createdTrack.trackID
                    }
                }

                // Transition overlap: when previous clip has a transition, overlap by transition duration
                var adjustedTimelineStart = clip.timelineRange.start
                if clipIndex > 0 {
                    let previousClip = sortedClips[clipIndex - 1]
                    if let transition = previousClip.transition, transition.duration > 0 {
                        adjustedTimelineStart = max(0, adjustedTimelineStart - transition.duration)
                    }
                }

                let sourceTimeRange = CMTimeRange(
                    start: CMTime(seconds: clip.sourceRange.start, preferredTimescale: 600),
                    duration: CMTime(seconds: clip.sourceRange.duration, preferredTimescale: 600)
                )
                let playbackRate = min(max(clip.playbackRate, 0.25), 4.0)

                // Freeze frame: very short sourceRange but long timelineRange
                let isFreezeFrame = clip.sourceRange.duration < 0.1 && clip.timelineRange.duration > 0.5
                let shouldRenderOpticalFlowSlowMotion = mediaType == .video
                    && clip.useOpticalFlow
                    && playbackRate < 1.0
                    && clip.speedRampPoints.count < 2
                    && !clip.isReversed
                    && !isFreezeFrame

                var insertionSourceTimeRange = sourceTimeRange
                var didRenderOpticalFlowSlowMotion = false
                if shouldRenderOpticalFlowSlowMotion {
                    let opticalFlowURL = temporaryOpticalFlowRenderURL(for: clip)
                    try await MotionAwareSlowMotionRenderService().renderSlowMotion(
                        asset: sourceAsset,
                        track: sourceTrack,
                        timeRange: sourceTimeRange,
                        playbackRate: playbackRate,
                        targetFrameRate: Self.maximumOpticalFlowFrameRate,
                        outputURL: opticalFlowURL
                    )

                    let interpolatedAsset = AVURLAsset(url: opticalFlowURL)
                    guard let interpolatedTrack = try await interpolatedAsset.loadTracks(withMediaType: .video).first else {
                        throw ExportEngineError.exportSessionCreationFailed
                    }
                    temporaryOpticalFlowURLs.append(opticalFlowURL)
                    sourceAsset = interpolatedAsset
                    sourceTrack = interpolatedTrack
                    insertionSourceTimeRange = CMTimeRange(
                        start: .zero,
                        duration: CMTime(seconds: clip.sourceRange.duration / playbackRate, preferredTimescale: 600)
                    )
                    didRenderOpticalFlowSlowMotion = true
                }

                let destinationTime: CMTime
                let clipDuration: CMTime

                if isFreezeFrame && mediaType == .video {
                    let frozenSourceRange = try await freezeFrameSourceTimeRange(
                        for: sourceTrack,
                        requestedStart: sourceTimeRange.start
                    )
                    destinationTime = CMTime(seconds: adjustedTimelineStart, preferredTimescale: 600)
                    clipDuration = CMTime(seconds: clip.timelineRange.duration, preferredTimescale: 600)

                    try compositionTrack.insertTimeRange(frozenSourceRange, of: sourceTrack, at: destinationTime)

                    let insertedRange = CMTimeRange(start: destinationTime, duration: frozenSourceRange.duration)
                    compositionTrack.scaleTimeRange(insertedRange, toDuration: clipDuration)
                } else {
                    destinationTime = CMTime(seconds: adjustedTimelineStart, preferredTimescale: 600)
                    clipDuration = CMTime(seconds: clip.timelineRange.duration, preferredTimescale: 600)

                    try compositionTrack.insertTimeRange(insertionSourceTimeRange, of: sourceTrack, at: destinationTime)
                }

                var effectiveSourceTrack = sourceTrack
                var effectiveSourceTimeRange = insertionSourceTimeRange
                var clipCompositionDuration = isFreezeFrame ? clipDuration : insertionSourceTimeRange.duration

                if clip.isReversed, mediaType == .video, !isFreezeFrame {
                    let reversedOutputURL = temporaryReverseRenderURL(for: clip)
                    try await ReverseRenderService().renderReversed(
                        clip: sourceAsset,
                        timeRange: sourceTimeRange,
                        outputURL: reversedOutputURL,
                        progress: { @Sendable _ in }
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
                if clip.speedRampPoints.count >= 2, !isFreezeFrame {
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

                if playbackRate != 1, !didApplySpeedRamp, !isFreezeFrame, !didRenderOpticalFlowSlowMotion {
                    let scaledDuration = CMTime(seconds: clip.sourceRange.duration / playbackRate, preferredTimescale: 600)
                    let insertedRange = CMTimeRange(start: destinationTime, duration: clipCompositionDuration)
                    compositionTrack.scaleTimeRange(insertedRange, toDuration: scaledDuration)
                    clipCompositionDuration = scaledDuration
                }

                if mediaType == .video {
                    videoClipInstructions.append(ExportClipInstructionMetadata(
                        clipID: clip.id,
                        timelineTrackID: track.id,
                        trackID: compositionTrack.trackID,
                        timeRange: CMTimeRange(start: destinationTime, duration: clipCompositionDuration),
                        transform: clip.transform,
                        opacity: clip.opacity,
                        transition: clip.transition,
                        mask: clip.mask,
                        colorCorrection: clip.colorCorrection,
                        colorGrade: clip.colorGrade,
                        chromaKey: clip.chromaKey,
                        chromaKeyColor: clip.chromaKeyColor,
                        chromaKeyThreshold: clip.chromaKeyThreshold,
                        effects: clip.effects,
                        keyframes: clip.keyframes,
                        isBackgroundRemoved: clip.isBackgroundRemoved || backgroundRemovedClipIds.contains(clip.id),
                        useOpticalFlow: clip.useOpticalFlow,
                        playbackRate: playbackRate
                    ))
                }

                if mediaType == .audio {
                    applyAudioVolumeAndFades(
                        for: clip,
                        audioParameters: audioParameters,
                        destinationTime: destinationTime,
                        clipDuration: clipCompositionDuration
                    )
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
            canvas: project.canvas,
            exportSettings: project.exportSettings,
            canvasBackground: project.canvasBackground
        )
        let audioMix = makeAudioMix(parameters: audioMixInputParameters)

        shouldKeepTemporaryEqualizedAudioURLs = true
        return ExportPackage(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix,
            temporaryRenderURLs: temporaryEqualizedAudioURLs + temporaryOpticalFlowURLs + temporaryImageRenderURLs
        )
    }

    private func makeVideoComposition(
        tracks: [AVCompositionTrack],
        clips: [ExportClipInstructionMetadata],
        duration: CMTime,
        canvas: CanvasPreset,
        exportSettings: ExportSettings,
        canvasBackground: CanvasBackground? = nil
    ) -> AVMutableVideoComposition? {
        guard !tracks.isEmpty else { return nil }

        let videoComposition = AVMutableVideoComposition()

        let resolvedSize = renderSize(for: exportSettings.resolution, canvas: canvas)
        let renderFrameRate = videoCompositionFrameRate(for: exportSettings, clips: clips)
        videoComposition.renderSize = resolvedSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(renderFrameRate))
        if clips.contains(where: \.usesOpticalFlowSlowMotion) {
            videoComposition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
        }

        let transitionEffects = makeTransitionEffects(from: clips)
        let usesCustomVideoCompositor = clips.contains { clip in
            clip.colorCorrection != nil
                || clip.colorGrade != nil
                || clip.textContent != nil
                || clip.stickerEmoji != nil
                || clip.stickerImageURL != nil
                || clip.chromaKey != nil
                || clip.chromaKeyColor != nil
                || clip.mask != nil
                || !clip.keyframes.isEmpty
                || !clip.effects.isEmpty
                || clip.isBackgroundRemoved
        } || !transitionEffects.isEmpty
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstructions = tracks.map { AVMutableVideoCompositionLayerInstruction(assetTrack: $0) }
        instruction.layerInstructions = layerInstructions

        let layerInstructionsByTrackID = Dictionary(
            uniqueKeysWithValues: zip(tracks.map(\.trackID), layerInstructions)
        )
        var customCompositorClips: [ExportClipInstructionMetadata] = []

        for clip in clips {
            if clip.textContent != nil || clip.stickerEmoji != nil || clip.stickerImageURL != nil {
                customCompositorClips.append(clip)
                continue
            }

            guard let layerInstruction = layerInstructionsByTrackID[clip.trackID] else {
                continue
            }

            if !isIdentityTransform(clip.transform) {
                layerInstruction.setTransform(
                    affineTransform(for: clip.transform, canvasSize: resolvedSize),
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

            if let transition = clip.transition, transition.duration > 0 {
                guard !transition.type.requiresTwoSourcePixelProcessing else {
                    continue
                }

                let overlapDuration = transition.duration
                let overlapStart = CMTimeAdd(
                    clip.timeRange.start,
                    CMTime(seconds: clip.timeRange.duration.seconds - overlapDuration, preferredTimescale: 600)
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
                        translationX: -CGFloat(clip.timeRange.duration.seconds) * 100,
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

            if clip.requiresCustomVideoCompositorMetadata {
                customCompositorClips.append(clip)
            }
        }

        if usesCustomVideoCompositor {
            videoComposition.customVideoCompositorClass = CustomVideoCompositor.self
            videoComposition.instructions = [
                CustomCompositionInstruction(
                    timeRange: CMTimeRange(start: .zero, duration: duration),
                    trackIDs: tracks.map(\.trackID),
                    clipEffects: clips.compactMap { clip in
                        CustomCompositionClipEffect(
                            trackID: clip.trackID,
                            timeRange: clip.timeRange,
                            transform: clip.transform,
                            opacity: clip.opacity,
                            keyframes: clip.keyframes,
                            colorCorrection: clip.colorCorrection,
                            colorGrade: clip.colorGrade,
                            chromaKey: clip.chromaKey,
                            chromaKeyColor: clip.chromaKeyColor,
                            chromaKeyThreshold: clip.chromaKeyThreshold,
                            mask: clip.mask,
                            effects: clip.effects,
                            textContent: clip.textContent,
                            stickerEmoji: clip.stickerEmoji,
                            stickerFallbackText: clip.stickerFallbackText,
                            stickerImageURL: clip.stickerImageURL,
                            stickerFontSize: clip.stickerFontSize,
                            isBackgroundRemoved: clip.isBackgroundRemoved
                        )
                    },
                    transitionEffects: transitionEffects,
                    canvasBackground: canvasBackground
                )
            ]
        } else {
            videoComposition.instructions = [instruction]
            videoComposition.animationTool = makeCustomVideoCompositorInstruction(
                tracks: tracks,
                clips: customCompositorClips,
                canvas: canvas
            )
        }

        return videoComposition
    }

    private func makeTransitionEffects(
        from clips: [ExportClipInstructionMetadata]
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

    private func videoCompositionFrameRate(
        for exportSettings: ExportSettings,
        clips: [ExportClipInstructionMetadata]
    ) -> Int32 {
        let baseFrameRate = exportSettings.frameRate.framesPerSecond
        guard let slowestOpticalFlowRate = clips.compactMap(\.opticalFlowSlowMotionRate).min() else {
            return baseFrameRate
        }

        let targetFrameRate = Int32((Double(baseFrameRate) / slowestOpticalFlowRate).rounded(.up))
        return min(max(baseFrameRate, targetFrameRate), Self.maximumOpticalFlowFrameRate)
    }

    private func makeCustomVideoCompositorInstruction(
        tracks: [AVCompositionTrack],
        clips: [ExportClipInstructionMetadata],
        canvas: CanvasPreset
    ) -> AVVideoCompositionCoreAnimationTool? {
        _ = tracks
        let parentLayer = CALayer()
        let videoLayer = CALayer()
        parentLayer.frame = CGRect(x: 0, y: 0, width: canvas.size.width, height: canvas.size.height)
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
            if let animation = textContent.animation {
                TextAnimationRenderer.applyCoreAnimation(
                    animation,
                    to: textLayer,
                    canvasSize: canvas.size,
                    fontSize: fontSize,
                    text: textContent.text,
                    beginTime: AVCoreAnimationBeginTimeAtZero + beginTime
                )
            }
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

    private func temporaryEqualizedAudioURL(for clip: Clip) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutEQ-\(clip.id.uuidString)-\(UUID().uuidString)")
            .appendingPathExtension("caf")
    }

    private func temporaryOpticalFlowRenderURL(for clip: Clip) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutOpticalFlow-\(clip.id.uuidString)-\(UUID().uuidString)")
            .appendingPathExtension("mov")
    }

    private func temporaryImageRenderURL(for clip: Clip) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutImage-\(clip.id.uuidString)-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
    }

    private func equalizedAudioAsset(
        for clip: Clip,
        mediaAsset: MediaAsset,
        preset: EqualizerPreset,
        temporaryURLs: inout [URL]
    ) async throws -> (asset: AVURLAsset, track: AVAssetTrack) {
        let outputURL = temporaryEqualizedAudioURL(for: clip)
        try await AudioEqualizerService().apply(
            preset: preset,
            inputURL: mediaAsset.originalURL,
            outputURL: outputURL
        )

        let asset = AVURLAsset(url: outputURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ExportEngineError.exportSessionCreationFailed
        }

        temporaryURLs.append(outputURL)
        return (asset, track)
    }

    private func removeTemporaryRenderURLs(_ urls: [URL]) {
        let fileManager = FileManager.default
        for url in urls where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
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

    private func freezeFrameSourceTimeRange(
        for sourceTrack: AVAssetTrack,
        requestedStart: CMTime
    ) async throws -> CMTimeRange {
        let trackTimeRange = try await sourceTrack.load(.timeRange)
        let minFrameDuration = try await sourceTrack.load(.minFrameDuration)
        let fallbackFrameDuration = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        let frameDuration = minFrameDuration.isValid && minFrameDuration > .zero
            ? minFrameDuration
            : fallbackFrameDuration

        let trackEnd = CMTimeAdd(trackTimeRange.start, trackTimeRange.duration)
        guard trackTimeRange.duration > .zero, trackEnd > trackTimeRange.start else {
            return CMTimeRange(start: requestedStart, duration: frameDuration)
        }

        let latestStart = CMTimeSubtract(trackEnd, frameDuration)
        let lowerBound = trackTimeRange.start
        let upperBound = latestStart >= lowerBound ? latestStart : lowerBound
        let clampedStart = min(max(requestedStart, lowerBound), upperBound)
        let clampedDuration = min(frameDuration, CMTimeSubtract(trackEnd, clampedStart))

        return CMTimeRange(start: clampedStart, duration: clampedDuration > .zero ? clampedDuration : frameDuration)
    }

    private func stickerEmoji(from textContent: TextClipContent) -> String? {
        guard textContent.isSticker || isLegacyStickerContent(textContent) else {
            return nil
        }

        let trimmedText = textContent.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSingleEmoji(trimmedText) else {
            return nil
        }

        return trimmedText
    }

    private func stickerImageURL(from textContent: TextClipContent) -> URL? {
        guard textContent.isSticker else {
            return nil
        }

        return textContent.stickerImageURL
    }

    private func isLegacyStickerContent(_ textContent: TextClipContent) -> Bool {
        textContent.fontFamily == "Apple Color Emoji"
    }

    private func isSingleEmoji(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }

        let variationSelector = "\u{FE0F}"
        let zeroWidthJoiner = "\u{200D}"
        let emojiAtom = "(?:\\p{Emoji_Presentation}|\\p{Extended_Pictographic}\(variationSelector)?)(?:\\p{Emoji_Modifier})?"
        let pattern = "^(?:(?:\\p{Regional_Indicator}{2})|\(emojiAtom))(?:\(zeroWidthJoiner)\(emojiAtom))*$"
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text.count == 1 && text.unicodeScalars.contains { scalar in
                scalar.properties.isEmojiPresentation
            }
        }

        return regex.firstMatch(in: text, range: range)?.range == range
    }

    // MARK: - Export Preset Helpers

    private func renderSize(for resolution: ExportResolution, canvas: CanvasPreset) -> CGSize {
        let shortEdge: CGFloat
        switch resolution {
        case .p4K:
            shortEdge = 2160
        case .p1080:
            shortEdge = 1080
        case .p720:
            shortEdge = 720
        }

        let canvasSize = canvas.size
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return CGSize(width: shortEdge * 16 / 9, height: shortEdge)
        }

        let aspectRatio = canvasSize.width / canvasSize.height
        guard aspectRatio.isFinite, aspectRatio > 0 else {
            return CGSize(width: shortEdge * 16 / 9, height: shortEdge)
        }

        if aspectRatio >= 1 {
            return CGSize(width: evenDimension(shortEdge * aspectRatio), height: evenDimension(shortEdge))
        }

        return CGSize(width: evenDimension(shortEdge), height: evenDimension(shortEdge / aspectRatio))
    }

    private func evenDimension(_ value: CGFloat) -> CGFloat {
        let rounded = max(2, Int(value.rounded()))
        return CGFloat(rounded - (rounded % 2))
    }

    private func bitrateForQuality(_ settings: ExportSettings) -> Int {
        guard let megabits = settings.resolvedVideoBitrateMbps, megabits > 0 else {
            return 0
        }

        return megabits * 1_000_000
    }

    private func estimatedAudioBitrateBitsPerSecond(for codec: MovieCutCore.AudioCodec) -> Int {
        switch codec {
        case .aac:
            return 192_000
        case .pcm:
            return 1_536_000
        }
    }

    // MARK: - Transform Helpers

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

    private func makeAudioMix(parameters: [AVMutableAudioMixInputParameters]) -> AVMutableAudioMix? {
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
        _ = url
        for fileType in fallbackFileTypes(for: settings) where supportedFileTypes.contains(fileType) {
            return fileType
        }

        return supportedFileTypes.first ?? .mov
    }

    private func fallbackFileTypes(for settings: ExportSettings) -> [AVFileType] {
        switch settings.containerFormat {
        case .mp4:
            return settings.codec == .hevc ? [.mp4, .mov, .m4v] : [.mp4, .m4v, .mov]
        case .mov:
            return [.mov, .mp4, .m4v]
        case .m4v:
            return [.m4v, .mp4, .mov]
        }
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

    // MARK: - Additional export kinds (ExportPlanner-backed)

    /// Exports the project's mixed audio as a standalone AAC `.m4a` file.
    ///
    /// Reuses the same composition/audio-mix builder as the video path so
    /// volume, fades, ducking, and EQ are preserved, then muxes audio only.
    @discardableResult
    func exportAudioOnly(
        project: Project,
        to url: URL,
        audioProcessing: ClipAudioProcessingOptions = ClipAudioProcessingOptions()
    ) async throws -> URL {
        isExporting = true
        exportProgress = 0
        exportError = nil
        lastExportURL = nil

        do {
            let exportPackage = try await makeExportPackage(for: project, audioProcessing: audioProcessing)
            defer { removeTemporaryRenderURLs(exportPackage.temporaryRenderURLs) }
            guard !exportPackage.composition.tracks(withMediaType: .audio).isEmpty else {
                throw ExportEngineError.noExportableMedia
            }
            guard let exportSession = AVAssetExportSession(
                asset: exportPackage.composition,
                presetName: AVAssetExportPresetAppleM4A
            ) else {
                throw ExportEngineError.exportSessionCreationFailed
            }

            exportSession.audioMix = exportPackage.audioMix
            activeExportSession = exportSession
            startProgressPolling()

            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }

            try await exportSession.export(to: url, as: .m4a)
            exportProgress = 1
            lastExportURL = url
            finishExport()
            return url
        } catch {
            exportError = error.localizedDescription
            finishExport()
            throw error
        }
    }

    /// Renders a single fully-composited still frame to a PNG at the requested
    /// timeline time. Effects, transforms, and overlays render through the same
    /// video composition used by export.
    @discardableResult
    func exportStillFrame(
        project: Project,
        at timeSeconds: Double,
        to url: URL,
        audioProcessing: ClipAudioProcessingOptions = ClipAudioProcessingOptions()
    ) async throws -> URL {
        let exportPackage = try await makeExportPackage(for: project, audioProcessing: audioProcessing)
        defer { removeTemporaryRenderURLs(exportPackage.temporaryRenderURLs) }
        guard !exportPackage.composition.tracks(withMediaType: .video).isEmpty else {
            throw ExportEngineError.noExportableMedia
        }

        let generator = AVAssetImageGenerator(asset: exportPackage.composition)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        if let videoComposition = exportPackage.videoComposition {
            generator.videoComposition = videoComposition
        }

        let clampedTime = min(max(timeSeconds, 0), max(project.timeline.duration, 0))
        let requestedTime = CMTime(seconds: clampedTime, preferredTimescale: 600)
        let cgImage = try generator.copyCGImage(at: requestedTime, actualTime: nil)

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try writeImage(cgImage, to: url, type: UTType.png)
        lastExportURL = url
        return url
    }

    /// Renders an animated GIF by sampling composited frames across the timeline.
    @discardableResult
    func exportAnimatedGIF(
        project: Project,
        to url: URL,
        frameRate: Int = 12,
        maxEdge: Int = 480,
        audioProcessing: ClipAudioProcessingOptions = ClipAudioProcessingOptions()
    ) async throws -> URL {
        isExporting = true
        exportProgress = 0
        exportError = nil
        lastExportURL = nil

        do {
            let plan = exportPlanner.plan(
                settings: project.exportSettings,
                canvas: project.canvas,
                mediaKind: .animatedGIF,
                options: ExportPlanOptions(gifFrameRate: frameRate, gifMaxEdge: maxEdge)
            )
            guard let gif = plan.gif else {
                throw ExportEngineError.exportSessionCreationFailed
            }

            let exportPackage = try await makeExportPackage(for: project, audioProcessing: audioProcessing)
            defer { removeTemporaryRenderURLs(exportPackage.temporaryRenderURLs) }
            let duration = project.timeline.duration
            guard duration > 0, !exportPackage.composition.tracks(withMediaType: .video).isEmpty else {
                throw ExportEngineError.noExportableMedia
            }

            let generator = AVAssetImageGenerator(asset: exportPackage.composition)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = CMTime(seconds: gif.frameDelaySeconds / 2, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: gif.frameDelaySeconds / 2, preferredTimescale: 600)
            generator.maximumSize = CGSize(width: gif.width, height: gif.height)
            if let videoComposition = exportPackage.videoComposition {
                generator.videoComposition = videoComposition
            }

            let frameCount = max(1, Int((duration * Double(gif.frameRate)).rounded(.down)))

            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.gif.identifier as CFString,
                frameCount,
                nil
            ) else {
                throw ExportEngineError.exportSessionCreationFailed
            }

            let fileProperties = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFLoopCount as String: gif.loopForever ? 0 : 1
                ]
            ] as CFDictionary
            CGImageDestinationSetProperties(destination, fileProperties)

            let frameProperties = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFDelayTime as String: gif.frameDelaySeconds
                ]
            ] as CFDictionary

            for frameIndex in 0..<frameCount {
                let time = CMTime(seconds: Double(frameIndex) / Double(gif.frameRate), preferredTimescale: 600)
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                CGImageDestinationAddImage(destination, cgImage, frameProperties)
                exportProgress = Double(frameIndex + 1) / Double(frameCount)
            }

            guard CGImageDestinationFinalize(destination) else {
                throw ExportEngineError.exportSessionCreationFailed
            }

            exportProgress = 1
            lastExportURL = url
            finishExport()
            return url
        } catch {
            exportError = error.localizedDescription
            finishExport()
            throw error
        }
    }

    /// Exports the project to a movie using an explicit average video bitrate.
    ///
    /// Unlike the preset-based `export(project:to:)` path, this drives an
    /// `AVAssetWriter` with the planner's resolved `outputSettings`, so the
    /// selected target bitrate (and ProRes mastering, when overridden) is
    /// applied precisely instead of being approximated by `fileLengthLimit`.
    @discardableResult
    func exportVideoWithExplicitBitrate(
        project: Project,
        to url: URL,
        profileOverride: VideoCompressionProfile? = nil,
        audioProcessing: ClipAudioProcessingOptions = ClipAudioProcessingOptions()
    ) async throws -> URL {
        isExporting = true
        exportProgress = 0
        exportError = nil
        lastExportURL = nil

        do {
            let exportPackage = try await makeExportPackage(for: project, audioProcessing: audioProcessing)
            defer { removeTemporaryRenderURLs(exportPackage.temporaryRenderURLs) }
            guard !exportPackage.composition.tracks.isEmpty else {
                throw ExportEngineError.noExportableMedia
            }

            let plan = exportPlanner.plan(
                settings: project.exportSettings,
                canvas: project.canvas,
                mediaKind: .video,
                options: ExportPlanOptions(videoProfileOverride: profileOverride)
            )
            guard let videoOutputSettings = exportPlanner.assetWriterVideoOutputSettings(for: plan) else {
                throw ExportEngineError.exportSessionCreationFailed
            }

            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }

            let fileType: AVFileType = plan.fileExtension == "mov" ? .mov : .mp4
            let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
            let reader = try AVAssetReader(asset: exportPackage.composition)
            let chapterGroups = chapterMetadataGroups(for: project)

            let videoTracks = exportPackage.composition.tracks(withMediaType: .video)
            var videoReaderOutput: AVAssetReaderVideoCompositionOutput?
            var writerVideoInput: AVAssetWriterInput?
            if !videoTracks.isEmpty {
                let readerPixelFormat = (plan.video?.profile.isHDR ?? false)
                    ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
                    : kCVPixelFormatType_32BGRA
                let readerOutput = AVAssetReaderVideoCompositionOutput(
                    videoTracks: videoTracks,
                    videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: readerPixelFormat]
                )
                readerOutput.alwaysCopiesSampleData = false
                if let videoComposition = exportPackage.videoComposition {
                    readerOutput.videoComposition = videoComposition
                } else {
                    readerOutput.videoComposition = makeDefaultVideoComposition(for: exportPackage.composition, project: project)
                }
                guard reader.canAdd(readerOutput) else {
                    throw ExportEngineError.exportSessionCreationFailed
                }
                reader.add(readerOutput)
                videoReaderOutput = readerOutput

                let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings)
                input.expectsMediaDataInRealTime = false
                guard writer.canAdd(input) else {
                    throw ExportEngineError.exportSessionCreationFailed
                }
                writer.add(input)
                writerVideoInput = input
            }

            let audioTracks = exportPackage.composition.tracks(withMediaType: .audio)
            var audioReaderOutput: AVAssetReaderAudioMixOutput?
            var writerAudioInput: AVAssetWriterInput?
            if !audioTracks.isEmpty, let audioOutputSettings = exportPlanner.assetWriterAudioOutputSettings(for: plan) {
                let readerOutput = AVAssetReaderAudioMixOutput(
                    audioTracks: audioTracks,
                    audioSettings: [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsNonInterleaved: false
                    ]
                )
                readerOutput.audioMix = exportPackage.audioMix
                if reader.canAdd(readerOutput) {
                    reader.add(readerOutput)
                    audioReaderOutput = readerOutput

                    let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings)
                    input.expectsMediaDataInRealTime = false
                    if writer.canAdd(input) {
                        writer.add(input)
                        writerAudioInput = input
                    }
                }
            }

            var metadataAdaptor: AVAssetWriterInputMetadataAdaptor?
            var metadataInput: AVAssetWriterInput?
            if let firstChapterGroup = chapterGroups.first,
               let formatDescription = firstChapterGroup.copyFormatDescription() {
                let input = AVAssetWriterInput(
                    mediaType: .metadata,
                    outputSettings: nil,
                    sourceFormatHint: formatDescription
                )
                input.expectsMediaDataInRealTime = false
                if writer.canAdd(input) {
                    writer.add(input)
                    if let writerVideoInput {
                        writerVideoInput.addTrackAssociation(withTrackOf: input, type: AVAssetTrack.AssociationType.chapterList.rawValue)
                    }
                    metadataInput = input
                    metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: input)
                }
            }

            guard reader.startReading() else {
                throw reader.error ?? ExportEngineError.exportSessionCreationFailed
            }
            guard writer.startWriting() else {
                throw writer.error ?? ExportEngineError.exportSessionCreationFailed
            }
            writer.startSession(atSourceTime: .zero)

            if let metadataAdaptor, let metadataInput {
                for chapterGroup in chapterGroups {
                    guard metadataAdaptor.append(chapterGroup) else {
                        throw writer.error ?? ExportEngineError.exportSessionCreationFailed
                    }
                }
                metadataInput.markAsFinished()
            }

            let totalDuration = max(project.timeline.duration, 1.0 / 600.0)
            if let writerVideoInput, let videoReaderOutput {
                try await pumpSamples(
                    output: UncheckedSendable(videoReaderOutput),
                    input: UncheckedSendable(writerVideoInput),
                    queueLabel: "moviecut.export.writer.video",
                    totalDuration: totalDuration,
                    reportsProgress: true
                )
            }
            if let writerAudioInput, let audioReaderOutput {
                try await pumpSamples(
                    output: UncheckedSendable(audioReaderOutput),
                    input: UncheckedSendable(writerAudioInput),
                    queueLabel: "moviecut.export.writer.audio",
                    totalDuration: totalDuration,
                    reportsProgress: false
                )
            }

            guard reader.status != .failed else {
                throw reader.error ?? ExportEngineError.exportSessionCreationFailed
            }

            await finishWriting(UncheckedSendable(writer))
            guard writer.status == .completed else {
                throw writer.error ?? ExportEngineError.exportSessionCreationFailed
            }

            exportProgress = 1
            lastExportURL = url
            finishExport()
            return url
        } catch {
            exportError = error.localizedDescription
            finishExport()
            throw error
        }
    }

    /// Streams sample buffers from a reader output into a writer input, driving
    /// the writer's pull model and updating progress from presentation time.
    ///
    /// AVFoundation reader outputs and writer inputs are not `Sendable`, but this
    /// pump owns them for the duration of the transfer and serializes all access
    /// through the writer's request queue, so they are passed in `@unchecked
    /// Sendable` boxes.
    private nonisolated func pumpSamples(
        output: UncheckedSendable<AVAssetReaderOutput>,
        input: UncheckedSendable<AVAssetWriterInput>,
        queueLabel: String,
        totalDuration: Double,
        reportsProgress: Bool
    ) async throws {
        let queue = DispatchQueue(label: queueLabel)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            input.value.requestMediaDataWhenReady(on: queue) { [weak self] in
                let writerInput = input.value
                let readerOutput = output.value
                while writerInput.isReadyForMoreMediaData {
                    guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                        writerInput.markAsFinished()
                        continuation.resume(returning: ())
                        return
                    }

                    if reportsProgress, totalDuration > 0 {
                        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                        if presentationTime.isFinite {
                            let progress = min(max(presentationTime / totalDuration, 0), 1)
                            Task { @MainActor [weak self] in
                                self?.exportProgress = progress
                            }
                        }
                    }

                    if !writerInput.append(sampleBuffer) {
                        continuation.resume(throwing: ExportEngineError.exportSessionCreationFailed)
                        return
                    }
                }
            }
        }
    }

    /// Awaits an `AVAssetWriter`'s completion handler. The writer is passed in an
    /// `@unchecked Sendable` box because it is not `Sendable` but is only touched
    /// from this single awaiting continuation.
    private nonisolated func finishWriting(_ writer: UncheckedSendable<AVAssetWriter>) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.value.finishWriting {
                continuation.resume(returning: ())
            }
        }
    }

    /// Builds a default video composition for the explicit-bitrate reader path
    /// when the export package has no custom composition (passthrough render).
    private func makeDefaultVideoComposition(
        for composition: AVComposition,
        project: Project
    ) -> AVMutableVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = exportPlanner.renderSize(for: project.exportSettings.resolution, canvas: project.canvas)
        videoComposition.frameDuration = CMTime(
            value: 1,
            timescale: CMTimeScale(project.exportSettings.frameRate.framesPerSecond)
        )

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        instruction.layerInstructions = composition.tracks(withMediaType: .video).map {
            AVMutableVideoCompositionLayerInstruction(assetTrack: $0)
        }
        videoComposition.instructions = [instruction]
        return videoComposition
    }

    /// Writes a single `CGImage` to disk as the supplied image type.
    private func writeImage(_ image: CGImage, to url: URL, type: UTType) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw ExportEngineError.exportSessionCreationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportEngineError.exportSessionCreationFailed
        }
    }

    func cancelExport() {
        activeExportSession?.cancelExport()
        progressTask?.cancel()
        activeExportSession = nil
        exportProgress = 0
        lastExportURL = nil
        isExporting = false
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
    var temporaryRenderURLs: [URL] = []
}

/// Carries a non-`Sendable` value across a concurrency boundary when the caller
/// guarantees exclusive, serialized access (used for AVFoundation reader/writer
/// objects in the explicit-bitrate export pump).
private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

@MainActor
private final class MotionAwareSlowMotionRenderService {
    private struct Frame {
        var width: Int
        var height: Int
        var data: [UInt8]
    }

    private struct Pixel {
        var b: Double
        var g: Double
        var r: Double
        var a: Double

        static let black = Pixel(b: 0, g: 0, r: 0, a: 255)
    }

    private struct ForegroundStats {
        var count: Int
        var centroidX: Double
        var centroidY: Double
    }

    private struct MotionVector {
        var dx: Double
        var dy: Double
    }

    func renderSlowMotion(
        asset: AVAsset,
        track: AVAssetTrack,
        timeRange: CMTimeRange,
        playbackRate: Double,
        targetFrameRate: Int32,
        outputURL: URL
    ) async throws {
        let rate = min(max(playbackRate, 0.25), 1.0)
        let outputFPS = max(targetFrameRate, 1)
        let frames = try decodedFrames(from: asset, track: track, timeRange: timeRange)
        guard let firstFrame = frames.first else {
            throw MotionAwareSlowMotionRenderError.noFrames
        }

        let sourceDuration = timeRange.duration.seconds.isFinite && timeRange.duration.seconds > 0
            ? timeRange.duration.seconds
            : Double(frames.count) / 30.0
        let outputDuration = sourceDuration / rate
        let outputFrameCount = max(1, Int((outputDuration * Double(outputFPS)).rounded()))
        let sourceFPS = Double(frames.count) / max(sourceDuration, 1.0 / 600.0)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: firstFrame.width,
                AVVideoHeightKey: firstFrame.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoExpectedSourceFrameRateKey: Int(outputFPS),
                    AVVideoAverageBitRateKey: max(firstFrame.width * firstFrame.height * 24, 2_000_000)
                ]
            ]
        )
        writerInput.expectsMediaDataInRealTime = false
        writerInput.mediaTimeScale = CMTimeScale(outputFPS)

        guard writer.canAdd(writerInput) else {
            throw MotionAwareSlowMotionRenderError.cannotAddWriterInput
        }
        writer.add(writerInput)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: firstFrame.width,
                kCVPixelBufferHeightKey as String: firstFrame.height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        do {
            guard writer.startWriting() else {
                throw writer.error ?? MotionAwareSlowMotionRenderError.writerFailed
            }
            writer.startSession(atSourceTime: .zero)

            for outputIndex in 0..<outputFrameCount {
                try Task.checkCancellation()
                try await Self.waitForWriterInput(writerInput, writer: writer)

                let outputTime = Double(outputIndex) / Double(outputFPS)
                let sourceFramePosition = min(
                    max(outputTime * rate * sourceFPS, 0),
                    Double(max(frames.count - 1, 0))
                )
                let frame = Self.frame(at: sourceFramePosition, in: frames)
                let pixelBuffer = try Self.pixelBuffer(from: frame)
                let presentationTime = CMTime(value: CMTimeValue(outputIndex), timescale: CMTimeScale(outputFPS))

                guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                    throw writer.error ?? MotionAwareSlowMotionRenderError.appendFailed
                }
            }

            writerInput.markAsFinished()
            await Self.finishWriting(writer)

            switch writer.status {
            case .completed:
                break
            case .cancelled:
                throw CancellationError()
            case .failed:
                throw writer.error ?? MotionAwareSlowMotionRenderError.writerFailed
            default:
                break
            }
        } catch {
            writer.cancelWriting()
            throw error
        }
    }

    private func decodedFrames(
        from asset: AVAsset,
        track: AVAssetTrack,
        timeRange: CMTimeRange
    ) throws -> [Frame] {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = timeRange
        let readerOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
        )
        readerOutput.alwaysCopiesSampleData = false

        guard reader.canAdd(readerOutput) else {
            throw MotionAwareSlowMotionRenderError.cannotAddReaderOutput
        }
        reader.add(readerOutput)

        guard reader.startReading() else {
            throw reader.error ?? MotionAwareSlowMotionRenderError.readerFailed
        }

        var frames: [Frame] = []
        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }
            frames.append(try Self.copyFrame(from: pixelBuffer))
        }

        switch reader.status {
        case .completed:
            return frames
        case .cancelled:
            throw CancellationError()
        case .failed:
            throw reader.error ?? MotionAwareSlowMotionRenderError.readerFailed
        default:
            return frames
        }
    }

    private static func frame(at sourceFramePosition: Double, in frames: [Frame]) -> Frame {
        guard frames.count > 1 else {
            return frames[0]
        }

        let lowerIndex = min(max(Int(floor(sourceFramePosition)), 0), frames.count - 1)
        let upperIndex = min(lowerIndex + 1, frames.count - 1)
        let fraction = min(max(sourceFramePosition - Double(lowerIndex), 0), 1)

        guard lowerIndex != upperIndex, fraction > 1.0e-9 else {
            return frames[lowerIndex]
        }

        let previous = frames[lowerIndex]
        let next = frames[upperIndex]
        let vector = motionVector(from: previous, to: next)
        return motionCompensatedFrame(from: previous, to: next, fraction: fraction, vector: vector)
    }

    private static func motionVector(from previous: Frame, to next: Frame) -> MotionVector {
        if let previousStats = foregroundStats(in: previous),
           let nextStats = foregroundStats(in: next),
           previousStats.count > 24,
           nextStats.count > 24 {
            return MotionVector(
                dx: nextStats.centroidX - previousStats.centroidX,
                dy: nextStats.centroidY - previousStats.centroidY
            )
        }

        return blockMotionVector(from: previous, to: next)
    }

    private static func foregroundStats(in frame: Frame) -> ForegroundStats? {
        var count = 0
        var sumX = 0.0
        var sumY = 0.0

        for y in 0..<frame.height {
            let row = y * frame.width * 4
            for x in 0..<frame.width {
                let offset = row + x * 4
                let luma = luminance(
                    b: Double(frame.data[offset]),
                    g: Double(frame.data[offset + 1]),
                    r: Double(frame.data[offset + 2])
                )
                guard luma > 32 else { continue }
                count += 1
                sumX += Double(x)
                sumY += Double(y)
            }
        }

        guard count > 0 else { return nil }
        return ForegroundStats(
            count: count,
            centroidX: sumX / Double(count),
            centroidY: sumY / Double(count)
        )
    }

    private static func blockMotionVector(from previous: Frame, to next: Frame) -> MotionVector {
        let maxSearch = 24
        let sampleStride = 8
        var samplePoints: [(x: Int, y: Int)] = []

        for y in stride(from: sampleStride, to: previous.height - sampleStride, by: sampleStride) {
            for x in stride(from: sampleStride, to: previous.width - sampleStride, by: sampleStride) {
                let previousLuma = luma(atX: x, y: y, in: previous)
                let nextLuma = luma(atX: x, y: y, in: next)
                if previousLuma > 24 || nextLuma > 24 || abs(previousLuma - nextLuma) > 16 {
                    samplePoints.append((x, y))
                }
            }
        }

        guard !samplePoints.isEmpty else {
            return MotionVector(dx: 0, dy: 0)
        }

        var bestVector = MotionVector(dx: 0, dy: 0)
        var bestScore = Double.greatestFiniteMagnitude

        for dy in stride(from: -maxSearch, through: maxSearch, by: 2) {
            for dx in stride(from: -maxSearch, through: maxSearch, by: 2) {
                var score = 0.0
                var compared = 0
                for point in samplePoints {
                    let shiftedX = point.x + dx
                    let shiftedY = point.y + dy
                    guard shiftedX >= 0,
                          shiftedX < next.width,
                          shiftedY >= 0,
                          shiftedY < next.height else {
                        continue
                    }
                    score += abs(luma(atX: point.x, y: point.y, in: previous) - luma(atX: shiftedX, y: shiftedY, in: next))
                    compared += 1
                }

                guard compared > 0 else { continue }
                let normalizedScore = score / Double(compared)
                if normalizedScore < bestScore {
                    bestScore = normalizedScore
                    bestVector = MotionVector(dx: Double(dx), dy: Double(dy))
                }
            }
        }

        return bestVector
    }

    private static func motionCompensatedFrame(
        from previous: Frame,
        to next: Frame,
        fraction: Double,
        vector: MotionVector
    ) -> Frame {
        guard previous.width == next.width, previous.height == next.height else {
            return previous
        }

        let width = previous.width
        let height = previous.height
        let clampedFraction = min(max(fraction, 0), 1)
        var output = [UInt8](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let xf = Double(x)
                let yf = Double(y)
                let movedPrevious = sample(
                    previous,
                    x: xf - vector.dx * clampedFraction,
                    y: yf - vector.dy * clampedFraction
                )
                let movedNext = sample(
                    next,
                    x: xf + vector.dx * (1.0 - clampedFraction),
                    y: yf + vector.dy * (1.0 - clampedFraction)
                )
                let previousAlpha = foregroundAlpha(movedPrevious)
                let nextAlpha = foregroundAlpha(movedNext)
                let pixel: Pixel

                if previousAlpha + nextAlpha > 0.01 {
                    let previousWeight = previousAlpha * (1.0 - clampedFraction)
                    let nextWeight = nextAlpha * clampedFraction
                    let denominator = max(previousWeight + nextWeight, 1.0e-6)
                    pixel = Pixel(
                        b: (movedPrevious.b * previousWeight + movedNext.b * nextWeight) / denominator,
                        g: (movedPrevious.g * previousWeight + movedNext.g * nextWeight) / denominator,
                        r: (movedPrevious.r * previousWeight + movedNext.r * nextWeight) / denominator,
                        a: 255
                    )
                } else {
                    pixel = backgroundPixel(
                        previous: sample(previous, x: xf, y: yf),
                        next: sample(next, x: xf, y: yf),
                        fraction: clampedFraction
                    )
                }

                let offset = (y * width + x) * 4
                output[offset] = UInt8(min(max(pixel.b.rounded(), 0), 255))
                output[offset + 1] = UInt8(min(max(pixel.g.rounded(), 0), 255))
                output[offset + 2] = UInt8(min(max(pixel.r.rounded(), 0), 255))
                output[offset + 3] = 255
            }
        }

        return Frame(width: width, height: height, data: output)
    }

    private static func backgroundPixel(previous: Pixel, next: Pixel, fraction: Double) -> Pixel {
        if foregroundAlpha(previous) > 0.05 || foregroundAlpha(next) > 0.05 {
            return Pixel(
                b: min(previous.b, next.b),
                g: min(previous.g, next.g),
                r: min(previous.r, next.r),
                a: 255
            )
        }

        return Pixel(
            b: previous.b * (1.0 - fraction) + next.b * fraction,
            g: previous.g * (1.0 - fraction) + next.g * fraction,
            r: previous.r * (1.0 - fraction) + next.r * fraction,
            a: 255
        )
    }

    private static func foregroundAlpha(_ pixel: Pixel) -> Double {
        min(max((luminance(b: pixel.b, g: pixel.g, r: pixel.r) - 12.0) / 80.0, 0), 1)
    }

    private static func sample(_ frame: Frame, x: Double, y: Double) -> Pixel {
        guard x >= 0,
              y >= 0,
              x <= Double(frame.width - 1),
              y <= Double(frame.height - 1) else {
            return .black
        }

        let x0 = min(max(Int(floor(x)), 0), frame.width - 1)
        let y0 = min(max(Int(floor(y)), 0), frame.height - 1)
        let x1 = min(x0 + 1, frame.width - 1)
        let y1 = min(y0 + 1, frame.height - 1)
        let tx = x - Double(x0)
        let ty = y - Double(y0)

        let p00 = pixel(atX: x0, y: y0, in: frame)
        let p10 = pixel(atX: x1, y: y0, in: frame)
        let p01 = pixel(atX: x0, y: y1, in: frame)
        let p11 = pixel(atX: x1, y: y1, in: frame)

        return Pixel(
            b: bilinear(p00.b, p10.b, p01.b, p11.b, tx: tx, ty: ty),
            g: bilinear(p00.g, p10.g, p01.g, p11.g, tx: tx, ty: ty),
            r: bilinear(p00.r, p10.r, p01.r, p11.r, tx: tx, ty: ty),
            a: 255
        )
    }

    private static func bilinear(_ p00: Double, _ p10: Double, _ p01: Double, _ p11: Double, tx: Double, ty: Double) -> Double {
        let top = p00 * (1.0 - tx) + p10 * tx
        let bottom = p01 * (1.0 - tx) + p11 * tx
        return top * (1.0 - ty) + bottom * ty
    }

    private static func pixel(atX x: Int, y: Int, in frame: Frame) -> Pixel {
        let offset = (y * frame.width + x) * 4
        return Pixel(
            b: Double(frame.data[offset]),
            g: Double(frame.data[offset + 1]),
            r: Double(frame.data[offset + 2]),
            a: Double(frame.data[offset + 3])
        )
    }

    private static func luma(atX x: Int, y: Int, in frame: Frame) -> Double {
        let offset = (y * frame.width + x) * 4
        return luminance(
            b: Double(frame.data[offset]),
            g: Double(frame.data[offset + 1]),
            r: Double(frame.data[offset + 2])
        )
    }

    private static func luminance(b: Double, g: Double, r: Double) -> Double {
        0.114 * b + 0.587 * g + 0.299 * r
    }

    private static func copyFrame(from pixelBuffer: CVPixelBuffer) throws -> Frame {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw MotionAwareSlowMotionRenderError.pixelBufferUnavailable
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytesPerOutputRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerOutputRow * height)

        data.withUnsafeMutableBytes { destination in
            guard let destinationBaseAddress = destination.baseAddress else { return }
            for y in 0..<height {
                memcpy(
                    destinationBaseAddress.advanced(by: y * bytesPerOutputRow),
                    baseAddress.advanced(by: y * bytesPerRow),
                    bytesPerOutputRow
                )
            }
        }

        return Frame(width: width, height: height, data: data)
    }

    private static func pixelBuffer(from frame: Frame) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: frame.width,
            kCVPixelBufferHeightKey as String: frame.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            frame.width,
            frame.height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw MotionAwareSlowMotionRenderError.pixelBufferCreationFailed(status)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw MotionAwareSlowMotionRenderError.pixelBufferUnavailable
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytesPerInputRow = frame.width * 4
        frame.data.withUnsafeBytes { source in
            guard let sourceBaseAddress = source.baseAddress else { return }
            for y in 0..<frame.height {
                memcpy(
                    baseAddress.advanced(by: y * bytesPerRow),
                    sourceBaseAddress.advanced(by: y * bytesPerInputRow),
                    bytesPerInputRow
                )
            }
        }

        return pixelBuffer
    }

    private static func waitForWriterInput(_ writerInput: AVAssetWriterInput, writer: AVAssetWriter) async throws {
        while !writerInput.isReadyForMoreMediaData {
            try Task.checkCancellation()

            switch writer.status {
            case .failed:
                throw writer.error ?? MotionAwareSlowMotionRenderError.writerFailed
            case .cancelled:
                throw CancellationError()
            default:
                break
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private static func finishWriting(_ writer: AVAssetWriter) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume(returning: ())
            }
        }
    }
}

private enum MotionAwareSlowMotionRenderError: LocalizedError {
    case appendFailed
    case cannotAddReaderOutput
    case cannotAddWriterInput
    case noFrames
    case pixelBufferCreationFailed(CVReturn)
    case pixelBufferUnavailable
    case readerFailed
    case writerFailed

    var errorDescription: String? {
        switch self {
        case .appendFailed:
            return "Could not append an interpolated slow-motion frame."
        case .cannotAddReaderOutput:
            return "Could not configure the slow-motion frame reader."
        case .cannotAddWriterInput:
            return "Could not configure the slow-motion frame writer."
        case .noFrames:
            return "No source frames were available for slow-motion interpolation."
        case .pixelBufferCreationFailed(let status):
            return "Could not create a slow-motion pixel buffer (\(status))."
        case .pixelBufferUnavailable:
            return "Could not access slow-motion pixel data."
        case .readerFailed:
            return "Could not read source frames for slow-motion interpolation."
        case .writerFailed:
            return "Could not write the interpolated slow-motion asset."
        }
    }
}

private struct ExportClipInstructionMetadata {
    var clipID: UUID
    var timelineTrackID: UUID
    var trackID: CMPersistentTrackID
    var timeRange: CMTimeRange
    var transform: ClipTransform
    var opacity: Double
    var transition: Transition?
    var mask: Mask?
    var colorCorrection: ColorCorrection?
    var colorGrade: ColorGrade?
    var chromaKey: ChromaKeySettings?
    var chromaKeyColor: SIMD3<Float>?
    var chromaKeyThreshold: Float = 0.3
    var effects: [Effect]
    var textContent: TextClipContent?
    var stickerEmoji: String? = nil
    var stickerFallbackText: String? = nil
    var stickerImageURL: URL? = nil
    var stickerFontSize: CGFloat? = nil
    var keyframes: [Keyframe]
    var isBackgroundRemoved: Bool
    var useOpticalFlow: Bool = false
    var playbackRate: Double = 1.0

    var usesOpticalFlowSlowMotion: Bool {
        opticalFlowSlowMotionRate != nil
    }

    var opticalFlowSlowMotionRate: Double? {
        guard useOpticalFlow, trackID != kCMPersistentTrackID_Invalid else { return nil }
        let rate = min(max(playbackRate, 0.25), 4.0)
        return rate < 1.0 ? rate : nil
    }

    var requiresCustomVideoCompositorMetadata: Bool {
        textContent != nil
            || stickerEmoji != nil
            || stickerImageURL != nil
            || mask != nil
            || colorCorrection != nil
            || colorGrade != nil
            || chromaKey != nil
            || chromaKeyColor != nil
            || !effects.isEmpty
            || isBackgroundRemoved
            || !keyframes.isEmpty
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
