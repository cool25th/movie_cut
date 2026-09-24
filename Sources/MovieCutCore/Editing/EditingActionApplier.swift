import Foundation

/// P3 increment 2 — the applier: the bridge from typed agent actions to real
/// `EditorCommand`s applied through the session's proven contracts.
///
/// Contract (the agent-editing safety layer, pre-registered in CAPCUT_FEATURE
/// BACKLOG P3-01):
///   1. **Fail-closed**: every action in a script is validated (kernel
///      `plan()`) against the project BEFORE anything compiles or applies.
///      One invalid action rejects the whole script.
///   2. **Atomic**: the script compiles into a single
///      `EditingActionBatchCommand` — one `dispatch`, one undo unit, and the
///      batch itself applies to a draft so a mid-sequence failure cannot
///      mutate the session.
///   3. **Offline**: analysis-backed actions (`duckBackground`,
///      `removeSilence`) run the on-device `SpeechDuckingService` /
///      `SilenceDetectionProvider` — no provider, no network, ever.
///
/// The wire boundary for agents is `EditingActionDSL.decode` → this applier;
/// UI (and the future MCP surface) never hands raw timeline mutations to an
/// agent.
public enum EditingActionApplier {

    /// Typed failures that only occur at compile/apply time (the kernel's
    /// `PlanningError` covers everything knowable from the project alone).
    public enum ApplierError: Error, Equatable, Sendable {
        /// The clip references an asset id that is not in the media library.
        case assetMissing(UUID)
        /// The speech clip has no detectable voiced intervals to duck around.
        case noVoicedIntervals
    }

    /// What an applied script reports back to the calling surface.
    public struct ApplyReport: Equatable, Sendable {
        /// Actions in the applied script.
        public let actionCount: Int
        /// Real commands the script compiled to.
        public let commandCount: Int
        /// Undo units consumed — always 1 (the atomicity contract).
        public let undoUnits: Int
    }

    /// Validates every action first (fail-closed), then compiles the whole
    /// script into one batch command. Analysis-backed actions resolve their
    /// audio here, on-device.
    public static func compile(
        _ actions: [EditingActionDSL.Action],
        for project: Project
    ) async throws -> EditingActionBatchCommand {
        for action in actions {
            _ = try EditingActionDSL.plan(action, for: project)
        }
        var commands: [any EditorCommand] = []
        for action in actions {
            commands.append(contentsOf: try await compileOne(action, for: project))
        }
        return EditingActionBatchCommand(
            label: "agent plan (\(actions.count) action\(actions.count == 1 ? "" : "s"))",
            commands: commands
        )
    }

    /// Applies a script to a session as ONE undo unit. Throws before any
    /// mutation if any action is invalid or any analysis fails.
    @discardableResult
    public static func apply(
        _ actions: [EditingActionDSL.Action],
        to session: EditorSession
    ) async throws -> ApplyReport {
        let project = await session.snapshot()
        let batch = try await compile(actions, for: project)
        let commandCount = batch.commands.count
        try await session.dispatch(batch)
        return ApplyReport(
            actionCount: actions.count,
            commandCount: commandCount,
            undoUnits: 1
        )
    }

    // MARK: - Per-action compilation

    private static func compileOne(
        _ action: EditingActionDSL.Action,
        for project: Project
    ) async throws -> [any EditorCommand] {
        switch action {
        case let .deleteTimelineRange(start, end):
            let lower = min(start, end), upper = max(start, end)
            return [AutoCutCommand(removableRanges: [TimeRange(start: lower, duration: upper - lower)])]

        case let .keepTimelineRange(start, end):
            // Keep [lower, upper) by cutting its inverse — the N1 keep-only
            // reduction. The kernel already rejected the empty case.
            let lower = min(start, end), upper = max(start, end)
            let total = project.timeline.duration
            var removable: [TimeRange] = []
            if lower > 0.01 {
                removable.append(TimeRange(start: 0, duration: lower))
            }
            if upper < total - 0.01 {
                removable.append(TimeRange(start: upper, duration: total - upper))
            }
            return [AutoCutCommand(removableRanges: removable)]

        case let .deleteClip(clipId):
            return [DeleteClipCommand(clipId: clipId)]

        case let .splitClip(clipId, time):
            return [SplitClipCommand(clipId: clipId, splitTime: time)]

        case let .moveClip(clipId, timelineStart):
            let clip = try findClip(clipId, in: project)
            return [MoveClipCommand(
                clipId: clipId,
                newTimelineRange: TimeRange(
                    start: timelineStart,
                    duration: clip.timelineRange.duration
                )
            )]

        case let .setVolume(clipId, volume):
            return [SetVolumeCommand(clipId: clipId, volume: volume)]

        case let .setSpeed(clipId, rate):
            return [SetClipSpeedCommand(clipId: clipId, change: .constantRate(rate))]

        case let .applyAudioPreset(clipId, preset):
            return [SetClipPropertyCommand(
                clipId: clipId,
                property: .equalizer(ClipEqualizerSettings(preset: preset))
            )]

        case let .duckBackground(speechClipId):
            let speechClip = try findClip(speechClipId, in: project)
            let asset = try resolveAsset(for: speechClip, in: project)
            switch try await SpeechDuckingService.plan(project: project, speechClip: speechClip, asset: asset) {
            case let .ducked(rangesByClip, _):
                return [SetAudioDuckingCommand(
                    duckingRangesByClip: rangesByClip,
                    level: AudioDuckingPlanner.defaultDuckingLevel
                )]
            case .noVoicedIntervals:
                throw ApplierError.noVoicedIntervals
            case .noOverlappingAudio:
                // The kernel's pure validation already screens this; keep the
                // typed mapping if state shifted between validate and compile.
                throw EditingActionDSL.PlanningError.noOverlappingAudio
            }

        case let .removeSilence(clipId):
            let clip = try findClip(clipId, in: project)
            let asset = try resolveAsset(for: clip, in: project)
            let analysis = try await SilenceDetectionProvider().analyze(asset: asset, in: project)
            let silenceRanges = analysis.suggestions.flatMap { suggestion -> [TimeRange] in
                guard case .silenceRemoval(let ranges) = suggestion else { return [] }
                return ranges.compactMap { clip.timelineMapping(for: $0)?.timelineRange }
            }
            guard !silenceRanges.isEmpty else {
                throw EditingActionDSL.PlanningError.noSilenceDetected
            }
            return [AutoCutCommand(removableRanges: silenceRanges)]
        }
    }

    private static func findClip(_ clipId: UUID, in project: Project) throws -> Clip {
        for track in project.timeline.tracks {
            if let clip = track.clips.first(where: { $0.id == clipId }) {
                return clip
            }
        }
        throw EditingActionDSL.PlanningError.clipNotFound(clipId)
    }

    private static func resolveAsset(for clip: Clip, in project: Project) throws -> MediaAsset {
        guard let assetId = clip.assetId,
              let asset = project.mediaLibrary.assets[assetId] else {
            let missing = clip.assetId ?? clip.id
            throw ApplierError.assetMissing(missing)
        }
        return asset
    }
}
