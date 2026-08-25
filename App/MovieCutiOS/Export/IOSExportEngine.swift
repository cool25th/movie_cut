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
    /// G-15: temp segments backing image clips in the CURRENT render plan.
    @ObservationIgnored private var imageRenderURLs: [URL] = []

    /// RENDER-01: the single render plan BOTH the preview and the export
    /// consume — one composition (durations, speed, ramps, freeze, reverse)
    /// and one videoComposition (per-clip effects through the custom
    /// compositor). The preview used to build its own simpler composition and
    /// post-filter single-clip frames, so ramps, reverse, masks, blend modes,
    /// multi-track compositing, text, and stickers never matched the export.
    struct IOSRenderPlan {
        let composition: AVMutableComposition
        let videoComposition: AVVideoComposition?
        /// BUG-IOS-10: volume/fade ramps for BOTH the preview player and the
        /// export session. Nil when no clip carries audio edits.
        let audioMix: AVMutableAudioMix?
    }

    /// Builds the shared render plan. Throws when the project has no
    /// exportable media (preview callers treat that as "nothing to play").
    func makeRenderPlan(for project: Project) async throws -> IOSRenderPlan {
        // G-15: image clips pre-render into temp video segments. Drop the
        // PREVIOUS plan's segments first so repeated preview rebuilds don't
        // accumulate — the newest plan owns the live set (plans start on the
        // main actor, so a segment list only ever contains finished plans).
        removeTemporaryImageRenders()
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
        // BUG-IOS-10: audio edits ride the same plan the preview consumes.
        let audioMix = makeAudioMix(from: audioMixEntries, composition: composition)
        audioMixEntries.removeAll()
        return IOSRenderPlan(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix
        )
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
            // BUG-IOS-10: volume/fades reach the exported file.
            exportSession.audioMix = plan.audioMix
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
        // BUG-IOS-09: one entry per minted VIDEO track for the timeline track —
        // transition tracks mint two (alternating slots). The allocation order
        // mirrors insertVideoTrack exactly so the IDs match the real
        // composition's.
        var videoTrackIDsByTrackID: [UUID: [CMPersistentTrackID]] = [:]

        for timelineTrack in sortedTracks {
            switch timelineTrack.kind {
            case .video:
                let playableClips = timelineTrack.clips
                    .filter { ($0.kind == .video || $0.kind == .image) && $0.isAdjustmentLayer == false }
                guard !playableClips.isEmpty else { continue }
                let slotCount = Self.transitionSlotCount(for: playableClips)

                if !timelineTrack.isHidden {
                    var mintedTrackIDs: [CMPersistentTrackID] = []
                    for _ in 0..<slotCount {
                        if let videoTrack = trackIDComposition.addMutableTrack(
                            withMediaType: .video,
                            preferredTrackID: kCMPersistentTrackID_Invalid
                        ) {
                            mintedTrackIDs.append(videoTrack.trackID)
                        }
                    }
                    if !mintedTrackIDs.isEmpty {
                        videoTrackIDsByTrackID[timelineTrack.id] = mintedTrackIDs
                    }
                }

                if !timelineTrack.isMuted, !audioSoloSuppresses(timelineTrack, in: project) {
                    for _ in 0..<slotCount {
                        trackIDComposition.addMutableTrack(
                            withMediaType: .audio,
                            preferredTrackID: kCMPersistentTrackID_Invalid
                        )
                    }
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
        var transitionClipInfos: [VideoClipTransitionInfo] = []

        for timelineTrack in sortedTracks {
            switch timelineTrack.kind {
            case .video:
                guard let trackIDs = videoTrackIDsByTrackID[timelineTrack.id], !trackIDs.isEmpty else { continue }
                videoTrackIDs.append(contentsOf: trackIDs)

                let sortedClips = timelineTrack.clips
                    .filter({ ($0.kind == .video || $0.kind == .image) && $0.isAdjustmentLayer == false })
                    .sorted(by: { $0.timelineRange.start < $1.timelineRange.start })

                for (clipIndex, clip) in sortedClips.enumerated() {
                    let slot = trackIDs.count > 1 ? clipIndex % trackIDs.count : 0
                    let trackID = trackIDs[slot]

                    // BUG-IOS-09: effect timeRanges follow the SAME adjusted
                    // (back-timed) starts the composition inserts with, so
                    // instruction boundaries and the transition window line up
                    // with the real track content.
                    var adjustedStart = clip.timelineRange.start
                    if clipIndex > 0,
                       let transition = sortedClips[clipIndex - 1].transition,
                       transition.duration > 0 {
                        adjustedStart = max(0, adjustedStart - transition.duration)
                    }
                    let timeRange = CMTimeRange(
                        start: cmTime(adjustedStart),
                        duration: cmTime(clip.timelineRange.duration)
                    )
                    transitionClipInfos.append(
                        VideoClipTransitionInfo(
                            timelineTrackID: timelineTrack.id,
                            trackID: trackID,
                            timeRange: timeRange,
                            transition: clip.transition
                        )
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

        // BUG-IOS-09: transition overlaps shorten the composition below the
        // model timeline duration — boundaries must follow the REAL extent,
        // or a trailing no-content segment would request source frames after
        // the last clip ends.
        let durationSeconds = max(composition.duration.seconds, 0)
        let duration = cmTime(durationSeconds)
        let transitionEffects = makeTransitionEffects(from: transitionClipInfos)
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
                    transitionEffects: transitionEffects,
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
                    transitionEffects: transitionEffects,
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

    /// BUG-IOS-09: per-clip metadata for transition pairing (Mac
    /// ExportEngine's ExportClipInstructionMetadata, scoped to what the
    /// compositor needs).
    private struct VideoClipTransitionInfo {
        let timelineTrackID: UUID
        let trackID: CMPersistentTrackID
        let timeRange: CMTimeRange
        let transition: Transition?
    }

    /// BUG-IOS-09 (Mac ExportEngine parity, ExportEngine.swift:831-882):
    /// pairs consecutive clips within each timeline track where the OUTGOING
    /// clip carries a two-source transition. The window is the outgoing
    /// clip's tail (clamped to the shorter clip), during which both slot
    /// tracks carry live source frames for the compositor's transition
    /// branch.
    private func makeTransitionEffects(
        from infos: [VideoClipTransitionInfo]
    ) -> [CustomCompositionTransitionEffect] {
        let clipsByTimelineTrack = Dictionary(
            grouping: infos.filter { $0.trackID != kCMPersistentTrackID_Invalid },
            by: \.timelineTrackID
        )

        return clipsByTimelineTrack.values.flatMap { trackClips in
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

    /// G-15: temp segment backing an image clip in the current render plan.
    private func temporaryImageRenderURL(for clip: Clip) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutiOSImage-\(clip.id.uuidString)-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
    }

    /// Deletes the temp segments from the PREVIOUS plan (see makeRenderPlan).
    private func removeTemporaryImageRenders() {
        let fileManager = FileManager.default
        for url in imageRenderURLs where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
        imageRenderURLs.removeAll()
    }

    private func insertVideoTrack(
        _ timelineTrack: Track,
        from project: Project,
        into composition: AVMutableComposition
    ) async throws {
        // G-15: image clips ride the video pipeline through a pre-rendered
        // segment (Mac ExportEngine parity) — filtering to .video only made
        // photo-only projects export nothing and previews empty. Adjustment
        // layers carry no content (they render via instruction.adjustmentClips)
        // and must not consume a transition slot — the effect loop in
        // makeVideoComposition enumerates the identical list.
        let playableClips = timelineTrack.clips
            .filter { ($0.kind == .video || $0.kind == .image) && $0.isAdjustmentLayer == false }
            .sorted { $0.timelineRange.start < $1.timelineRange.start }

        guard !playableClips.isEmpty else { return }

        // BUG-IOS-09: two-source transitions need consecutive clips on
        // DIFFERENT composition tracks — the custom compositor reads one
        // source frame per track. Slots are allocated only when the track
        // actually carries a transition; transition-free tracks keep the
        // exact single-track layout (and byte-identical renders).
        let slotCount = Self.transitionSlotCount(for: playableClips)

        var videoTracks: [AVMutableCompositionTrack] = []
        if !timelineTrack.isHidden {
            for _ in 0..<slotCount {
                if let track = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) {
                    videoTracks.append(track)
                }
            }
        }
        // Audio alternates across the same slot count with the same
        // back-timing, so the overlapped window mixes both clips' audio and
        // the composition extent stays aligned with the video.
        let wantsAudio = !(timelineTrack.isMuted || audioSoloSuppresses(timelineTrack, in: project))
        var audioTracks: [AVMutableCompositionTrack] = []
        if wantsAudio {
            for _ in 0..<slotCount {
                if let track = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) {
                    audioTracks.append(track)
                }
            }
        }

        var videoCursors = [CMTime](repeating: .zero, count: videoTracks.count)
        var audioCursors = [CMTime](repeating: .zero, count: audioTracks.count)

        for (clipIndex, clip) in playableClips.enumerated() {
            guard
                let assetId = clip.assetId,
                let mediaAsset = project.mediaLibrary.assets[assetId]
            else { continue }

            // G-15 (Mac ExportEngine parity): an image asset renders into a
            // temp H.264 segment at the canvas size, then inserts like any
            // video. EXIF orientation is baked upright by the shared service.
            let asset: AVURLAsset
            if mediaAsset.kind == .image {
                let renderDuration = max(clip.sourceRange.duration, clip.timelineRange.duration, 5)
                let canvasSize = project.canvas.size
                let renderSize = canvasSize.width > 0 && canvasSize.height > 0
                    ? canvasSize
                    : CGSize(width: 1920, height: 1080)
                let imageVideoURL = temporaryImageRenderURL(for: clip)
                try await ImageVideoRenderService().render(
                    imageURL: mediaAsset.originalURL,
                    duration: renderDuration,
                    renderSize: renderSize,
                    outputURL: imageVideoURL,
                    kenBurnsEffect: clip.kenBurnsEffect
                )
                imageRenderURLs.append(imageVideoURL)
                asset = AVURLAsset(url: imageVideoURL)
            } else {
                asset = AVURLAsset(url: mediaAsset.originalURL)
            }

            // BUG-IOS-09: overlap back-timing — the incoming clip starts
            // transition-duration earlier so both sources are live during
            // the transition window (Mac ExportEngine parity).
            var adjustedStart = clip.timelineRange.start
            if clipIndex > 0,
               let transition = playableClips[clipIndex - 1].transition,
               transition.duration > 0 {
                adjustedStart = max(0, adjustedStart - transition.duration)
            }

            if !videoTracks.isEmpty {
                let slot = videoTracks.count > 1 ? clipIndex % videoTracks.count : 0
                try await insertClip(
                    clip,
                    mediaType: .video,
                    from: asset,
                    into: videoTracks[slot],
                    cursor: &videoCursors[slot],
                    timelineStartOverride: adjustedStart
                )
            }

            if !audioTracks.isEmpty {
                let slot = audioTracks.count > 1 ? clipIndex % audioTracks.count : 0
                try await insertClip(
                    clip,
                    mediaType: .audio,
                    from: asset,
                    into: audioTracks[slot],
                    cursor: &audioCursors[slot],
                    timelineStartOverride: adjustedStart
                )
            }
        }
    }

    /// BUG-IOS-09: two composition tracks per video timeline track when any
    /// clip boundary carries a two-source pixel transition, else one.
    private static func transitionSlotCount(for clips: [Clip]) -> Int {
        let needsSlots = clips.contains { clip in
            guard let transition = clip.transition else { return false }
            return transition.duration > 0 && transition.type.requiresTwoSourcePixelProcessing
        }
        return needsSlots ? 2 : 1
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

    /// Per-clip audio placement captured during insertion (BUG-IOS-10): the
    /// audioMix must follow the REAL placed span (speed-scaled, back-timed),
    /// not the model timelineRange.
    private struct AudioMixEntry {
        let trackID: CMPersistentTrackID
        let start: CMTime
        let duration: CMTime
        let volume: Double
        let fadeInDuration: TimeInterval
        let fadeOutDuration: TimeInterval
    }

    /// BUG-IOS-10: audio placements collected while building the composition.
    @ObservationIgnored private var audioMixEntries: [AudioMixEntry] = []

    @discardableResult
    private func insertClip(
        _ clip: Clip,
        mediaType: AVMediaType,
        from asset: AVURLAsset,
        into compositionTrack: AVMutableCompositionTrack,
        cursor: inout CMTime,
        timelineStartOverride: TimeInterval? = nil
    ) async throws -> CMTime {
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
            return .zero
        }

        guard var sourceTimeRange = sourceTimeRange(for: clip) else {
            return .zero
        }
        if clip.isReversed {
            // Reversed asset starts at 0; remap the source range.
            sourceTimeRange = CMTimeRange(
                start: cmTime(effectiveSourceStart),
                duration: sourceTimeRange.duration
            )
        }

        // BUG-IOS-09: transition back-timing shifts the insertion earlier than
        // the model timeline position; the caller passes the adjusted start.
        let timelineStart = cmTime(timelineStartOverride ?? clip.timelineRange.start)
        guard CMTimeCompare(timelineStart, cursor) >= 0 else {
            return .zero
        }

        if CMTimeCompare(cursor, timelineStart) < 0 {
            let gap = CMTimeSubtract(timelineStart, cursor)
            compositionTrack.insertEmptyTimeRange(CMTimeRange(start: cursor, duration: gap))
            cursor = timelineStart
        }

        let placedStart = cursor

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
            recordAudioMixEntry(
                for: clip, mediaType: mediaType, trackID: compositionTrack.trackID,
                start: placedStart, duration: CMTimeSubtract(cursor, placedStart)
            )
            return CMTimeSubtract(cursor, placedStart)
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

        recordAudioMixEntry(
            for: clip, mediaType: mediaType, trackID: compositionTrack.trackID,
            start: placedStart, duration: CMTimeSubtract(cursor, placedStart)
        )
        return CMTimeSubtract(cursor, placedStart)
    }

    /// BUG-IOS-10: remembers an audio placement for the render plan's
    /// audioMix (volume + fade ramps), following the real placed span.
    private func recordAudioMixEntry(
        for clip: Clip,
        mediaType: AVMediaType,
        trackID: CMPersistentTrackID,
        start: CMTime,
        duration: CMTime
    ) {
        guard mediaType == .audio, duration > .zero else { return }
        audioMixEntries.append(
            AudioMixEntry(
                trackID: trackID,
                start: start,
                duration: duration,
                volume: clip.volume,
                fadeInDuration: clip.fadeInDuration,
                fadeOutDuration: clip.fadeOutDuration
            )
        )
    }

    /// BUG-IOS-10 (Mac PlaybackEngine.applyAudioVolumeAndFades parity): one
    /// input-parameters object per composition audio track, with the clips'
    /// base volume plus fade-in/fade-out ramps. Nil when no clip carries
    /// audio edits — the untouched mix stays exactly as before.
    private func makeAudioMix(from entries: [AudioMixEntry], composition: AVMutableComposition) -> AVMutableAudioMix? {
        let audibleEntries = entries.filter { entry in
            entry.volume != 1 || entry.fadeInDuration > 0 || entry.fadeOutDuration > 0
        }
        guard !audibleEntries.isEmpty else { return nil }

        var parametersByTrack: [CMPersistentTrackID: AVMutableAudioMixInputParameters] = [:]
        for entry in audibleEntries {
            let parameters: AVMutableAudioMixInputParameters
            if let existing = parametersByTrack[entry.trackID] {
                parameters = existing
            } else {
                guard let track = composition.track(withTrackID: entry.trackID) else { continue }
                parameters = AVMutableAudioMixInputParameters(track: track)
                parametersByTrack[entry.trackID] = parameters
            }

            let volume = Float(min(max(entry.volume, 0), 2))
            parameters.setVolume(volume, at: entry.start)

            guard entry.duration.seconds.isFinite, entry.duration.seconds > 0 else { continue }

            // Fades clamp to the placed span; when both would overlap they
            // share it evenly so neither ramp window is undefined.
            var fadeIn = min(entry.fadeInDuration, entry.duration.seconds)
            var fadeOut = min(entry.fadeOutDuration, entry.duration.seconds)
            if fadeIn + fadeOut > entry.duration.seconds {
                fadeIn = entry.duration.seconds / 2
                fadeOut = entry.duration.seconds / 2
            }

            if fadeIn > 0 {
                parameters.setVolumeRamp(
                    fromStartVolume: 0,
                    toEndVolume: volume,
                    timeRange: CMTimeRange(start: entry.start, duration: cmTime(fadeIn))
                )
            }
            if fadeOut > 0 {
                let fadeOutStart = CMTimeAdd(entry.start, cmTime(entry.duration.seconds - fadeOut))
                parameters.setVolumeRamp(
                    fromStartVolume: volume,
                    toEndVolume: 0,
                    timeRange: CMTimeRange(start: fadeOutStart, duration: cmTime(fadeOut))
                )
            }
        }

        guard !parametersByTrack.isEmpty else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = Array(parametersByTrack.values)
        return mix
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
