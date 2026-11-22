import Foundation
import MovieCutCore

// MARK: - Assistant provider wiring (F-21, requirement 10.3)

// The assistant UI reaches the editor through the `AIEditingProvider` protocol.
// `RuleBasedEditingProvider` (Core) wraps the existing `AssistantCommandParser`
// → `AssistantIntent` path, so this is a protocol seam inserted into the existing
// flow, not a new execution path. The intents the provider returns are dispatched
// through the same `executeAssistantIntent` used by the legacy direct-parse path.

extension EditorViewModel {

    /// The editing provider the assistant UI routes through.
    ///
    /// `RuleBasedEditingProvider` is a stateless value type, so a fresh instance per
    /// call is fine and avoids stored-property restrictions on extensions. It needs
    /// no network access and is deterministic (requirement 10.3 acceptance 4).
    private var assistantEditingProvider: any AIEditingProvider { RuleBasedEditingProvider() }

    /// Builds the structured project context snapshot (`AI-05`) and derives the
    /// lightweight `AIEditContext` handed to an `AIEditingProvider`.
    func buildProjectContextSnapshot(baseRevision: SessionRevision = SessionRevision(0)) -> ProjectContextSnapshot {
        ProjectContextBuilder.build(
            from: currentProject,
            baseRevision: baseRevision,
            selectedClipIds: selectedClipIds,
            playheadSeconds: playheadTime
        )
    }

    private func assistantContext() -> AIEditContext {
        buildProjectContextSnapshot().aiEditContext
    }

    /// Runs a natural-language instruction via `AIEditingProvider` and applies the
    /// resulting plan to the timeline through the existing intent executor.
    ///
    /// The provider is the primary path. When it reports no applicable action
    /// (`AIEditingError.noApplicableActions`), the suggestion list from the parser
    /// is surfaced so the user-visible "try one of the examples" UX is preserved.
    func executeAssistantPlan(for text: String) async {
        assistantResultMessage = nil
        assistantSuggestions = []

        let snapshot = await session.snapshotWithRevision()

        // 1. Follow-up montage duration rebalance (AI-05: e.g. "3번째 사진 2초 늘리고 전체 30초 유지")
        if let rebalanceRequest = PhotoMontagePlanner.parseRebalanceInstruction(text) {
            do {
                let actions = try PhotoMontagePlanner.planDurationRebalance(
                    project: snapshot.project,
                    request: rebalanceRequest
                )
                let prepared = try await EditingPlanCompiler.compile(
                    actions,
                    for: snapshot.project,
                    baseRevision: snapshot.revision,
                    label: "AI Montage Rebalance"
                )
                try await session.dispatch(
                    prepared.batchCommand,
                    planId: prepared.planId,
                    expectedRevision: snapshot.revision
                )
                try await refreshFromSession()
                assistantResultMessage = String(
                    format: NSLocalizedString(
                        "Rebalanced clip #%d (%+.1fs) while keeping %.1fs total.",
                        comment: "AI montage rebalance completion message"
                    ),
                    rebalanceRequest.targetClipOneBasedIndex,
                    rebalanceRequest.deltaSeconds,
                    prepared.expectedDuration
                )
                lastStatusMessage = assistantResultMessage
                return
            } catch {
                assistantResultMessage = error.localizedDescription
                lastStatusMessage = nil
                return
            }
        }

        // 2. Primary provider path (`AIEditingProvider`) compiled into an atomic, revision-checked batch (AI-04)
        do {
            let plan = try await assistantEditingProvider.plan(for: text, context: assistantContext())
            let mapped = compileIntentsToDSLActions(plan.intents, in: snapshot.project)
            if mapped.hadMissingTargets {
                assistantResultMessage = NSLocalizedString(
                    "No matching clips for that instruction.",
                    comment: "Assistant no matching clips message"
                )
                lastStatusMessage = nil
                return
            }
            guard !mapped.actions.isEmpty else {
                assistantResultMessage = NSLocalizedString(
                    "That instruction doesn't apply to the selected clips.",
                    comment: "Assistant inapplicable instruction message"
                )
                lastStatusMessage = nil
                return
            }

            let prepared = try await EditingPlanCompiler.compile(
                mapped.actions,
                for: snapshot.project,
                baseRevision: snapshot.revision,
                label: mapped.summaryLabel
            )
            try await session.dispatch(
                prepared.batchCommand,
                planId: prepared.planId,
                expectedRevision: snapshot.revision
            )
            try await refreshFromSession()
            assistantResultMessage = mapped.resultMessage
            lastStatusMessage = assistantResultMessage
            assistantSuggestions = []
        } catch AIEditingError.noApplicableActions {
            // 3. P3 deterministic intent planner (ko/en split, range delete/keep, speed, EQ, ducking, silence)
            if let p3Result = try? EditingIntentPlanner.plan(instruction: text, for: snapshot.project),
               !p3Result.actions.isEmpty {
                do {
                    let label = p3Result.rationale.first ?? "AI Edit Plan"
                    let prepared = try await EditingPlanCompiler.compile(
                        p3Result.actions,
                        for: snapshot.project,
                        baseRevision: snapshot.revision,
                        label: label
                    )
                    try await session.dispatch(
                        prepared.batchCommand,
                        planId: prepared.planId,
                        expectedRevision: snapshot.revision
                    )
                    try await refreshFromSession()
                    assistantResultMessage = p3Result.rationale.joined(separator: " · ")
                    lastStatusMessage = assistantResultMessage
                    assistantSuggestions = []
                    return
                } catch {
                    assistantResultMessage = error.localizedDescription
                    lastStatusMessage = nil
                    return
                }
            }

            // 4. Fall back to the parser's suggestions to preserve the existing UX.
            if case .unrecognized(let suggestions) = AssistantCommandParser.parse(text) {
                assistantSuggestions = suggestions
            }
            assistantResultMessage = NSLocalizedString(
                "I couldn't map that to an edit. Try one of the examples.",
                comment: "Assistant unrecognized command"
            )
            lastStatusMessage = nil
        } catch {
            assistantResultMessage = error.localizedDescription
            lastStatusMessage = nil
        }
    }

    private struct MappedAssistantActions {
        var actions: [EditingActionDSL.Action]
        var hadMissingTargets: Bool
        var summaryLabel: String
        var resultMessage: String
    }

    /// Maps legacy `AssistantIntent` values into typed `EditingActionDSL.Action` entries so
    /// all assistant edits compile through `EditingPlanCompiler` as one atomic batch.
    private func compileIntentsToDSLActions(
        _ intents: [AssistantIntent],
        in project: Project
    ) -> MappedAssistantActions {
        var actions: [EditingActionDSL.Action] = []
        var labels: [String] = []
        var markerOffset = 0

        for intent in intents {
            if case .addMarker = intent.action {
                markerOffset += 1
                let name = "Marker \(project.markers.count + markerOffset)"
                actions.append(.addMarker(name: name, time: playheadTime))
                labels.append(assistantActionLabel(intent.action))
                continue
            }

            let clips = assistantTargetClips(intent.target, in: project)
            if clips.isEmpty {
                return MappedAssistantActions(
                    actions: [],
                    hadMissingTargets: true,
                    summaryLabel: "Assistant Edit",
                    resultMessage: ""
                )
            }

            var appliedForIntent = 0
            for clip in clips {
                if let dslAction = dslAction(for: intent.action, clip: clip) {
                    actions.append(dslAction)
                    appliedForIntent += 1
                }
            }
            if appliedForIntent > 0 {
                labels.append("\(assistantActionLabel(intent.action)) applied to \(appliedForIntent) clip(s).")
            }
        }

        let resultMessage: String
        if intents.count == 1, case .addMarker = intents[0].action {
            resultMessage = "Added a marker at the playhead."
        } else {
            resultMessage = labels.joined(separator: " ")
        }

        return MappedAssistantActions(
            actions: actions,
            hadMissingTargets: false,
            summaryLabel: labels.first ?? "Assistant Edit",
            resultMessage: resultMessage
        )
    }

    private func dslAction(for action: AssistantAction, clip: Clip) -> EditingActionDSL.Action? {
        switch action {
        case .applyFilter(let type):
            guard clip.kind == .video || clip.kind == .image else { return nil }
            var effects = clip.effects.filter { $0.type != type }
            effects.append(Effect(type: type))
            return .setClipEffects(clipId: clip.id, effects: effects)

        case .removeFilters:
            guard !clip.effects.isEmpty else { return nil }
            return .setClipEffects(clipId: clip.id, effects: [])

        case .setVolume(let value):
            guard clip.kind == .video || clip.kind == .audio else { return nil }
            return .setVolume(clipId: clip.id, volume: value)

        case .setFade(let seconds):
            guard clip.kind == .video || clip.kind == .audio else { return nil }
            let clamped = min(max(seconds, 0), clip.timelineRange.duration / 2)
            return .setClipFade(clipId: clip.id, fadeIn: clamped, fadeOut: clamped)

        case .removeFade:
            guard clip.fadeInDuration > 0 || clip.fadeOutDuration > 0 else { return nil }
            return .setClipFade(clipId: clip.id, fadeIn: 0, fadeOut: 0)

        case .adjustBrightness(let delta):
            guard clip.kind == .video || clip.kind == .image else { return nil }
            let current = clip.colorCorrection ?? ColorCorrection()
            let updated = ColorCorrection(
                brightness: current.brightness + delta,
                contrast: current.contrast,
                saturation: current.saturation,
                warmth: current.warmth,
                tint: current.tint
            )
            return .setClipColorCorrection(clipId: clip.id, colorCorrection: updated)

        case .adjustContrast(let delta):
            guard clip.kind == .video || clip.kind == .image else { return nil }
            let current = clip.colorCorrection ?? ColorCorrection()
            let updated = ColorCorrection(
                brightness: current.brightness,
                contrast: current.contrast + delta,
                saturation: current.saturation,
                warmth: current.warmth,
                tint: current.tint
            )
            return .setClipColorCorrection(clipId: clip.id, colorCorrection: updated)

        case .adjustSaturation(let delta):
            guard clip.kind == .video || clip.kind == .image else { return nil }
            let current = clip.colorCorrection ?? ColorCorrection()
            let updated = ColorCorrection(
                brightness: current.brightness,
                contrast: current.contrast,
                saturation: current.saturation + delta,
                warmth: current.warmth,
                tint: current.tint
            )
            return .setClipColorCorrection(clipId: clip.id, colorCorrection: updated)

        case .addMarker:
            return nil
        }
    }

    /// Generates a photo montage video from attached photo and optional music URLs,
    /// compiles the sequence into an atomic batch, and commits it to the session.
    @discardableResult
    func applyPhotoMontage(
        photoURLs: [URL],
        musicURL: URL? = nil,
        targetDuration: TimeInterval = 15.0,
        targetCanvas: CanvasPreset = .portrait9x16
    ) async throws -> PreparedEditPlan {
        assistantResultMessage = nil
        assistantSuggestions = []

        // 1. Prepare and validate local assets
        let photoAssets = try PreparedAssetStore.preparePhotoAssets(from: photoURLs)
        let musicAsset: MediaAsset?
        if let musicURL {
            musicAsset = try await PreparedAssetStore.prepareMusicAsset(from: musicURL)
        } else {
            musicAsset = nil
        }

        // 2. Snapshot current project and session revision
        let snapshot = await session.snapshotWithRevision()

        // 3. Generate production plan
        let plan = try PhotoMontagePlanner.plan(
            photos: photoAssets,
            music: musicAsset,
            targetDuration: targetDuration,
            targetCanvas: targetCanvas,
            existingTracks: snapshot.project.timeline.tracks,
            baseRevision: snapshot.revision
        )

        // 4. Sequentially compile actions into a single atomic batch command
        let prepared = try await EditingPlanCompiler.compile(
            plan.actions,
            for: snapshot.project,
            baseRevision: snapshot.revision,
            planId: plan.planId,
            label: String(
                format: NSLocalizedString("AI Photo Montage (%d photos, %ds)", comment: "AI photo montage undo label"),
                photoURLs.count,
                Int(targetDuration)
            )
        )

        // 5. Commit batch atomically with expected revision check (includes canvas preset).
        // The plan id rides along so a double dispatch of the SAME prepared
        // batch (retry/double click) is rejected instead of duplicating clips.
        try await session.dispatch(
            prepared.batchCommand,
            planId: prepared.planId,
            expectedRevision: snapshot.revision
        )

        // 6. Refresh view model state from session
        try await refreshFromSession()
        assistantResultMessage = String(
            format: NSLocalizedString("Created %ds video with %d photo(s).", comment: "AI photo montage completion message"),
            Int(targetDuration),
            photoURLs.count
        )
        lastStatusMessage = assistantResultMessage
        return prepared
    }
}
