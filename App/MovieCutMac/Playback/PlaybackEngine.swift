import AVFoundation
import AppKit
import AudioToolbox
import CoreVideo
import Foundation
import MediaToolbox
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
final class PlaybackEngine: FlattenedTimelineConsumer {
    var player: AVPlayer
    var isPlaying: Bool
    var currentTime: TimeInterval
    var duration: TimeInterval
    var playerItem: AVPlayerItem?
    var playbackRate: Float
    /// The exact single-source snapshot attached by EditorViewModel. This is
    /// not an engine-owned cache: the engine never computes or refreshes it.
    @ObservationIgnored private var flattenedTimeline: FlattenedTimeline?
    @ObservationIgnored private var flattenedProjectId: UUID?

    func boundProjectId() async -> UUID? {
        flattenedProjectId
    }

    func attach(_ project: Project, flattened: FlattenedTimeline) async {
        guard flattened.projectId == project.id else {
            flattenedTimeline = nil
            flattenedProjectId = nil
            return
        }
        flattenedTimeline = flattened
        flattenedProjectId = project.id
    }

    func currentFlattenedTimeline() async -> FlattenedTimeline? {
        flattenedTimeline
    }

    private func renderingTracks(for project: Project) -> [Track] {
        guard flattenedProjectId == project.id,
              flattenedTimeline?.schemaVersion == project.schemaVersion,
              let flattenedTimeline else {
            return project.timeline.tracks
        }
        return flattenedTimeline.tracks
    }
    /// Most recent composition build error, surfaced to the UI instead of being
    /// silently swallowed by `clear()`. Reset to `nil` on a successful build.
    var lastCompositionError: String?
    /// Monotonically increasing token stamped on every `loadProject` request and
    /// checked before applying a built composition, so a slow stale rebuild can
    /// never overwrite a newer composition (Step 1 stale-rebuild guard).
    private var compositionGeneration: UInt64 = 0
    /// Generation of the composition currently installed in `playerItem`.
    /// Harnesses use this to avoid mistaking an older ready item for a newly
    /// requested asynchronous rebuild.
    private(set) var installedCompositionGeneration: UInt64 = 0

    @ObservationIgnored private var textLayers: [CALayer] = []
    /// Tracks karaoke text clips so their per-word layers can be recolored on
    /// the playback tick. Keyed by the text clip's timeline start, which is
    /// unique within a track and stable across the composition build.
    @ObservationIgnored private var karaokeClips: [KaraokePreviewClip] = []
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var playbackTimerTask: Task<Void, Never>?
    @ObservationIgnored private var compositionBuildTask: Task<Void, Never>?
    @ObservationIgnored private var temporaryReverseRenderURLs: [URL] = []
    /// G-25 2C-2 (spec §0 v1.1): EQ clips' preview audio consumes DERIVED
    /// effective media — the same `AudioEqualizerService` render the export
    /// and graph paths use — instead of an MTAudioProcessingTap. One DSP
    /// everywhere, and the tap's export-session defect class is structurally
    /// gone. Cached per clip while the preset is unchanged (the
    /// reverse-media precedent); cleaned on clear/loadProject.
    @ObservationIgnored private var equalizedPreviewAudio: [UUID: (preset: EqualizerPreset, url: URL)] = [:]
    @ObservationIgnored private var temporaryEqualizedPreviewURLs: [URL] = []
    /// Security scopes started for the assets in the currently loaded single
    /// asset or composition. Each entry pairs with a `stopAccessing` on clear
    /// or next load so the access pair never leaks across reloads. (S2)
    @ObservationIgnored private var activeSecurityScopes: [URL] = []
    /// Runtime-only: preview dropped to proxy because of thermal pressure (S7).
    /// Distinct from the user's persistent `useProxyPlayback` so cooling the
    /// device restores the original even if the user never toggled proxy on.
    var autoProxyDowngrade: Bool {
        didSet {
            guard oldValue != autoProxyDowngrade else { return }
            AppLog.playback.info("thermal proxy downgrade: \(self.autoProxyDowngrade, privacy: .public)")
        }
    }
    /// Runtime-only: the latest thermal state (S7 gradual degradation). Drives
    /// the preview render-size clamp at `.fair` via
    /// `ProxyDowngradePolicy.effectivePreviewQuality`; the proxy flip at
    /// `.serious`+ stays on `autoProxyDowngrade`. Observed (not Ignored) so the
    /// timeline's quality-degrade badge re-resolves when the clamp engages.
    private(set) var currentThermalState: ThermalState = .nominal
    /// The last project + audio processing passed to `loadProject`, kept so a
    /// thermal transition can rebuild the composition at the new proxy state.
    @ObservationIgnored private var loadedProject: Project?
    @ObservationIgnored private var loadedAudioProcessing: ClipAudioProcessingOptions = ClipAudioProcessingOptions()
    @ObservationIgnored private let thermalObserver = ThermalStateObserver()
    /// Video output used to pull the currently displayed preview pixel buffer
    /// for Preview↔Export parity verification. Lazily attached to the active
    /// player item.
    @ObservationIgnored private var previewVideoOutput: AVPlayerItemVideoOutput?

    init() {
        self.player = AVPlayer()
        self.isPlaying = false
        self.currentTime = 0
        self.duration = 0
        self.playerItem = nil
        self.playbackRate = 1
        self.autoProxyDowngrade = false
        // Begin thermal observation: on serious/critical pressure (and if the
        // user allows it), drop preview to proxy; on cooling, restore. (S7)
        thermalObserver.onChange = { [weak self] state in
            self?.thermalStateChanged(to: state)
        }
        thermalObserver.start()
    }

    /// Reacts to a thermal transition by applying gradual degradation (S7):
    /// at `.fair` the preview render size clamps to at most 1/2 (no rebuild
    /// needed beyond the one triggered here); at `.serious`+ the proxy flips
    /// (when the user allows it). Rebuilds whenever EITHER the proxy flag or
    /// the effective preview quality changes so both rungs take effect.
    private func thermalStateChanged(to state: ThermalState) {
        guard let project = loadedProject else { return }
        let previousQuality = ProxyDowngradePolicy.effectivePreviewQuality(
            user: project.playbackSettings.previewQuality,
            thermalState: currentThermalState
        )
        currentThermalState = state
        let shouldDowngrade = ProxyDowngradePolicy.shouldAutoDowngrade(
            thermalState: state,
            autoProxyOnThermalPressure: project.playbackSettings.autoProxyOnThermalPressure
        )
        let nextQuality = ProxyDowngradePolicy.effectivePreviewQuality(
            user: project.playbackSettings.previewQuality,
            thermalState: state
        )
        guard shouldDowngrade != autoProxyDowngrade || previousQuality != nextQuality else { return }
        if shouldDowngrade != autoProxyDowngrade {
            autoProxyDowngrade = shouldDowngrade
        } else {
            AppLog.playback.info("thermal preview quality clamp: \(previousQuality.shortLabel, privacy: .public) -> \(nextQuality.shortLabel, privacy: .public)")
        }
        // Rebuild at the new proxy/quality state. loadProject preserves
        // playback state (it re-stamps the generation guard).
        loadProject(project, audioProcessing: loadedAudioProcessing)
    }

    func load(asset: MediaAsset) {
        compositionBuildTask?.cancel()
        compositionBuildTask = nil
        compositionGeneration &+= 1
        installedCompositionGeneration = 0
        pause()
        statusObservation?.invalidate()
        statusObservation = nil
        clearPreviewVideoOutput()
        endActiveSecurityScopes()

        // Resolve the bookmark and start a scope so the file stays reachable
        // under App Sandbox for the lifetime of this player item. (S2)
        let resolvedURL = SecurityScopedAccess.beginScope(for: asset)
        activeSecurityScopes = [resolvedURL]
        let avAsset = AVURLAsset(url: resolvedURL)
        let item = AVPlayerItem(asset: avAsset)

        playerItem = item
        currentTime = 0
        duration = asset.duration ?? 0
        player.replaceCurrentItem(with: item)
        cleanupTemporaryReverseRenderURLs()
        cleanupTemporaryEqualizedPreviewURLs()
        observeStatus(for: item)
    }

    /// Returns the monotonically increasing composition generation counter.
    /// Exposed for behavioral tests that verify stale rebuilds cannot
    /// overwrite a newer composition (Step 1 acceptance criterion).
    var currentCompositionGeneration: UInt64 {
        compositionGeneration
    }

    func loadProject(_ project: Project, audioProcessing: ClipAudioProcessingOptions = ClipAudioProcessingOptions()) {
        pause()
        statusObservation?.invalidate()
        statusObservation = nil
        endActiveSecurityScopes()

        // Start a security scope for every source asset referenced by the
        // composition, so each stays reachable under App Sandbox while the
        // player holds the composition. (S2)
        activeSecurityScopes = project.mediaLibrary.assets.values.map { asset in
            SecurityScopedAccess.beginScope(for: asset)
        }

        // Remember the project so a thermal transition can rebuild at the new
        // proxy state. (S7)
        loadedProject = project
        loadedAudioProcessing = audioProcessing

        // Stamp a new generation before any async work. Only the holder of the
        // latest token is allowed to install a player item, so a slow earlier
        // rebuild that completes after a newer request cannot overwrite it.
        compositionGeneration &+= 1
        let requestedGeneration = compositionGeneration

        compositionBuildTask?.cancel()
        compositionBuildTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let signposter = AppLog.Signpost.playback
            let signpostState = signposter.beginInterval("playback.buildComposition")

            do {
                let (composition, videoComposition, audioMix, temporaryReverseRenderURLs) = try await buildComposition(from: project, audioProcessing: audioProcessing)

                // Stale guard: another rebuild was requested while we built.
                guard requestedGeneration == compositionGeneration else {
                    removeTemporaryReverseRenderURLs(temporaryReverseRenderURLs)
                    return
                }

                let item = AVPlayerItem(asset: composition)
                item.videoComposition = videoComposition
                item.audioMix = audioMix
                attachPreviewVideoOutput(to: item)

                playerItem = item
                currentTime = 0
                duration = composition.duration.seconds.isFinite ? composition.duration.seconds : 0
                installedCompositionGeneration = requestedGeneration
                lastCompositionError = nil
                player.replaceCurrentItem(with: item)
                cleanupTemporaryReverseRenderURLs()
                self.temporaryReverseRenderURLs = temporaryReverseRenderURLs
                observeStatus(for: item)
                signposter.endInterval("playback.buildComposition", signpostState)
            } catch {
                // Stale guard applies to the failure path too.
                guard requestedGeneration == compositionGeneration else { return }
                let nsError = error as NSError
                var errorDetail = "\(nsError.localizedDescription) [\(nsError.domain):\(nsError.code)]"
                if let failureReason = nsError.localizedFailureReason, !failureReason.isEmpty {
                    errorDetail += " reason=\(failureReason)"
                }
                if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                    errorDetail += " underlying=\(underlyingError.localizedDescription) [\(underlyingError.domain):\(underlyingError.code)]"
                }
                AppLog.playback.error("composition build failed: \(errorDetail, privacy: .public)")
                installedCompositionGeneration = 0
                lastCompositionError = errorDetail
                clearPreviewVideoOutput()
                player.replaceCurrentItem(with: nil)
                cleanupTemporaryReverseRenderURLs()
                playerItem = nil
                currentTime = 0
                duration = 0
                signposter.endInterval("playback.buildComposition", signpostState, "failed")
            }
        }
    }

    private func attachPreviewVideoOutput(to item: AVPlayerItem) {
        clearPreviewVideoOutput()
        let settings: [String: Any] = [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA]
        let output = AVPlayerItemVideoOutput(outputSettings: settings)
        item.add(output)
        previewVideoOutput = output
    }

    private func clearPreviewVideoOutput() {
        if let output = previewVideoOutput, let item = playerItem {
            item.remove(output)
        }
        previewVideoOutput = nil
    }

    /// Returns the preview frame currently displayed at the player's time, or
    /// `nil` when no composition is loaded / the renderer has not produced a
    /// frame yet. Used by Preview↔Export parity verification (Step 1).
    func snapshotCurrentFrame() -> CGImage? {
        guard let output = previewVideoOutput else { return nil }
        // AVPlayerItemVideoOutput.itemTime(forHostTime:) takes a host-time
        // scalar (CFTimeInterval), not a CMTime.
        let hostTimeSeconds = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        guard hostTimeSeconds.isFinite else { return nil }
        let itemTime = output.itemTime(forHostTime: hostTimeSeconds)
        guard CMTIME_IS_NUMERIC(itemTime) else { return nil }
        if output.hasNewPixelBuffer(forItemTime: itemTime) {
            if let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
                return Self.cgImage(from: pixelBuffer)
            }
        }
        return nil
    }

    /// Returns the preview frame at an arbitrary composition time by seeking
    /// the player first. Intended for parity harness use where the host must
    /// capture a frame at a known timestamp regardless of live playback.
    func snapshotFrame(at time: TimeInterval) async -> CGImage? {
        // Wait until the player item is ready to produce frames. The video
        // output cannot copy a pixel buffer before .readyToPlay, and the first
        // seek after install frequently returns nil without this gate.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let item = playerItem, item.status == .readyToPlay { break }
            if lastCompositionError != nil { return nil }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        let targetTime: TimeInterval
        if duration > 0 {
            targetTime = min(max(0, time), duration)
        } else {
            targetTime = max(0, time)
        }
        currentTime = targetTime
        let itemTime = CMTime(seconds: targetTime, preferredTimescale: 600)
        await withCheckedContinuation { continuation in
            player.seek(
                to: itemTime,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { _ in
                continuation.resume()
            }
        }

        // Poll the exact requested item time. Custom-compositor frames can take
        // longer than a decoded passthrough frame on their first request, and
        // host-time lookup is ambiguous while the player is paused after seek.
        let frameDeadline = Date().addingTimeInterval(2)
        while Date() < frameDeadline {
            if let output = previewVideoOutput,
               output.hasNewPixelBuffer(forItemTime: itemTime),
               let pixelBuffer = output.copyPixelBuffer(
                   forItemTime: itemTime,
                   itemTimeForDisplay: nil
               ),
               let image = Self.cgImage(from: pixelBuffer) {
                return image
            }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        return snapshotCurrentFrame()
    }

    /// Renders the exact asset/audio-mix currently installed in Preview to an
    /// audio file. The integration harness decodes this output as PCM so it can
    /// measure Preview's real composition path rather than the processed source
    /// file in isolation.
    func renderCurrentPreviewAudio(to outputURL: URL) async throws {
        guard let playerItem else {
            throw PlaybackPreviewAudioError.noPlayerItem
        }
        guard let exportSession = AVAssetExportSession(
            asset: playerItem.asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw PlaybackPreviewAudioError.exportSessionCreationFailed
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        exportSession.audioMix = playerItem.audioMix
        try await AVExportCompatibility.export(.init(exportSession), to: outputURL, as: .m4a)
    }

    private static func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: RenderColorConfiguration.contextOptions.merging([.useSoftwareRenderer: false]) { _, new in new })
        return context.createCGImage(ciImage, from: ciImage.extent)
    }

    func clear() {
        compositionBuildTask?.cancel()
        compositionBuildTask = nil
        compositionGeneration &+= 1
        installedCompositionGeneration = 0
        pause()
        statusObservation?.invalidate()
        statusObservation = nil
        clearPreviewVideoOutput()
        player.replaceCurrentItem(with: nil)
        cleanupTemporaryReverseRenderURLs()
        cleanupTemporaryEqualizedPreviewURLs()
        endActiveSecurityScopes()
        playerItem = nil
        currentTime = 0
        duration = 0
        playbackRate = 1
    }

    /// Stops every security scope started for the current composition/single
    /// asset and forgets them. Called on clear and before starting fresh scopes
    /// so the start/stop pair never leaks across reloads. (S2)
    private func endActiveSecurityScopes() {
        for url in activeSecurityScopes {
            SecurityScopedAccess.endScope(for: url)
        }
        activeSecurityScopes = []
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
        // Signpost measures the seek REQUEST (AVPlayer.seek is fire-and-forget;
        // render completion is not observable here) — the SLO doc's intended
        // `playback.seek` probe for scrub-latency regression direction.
        let signposter = AppLog.Signpost.playback
        let state = signposter.beginInterval("playback.seek")
        let targetTime: TimeInterval
        if duration > 0 {
            targetTime = min(max(0, time), duration)
        } else {
            targetTime = max(0, time)
        }

        currentTime = targetTime
        let cmTime = CMTime(seconds: targetTime, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        signposter.endInterval("playback.seek", state)
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
        karaokeClips = []
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

        /// Picks the playback URL for a media asset. When proxy playback is on and
        /// the asset has a ready proxy, the lower-resolution proxy is used for
        /// smoother previewing; otherwise the original is used. Mirrors the
        /// `BeatDetectionProvider` idiom so behavior stays consistent across the
        /// codebase.
        func playbackURL(for asset: MediaAsset) -> URL {
            // Proxy is used when the user opted in OR when thermal pressure
            // auto-downgraded preview (S7). Export never uses this path.
            if (project.playbackSettings.useProxyPlayback || autoProxyDowngrade),
               let proxyURL = asset.proxy?.proxyURL {
                return proxyURL
            }
            return asset.originalURL
        }

        let composition = AVMutableComposition()
        var videoCompositionTracks: [(track: AVMutableCompositionTrack, zIndex: Int)] = []
        var videoClipInstructions: [PlaybackClipInstructionMetadata] = []
        var textOverlayClipEffects: [CustomCompositionClipEffect] = []
        var audioMixInputParameters: [AVMutableAudioMixInputParameters] = []
        let renderTracks = renderingTracks(for: project)
        // G-26: a project-level master chain is rendered once by the shared
        // graph and inserted as Preview's single audio track. Off/nil keeps
        // the established per-track AVAudioMix path.
        let usesGraphMasterAudio = project.masterAudioProcessing != nil
        // G-25 Inc 9 audio solo: any soloed audio-capable track silences
        // every non-solo track's AUDIO (video keeps rendering).
        let anyTrackSoloed = project.timeline.tracks.contains { $0.isSolo && $0.kind != .text }

        for track in renderTracks.sorted(by: { $0.zIndex < $1.zIndex }) {
            switch track.kind {
            case .video:
                var videoCompositionTracksBySlot: [Int: AVMutableCompositionTrack] = [:]
                let audioCompositionTrack: AVMutableCompositionTrack?
                if usesGraphMasterAudio || track.isMuted || (anyTrackSoloed && !track.isSolo) {
                    audioCompositionTrack = nil
                } else {
                    audioCompositionTrack = try makeCompositionTrack(
                        in: composition,
                        mediaType: .audio
                    )
                }
                let audioParameters = AVMutableAudioMixInputParameters()

                if let audioCompositionTrack {
                    audioParameters.trackID = audioCompositionTrack.trackID
                }

                let sortedClips = track.clips.sorted(by: { $0.timelineRange.start < $1.timelineRange.start })
                for (clipIndex, clip) in sortedClips.enumerated() {
                    // G-03: adjustment clips carry no content — render nothing.
                    guard clip.isAdjustmentLayer == false else { continue }
                    guard let assetId = clip.assetId,
                          let mediaAsset = project.mediaLibrary.assets[assetId] else {
                        continue
                    }

                    // Image clips render from the original, so proxy playback
                    // only applies to the non-image (video/audio) branch below.
                    var sourceAsset = AVURLAsset(url: playbackURL(for: mediaAsset))
                    var sourceTrack: AVAssetTrack
                    if mediaAsset.kind == .image {
                        let renderDuration = max(clip.sourceRange.duration, clip.timelineRange.duration, 5)
                        let imageVideoURL = temporaryImageRenderURL(for: clip)
                        try await ImageVideoRenderService().render(
                            imageURL: mediaAsset.originalURL,
                            duration: renderDuration,
                            renderSize: project.timeline.canvasSize,
                            outputURL: imageVideoURL,
                            kenBurnsEffect: clip.kenBurnsEffect
                        )
                        temporaryReverseRenderURLs.append(imageVideoURL)
                        sourceAsset = AVURLAsset(url: imageVideoURL)
                        guard let renderedTrack = try await sourceAsset.loadTracks(withMediaType: .video).first else {
                            continue
                        }
                        sourceTrack = renderedTrack
                    } else {
                        guard let loadedTrack = try await sourceAsset.loadTracks(withMediaType: .video).first else {
                            continue
                        }
                        sourceTrack = loadedTrack
                    }
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

                    if !track.isHidden {
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

                        let effectiveSourceTrack = sourceTrack
                        let effectiveSourceTimeRange = isFreezeFrame
                            ? freezeFrameSourceTimeRange(for: clip)
                            : sourceTimeRange

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
                        } else if clip.isReversed {
                            let insertedDuration = try await ReverseCompositionInserter.insertReversedFrames(
                                from: effectiveSourceTrack,
                                sourceTimeRange: effectiveSourceTimeRange,
                                into: videoCompositionTrack,
                                at: destinationTime
                            )
                            targetDuration = cmTime(clip.timelineRange.duration)
                            if targetDuration != insertedDuration {
                                videoCompositionTrack.scaleTimeRange(
                                    CMTimeRange(start: destinationTime, duration: insertedDuration),
                                    toDuration: targetDuration
                                )
                            }
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

                        let preferredTransform = try await effectiveSourceTrack.load(.preferredTransform)
                        let sourceSize = try await effectiveSourceTrack.load(.naturalSize)
                        // BUG-06 parity: the export path aspect-fits every
                        // source into the canvas; the preview instruction must
                        // carry the same base fit or preview and export drift
                        // (and mismatched aspects previewed 1:1 at the corner).
                        let displaySize: CGSize = sourceSize.applying(preferredTransform)
                        let absWidth: CGFloat = abs(displaySize.width)
                        let absHeight: CGFloat = abs(displaySize.height)
                        let canvas: CGSize = project.timeline.canvasSize
                        var previewFit: CGAffineTransform = .identity
                        if absWidth > 0, absHeight > 0 {
                            let fitScaleW: CGFloat = canvas.width / absWidth
                            let fitScaleH: CGFloat = canvas.height / absHeight
                            let fitScale: CGFloat = min(fitScaleW, fitScaleH)
                            let scaledW: CGFloat = absWidth * fitScale
                            let scaledH: CGFloat = absHeight * fitScale
                            let tx: CGFloat = (canvas.width - scaledW) / 2
                            let ty: CGFloat = (canvas.height - scaledH) / 2
                            previewFit = CGAffineTransform(translationX: tx, y: ty)
                                .scaledBy(x: fitScale, y: fitScale)
                        }
                        videoClipInstructions.append(PlaybackClipInstructionMetadata(
                            timelineTrackID: track.id,
                            trackID: videoCompositionTrack.trackID,
                            timeRange: CMTimeRange(start: destinationTime, duration: targetDuration),
                            transform: previewFit.concatenating(
                                clip.transform.affineTransform(
                                    for: .sourceFrame(preferredTransform: preferredTransform, size: sourceSize)
                                )
                            ),
                            clipTransform: clip.transform,
                            keyframes: clip.keyframes,
                            opacity: Float(min(max(clip.opacity, 0), 1)),
                            transition: clip.transition,
                            colorCorrection: clip.colorCorrection,
                            colorGrade: clip.colorGrade,
                            chromaKey: clip.chromaKey,
                            chromaKeyColor: clip.chromaKeyColor,
                            chromaKeyThreshold: clip.chromaKeyThreshold,
                            mask: clip.mask,
                            effects: clip.effects,
                            isBackgroundRemoved: clip.isBackgroundRemoved,
                            blendMode: clip.blendMode,
                            cropRect: clip.cropRect,
                            stabilization: clip.stabilization
                        ))
                    }

                    if !isFreezeFrame, let audioCompositionTrack {
                        // G-25 2C-2 (spec §0 v1.1): an EQ'd clip's embedded
                        // audio comes from DERIVED effective media (the same
                        // AudioEqualizerService render export and the graph
                        // use) — the audio tap is retired.
                        var audioSourceAsset = sourceAsset
                        if let equalizedURL = try await equalizedPreviewURL(
                            for: clip, inputURL: playbackURL(for: mediaAsset), audioProcessing: audioProcessing
                        ) {
                            audioSourceAsset = AVURLAsset(url: equalizedURL)
                        }
                        guard let sourceTrack = try await audioSourceAsset.loadTracks(withMediaType: .audio).first else { continue }
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
                // The graph master mix already contains every audio-capable
                // track; inserting legacy clip audio here would double it.
                guard !usesGraphMasterAudio else { continue }
                guard !track.isMuted, !(anyTrackSoloed && !track.isSolo) else { continue }

                let audioCompositionTrack = try makeCompositionTrack(in: composition, mediaType: .audio)
                let audioParameters = AVMutableAudioMixInputParameters()
                audioParameters.trackID = audioCompositionTrack.trackID

                for clip in track.clips.sorted(by: { $0.timelineRange.start < $1.timelineRange.start }) {
                    guard let assetId = clip.assetId,
                          let mediaAsset = project.mediaLibrary.assets[assetId] else {
                        continue
                    }

                    // G-25 2C-2 (spec §0 v1.1): an EQ'd clip consumes
                    // DERIVED effective media — the same render export and
                    // the graph use; the audio tap is retired.
                    let playbackSourceURL = playbackURL(for: mediaAsset)
                    var sourceAsset = AVURLAsset(url: playbackSourceURL)
                    if let equalizedURL = try await equalizedPreviewURL(
                        for: clip, inputURL: playbackSourceURL, audioProcessing: audioProcessing
                    ) {
                        sourceAsset = AVURLAsset(url: equalizedURL)
                    }
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

                    // Ordinary text uses the same shared Core Image processor as
                    // export. Besides removing the Preview↔Export implementation
                    // split, this avoids AVVideoCompositionCoreAnimationTool
                    // stalling in headless parity runs. Keep sticker layers on
                    // their established Core Animation path.
                    if !textContent.isSticker,
                       textContent.fontFamily != "Apple Color Emoji",
                       let textEffect = CustomCompositionClipEffect(
                           trackID: kCMPersistentTrackID_Invalid,
                           timeRange: CMTimeRange(
                               start: cmTime(clip.timelineRange.start),
                               duration: cmTime(clip.timelineRange.duration)
                           ),
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
                           textContent: textContent,
                           isBackgroundRemoved: clip.isBackgroundRemoved
                       ) {
                        textOverlayClipEffects.append(textEffect)
                        continue
                    }

                    let fontSize = CGFloat(textContent.fontSize)
                    let canvasSize = project.timeline.canvasSize
                    let fallbackPosition = CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
                    // Note: previously preview used exact `== 0` while export
                    // used an epsilon; the two disagreed at the boundary, which
                    // was a subtle preview↔export drift source. Both now use
                    // the epsilon comparison for parity.
                    let position: CGPoint
                    if abs(textContent.position.x) > 1.0e-9 || abs(textContent.position.y) > 1.0e-9 {
                        position = textContent.position
                    } else if abs(clip.transform.position.x) > 1.0e-9 || abs(clip.transform.position.y) > 1.0e-9 {
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

                    // Karaoke captions render into a single CATextLayer whose
                    // attributed string (per-word color) is refreshed on the
                    // playback tick. Falls through to the uniform-color layer for
                    // ordinary text, so non-karaoke clips are unchanged.
                    if textContent.karaokeEnabled,
                       let wordTimings = textContent.wordTimings,
                       !wordTimings.isEmpty,
                       let karaokeLayer = makeKaraokeTextLayer(
                           for: clip,
                           textContent: textContent,
                           fontSize: fontSize,
                           layerPosition: layerPosition,
                           canvasSize: canvasSize
                       ) {
                        textLayers.append(karaokeLayer.layer)
                        karaokeClips.append(
                            KaraokePreviewClip(
                                timelineStart: clip.timelineRange.start,
                                text: textContent.text,
                                wordTimings: wordTimings,
                                baseColor: textContent.fontColor,
                                highlightColor: textContent.highlightFontColor ?? textContent.fontColor,
                                alignment: textContent.alignment,
                                layer: karaokeLayer.layer,
                                font: karaokeLayer.font
                            )
                        )
                        continue
                    }

                    let textLayer = CATextLayer()
                    let fontName = textContent.fontFamily == "System" ? "Helvetica Neue" : textContent.fontFamily
                    let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)

                    textLayer.string = textContent.text
                    textLayer.font = font
                    textLayer.fontSize = fontSize
                    textLayer.foregroundColor = CompositionRenderHelpers.cgColor(hexRGB: textContent.fontColor)
                    textLayer.alignmentMode = CompositionRenderHelpers.textAlignmentMode(for: textContent.alignment)
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

        // G-26 Preview↔Export parity: with master processing enabled,
        // install the exact shared graph mix as Preview's SINGLE audio track.
        // The temp AAC joins the composition-build owned URL set.
        if usesGraphMasterAudio,
           let graphAudioURL = try await renderGraphPreviewAudio(
               for: project,
               audioProcessing: audioProcessing,
               tracks: renderTracks
           ) {
            temporaryReverseRenderURLs.append(graphAudioURL)
            let graphAudioAsset = AVURLAsset(url: graphAudioURL)
            if let graphAudioTrack = try await graphAudioAsset.loadTracks(withMediaType: .audio).first {
                let trackRange = try await graphAudioTrack.load(.timeRange)
                if trackRange.duration > .zero {
                    let previewAudioTrack = try makeCompositionTrack(in: composition, mediaType: .audio)
                    try previewAudioTrack.insertTimeRange(trackRange, of: graphAudioTrack, at: .zero)
                }
            }
        }

        let sortedVideoCompositionTracks = videoCompositionTracks.sorted { $0.zIndex > $1.zIndex }
        let videoComposition: AVMutableVideoComposition?
        if sortedVideoCompositionTracks.isEmpty {
            videoComposition = nil
        } else {
            let mutableVideoComposition = AVMutableVideoComposition()
            // Requirement 5: lower the *preview* render resolution when the user
            // picked a performance-priority quality. Export derives its size
            // from `project.canvas` + `ExportSettings.resolution` and never
            // reads this setting, so export output is unaffected. `.full` is a
            // no-op here. Thermal state also clamps the effective quality
            // (S7 gradual degradation: .fair+ caps it at 1/2) — routed through
            // the Core policy so the transition table is unit-testable.
            mutableVideoComposition.renderSize = PreviewRenderSize.resolve(
                canvas: project.timeline.canvasSize,
                quality: ProxyDowngradePolicy.effectivePreviewQuality(
                    user: project.playbackSettings.previewQuality,
                    thermalState: currentThermalState
                )
            )
            mutableVideoComposition.frameDuration = CMTime(
                seconds: 1 / max(project.timeline.frameRate.doubleValue, 1),
                preferredTimescale: 600
            )

            let transitionEffects = makeTransitionEffects(from: videoClipInstructions)
            // `isBackgroundRemoved` must route through the custom compositor:
            // the person-segmentation render only exists there, and the export
            // engine's trigger already includes it — leaving it out here made
            // preview silently ignore background removal while export applied
            // it (the same trigger-gap class as the G-23 Inc 1 cropRect bug;
            // reproduced 2026-08-17 with the compositor probe: bg-removal-only
            // project → preview_render_n=0 pre-fix).
            // Code-review #6: an adjustment layer needs the custom
            // compositor — the adjustment chain applies there (the
            // same trigger-gap class as cropRect/keyframes).
            let hasAdjustmentLayer = project.timeline.tracks
                .flatMap(\.clips)
                .contains { $0.isAdjustmentLayer }
            let usesCustomVideoCompositor = hasAdjustmentLayer || videoClipInstructions.contains { clipInstruction in
                clipInstruction.colorCorrection != nil
                    || clipInstruction.colorGrade != nil
                    || clipInstruction.chromaKey != nil
                    || clipInstruction.chromaKeyColor != nil
                    || clipInstruction.mask != nil
                    || !clipInstruction.effects.isEmpty
                    || clipInstruction.blendMode != .normal
                    || clipInstruction.cropRect != nil
                    || clipInstruction.isBackgroundRemoved
                    // Keyframed animation (motion tracking, manual keyframes)
                    // only renders through the custom compositor — the same
                    // trigger-gap class as cropRect / isBackgroundRemoved:
                    // ExportEngine's trigger includes keyframes, so without
                    // this the preview silently ignored keyframe-only clips
                    // (proved by the motion_tracking parity scenario).
                    || !clipInstruction.keyframes.isEmpty
                    // G-24 (#9): stabilization warps in the custom
                    // compositor — same trigger-gap class as keyframes.
                    || clipInstruction.stabilization != nil
            } || !transitionEffects.isEmpty || !textOverlayClipEffects.isEmpty
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
                // G-03: the timeline's adjustment clips (bottom-first,
                // full-timeline instruction — same granularity note as
                // the export side).
                let adjustmentClips: [Clip] = project.timeline.tracks
                    .filter { $0.kind == .video }
                    .sorted { $0.zIndex < $1.zIndex }
                    .flatMap(\.clips)
                    .filter(\.isAdjustmentLayer)
                mutableVideoComposition.instructions = [
                    CustomCompositionInstruction(
                        timeRange: CMTimeRange(start: .zero, duration: composition.duration),
                        trackIDs: sortedVideoCompositionTracks.map { $0.track.trackID },
                        clipEffects: videoClipInstructions.compactMap { clipInstruction in
                            CustomCompositionClipEffect(
                                trackID: clipInstruction.trackID,
                                timeRange: clipInstruction.timeRange,
                                transform: clipInstruction.clipTransform,
                                opacity: Double(clipInstruction.opacity),
                                keyframes: clipInstruction.keyframes,
                                colorCorrection: clipInstruction.colorCorrection,
                                colorGrade: clipInstruction.colorGrade,
                                chromaKey: clipInstruction.chromaKey,
                                chromaKeyColor: clipInstruction.chromaKeyColor,
                                chromaKeyThreshold: clipInstruction.chromaKeyThreshold,
                                mask: clipInstruction.mask,
                                effects: clipInstruction.effects,
                                isBackgroundRemoved: clipInstruction.isBackgroundRemoved,
                                blendMode: clipInstruction.blendMode,
                                cropRect: clipInstruction.cropRect,
                                stabilization: clipInstruction.stabilization
                            )
                        } + textOverlayClipEffects,
                        transitionEffects: transitionEffects,
                        canvasBackground: project.canvasBackground,
                        prefersFastSegmentation: true,
                        adjustmentClips: adjustmentClips.isEmpty ? nil : adjustmentClips
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

        // MARK: - Noise Reduction
        // G-25 2C-2: there is NO real-time NR filter in the preview
        // composition path (the historical comment described one that never
        // existed here). NR is an EDIT-TIME destructive transform
        // (`applyNoiseReduction` produces denoised media), so preview,
        // export, and the graph all consume the clip's derived media
        // identically (spec §0 v1.1).

        // MARK: - Audio Ducking
        if audioProcessing.duckLevel > 0, !audioProcessing.voiceClipIds.isEmpty {
            let duckMultiplier = 1.0 - audioProcessing.duckLevel
            var voiceTimeRanges: [(start: Double, end: Double)] = []
            let renderingTracks = renderingTracks(for: project)
            for projTrack in renderingTracks where projTrack.kind == .video {
                for clip in projTrack.clips where audioProcessing.voiceClipIds.contains(clip.id) {
                    voiceTimeRanges.append((clip.timelineRange.start, clip.timelineRange.end))
                }
            }
            // Lower volume of audio-track clips during voice ranges
            for mutableParams in audioMixInputParameters {
                for projTrack in renderingTracks where projTrack.kind == .audio {
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
        _ = displaySize
        TextAnimationRenderer.applyLayerAnimation(
            textAnimation,
            to: layer,
            canvasSize: canvasSize
        )
    }

    /// Renders Preview's project-level master audio through the same graph
    /// path used by export. AAC encoding is detached so the MainActor-owned
    /// player never synchronously encodes the whole timeline.
    private func renderGraphPreviewAudio(
        for project: Project,
        audioProcessing: ClipAudioProcessingOptions,
        tracks: [Track]
    ) async throws -> URL? {
        let mix: AudioGraphSourceAudio
        do {
            mix = try await GraphMixRenderer.renderMix(
                project: project,
                eqPresetsByClipId: audioProcessing.eqPresets,
                trimToAudibleSpan: false,
                tracks: tracks
            )
        } catch GraphMixRenderer.RenderError.noAudio {
            return nil
        }

        try Task.checkCancellation()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutGraphPreview-\(UUID().uuidString).m4a")
        do {
            try await Task.detached(priority: .userInitiated) {
                try AudioGraphAacEncoder.encode(mix, to: url)
            }.value
            try Task.checkCancellation()
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private func temporaryImageRenderURL(for clip: Clip) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutPlaybackImage-\(clip.id.uuidString)-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
    }

    private func cleanupTemporaryReverseRenderURLs() {
        removeTemporaryReverseRenderURLs(temporaryReverseRenderURLs)
        temporaryReverseRenderURLs = []
    }

    /// G-25 2C-2: the derived EQ media for a preview clip, rendered (and
    /// cached while the preset is unchanged) from the clip's playback URL.
    /// nil = no EQ applied. The temp files outlive composition rebuilds on
    /// purpose — re-rendering on every unrelated edit would be prohibitive
    /// — and are removed on clear/loadProject together with the cache.
    private func equalizedPreviewURL(
        for clip: Clip,
        inputURL: URL,
        audioProcessing: ClipAudioProcessingOptions
    ) async throws -> URL? {
        guard let preset = clip.resolvedEqualizerPreset(fallback: audioProcessing.eqPresets[clip.id]) else {
            return nil
        }
        if let cached = equalizedPreviewAudio[clip.id], cached.preset == preset {
            return cached.url
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutPreviewEQ-\(clip.id.uuidString)-\(UUID().uuidString).caf")
        try await AudioEqualizerService().apply(
            preset: preset, inputURL: inputURL, outputURL: outputURL
        )
        equalizedPreviewAudio[clip.id] = (preset, outputURL)
        temporaryEqualizedPreviewURLs.append(outputURL)
        return outputURL
    }

    private func cleanupTemporaryEqualizedPreviewURLs() {
        let fileManager = FileManager.default
        for url in temporaryEqualizedPreviewURLs where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
        temporaryEqualizedPreviewURLs = []
        equalizedPreviewAudio = [:]
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
        refreshKaraokeHighlights(at: seconds)
    }

    /// Recolors the per-word attributed string of each karaoke text layer for
    /// the current playback time. Called on the playback tick so the active
    /// word advances in lockstep with audio. A no-op when no karaoke clips are
    /// loaded, leaving ordinary playback untouched.
    private func refreshKaraokeHighlights(at timelineTime: TimeInterval) {
        guard !karaokeClips.isEmpty else { return }
        for clip in karaokeClips {
            let localTime = timelineTime - clip.timelineStart
            clip.layer.string = clip.attributedString(at: max(0, localTime))
        }
    }

    /// Alignment mapping for the karaoke text path. Mirrors
    /// `CompositionRenderHelpers.textAlignmentMode(for:)`; kept at class scope
    /// (static) because the build-composition helper that the uniform-color
    /// path uses is a nested local function, which cannot reach the shared
    /// helper directly.
    private static func karaokeAlignmentMode(for alignment: TextAlignment) -> CATextLayerAlignmentMode {
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

    /// Builds the single CATextLayer used for a karaoke caption. The layer's
    /// attributed string is seeded once here for t=0 and then refreshed by
    /// `refreshKaraokeHighlights` on each playback tick. Returns nil when the
    /// text tokens do not line up with the word timings, in which case the
    /// caller falls back to the ordinary uniform-color layer.
    private func makeKaraokeTextLayer(
        for clip: Clip,
        textContent: TextClipContent,
        fontSize: CGFloat,
        layerPosition: CGPoint,
        canvasSize: CGSize
    ) -> (layer: CATextLayer, font: NSFont)? {
        guard let wordTimings = textContent.wordTimings, !wordTimings.isEmpty else {
            return nil
        }

        let fontName = textContent.fontFamily == "System" ? "Helvetica Neue" : textContent.fontFamily
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)

        let textLayer = CATextLayer()
        textLayer.font = font
        textLayer.fontSize = fontSize
        textLayer.alignmentMode = Self.karaokeAlignmentMode(for: textContent.alignment)
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

        textLayer.beginTime = AVCoreAnimationBeginTimeAtZero + clip.timelineRange.start
        textLayer.duration = clip.timelineRange.duration

        let preview = KaraokePreviewClip(
            timelineStart: clip.timelineRange.start,
            text: textContent.text,
            wordTimings: wordTimings,
            baseColor: textContent.fontColor,
            highlightColor: textContent.highlightFontColor ?? textContent.fontColor,
            alignment: textContent.alignment,
            layer: textLayer,
            font: font
        )
        // Seed the initial state; the playback tick takes over from here.
        textLayer.string = preview.attributedString(at: 0)
        return (textLayer, font)
    }
}

/// Backing state for one karaoke text clip's live-preview recoloring.
private struct KaraokePreviewClip {
    let timelineStart: TimeInterval
    let text: String
    let wordTimings: [WordTiming]
    let baseColor: String
    let highlightColor: String
    let alignment: TextAlignment
    let layer: CATextLayer
    let font: NSFont

    /// Produces the per-word colored attributed string for the given clip-local
    /// time. Spoken and active words use `highlightColor`; upcoming words use
    /// `baseColor`. Returns the plain string (no attributes) when token/timing
    /// counts disagree, matching the export renderer's fallback behavior.
    ///
    /// Whitespace is preserved by building over the original `text` and applying
    /// color only to each word range — the same rule the export renderer uses
    /// (`TextOverlayPixelProcessor.karaokeWordRanges`), so preview and export
    /// never disagree on layout.
    func attributedString(at localTime: TimeInterval) -> NSAttributedString {
        let wordRanges = TextOverlayPixelProcessor.karaokeWordRanges(in: text)

        guard wordRanges.count == wordTimings.count else {
            return NSAttributedString(string: text)
        }

        let result = NSMutableAttributedString(string: text)
        result.addAttribute(.font, value: font, range: NSRange(location: 0, length: result.length))
        for (index, wordRange) in wordRanges.enumerated() {
            let hasBegun = wordTimings[index].startTime <= localTime
            let hex = hasBegun ? highlightColor : baseColor
            result.addAttribute(
                .foregroundColor,
                value: Self.color(hexRGB: hex),
                range: NSRange(wordRange, in: text)
            )
        }
        return result
    }

    /// Builds an `NSColor` from a `#RRGGBB` hex string. Mirrors the Core
    /// renderer's `CGColor` helper so preview colors match export output.
    private static func color(hexRGB: String) -> NSColor {
        guard let rgb = HexColorMath.rgb(fromHex: hexRGB) else {
            return NSColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
        return NSColor(
            calibratedRed: CGFloat(rgb.red),
            green: CGFloat(rgb.green),
            blue: CGFloat(rgb.blue),
            alpha: 1
        )
    }
}

private struct PlaybackClipInstructionMetadata {
    var timelineTrackID: UUID
    var trackID: CMPersistentTrackID
    var timeRange: CMTimeRange
    var transform: CGAffineTransform
    // The ORIGINAL ClipTransform (not the resolved affine above), carried for
    // the custom-compositor path, which applies transforms through
    // ClipAnimationCompositor instead of layer instructions. The plain path
    // keeps using `transform`; the custom path uses `clipTransform`.
    var clipTransform: ClipTransform
    var keyframes: [Keyframe]
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
    var blendMode: BlendMode = .normal
    var cropRect: NormalizedRect? = nil
    var stabilization: StabilizationPlan? = nil
}

private enum PlaybackPreviewAudioError: LocalizedError {
    case noPlayerItem
    case exportSessionCreationFailed

    var errorDescription: String? {
        switch self {
        case .noPlayerItem:
            return "Preview has no installed player item to render."
        case .exportSessionCreationFailed:
            return "Could not create the Preview audio export session."
        }
    }
}
