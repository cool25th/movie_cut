#if os(iOS)
import AVFoundation
import Foundation
import MovieCutCore
import Observation

@MainActor
@Observable
final class IOSExportEngine {
    var isExporting = false
    var exportProgress: Double = 0
    var lastExportURL: URL?

    @ObservationIgnored private var activeExportSession: AVAssetExportSession?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    @discardableResult
    func exportProject(_ project: Project) async throws -> URL {
        guard !isExporting else {
            throw IOSExportEngineError.exportAlreadyInProgress
        }

        isExporting = true
        exportProgress = 0
        lastExportURL = nil

        do {
            let composition = try await makeComposition(for: project)
            guard !composition.tracks.isEmpty else {
                throw IOSExportEngineError.noExportableMedia
            }

            let shouldUseCustomCompositor = needsCustomCompositor(for: project)
            guard let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                throw IOSExportEngineError.exportSessionCreationFailed
            }

            guard exportSession.supportedFileTypes.contains(.mov) else {
                throw IOSExportEngineError.unsupportedOutputType
            }

            let outputURL = try makeOutputURL()
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mov
            exportSession.shouldOptimizeForNetworkUse = true
            if shouldUseCustomCompositor {
                exportSession.videoComposition = makeVideoComposition(for: project)
            }
            activeExportSession = exportSession
            startProgressPolling()

            try await exportSession.export(to: outputURL, as: .mov)
            exportProgress = 1
            lastExportURL = outputURL
            finishExport()
            return outputURL
        } catch {
            finishExport()
            throw error
        }
    }

    func cancelExport() {
        activeExportSession?.cancelExport()
        progressTask?.cancel()
        progressTask = nil
        activeExportSession = nil
        exportProgress = 0
        lastExportURL = nil
        isExporting = false
    }

    private func makeComposition(for project: Project) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()

        for timelineTrack in project.timeline.tracks.sorted(by: { $0.zIndex < $1.zIndex }) {
            switch timelineTrack.kind {
            case .video:
                try await insertVideoTrack(timelineTrack, from: project, into: composition)
            case .audio:
                try await insertAudioTrack(timelineTrack, from: project, into: composition)
            case .text:
                continue
            }
        }

        return composition
    }

    private func needsCustomCompositor(for project: Project) -> Bool {
        project.timeline.tracks.contains { track in
            track.clips.contains { clip in
                clip.colorCorrection != nil
                    || !clip.effects.isEmpty
                    || clip.mask != nil
                    || clip.chromaKey != nil
                    || clip.textContent != nil
            }
        }
    }

    private func makeVideoComposition(for project: Project) -> AVVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        let canvasSize = project.canvas.size
        let renderSize = canvasSize.width > 0 && canvasSize.height > 0
            ? canvasSize
            : CGSize(width: 1920, height: 1080)

        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.customVideoCompositorClass = CustomVideoCompositor.self

        let sortedTracks = project.timeline.tracks.sorted(by: { $0.zIndex < $1.zIndex })
        let trackIDComposition = AVMutableComposition()
        var videoTrackIDsByTrackID: [UUID: CMPersistentTrackID] = [:]

        for timelineTrack in sortedTracks {
            switch timelineTrack.kind {
            case .video:
                let playableClips = timelineTrack.clips.filter { $0.kind == .video }
                guard !playableClips.isEmpty else { continue }

                if !timelineTrack.isHidden,
                   let videoTrack = trackIDComposition.addMutableTrack(
                       withMediaType: .video,
                       preferredTrackID: kCMPersistentTrackID_Invalid
                   ) {
                    videoTrackIDsByTrackID[timelineTrack.id] = videoTrack.trackID
                }

                if !timelineTrack.isMuted {
                    trackIDComposition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )
                }
            case .audio:
                let playableClips = timelineTrack.clips.filter { $0.kind == .audio || $0.kind == .video }
                guard !timelineTrack.isMuted, !playableClips.isEmpty else { continue }
                trackIDComposition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
            case .text:
                continue
            }
        }

        var clipEffects: [CustomCompositionClipEffect] = []
        var videoTrackIDs: [CMPersistentTrackID] = []

        for timelineTrack in sortedTracks {
            switch timelineTrack.kind {
            case .video:
                guard let trackID = videoTrackIDsByTrackID[timelineTrack.id] else { continue }
                videoTrackIDs.append(trackID)

                for clip in timelineTrack.clips
                    .filter({ $0.kind == .video })
                    .sorted(by: { $0.timelineRange.start < $1.timelineRange.start }) {
                    let timeRange = CMTimeRange(
                        start: cmTime(clip.timelineRange.start),
                        duration: cmTime(clip.timelineRange.duration)
                    )

                    guard let clipEffect = CustomCompositionClipEffect(
                        trackID: trackID,
                        timeRange: timeRange,
                        transform: clip.transform,
                        opacity: clip.opacity,
                        keyframes: clip.keyframes,
                        colorCorrection: clip.colorCorrection,
                        chromaKeyColor: clip.chromaKeyColor,
                        chromaKeyThreshold: clip.chromaKeyThreshold,
                        mask: clip.mask,
                        effects: clip.effects,
                        textContent: clip.textContent,
                        isBackgroundRemoved: false
                    ) else {
                        continue
                    }

                    clipEffects.append(clipEffect)
                }
            case .text:
                guard !timelineTrack.isHidden else { continue }

                for clip in timelineTrack.clips
                    .filter({ $0.kind == .text })
                    .sorted(by: { $0.timelineRange.start < $1.timelineRange.start }) {
                    let timeRange = CMTimeRange(
                        start: cmTime(clip.timelineRange.start),
                        duration: cmTime(clip.timelineRange.duration)
                    )
                    let stickerEmoji = clip.textContent.flatMap(stickerEmoji(from:))
                    let exportTextContent = stickerEmoji == nil ? clip.textContent : nil
                    let stickerFontSize = stickerEmoji == nil ? nil : clip.textContent.map { CGFloat($0.fontSize) }

                    guard let clipEffect = CustomCompositionClipEffect(
                        trackID: kCMPersistentTrackID_Invalid,
                        timeRange: timeRange,
                        transform: clip.transform,
                        opacity: clip.opacity,
                        keyframes: clip.keyframes,
                        colorCorrection: clip.colorCorrection,
                        chromaKeyColor: clip.chromaKeyColor,
                        chromaKeyThreshold: clip.chromaKeyThreshold,
                        mask: clip.mask,
                        effects: clip.effects,
                        textContent: exportTextContent,
                        stickerEmoji: stickerEmoji,
                        stickerFontSize: stickerFontSize,
                        isBackgroundRemoved: false
                    ) else {
                        continue
                    }

                    clipEffects.append(clipEffect)
                }
            case .audio:
                continue
            }
        }

        let durationSeconds = max(project.timeline.duration, 0)
        let duration = cmTime(durationSeconds)
        var instructionBoundaries = [TimeInterval(0), durationSeconds]
        for clipEffect in clipEffects {
            let start = min(max(clipEffect.timeRange.start.seconds, 0), durationSeconds)
            let end = min(max(CMTimeAdd(clipEffect.timeRange.start, clipEffect.timeRange.duration).seconds, 0), durationSeconds)
            guard end > start else { continue }
            instructionBoundaries.append(start)
            instructionBoundaries.append(end)
        }

        let sortedBoundaries = instructionBoundaries
            .sorted()
            .reduce(into: [TimeInterval]()) { result, boundary in
                guard result.last.map({ abs($0 - boundary) > 1.0e-9 }) ?? true else {
                    return
                }
                result.append(boundary)
            }

        let instructions = zip(sortedBoundaries, sortedBoundaries.dropFirst()).compactMap { start, end in
            guard end > start else { return nil }

            let segmentStart = cmTime(start)
            let segmentEnd = cmTime(end)
            let segmentRange = CMTimeRange(
                start: segmentStart,
                duration: CMTimeSubtract(segmentEnd, segmentStart)
            )
            let activeClipEffects = clipEffects.filter { clipEffect in
                let clipEnd = CMTimeAdd(clipEffect.timeRange.start, clipEffect.timeRange.duration)
                return CMTimeCompare(clipEffect.timeRange.start, segmentEnd) < 0
                    && CMTimeCompare(clipEnd, segmentStart) > 0
            }

            return CustomCompositionInstruction(
                timeRange: segmentRange,
                trackIDs: videoTrackIDs,
                clipEffects: activeClipEffects
            )
        }

        videoComposition.instructions = instructions.isEmpty
            ? [
                CustomCompositionInstruction(
                    timeRange: CMTimeRange(start: .zero, duration: duration),
                    trackIDs: videoTrackIDs,
                    clipEffects: clipEffects
                )
            ]
            : instructions

        return videoComposition
    }

    private func stickerEmoji(from textContent: TextClipContent) -> String? {
        guard textContent.isSticker || textContent.fontFamily == "Apple Color Emoji" else {
            return nil
        }

        let trimmedText = textContent.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSingleEmoji(trimmedText) else {
            return nil
        }

        return trimmedText
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

    private func insertVideoTrack(
        _ timelineTrack: Track,
        from project: Project,
        into composition: AVMutableComposition
    ) async throws {
        let playableClips = timelineTrack.clips
            .filter { $0.kind == .video }
            .sorted { $0.timelineRange.start < $1.timelineRange.start }

        guard !playableClips.isEmpty else { return }

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

        for clip in playableClips {
            guard
                let assetId = clip.assetId,
                let mediaAsset = project.mediaLibrary.assets[assetId]
            else { continue }

            let asset = AVURLAsset(url: mediaAsset.originalURL)

            if let compositionVideoTrack, !timelineTrack.isHidden {
                try await insertClip(
                    clip,
                    mediaType: .video,
                    from: asset,
                    into: compositionVideoTrack,
                    cursor: &videoCursor
                )
            }

            if let compositionAudioTrack, !timelineTrack.isMuted {
                try await insertClip(
                    clip,
                    mediaType: .audio,
                    from: asset,
                    into: compositionAudioTrack,
                    cursor: &audioCursor
                )
            }
        }
    }

    private func insertAudioTrack(
        _ timelineTrack: Track,
        from project: Project,
        into composition: AVMutableComposition
    ) async throws {
        guard !timelineTrack.isMuted else { return }

        let playableClips = timelineTrack.clips
            .filter { $0.kind == .audio || $0.kind == .video }
            .sorted { $0.timelineRange.start < $1.timelineRange.start }

        guard
            !playableClips.isEmpty,
            let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else { return }

        var audioCursor = CMTime.zero

        for clip in playableClips {
            guard
                let assetId = clip.assetId,
                let mediaAsset = project.mediaLibrary.assets[assetId]
            else { continue }

            let asset = AVURLAsset(url: mediaAsset.originalURL)
            try await insertClip(
                clip,
                mediaType: .audio,
                from: asset,
                into: compositionAudioTrack,
                cursor: &audioCursor
            )
        }
    }

    private func insertClip(
        _ clip: Clip,
        mediaType: AVMediaType,
        from asset: AVURLAsset,
        into compositionTrack: AVMutableCompositionTrack,
        cursor: inout CMTime
    ) async throws {
        guard let sourceTrack = try await asset.loadTracks(withMediaType: mediaType).first else {
            return
        }

        guard let sourceTimeRange = sourceTimeRange(for: clip) else {
            return
        }

        let timelineStart = cmTime(clip.timelineRange.start)
        guard CMTimeCompare(timelineStart, cursor) >= 0 else {
            return
        }

        if CMTimeCompare(cursor, timelineStart) < 0 {
            let gap = CMTimeSubtract(timelineStart, cursor)
            compositionTrack.insertEmptyTimeRange(CMTimeRange(start: cursor, duration: gap))
            cursor = timelineStart
        }

        if mediaType == .video, compositionTrack.preferredTransform == .identity {
            compositionTrack.preferredTransform = try await sourceTrack.load(.preferredTransform)
        }

        try compositionTrack.insertTimeRange(sourceTimeRange, of: sourceTrack, at: cursor)
        cursor = CMTimeAdd(cursor, sourceTimeRange.duration)
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

    private func makeOutputURL() throws -> URL {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutiOSExports", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let outputURL = folderURL
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        return outputURL
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

    private func cmTime(_ seconds: TimeInterval) -> CMTime {
        CMTime(seconds: max(0, seconds.isFinite ? seconds : 0), preferredTimescale: 600)
    }
}

private enum IOSExportEngineError: LocalizedError {
    case exportAlreadyInProgress
    case noExportableMedia
    case exportSessionCreationFailed
    case unsupportedOutputType

    var errorDescription: String? {
        switch self {
        case .exportAlreadyInProgress:
            "An export is already in progress."
        case .noExportableMedia:
            "The timeline does not contain exportable media."
        case .exportSessionCreationFailed:
            "MovieCut could not create an export session for this project."
        case .unsupportedOutputType:
            "The export session does not support QuickTime movie output."
        }
    }
}
#endif
