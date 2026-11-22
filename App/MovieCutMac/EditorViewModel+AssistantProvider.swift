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
    func buildProjectContextSnapshot(
        from project: Project? = nil,
        baseRevision: SessionRevision = SessionRevision(0)
    ) -> ProjectContextSnapshot {
        ProjectContextBuilder.build(
            from: project ?? currentProject,
            baseRevision: baseRevision,
            selectedClipIds: selectedClipIds,
            playheadSeconds: playheadTime
        )
    }

    private func assistantContext(
        for project: Project,
        baseRevision: SessionRevision
    ) -> AIEditContext {
        buildProjectContextSnapshot(from: project, baseRevision: baseRevision).aiEditContext
    }

    /// Commits a compiled plan immediately when non-destructive, or stages it for
    /// explicit user confirmation when it contains destructive timeline changes (CA-35).
    private func commitOrStageAssistantPlan(
        prepared: PreparedEditPlan,
        expectedRevision: SessionRevision,
        summary: String,
        completionMessage: String
    ) async throws {
        if prepared.containsDestructiveActions {
            pendingAssistantPlan = PendingAssistantPlan(
                prepared: prepared,
                expectedRevision: expectedRevision,
                summary: summary,
                completionMessage: completionMessage
            )
            assistantResultMessage = NSLocalizedString(
                "Review the planned edit below and click Apply to commit.",
                comment: "CA-35 assistant confirmation prompt"
            )
            lastStatusMessage = nil
            assistantSuggestions = []
            return
        }

        try await session.dispatch(
            prepared.batchCommand,
            planId: prepared.planId,
            expectedRevision: expectedRevision
        )
        try await refreshFromSession()
        pendingAssistantPlan = nil
        assistantResultMessage = completionMessage
        lastStatusMessage = completionMessage
        assistantSuggestions = []
    }

    /// Confirms and dispatches a staged destructive assistant plan after re-verifying
    /// its expected session revision against the live session (CA-35).
    func confirmPendingAssistantPlan() async {
        guard let pending = pendingAssistantPlan else { return }
        do {
            try await session.dispatch(
                pending.prepared.batchCommand,
                planId: pending.prepared.planId,
                expectedRevision: pending.expectedRevision
            )
            try await refreshFromSession()
            pendingAssistantPlan = nil
            assistantResultMessage = pending.completionMessage
            lastStatusMessage = pending.completionMessage
            assistantSuggestions = []
        } catch EditorCommandError.staleRevision {
            pendingAssistantPlan = nil
            assistantResultMessage = NSLocalizedString(
                "The timeline changed while reviewing this plan. Run the instruction again.",
                comment: "CA-35 stale revision rejection on confirmation"
            )
            lastStatusMessage = nil
        } catch {
            pendingAssistantPlan = nil
            assistantResultMessage = error.localizedDescription
            lastStatusMessage = nil
        }
    }

    /// Discards a staged destructive assistant plan without modifying the session.
    func cancelPendingAssistantPlan() {
        guard pendingAssistantPlan != nil else { return }
        pendingAssistantPlan = nil
        assistantResultMessage = NSLocalizedString(
            "Cancelled pending edit plan.",
            comment: "CA-35 assistant plan cancelled message"
        )
        lastStatusMessage = nil
    }

    /// Runs a natural-language instruction via `AIEditingProvider` and applies the
    /// resulting plan to the timeline (staging destructive plans for confirmation).
    func executeAssistantPlan(for text: String) async {
        assistantResultMessage = nil
        assistantSuggestions = []
        pendingAssistantPlan = nil

        let snapshot = await session.snapshotWithRevision()

        // 1. Follow-up montage duration rebalance (AI-05: e.g. "3번째 사진 2초 늘리고 전체 30초 유지")
        if let rebalanceRequest = PhotoMontagePlanner.parseRebalanceInstruction(text) {
            do {
                let actions = try PhotoMontagePlanner.planDurationRebalance(
                    project: snapshot.project,
                    request: rebalanceRequest
                )
                let summary = String(
                    format: NSLocalizedString(
                        "Rebalance clip #%d (%+.1fs)",
                        comment: "AI montage rebalance confirmation summary"
                    ),
                    rebalanceRequest.targetClipOneBasedIndex,
                    rebalanceRequest.deltaSeconds
                )
                let prepared = try await EditingPlanCompiler.compile(
                    actions,
                    for: snapshot.project,
                    baseRevision: snapshot.revision,
                    label: "AI Montage Rebalance",
                    summaryLines: [summary]
                )
                let completionMessage = String(
                    format: NSLocalizedString(
                        "Rebalanced clip #%d (%+.1fs) while keeping %.1fs total.",
                        comment: "AI montage rebalance completion message"
                    ),
                    rebalanceRequest.targetClipOneBasedIndex,
                    rebalanceRequest.deltaSeconds,
                    prepared.expectedDuration
                )
                try await commitOrStageAssistantPlan(
                    prepared: prepared,
                    expectedRevision: snapshot.revision,
                    summary: summary,
                    completionMessage: completionMessage
                )
                return
            } catch {
                assistantResultMessage = error.localizedDescription
                lastStatusMessage = nil
                return
            }
        }

        // 2. Primary provider path (`AIEditingProvider`) compiled into an atomic, revision-checked batch (AI-04)
        do {
            let context = assistantContext(for: snapshot.project, baseRevision: snapshot.revision)
            let plan = try await assistantEditingProvider.plan(for: text, context: context)
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
                label: mapped.summaryLabel,
                summaryLines: [mapped.resultMessage]
            )
            try await commitOrStageAssistantPlan(
                prepared: prepared,
                expectedRevision: snapshot.revision,
                summary: mapped.resultMessage,
                completionMessage: mapped.resultMessage
            )
        } catch AIEditingError.noApplicableActions {
            // 3. P3 deterministic intent planner (ko/en split, range delete/keep, speed, EQ, ducking, silence)
            do {
                let p3Result = try EditingIntentPlanner.plan(instruction: text, for: snapshot.project)
                if !p3Result.actions.isEmpty {
                    let label = p3Result.rationale.first ?? "AI Edit Plan"
                    let summary = p3Result.rationale.joined(separator: " · ")
                    let prepared = try await EditingPlanCompiler.compile(
                        p3Result.actions,
                        for: snapshot.project,
                        baseRevision: snapshot.revision,
                        label: label,
                        summaryLines: p3Result.rationale
                    )
                    try await commitOrStageAssistantPlan(
                        prepared: prepared,
                        expectedRevision: snapshot.revision,
                        summary: summary,
                        completionMessage: summary
                    )
                    return
                }
            } catch EditingIntentPlanner.PlannerError.unrecognized {
                // Fall through to suggestion list below.
            } catch EditingIntentPlanner.PlannerError.noClips {
                assistantResultMessage = NSLocalizedString(
                    "Add at least one clip to the timeline before running that instruction.",
                    comment: "Assistant planner no clips error"
                )
                lastStatusMessage = nil
                return
            } catch EditingIntentPlanner.PlannerError.clipOrdinal(let requested, let count) {
                assistantResultMessage = String(
                    format: NSLocalizedString(
                        "Clip #%d is out of range (timeline has %d clip(s)).",
                        comment: "Assistant planner clip ordinal out of range error"
                    ),
                    requested,
                    count
                )
                lastStatusMessage = nil
                return
            } catch EditingIntentPlanner.PlannerError.noTime {
                assistantResultMessage = NSLocalizedString(
                    "Specify a timestamp (e.g. 3s) for that instruction.",
                    comment: "Assistant planner missing timestamp error"
                )
                lastStatusMessage = nil
                return
            } catch {
                assistantResultMessage = error.localizedDescription
                lastStatusMessage = nil
                return
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
                labels.append(
                    String(
                        format: NSLocalizedString(
                            "%@ applied to %d clip(s).",
                            comment: "Assistant action applied to clip count"
                        ),
                        assistantActionLabel(intent.action),
                        appliedForIntent
                    )
                )
            }
        }

        let resultMessage: String
        if intents.count == 1, case .addMarker = intents[0].action {
            resultMessage = NSLocalizedString(
                "Added a marker at the playhead.",
                comment: "Assistant added marker message"
            )
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
                brightness: min(max(current.brightness + delta, -1.0), 1.0),
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
                contrast: min(max(current.contrast + delta, 0.0), 2.0),
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
                saturation: min(max(current.saturation + delta, 0.0), 2.0),
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
