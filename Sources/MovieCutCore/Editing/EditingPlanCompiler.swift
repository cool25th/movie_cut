import Foundation

/// Sequential compiler for agent/AI editing plans.
///
/// Evaluates each action against an evolving draft project so that subsequent actions
/// can validly reference tracks, assets, and clips created by preceding actions
/// (e.g. `createTrack` -> `registerAsset` -> `addClip` -> `setClipTransform`).
///
/// The entire sequence compiles into a single atomic `EditingActionBatchCommand`,
/// upholding fail-closed verification, all-or-nothing execution, and single-unit undo.
public enum EditingPlanCompiler {

    /// Compiles an ordered list of actions against a snapshot project and session revision.
    ///
    /// Throws immediately upon encountering any invalid action, preserving the original project
    /// and session completely untouched.
    public static func compile(
        _ actions: [EditingActionDSL.Action],
        for project: Project,
        baseRevision: SessionRevision,
        planId: UUID = UUID(),
        label: String? = nil
    ) async throws -> PreparedEditPlan {
        var draft = project
        var compiledCommands: [any EditorCommand] = []

        for action in actions {
            // 1. Validate the action against the current draft state
            _ = try EditingActionDSL.plan(action, for: draft)

            // 2. Compile the action into concrete EditorCommands
            let commands = try await compileOne(action, for: draft)

            // 3. Apply the commands to the draft so subsequent actions observe the changes
            for cmd in commands {
                try cmd.apply(to: &draft)
                compiledCommands.append(cmd)
            }
        }

        let batchLabel = label ?? "AI Plan (\(actions.count) action\(actions.count == 1 ? "" : "s"))"
        let batchCommand = EditingActionBatchCommand(
            id: planId,
            label: batchLabel,
            commands: compiledCommands
        )

        return PreparedEditPlan(
            planId: planId,
            baseRevision: baseRevision,
            batchCommand: batchCommand,
            expectedDuration: draft.timeline.duration
        )
    }

    // MARK: - Per-Action Compilation

    private static func compileOne(
        _ action: EditingActionDSL.Action,
        for project: Project
    ) async throws -> [any EditorCommand] {
        switch action {
        case let .deleteTimelineRange(start, end):
            let lower = min(start, end), upper = max(start, end)
            return [AutoCutCommand(removableRanges: [TimeRange(start: lower, duration: upper - lower)])]

        case let .keepTimelineRange(start, end):
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
                throw EditingActionApplier.ApplierError.noVoicedIntervals
            case .noOverlappingAudio:
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

        // MARK: - Synthesis & Assembly Actions

        case let .registerAsset(asset):
            return [ImportMediaCommand(asset: asset)]

        case let .createTrack(trackId, kind, name):
            let track = Track(id: trackId, kind: kind, name: name)
            return [CreateTrackCommand(track: track)]

        case let .addClip(clipId, trackId, assetId, timelineRange, sourceRange, kind):
            let track = project.timeline.tracks.first(where: { $0.id == trackId })
            let nextZIndex = (track?.clips.map(\.zIndex).max() ?? -1) + 1
            let clip = Clip(
                id: clipId,
                assetId: assetId,
                kind: kind,
                sourceRange: sourceRange,
                timelineRange: timelineRange,
                zIndex: nextZIndex
            )
            return [AddClipCommand(trackId: trackId, clip: clip)]

        case let .setClipTransform(clipId, transform):
            return [SetClipPropertyCommand(clipId: clipId, property: .transform(transform))]

        case let .setClipKeyframes(clipId, keyframes):
            return [SetClipPropertyCommand(clipId: clipId, property: .keyframes(keyframes))]

        case let .setClipTransition(clipId, transition):
            return [SetClipPropertyCommand(clipId: clipId, property: .transition(transition))]

        case let .setClipFade(clipId, fadeIn, fadeOut):
            return [AudioFadeCommand(clipId: clipId, fadeInDuration: fadeIn, fadeOutDuration: fadeOut)]

        case let .setClipTextContent(clipId, textContent):
            return [SetClipPropertyCommand(clipId: clipId, property: .textContent(textContent))]

        case let .setCanvas(canvas):
            return [SetProjectCanvasCommand(canvas: canvas)]
        }
    }

    // MARK: - Private Helpers

    private static func findClip(_ clipId: UUID, in project: Project) throws -> Clip {
        for track in project.timeline.tracks {
            if let clip = track.clips.first(where: { $0.id == clipId }) {
                return clip
            }
        }
        throw EditingActionDSL.PlanningError.clipNotFound(clipId)
    }

    private static func resolveAsset(for clip: Clip, in project: Project) throws -> MediaAsset {
        guard let assetId = clip.assetId, let asset = project.mediaLibrary.assets[assetId] else {
            throw EditingActionApplier.ApplierError.assetMissing(clip.assetId ?? UUID())
        }
        return asset
    }
}
