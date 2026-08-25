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
    @ObservationIgnored private var activeOutputURL: URL?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    /// RENDER-01: the single render plan BOTH the preview and the export
    /// consume — one composition (durations, speed, ramps, freeze, reverse)
    /// and one videoComposition (per-clip effects through the custom
    /// compositor). The preview used to build its own simpler composition and
    /// post-filter single-clip frames, so ramps, reverse, masks, blend modes,
    /// multi-track compositing, text, and stickers never matched the export.
    struct IOSRenderPlan {
        let composition: AVMutableComposition
        let videoComposition: AVVideoComposition?
    }

    /// Builds the shared render plan. Throws when the project has no
    /// exportable media (preview callers treat that as "nothing to play").
    func makeRenderPlan(for project: Project) async throws -> IOSRenderPlan {
        let composition = try await makeComposition(for: project)
        // A video track whose sources carry no embedded audio leaves an
        // EMPTY audio composition track — the export session fails with
        // AVErrorOperationNotSupported for media-less tracks (caught by
        // the output golden tests with a video-only fixture). A fresh
        // empty track's timeRange is INVALID (not zero), so validity is
        // part of the predicate.
        for track in composition.tracks
        where !track.timeRange.isValid || track.timeRange.duration <= .zero {
            try? composition.removeTrack(track)
        }
        guard !composition.tracks.isEmpty else {
            throw IOSExportEngineError.noExportableMedia
        }

        // CANVAS-01: the videoComposition is ALWAYS attached. Its renderSize
        // comes from the project canvas — without it, a project whose only
        // change was the canvas (16:9 source → 9:16/1:1) exported at the
        // source's natural size, silently ignoring the ratio. The compositor
        // also carries canvas backgrounds, so both are now guaranteed.
        let videoComposition = makeVideoComposition(for: project, composition: composition)
        return IOSRenderPlan(composition: composition, videoComposition: videoComposition)
    }

    @discardableResult
    func exportProject(_ project: Project) async throws -> URL {
        guard !isExporting else {
            throw IOSExportEngineError.exportAlreadyInProgress
        }

        isExporting = true
        exportProgress = 0
        lastExportURL = nil

        do {
            let plan = try await makeRenderPlan(for: project)
            let composition = plan.composition
            let shouldUseCustomCompositor = plan.videoComposition != nil
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
            activeOutputURL = outputURL
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mov
            exportSession.shouldOptimizeForNetworkUse = true
            if let videoComposition = plan.videoComposition {
                exportSession.videoComposition = videoComposition
            }
            activeExportSession = exportSession
            startProgressPolling()

            try await AVExportCompatibility.export(.init(exportSession), to: outputURL, as: .mov)
            exportProgress = 1
            lastExportURL = outputURL
            finishExport()
            activeOutputURL = nil
            return outputURL
        } catch {
            removePartialOutput()
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
        // UX-REC-01: a cancelled export leaves a truncated .mov at the output
        // — remove it so the user never shares a broken artifact. The
        // in-flight export call also fails into the catch path, which removes
        // again (idempotent).
        removePartialOutput()
    }

    /// Removes a partial output file left behind by a cancelled or failed
    /// export (Mac-parity with ExportEngine.removePartialOutput). Best-effort:
    /// cleanup failures must not mask the original export error.
    private func removePartialOutput() {
        guard let url = activeOutputURL else { return }
        try? FileManager.default.removeItem(at: url)
        activeOutputURL = nil
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

    /// Internal (not private) so the app-hosted iOS unit tests can pin the
    /// gate — the isBackgroundRemoved omission here was a silent no-op bug
    /// until W5 caught it.
    func needsCustomCompositor(for project: Project) -> Bool {
        // G-03: adjustment layers only render through the custom compositor.
        let hasAdjustmentLayer = project.timeline.tracks
            .flatMap(\.clips)
            .contains { $0.isAdjustmentLayer }
        if hasAdjustmentLayer { return true }
        return project.timeline.tracks.contains { track in
            track.clips.contains { clip in clipRequiresCustomCompositor(clip) }
        }
    }

    /// Per-clip compositor triggers, kept macOS-parity complete: without the
    /// gate, the listed feature silently no-ops on export (the W5 background-
    /// removal regression was exactly this class of gap).
    private func clipRequiresCustomCompositor(_ clip: Clip) -> Bool {
        if clip.colorCorrection != nil { return true }
        if clip.colorGrade != nil { return true }
        if !clip.effects.isEmpty { return true }
        if clip.mask != nil { return true }
        if clip.chromaKey != nil { return true }
        if clip.chromaKeyColor != nil { return true }
        if clip.textContent != nil { return true }
        if clip.isBackgroundRemoved { return true }
        if clip.blendMode != .normal { return true }
        if clip.cropRect != nil { return true }
        // BUG-IOS-03: a clip whose only edit is a transform or opacity change
        // must still render through the custom compositor — the plain path
        // drops both.
        if clip.transform != ClipTransform() { return true }
        if clip.opacity != 1 { return true }
        // Keyframed properties and G-24 stabilization render inside the
        // custom compositor.
        if !clip.keyframes.isEmpty { return true }
        if clip.stabilization != nil { return true }
        return false
    }

    /// G-25 Inc 9 audio solo: true when some audio-capable track is soloed
    /// and this track is not — the track's audio must be silenced (visuals
    /// are unaffected). Mirrors AudioGraphTrackBus.solo semantics.
    private func audioSoloSuppresses(_ track: Track, in project: Project) -> Bool {
        guard project.timeline.tracks.contains(where: { $0.isSolo && $0.kind != .text }) else {
            return false
        }
        return !track.isSolo
    }

    private func makeVideoComposition(
        for project: Project,
        composition: AVMutableComposition
    ) -> AVVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        // G-03: the timeline's adjustment clips (bottom-track-first).
        let adjustmentVideoTracks = project.timeline.tracks.filter { $0.kind == .video }
        let adjustmentClips: [Clip] = adjustmentVideoTracks
            .sorted { $0.zIndex < $1.zIndex }
            .flatMap(\.clips)
            .filter(\.isAdjustmentLayer)
        let canvasSize = project.canvas.size
        let renderSize = canvasSize.width > 0 && canvasSize.height > 0
            ? canvasSize
            : CGSize(width: 1920, height: 1080)

        videoComposition.renderSize = renderSize
        // Frame rate follows the PROJECT's export settings — a hard-coded 30
        // silently re-timed 24/60fps projects.
        let fps: Int
        switch project.exportSettings.frameRate {
        case .fps24: fps = 24
        case .fps30: fps = 30
        case .fps60: fps = 60
        }
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
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

                if !timelineTrack.isMuted, !audioSoloSuppresses(timelineTrack, in: project) {
                    trackIDComposition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )
                }
            case .audio:
                let playableClips = timelineTrack.clips.filter { $0.kind == .audio || $0.kind == .video }
                guard !timelineTrack.isMuted, !playableClips.isEmpty,
                      !audioSoloSuppresses(timelineTrack, in: project) else { continue }
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
                    .filter({ $0.kind == .video && $0.isAdjustmentLayer == false })
                    .sorted(by: { $0.timelineRange.start < $1.timelineRange.start }) {
                    let timeRange = CMTimeRange(
                        start: cmTime(clip.timelineRange.start),
                        duration: cmTime(clip.timelineRange.duration)
                    )

                    // BUG-IOS-08: composition source frames arrive in STORAGE
                    // orientation — the compositor orients them upright via
                    // this transform before the canvas fit (Mac BUG-07 parity;
                    // the composition track carries the same pt only as output
                    // metadata for external players).
                    let sourcePreferredTransform = composition.track(
                        withTrackID: trackID
                    )?.preferredTransform ?? .identity

                    // BUG-08: a plain clip with no visual edits must still
                    // produce an effect — without it the track never joins
                    // `instruction.clipEffects` and the compositor drops the
                    // layer beneath an overlay (Mac has passed the same flag
                    // since its code-review #7; iOS was missing it).
                    guard let clipEffect = CustomCompositionClipEffect(
                        trackID: trackID,
                        timeRange: timeRange,
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
                        isBackgroundRemoved: clip.isBackgroundRemoved,
                        blendMode: clip.blendMode,
                        cropRect: clip.cropRect,
                        stabilization: clip.stabilization,
                        sourcePreferredTransform: sourcePreferredTransform,
                        includeIdentitySource: true
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
                        colorGrade: clip.colorGrade,
                        chromaKey: clip.chromaKey,
                        chromaKeyColor: clip.chromaKeyColor,
                        chromaKeyThreshold: clip.chromaKeyThreshold,
                        mask: clip.mask,
                        effects: clip.effects,
                        textContent: exportTextContent,
                        stickerEmoji: stickerEmoji,
                        stickerFontSize: stickerFontSize,
                        isBackgroundRemoved: clip.isBackgroundRemoved,
                        blendMode: clip.blendMode
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

        var instructions: [CustomCompositionInstruction] = []
        for (start, end) in zip(sortedBoundaries, sortedBoundaries.dropFirst()) {
            guard end > start else { continue }

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

            instructions.append(
                CustomCompositionInstruction(
                    timeRange: segmentRange,
                    trackIDs: videoTrackIDs,
                    clipEffects: activeClipEffects,
                    canvasBackground: project.canvasBackground,
                    adjustmentClips: adjustmentClips.isEmpty ? nil : adjustmentClips
                )
            )
        }

        videoComposition.instructions = instructions.isEmpty
            ? [
                CustomCompositionInstruction(
                    timeRange: CMTimeRange(start: .zero, duration: duration),
                    trackIDs: videoTrackIDs,
                    clipEffects: clipEffects,
                    canvasBackground: project.canvasBackground,
                    adjustmentClips: adjustmentClips.isEmpty ? nil : adjustmentClips
                )
            ]
            : instructions

        return videoComposition
    }

    private func stickerEmoji(from textContent: TextClipContent) -> String? {
        StickerDetection.stickerEmoji(from: textContent)
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
        let compositionAudioTrack = (timelineTrack.isMuted
            || audioSoloSuppresses(timelineTrack, in: project)) ? nil : composition.addMutableTrack(
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
        guard !timelineTrack.isMuted, !audioSoloSuppresses(timelineTrack, in: project) else { return }

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
        // Step 7: handle reverse by substituting a pre-rendered reversed asset
        // (same pattern as macOS ExportEngine). The reversed asset's time 0
        // corresponds to the original sourceRange.end.
        let effectiveAsset: AVURLAsset
        let effectiveSourceStart: TimeInterval
        if clip.isReversed, mediaType == .video {
            // A failed reverse render must FAIL the export with a reason —
            // silently exporting the clip forward mislabels the output.
            effectiveAsset = AVURLAsset(url: try await renderReversedAsset(for: clip, from: asset))
            effectiveSourceStart = 0
        } else {
            effectiveAsset = asset
            effectiveSourceStart = clip.sourceRange.start
        }

        guard let sourceTrack = try await effectiveAsset.loadTracks(withMediaType: mediaType).first else {
            return
        }

        guard var sourceTimeRange = sourceTimeRange(for: clip) else {
            return
        }
        if clip.isReversed {
            // Reversed asset starts at 0; remap the source range.
            sourceTimeRange = CMTimeRange(
                start: cmTime(effectiveSourceStart),
                duration: sourceTimeRange.duration
            )
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

        // Step 7: freeze-frame handling. A tiny source range held over a long
        // timeline span stretches the single frame across the timeline duration.
        let isFreezeFrame = clip.sourceRange.duration < 0.1 && clip.timelineRange.duration > 0.5
        if isFreezeFrame {
            // Insert a minimal source window, then scale it to the timeline duration.
            let minimalSource = CMTimeRange(
                start: sourceTimeRange.start,
                duration: cmTime(0.04)
            )
            try compositionTrack.insertTimeRange(minimalSource, of: sourceTrack, at: cursor)
            // Scale the INSERTED window (macOS parity): scaling a range that
            // already has the target duration is a no-op and left the frozen
            // frame at 0.04s with a gap after it.
            let insertedWindow = CMTimeRange(start: cursor, duration: minimalSource.duration)
            compositionTrack.scaleTimeRange(insertedWindow, toDuration: cmTime(clip.timelineRange.duration))
            cursor = CMTimeAdd(cursor, cmTime(clip.timelineRange.duration))
            return
        }

        try compositionTrack.insertTimeRange(sourceTimeRange, of: sourceTrack, at: cursor)

        // Step 7: constant-rate speed. Scale the inserted range by the rate so
        // a 2x clip plays in half the timeline time. Speed ramps (>= 2 points)
        // need segment-level scaling; that path is handled in
        // applySpeedRampIfNeeded below for clips with ramps.
        let hasRamp = clip.speedRampPoints.count >= 2
        if !hasRamp {
            let playbackRate = min(max(clip.playbackRate, 0.25), 4.0)
            if playbackRate != 1 {
                let scaledDuration = CMTime(seconds: sourceTimeRange.duration.seconds / playbackRate, preferredTimescale: 600)
                let insertedRange = CMTimeRange(start: cursor, duration: cmTime(sourceTimeRange.duration.seconds))
                compositionTrack.scaleTimeRange(insertedRange, toDuration: scaledDuration)
                cursor = CMTimeAdd(cursor, scaledDuration)
            } else {
                cursor = CMTimeAdd(cursor, sourceTimeRange.duration)
            }
        } else {
            // Speed ramp: scale per-segment using the ramp curve (macOS pattern).
            cursor = try await applySpeedRamp(clip, sourceTrack: sourceTrack, sourceTimeRange: sourceTimeRange, into: compositionTrack, cursor: cursor)
        }
    }

    /// Renders a reversed copy of the clip's source range (video only).
    /// Throws on failure — the caller must not silently fall back to forward.
    /// Mirrors macOS ReverseRenderService usage.
    private func renderReversedAsset(for clip: Clip, from asset: AVURLAsset) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutiOSReverse-\(clip.id.uuidString)-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        do {
            let reversedService = ReverseRenderService()
            try await reversedService.renderReversed(
                clip: asset,
                timeRange: CMTimeRange(
                    start: cmTime(clip.sourceRange.start),
                    duration: cmTime(clip.sourceRange.duration)
                ),
                outputURL: outputURL,
                progress: { _ in }
            )
            return outputURL
        } catch {
            // Surface the underlying failure instead of exporting forward.
            throw error
        }
    }

    /// Applies a speed ramp by walking the curve's segments and scaling each
    /// portion of the inserted range. Mirrors macOS ExportEngine.applySpeedRamp.
    private func applySpeedRamp(
        _ clip: Clip,
        sourceTrack: AVAssetTrack,
        sourceTimeRange: CMTimeRange,
        into compositionTrack: AVMutableCompositionTrack,
        cursor: CMTime
    ) async throws -> CMTime {
        let curve = SpeedRampCurve(points: clip.speedRampPoints)
        let sourceDuration = clip.sourceRange.duration
        let destinationTime = cursor

        // Collect normalized boundary times: ramp points + 0 and 1.
        var boundaries: [TimeInterval] = [0]
        for point in clip.speedRampPoints where point.time > 0 && point.time < 1 {
            // Avoid duplicates near 0/1.
            if boundaries.allSatisfy({ abs($0 - point.time) > 1e-9 }) {
                boundaries.append(point.time)
            }
        }
        if !boundaries.contains(where: { abs($0 - 1) < 1e-9 }) {
            boundaries.append(1)
        }
        boundaries.sort()

        var accumulatedOutput: TimeInterval = 0
        var startRate = clip.speedRampPoints.first(where: { $0.time <= 0 })?.rate ?? (clip.speedRampPoints.first?.rate ?? 1)

        for i in 0..<(boundaries.count - 1) {
            let segStart = boundaries[i]
            let segEnd = boundaries[i + 1]
            let endRate = clip.speedRampPoints
                .filter { abs($0.time - segEnd) < 1e-9 }
                .last?.rate ?? startRate

            let outputSegmentStart = curve.timeMapping(sourceTime: segStart) * sourceDuration
            let outputSegmentEnd = curve.timeMapping(sourceTime: segEnd) * sourceDuration
            let outputSegmentDuration = max(outputSegmentEnd - outputSegmentStart, 1.0 / 600.0)

            let sourceSegmentDuration = (segEnd - segStart) * sourceDuration

            // Scale the ALREADY-inserted base range segment (macOS parity).
            // Re-inserting the segment on top of the base insertion duplicated
            // the media: every ramp clip rendered its content twice.
            let segDestination = CMTimeAdd(destinationTime, cmTime(accumulatedOutput))
            let scaledRange = CMTimeRange(start: segDestination, duration: cmTime(sourceSegmentDuration))
            compositionTrack.scaleTimeRange(scaledRange, toDuration: cmTime(outputSegmentDuration))

            accumulatedOutput += outputSegmentDuration
            startRate = endRate
        }

        return CMTimeAdd(destinationTime, cmTime(accumulatedOutput))
    }

    private func sourceTimeRange(for clip: Clip) -> CMTimeRange? {
        // The FULL source span (macOS parity). The previous
        // min(timelineRange.duration) clamp truncated the source to the
        // already speed-adjusted timeline length BEFORE dividing by the
        // playback rate — every constant-rate clip was shortened twice.
        let sourceDuration = max(clip.sourceRange.duration, 0)

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
