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
    }

    /// Why an action cannot be planned — typed, so a validator can reject
    /// agent output with machine reasons instead of guessing.
    public enum PlanningError: Error, Equatable, Sendable {
        case clipNotFound(UUID)
        case emptyRange
        case invalidRate(Double)
        case invalidVolume(Double)
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
