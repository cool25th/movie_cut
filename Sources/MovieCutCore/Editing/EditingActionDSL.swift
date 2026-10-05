import Foundation

/// P3 (direction consult): the typed editing-action DSL — the "agent-ready
/// editing kernel". An agent (or a user script) emits TYPED actions, never
/// free-form timeline mutations; the planner validates each action against
/// the current project and compiles it to existing `EditorCommand`s, so
/// preview (dry validation), apply, and undo all ride the session's proven
/// contracts (the torture suite locks undo exactness for arbitrary orders).
///
/// v1 action set (10) — deliberately the primitives the N1 transcript flow
/// and the audio presets already exercise:
///   deleteRange / keepRange / deleteClip / splitClip / moveClip /
///   setVolume / setSpeed / applyAudioPreset / duckBackground / removeSilence
///
/// Offline principle: the DSL is pure data + local planning; no provider,
/// network, or LLM is involved at this layer. UI exposure waits for the
/// consult's MVP promotion criteria (plan validity ≥95% on scripted sets,
/// intent match ≥90%, destructive-unrecoverable 0, undo recovery 100%).
public enum EditingActionDSL {

    /// One typed action (Codable — the wire form an agent emits).
    public enum Action: Codable, Equatable, Sendable {
        case deleteTimelineRange(start: TimeInterval, end: TimeInterval)
        case keepTimelineRange(start: TimeInterval, end: TimeInterval)
        case deleteClip(clipId: UUID)
        case splitClip(clipId: UUID, time: TimeInterval)
        case moveClip(clipId: UUID, timelineStart: TimeInterval)
        case setVolume(clipId: UUID, volume: Double)
        case setSpeed(clipId: UUID, rate: Double)
        case applyAudioPreset(clipId: UUID, preset: EqualizerPresetID)
        case duckBackground(speechClipId: UUID)
        case removeSilence(clipId: UUID)

        // Assembly & creation actions for AI video synthesis
        case registerAsset(asset: MediaAsset)
        case createTrack(trackId: UUID, kind: TrackKind, name: String)
        case addClip(clipId: UUID, trackId: UUID, assetId: UUID, timelineRange: TimeRange, sourceRange: TimeRange, kind: ClipKind)
        case setClipTransform(clipId: UUID, transform: ClipTransform)
        case setClipKeyframes(clipId: UUID, keyframes: [Keyframe])
        case setClipTransition(clipId: UUID, transition: Transition?)
        case setClipFade(clipId: UUID, fadeIn: TimeInterval, fadeOut: TimeInterval)
        case setClipTextContent(clipId: UUID, textContent: TextClipContent)
        case setCanvas(canvas: CanvasPreset)
    }

    /// Why an action cannot be planned — typed, so a validator can reject
    /// agent output with machine reasons instead of guessing.
    public enum PlanningError: Error, Equatable, Sendable {
        case clipNotFound(UUID)
        case trackNotFound(UUID)
        case trackAlreadyExists(UUID)
        case clipAlreadyExists(UUID)
        case assetNotFound(UUID)
        case assetAlreadyExists(UUID)
        case incompatibleAssetKind(clip: ClipKind, asset: MediaKind)
        case sourceRangeExceedsAssetDuration(requested: TimeInterval, duration: TimeInterval)
        case invalidTimeValue(String)
        case emptyRange
        case invalidRate(Double)
        case invalidVolume(Double)
        case invalidFade(Double)
        /// A new-content plan (e.g. a photo montage) was requested against a
        /// timeline that already carries clips — explicit placement modes
        /// are required, never an implicit overwrite.
        case timelineNotEmpty
        case clipNotAudio(UUID)
        case noSilenceDetected
        case noOverlappingAudio
    }

    /// The compiled plan: every command the action reduces to, in order.
    /// One action may compile to several commands (e.g. keepRange's inverse
    /// auto-cut); the caller dispatches them and the session's undo stack
    /// captures the outcome.
    public struct Plan: Equatable, Sendable {
        public let action: Action
        public let commands: [CommandBox]

        /// Commands are existential; equality rides a stable per-command
        /// box so tests can pin compiled plans.
        public struct CommandBox: Equatable, Sendable {
            public let kind: String
            public let clipId: UUID?
            public let detail: String

            init(kind: String, clipId: UUID? = nil, detail: String = "") {
                self.kind = kind
                self.clipId = clipId
                self.detail = detail
            }
        }
    }

    /// Validates and compiles one action against the project (pure — no
    /// session, no mutation). Throws `PlanningError` for invalid actions.
    public static func plan(
        _ action: Action,
        for project: Project
    ) throws -> [Plan.CommandBox] {
        func clip(_ id: UUID) throws -> (clip: Clip, trackId: UUID) {
            for track in project.timeline.tracks {
                if let clip = track.clips.first(where: { $0.id == id }) {
                    return (clip, track.id)
                }
            }
            throw PlanningError.clipNotFound(id)
        }

        switch action {
        case let .deleteTimelineRange(start, end):
            let lower = min(start, end), upper = max(start, end)
            guard upper - lower > 0.01 else { throw PlanningError.emptyRange }
            return [Plan.CommandBox(
                kind: "AutoCutCommand",
                detail: "delete[\(lower),\(upper))"
            )]

        case let .keepTimelineRange(start, end):
            let lower = min(start, end), upper = max(start, end)
            guard upper - lower > 0.01 else { throw PlanningError.emptyRange }
            let total = project.timeline.duration
            var detail = ""
            if lower > 0.01 { detail += "delete[0,\(lower)) " }
            if upper < total - 0.01 { detail += "delete[\(upper),\(total))" }
            guard !detail.isEmpty else { throw PlanningError.emptyRange }
            return [Plan.CommandBox(kind: "AutoCutCommand", detail: "keep[\(lower),\(upper)) via \(detail)")]

        case let .deleteClip(clipId):
            _ = try clip(clipId)
            return [Plan.CommandBox(kind: "DeleteClipCommand", clipId: clipId)]

        case let .splitClip(clipId, time):
            let target = try clip(clipId)
            let span = target.clip.timelineRange
            guard time > span.start, time < span.end else {
                // Splits at/beyond edges are no-ops, not plans.
                throw PlanningError.emptyRange
            }
            return [Plan.CommandBox(kind: "SplitClipCommand", clipId: clipId, detail: "at \(time)")]

        case let .moveClip(clipId, timelineStart):
            let target = try clip(clipId)
            guard timelineStart.isFinite, timelineStart >= 0 else {
                throw PlanningError.emptyRange
            }
            return [Plan.CommandBox(
                kind: "MoveClipCommand", clipId: clipId,
                detail: "start \(timelineStart) (was \(target.clip.timelineRange.start))"
            )]

        case let .setVolume(clipId, volume):
            _ = try clip(clipId)
            guard volume.isFinite, volume >= 0, volume <= 2 else {
                throw PlanningError.invalidVolume(volume)
            }
            return [Plan.CommandBox(kind: "SetVolumeCommand", clipId: clipId, detail: String(volume))]

        case let .setSpeed(clipId, rate):
            _ = try clip(clipId)
            guard rate.isFinite, rate >= 0.1, rate <= 10 else {
                throw PlanningError.invalidRate(rate)
            }
            return [Plan.CommandBox(kind: "SetClipSpeedCommand", clipId: clipId, detail: "\(rate)x")]

        case let .applyAudioPreset(clipId, preset):
            let target = try clip(clipId)
            guard target.clip.kind == .audio || target.clip.kind == .video else {
                throw PlanningError.clipNotAudio(clipId)
            }
            return [Plan.CommandBox(
                kind: "SetClipPropertyCommand(equalizer)", clipId: clipId,
                detail: preset.rawValue
            )]

        case let .duckBackground(speechClipId):
            let target = try clip(speechClipId)
            guard target.clip.kind == .audio || target.clip.kind == .video else {
                throw PlanningError.clipNotAudio(speechClipId)
            }
            guard project.timeline.tracks.contains(where: { track in
                track.kind == .audio && track.clips.contains {
                    $0.id != speechClipId && $0.timelineRange.overlaps(target.clip.timelineRange)
                }
            }) else {
                throw PlanningError.noOverlappingAudio
            }
            return [Plan.CommandBox(
                kind: "SetAudioDuckingCommand", clipId: speechClipId,
                detail: "via SpeechDuckingService"
            )]

        case let .removeSilence(clipId):
            _ = try clip(clipId)
            // Analysis happens at APPLY time (the planner cannot know the
            // audio content); the plan declares the reduction.
            return [Plan.CommandBox(kind: "AutoCutCommand(silence)", clipId: clipId, detail: "analysis at apply")]

        case let .registerAsset(asset):
            // Registration is NEW assets only: ANY existing id is rejected.
            // The old same-URL/same-kind carve-out silently overwrote the
            // stored metadata/bookmark (review 2026-10-05) — reusing an
            // asset means referencing it (`addClip`) without registering,
            // and refreshing stored metadata is the explicit
            // `UpdateMediaAssetCommand`.
            guard project.mediaLibrary.assets[asset.id] == nil else {
                throw PlanningError.assetAlreadyExists(asset.id)
            }
            guard asset.duration == nil || (asset.duration!.isFinite && asset.duration! > 0) else {
                throw PlanningError.invalidTimeValue(
                    "asset \(asset.originalURL.lastPathComponent) has an invalid duration (\(String(describing: asset.duration))) — probe it again"
                )
            }
            return [Plan.CommandBox(kind: "ImportMediaCommand", clipId: nil, detail: asset.originalURL.lastPathComponent)]

        case let .createTrack(trackId, _, name):
            if project.timeline.tracks.contains(where: { $0.id == trackId }) {
                throw PlanningError.trackAlreadyExists(trackId)
            }
            return [Plan.CommandBox(kind: "CreateTrackCommand", clipId: nil, detail: name)]

        case let .addClip(clipId, trackId, assetId, timelineRange, sourceRange, kind):
            guard project.timeline.tracks.contains(where: { $0.id == trackId }) else {
                throw PlanningError.trackNotFound(trackId)
            }
            if (try? clip(clipId)) != nil {
                throw PlanningError.clipAlreadyExists(clipId)
            }

            guard timelineRange.start.isFinite, timelineRange.start >= 0,
                  timelineRange.duration.isFinite, timelineRange.duration > 0,
                  sourceRange.start.isFinite, sourceRange.start >= 0,
                  sourceRange.duration.isFinite, sourceRange.duration > 0 else {
                throw PlanningError.invalidTimeValue("Clip timeline/source ranges must be finite, non-negative, and have positive duration")
            }

            guard let asset = project.mediaLibrary.assets[assetId] else {
                throw PlanningError.assetNotFound(assetId)
            }

            switch (kind, asset.kind) {
            case (.image, .image), (.image, .video):
                break
            case (.video, .video):
                break
            case (.audio, .audio), (.audio, .video):
                break
            case (.text, _):
                break
            default:
                throw PlanningError.incompatibleAssetKind(clip: kind, asset: asset.kind)
            }

            if kind != .image && kind != .text, let assetDuration = asset.duration {
                if sourceRange.end > assetDuration + 0.001 {
                    throw PlanningError.sourceRangeExceedsAssetDuration(requested: sourceRange.end, duration: assetDuration)
                }
            }

            return [Plan.CommandBox(kind: "AddClipCommand", clipId: clipId, detail: "\(kind) in \(trackId) asset:\(assetId)")]

        case let .setCanvas(canvas):
            return [Plan.CommandBox(kind: "SetProjectCanvasCommand", clipId: nil, detail: canvas.aspectRatio.rawValue)]

        case let .setClipTransform(clipId, transform):
            _ = try clip(clipId)
            guard transform.position.x.isFinite, transform.position.y.isFinite,
                  transform.offset.x.isFinite, transform.offset.y.isFinite,
                  transform.scale.width.isFinite, transform.scale.height.isFinite,
                  transform.scale.width > 0, transform.scale.height > 0,
                  transform.rotation.isFinite,
                  transform.anchorPoint.x.isFinite, transform.anchorPoint.y.isFinite
            else {
                throw PlanningError.invalidTimeValue(
                    "clip transform must be fully finite with positive scale"
                )
            }
            return [Plan.CommandBox(kind: "SetClipPropertyCommand(transform)", clipId: clipId)]

        case let .setClipKeyframes(clipId, keyframes):
            _ = try clip(clipId)
            for keyframe in keyframes {
                guard keyframe.time.isFinite, keyframe.time >= 0, keyframe.value.isFinite else {
                    throw PlanningError.invalidTimeValue(
                        "keyframe on clip \(clipId) must have finite value and finite time ≥ 0 (got time \(keyframe.time), value \(keyframe.value))"
                    )
                }
            }
            return [Plan.CommandBox(kind: "SetClipPropertyCommand(keyframes)", clipId: clipId, detail: "\(keyframes.count) keyframes")]

        case let .setClipTransition(clipId, transition):
            _ = try clip(clipId)
            return [Plan.CommandBox(kind: "SetClipPropertyCommand(transition)", clipId: clipId, detail: transition?.type.rawValue ?? "none")]

        case let .setClipFade(clipId, fadeIn, fadeOut):
            _ = try clip(clipId)
            guard fadeIn >= 0, fadeOut >= 0,
                  fadeIn.isFinite, fadeOut.isFinite else {
                throw PlanningError.invalidFade(min(fadeIn, fadeOut))
            }
            return [Plan.CommandBox(kind: "AudioFadeCommand", clipId: clipId, detail: "in:\(fadeIn), out:\(fadeOut)")]

        case let .setClipTextContent(clipId, textContent):
            _ = try clip(clipId)
            return [Plan.CommandBox(kind: "SetClipPropertyCommand(textContent)", clipId: clipId, detail: textContent.text)]
        }
    }

    /// Dry-runs a whole action script: returns per-action success so an
    /// agent's output can be validated BEFORE anything applies (the ≥95%
    /// plan-validity criterion's measuring stick).
    public static func validate(
        actions: [Action],
        for project: Project
    ) -> [Bool] {
        actions.map { action in
            (try? plan(action, for: project)) != nil
        }
    }

    /// Decodes the wire form (JSON array of typed actions). Unknown or
    /// malformed actions throw — an agent's output is never silently
    /// truncated (fail-closed).
    public static func decode(_ data: Data) throws -> [Action] {
        let decoder = JSONDecoder()
        return try decoder.decode([Action].self, from: data)
    }
}
