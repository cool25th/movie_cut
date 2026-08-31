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
    // RENDER-02: the tagged-writer export's live reader/writer (cancellation).
    @ObservationIgnored private var activeReaders: [AVAssetReader] = []
    @ObservationIgnored private var activeWriter: AVAssetWriter?
    /// G-15: temp segments backing image clips in the CURRENT render plan.
    @ObservationIgnored private var imageRenderURLs: [URL] = []
    /// RENDER-02: resolves writer output settings — SDR H.264 tagged
    /// explicitly Rec.709 (the root fix for the preset-path decode drift).
    @ObservationIgnored private let exportPlanner = ExportPlanner()

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
        sourceOrientations.removeAll()
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

            // RENDER-02: the export drives an AVAssetWriter with the planner's
            // resolved output settings instead of AVAssetExportSession's
            // preset. The preset path cannot control color tags — the decoder
            // then picked its default YUV matrix/range and the exported file
            // drifted ~21/255 luma from the preview (band-guarded at 26). The
            // planner tags SDR H.264 explicitly Rec.709, which the
            // end-to-end sRGB/Rec.709 pipeline already is (Mac parity).
            let resolvedPlan = exportPlanner.plan(
                settings: project.exportSettings,
                canvas: project.canvas,
                mediaKind: .video
            )
            guard let videoOutputSettings = exportPlanner.assetWriterVideoOutputSettings(for: resolvedPlan),
                  let audioOutputSettings = exportPlanner.assetWriterAudioOutputSettings(for: resolvedPlan) else {
                throw IOSExportEngineError.exportSessionCreationFailed
            }
            // The reader converts audio to the WRITER's resolved format. The
            // composition's native audio (e.g. 44.1kHz mono) fed straight
            // into a 48kHz stereo AAC input smeared the fade ramps across
            // ~2.5× their window (measured 2026-08-26); converting on the
            // reader side keeps the encoder on a matched stream.
            let audioSampleRate = audioOutputSettings[AVSampleRateKey] as? Int ?? 48_000
            let audioChannelCount = audioOutputSettings[AVNumberOfChannelsKey] as? Int ?? 2

            // Review P0: honor the planner's resolved container (the Phase-1
            // contract is MP4/H.264; ProRes profiles force .mov upstream in
            // ExportPlanner). The URL extension and the writer's file type
            // must both derive from the SAME resolved value, or the file
            // extension lies about the container.
            // ResolvedExportPlan carries the container via its fileExtension
            // (the extension IS the rawValue), so the reverse mapping is exact.
            let resolvedContainer = ExportContainerFormat(rawValue: resolvedPlan.fileExtension) ?? .mov
            let outputURL = try makeOutputURL(fileExtension: resolvedContainer.fileExtension)
            activeOutputURL = outputURL

            let writerFileType: AVFileType
            switch resolvedContainer {
            case .mp4, .m4v: writerFileType = .mp4
            case .mov: writerFileType = .mov
            }
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: writerFileType)
            writer.shouldOptimizeForNetworkUse = true
            // Separate readers per modality (W4-defect parity, Mac
            // code-review #3): one reader mixing a videoComposition output
            // with an audioMix output over the same composition can park
            // forever (measured on iOS 2026-08-26 — the audio-fade export
            // hung). The audio side reads its OWN dumped asset (below).
            let videoReader = try AVAssetReader(asset: composition)
            let audioReader = try AVAssetReader(asset: composition)

            // Video leg: the SAME videoComposition the preview renders with
            // (RENDER-01/CANVAS-01 — always attached, canvas-sized).
            let videoTracks = composition.tracks(withMediaType: .video)
            var videoReaderOutput: AVAssetReaderVideoCompositionOutput?
            var writerVideoInput: AVAssetWriterInput?
            if !videoTracks.isEmpty {
                let readerOutput = AVAssetReaderVideoCompositionOutput(
                    videoTracks: videoTracks,
                    videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                )
                readerOutput.alwaysCopiesSampleData = false
                readerOutput.videoComposition = plan.videoComposition
                guard videoReader.canAdd(readerOutput) else {
                    throw IOSExportEngineError.exportSessionCreationFailed
                }
                videoReader.add(readerOutput)
                videoReaderOutput = readerOutput

                let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings)
                input.expectsMediaDataInRealTime = false
                guard writer.canAdd(input) else {
                    throw IOSExportEngineError.exportSessionCreationFailed
                }
                writer.add(input)
                writerVideoInput = input
            }

            // Audio leg: the composition's inline audio through the plan's
            // audioMix (BUG-IOS-10 — volume/fades bake into the file), on its
            // own reader with the writer's resolved format so the AAC input
            // receives a matched stream.
            let audioTracks = composition.tracks(withMediaType: .audio)
            var audioReaderOutput: AVAssetReaderAudioMixOutput?
            var writerAudioInput: AVAssetWriterInput?
            if !audioTracks.isEmpty {
                let output = AVAssetReaderAudioMixOutput(
                    audioTracks: audioTracks,
                    audioSettings: [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsNonInterleaved: false,
                        AVSampleRateKey: audioSampleRate,
                        AVNumberOfChannelsKey: audioChannelCount
                    ]
                )
                output.audioMix = plan.audioMix
                guard audioReader.canAdd(output) else {
                    throw IOSExportEngineError.exportSessionCreationFailed
                }
                audioReader.add(output)
                audioReaderOutput = output

                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings)
                input.expectsMediaDataInRealTime = false
                guard writer.canAdd(input) else {
                    throw IOSExportEngineError.exportSessionCreationFailed
                }
                writer.add(input)
                writerAudioInput = input
            }

            guard videoReader.startReading() else {
                throw videoReader.error ?? IOSExportEngineError.exportSessionCreationFailed
            }
            guard audioReader.startReading() else {
                throw audioReader.error ?? IOSExportEngineError.exportSessionCreationFailed
            }
            guard writer.startWriting() else {
                throw writer.error ?? IOSExportEngineError.exportSessionCreationFailed
            }
            writer.startSession(atSourceTime: .zero)

            activeReaders = [videoReader, audioReader]
            activeWriter = writer

            let totalDuration = max(composition.duration.seconds, 1.0 / 600.0)
            // Both pumps run CONCURRENTLY. With an audio writer input
            // present, pumping video ALONE first stalls the video queue
            // (measured 2026-08-26 on simulator: video-pump completion never
            // fired while an audio input existed; no-audio and muted exports
            // were clean; concurrent pumping completes both in seconds).
            try await withThrowingTaskGroup(of: Void.self) { group in
                if let writerVideoInput, let videoReaderOutput {
                    let videoOutput = SendableBox(value: videoReaderOutput as AVAssetReaderOutput)
                    let videoInput = SendableBox(value: writerVideoInput)
                    group.addTask {
                        try await self.pumpSamples(
                            output: videoOutput,
                            input: videoInput,
                            totalDuration: totalDuration
                        )
                    }
                }
                if let writerAudioInput, let audioReaderOutput {
                    let audioOutputBox = SendableBox(value: audioReaderOutput as AVAssetReaderOutput)
                    let audioInputBox = SendableBox(value: writerAudioInput)
                    group.addTask {
                        try await self.pumpSamples(
                            output: audioOutputBox,
                            input: audioInputBox,
                            totalDuration: nil
                        )
                    }
                }
            }

            for reader in activeReaders where reader.status == .failed {
                throw reader.error ?? IOSExportEngineError.exportSessionCreationFailed
            }

            await Self.finishWriting(SendableBox(value: writer))
            switch writer.status {
            case .completed:
                break
            case .cancelled:
                throw CancellationError()
            default:
                throw writer.error ?? IOSExportEngineError.exportSessionCreationFailed
            }

            exportProgress = 1
            lastExportURL = outputURL
            finishExport()
            activeReaders.removeAll()
            activeWriter = nil
            return outputURL
        } catch {
            removePartialOutput()
            finishExport()
            activeReaders.removeAll()
            activeWriter = nil
            throw error
        }
    }

    /// Streams sample buffers from a reader output into a writer input,
    /// driving the writer's pull model (Mac ExportEngine.pumpSamples parity).
    /// `totalDuration` non-nil → progress reports by presentation time.
    private nonisolated func pumpSamples(
        output: SendableBox<AVAssetReaderOutput>,
        input: SendableBox<AVAssetWriterInput>,
        totalDuration: Double?
    ) async throws {
        let queue = DispatchQueue(label: "moviecut.ios.export.writer")
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

                    if let totalDuration, totalDuration > 0 {
                        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                        if presentationTime.isFinite {
                            let progress = min(max(presentationTime / totalDuration, 0), 1)
                            Task { @MainActor [weak self] in
                                self?.exportProgress = progress
                            }
                        }
                    }

                    if !writerInput.append(sampleBuffer) {
                        continuation.resume(throwing: IOSExportEngineError.exportSessionCreationFailed)
                        return
                    }
                }
            }
        }
    }

    /// Awaits an AVAssetWriter's completion handler off the main actor.
    private static nonisolated func finishWriting(_ writer: SendableBox<AVAssetWriter>) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.value.finishWriting {
                continuation.resume(returning: ())
            }
        }
    }

    /// Reader outputs and writer inputs are not Sendable; the pump owns them
    /// for the transfer's duration and serializes access through the writer's
    /// request queue.
    private struct SendableBox<T>: @unchecked Sendable {
        let value: T
    }

    func cancelExport() {
        // RENDER-02: the tagged-writer export cancels through its reader and
        // writer; the in-flight export call then fails into the catch path,
        // which removes the partial output (idempotent).
        for reader in activeReaders {
            reader.cancelReading()
        }
        activeReaders.removeAll()
        activeWriter?.cancelWriting()
        activeWriter = nil
        activeExportSession?.cancelExport()
        progressTask?.cancel()
        progressTask = nil
        activeExportSession = nil
        exportProgress = 0
        lastExportURL = nil
        isExporting = false
        // UX-REC-01: a cancelled export leaves a truncated .mov at the output
        // — remove it so the user never shares a broken artifact.
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
                    // with the real track content. CODEX-09: the pull is
                    // clamped to the shorter neighbor like the effect window.
                    var adjustedStart = clip.timelineRange.start
                    if clipIndex > 0,
                       let transition = sortedClips[clipIndex - 1].transition,
                       transition.duration > 0 {
                        let overlap = Self.clampedOverlapPull(
                            predecessorTransition: transition,
                            predecessorDuration: sortedClips[clipIndex - 1].timelineRange.duration,
                            clipTimelineStart: clip.timelineRange.start,
                            clipDuration: clip.timelineRange.duration
                        )
                        adjustedStart = max(0, adjustedStart - overlap)
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
                    // this transform before the canvas fit (Mac BUG-07 parity).
                    // CODEX-08: the transform is the clip's OWN (recorded at
                    // insert time from its effective source); the composition
                    // track's pt is first-writer-wins metadata and mis-orients
                    // mixed-rotation tracks when read back per clip.
                    let sourcePreferredTransform = sourceOrientations[clip.id]
                        ?? composition.track(withTrackID: trackID)?.preferredTransform
                        ?? .identity

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

    /// CODEX-09: the placement back-timing and the transition effect window
    /// must share ONE clamped duration. The effect window clamps the request
    /// to the shorter neighboring clip, but placement pulled by the RAW
    /// request — an oversized transition put the next clip before its slot
    /// cursor, where insertClip's `timelineStart >= cursor` guard silently
    /// dropped it from the export.
    static func clampedTransitionDuration(
        _ transition: Transition,
        outgoingDuration: TimeInterval,
        incomingDuration: TimeInterval
    ) -> TimeInterval {
        max(0, min(transition.duration, outgoingDuration, incomingDuration))
    }

    /// CODEX-09: overlap pull for a clip whose PREDECESSOR carries a
    /// transition — the clamped twin of the raw subtraction the effect
    /// window has always used.
    static func clampedOverlapPull(
        predecessorTransition: Transition,
        predecessorDuration: TimeInterval,
        clipTimelineStart: TimeInterval,
        clipDuration: TimeInterval
    ) -> TimeInterval {
        clampedTransitionDuration(
            predecessorTransition,
            outgoingDuration: predecessorDuration,
            incomingDuration: clipDuration
        )
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

                let transitionDuration = cmTime(Self.clampedTransitionDuration(
                    transition,
                    outgoingDuration: outgoingClip.timeRange.duration.seconds,
                    incomingDuration: incomingClip.timeRange.duration.seconds
                ))
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
            // the transition window (Mac ExportEngine parity). CODEX-09: the
            // pull is clamped to the shorter neighbor, matching the effect
            // window — the raw pull put oversized transitions before the
            // slot cursor and insertClip silently dropped the clip.
            var adjustedStart = clip.timelineRange.start
            if clipIndex > 0,
               let transition = playableClips[clipIndex - 1].transition,
               transition.duration > 0 {
                let overlap = Self.clampedOverlapPull(
                    predecessorTransition: transition,
                    predecessorDuration: playableClips[clipIndex - 1].timelineRange.duration,
                    clipTimelineStart: clip.timelineRange.start,
                    clipDuration: clip.timelineRange.duration
                )
                adjustedStart = max(0, adjustedStart - overlap)
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

    /// CODEX-08: each video clip's EFFECTIVE source orientation (original,
    /// reversed, or image pre-render asset), recorded by insertClip while
    /// building the composition. The composition track's preferredTransform
    /// is first-writer-wins output metadata for external players and cannot
    /// orient mixed-rotation tracks — the per-clip effect must carry the
    /// clip's own transform.
    @ObservationIgnored private var sourceOrientations: [UUID: CGAffineTransform] = [:]

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

        if mediaType == .video {
            // CODEX-08: record THIS clip's source orientation for its effect.
            // The track-level pt below stays first-writer-wins metadata for
            // external players — a mixed-rotation track must not read it
            // back per clip (the second clip inherited the first clip's
            // orientation and rendered sideways).
            let sourceTransform = try await sourceTrack.load(.preferredTransform)
            sourceOrientations[clip.id] = sourceTransform
            if compositionTrack.preferredTransform == .identity {
                compositionTrack.preferredTransform = sourceTransform
            }
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

    private func makeOutputURL(fileExtension: String) throws -> URL {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutiOSExports", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let outputURL = folderURL
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        return outputURL
    }

    private func finishExport() {
        progressTask?.cancel()
        progressTask = nil
        activeExportSession = nil
        activeOutputURL = nil
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
