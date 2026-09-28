// P3 semantic contract (32nd-cycle feedback): the agent-ready kernel is
// pinned by four semantic invariants that must hold for EVERY action —
// locking them is worth more than widening action breadth.
//
//   1. invalid action   → no mutation (a rejected script leaves the project
//                         byte-identical, not just "mostly untouched")
//   2. ambiguous plan   → no destructive inference (a typed rejection with
//                         zero compiled commands — never a best-effort guess)
//   3. replay           → identical resulting state (the same script on two
//                         fresh sessions from the same start converges)
//   4. serialize/decode → semantic-equivalent plan (JSON round-trip compiles
//                         to the SAME command boxes as the original action)
//
// Scope note: contracts 1 is asserted project-WIDE via canonical JSON of the
// whole Project (not spot fields) so an unexpected mutation anywhere fails.

import Foundation
import Testing
@testable import MovieCutCore

@Suite("Editing action semantic contracts (P3)")
struct EditingSemanticContractTests {

    private func makeProject() -> (Project, UUID) {
        let clipId = UUID()
        let clip = Clip(
            id: clipId,
            assetId: UUID(), kind: .video,
            sourceRange: TimeRange(start: 0, duration: 10),
            timelineRange: TimeRange(start: 0, duration: 10)
        )
        let project = Project(
            name: "semantic-contracts",
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V", zIndex: 0, clips: [clip]),
            ])
        )
        return (project, clipId)
    }

    /// Canonical whole-project state: JSON bytes of the project. Any mutation
    /// anywhere in the tree changes the digest — spot-field checks can miss.
    private func canonicalJSON(_ project: Project) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(project)
    }

    @Test("contract 1 — an invalid script leaves the whole project byte-identical")
    func invalidActionNoMutation() async throws {
        let (project, clipId) = makeProject()
        let before = try canonicalJSON(project)
        let session = EditorSession(project: project)

        await #expect(throws: EditingActionDSL.PlanningError.self) {
            try await EditingActionApplier.apply([
                .setVolume(clipId: clipId, volume: 0.2),   // valid prefix
                .deleteClip(clipId: UUID()),               // invalid suffix
            ], to: session)
        }

        let dispatched = await session.commandCount
        #expect(dispatched == 0, "nothing dispatched for a rejected script")
        let after = try canonicalJSON(await session.snapshot())
        #expect(after == before, "a rejected script must leave EVERY field identical")
    }

    @Test("contract 2 — ambiguous plans are typed rejections with zero commands, never guesses")
    func ambiguousPlanNoDestructiveInference() throws {
        let (project, clipId) = makeProject()

        // Each ambiguous/invalid request must throw a TYPED reason and yield
        // no plan at all — a best-effort destructive fallback would surface
        // as a compiled command box here. (removeSilence is intentionally
        // absent: its content analysis happens at APPLY time by design — the
        // planner only validates the target exists.)
        let missingId = UUID()
        let ambiguous: [(EditingActionDSL.Action, EditingActionDSL.PlanningError)] = [
            (.deleteTimelineRange(start: 5, end: 5), .emptyRange),
            (.keepTimelineRange(start: 7, end: 7), .emptyRange),
            (.setSpeed(clipId: clipId, rate: 0), .invalidRate(0)),
            (.setVolume(clipId: clipId, volume: -1), .invalidVolume(-1)),
            (.deleteClip(clipId: missingId), .clipNotFound(missingId)),
            (.duckBackground(speechClipId: clipId), .noOverlappingAudio),
        ]
        for (action, expected) in ambiguous {
            do {
                _ = try EditingActionDSL.plan(action, for: project)
                Issue.record("ambiguous input \(action) produced a plan — destructive inference")
            } catch let error as EditingActionDSL.PlanningError {
                #expect(error == expected, "\(action) rejected with the wrong typed reason")
            }
        }
    }

    @Test("contract 3 — replaying a script on fresh sessions converges to identical state")
    func replayIdenticalState() async throws {
        let (projectA, clipIdA) = makeProject()
        let (projectB, clipIdB) = makeProject()
        // Same semantic start — distinct UUIDs are fine as long as the SCRIPT
        // is rebuilt per session against its own ids.
        let script: (UUID) -> [EditingActionDSL.Action] = { clip in
            [
                .deleteTimelineRange(start: 2, end: 6),
                .setVolume(clipId: clip, volume: 0.5),
                .splitClip(clipId: clip, time: 1),
            ]
        }

        let sessionA = EditorSession(project: projectA)
        let sessionB = EditorSession(project: projectB)
        _ = try await EditingActionApplier.apply(script(clipIdA), to: sessionA)
        _ = try await EditingActionApplier.apply(script(clipIdB), to: sessionB)

        let stateA = try canonicalJSON(await sessionA.snapshot())
        let stateB = try canonicalJSON(await sessionB.snapshot())
        // Raw byte counts differ legitimately (per-session UUIDs, embedded
        // timestamps) — the CONTRACT is semantic convergence, asserted on
        // the deterministic shape (clip extents + volumes in track order).
        let shapeA = await semanticShape(sessionA)
        let shapeB = await semanticShape(sessionB)
        #expect(shapeA == shapeB, "replay must converge to the same semantic state")
    }

    private func semanticShape(_ session: EditorSession) async -> [[String]] {
        let project = await session.snapshot()
        return project.timeline.tracks.map { track in
            track.clips
                .sorted { $0.timelineRange.start < $1.timelineRange.start }
                .map { "\($0.timelineRange.start)-\($0.timelineRange.end):v\($0.volume)" }
        }
    }

    @Test("contract 4 — JSON round-trip compiles to the identical command plan")
    func serializationRoundTripSemanticEquivalent() throws {
        let (project, clipId) = makeProject()
        // duckBackground is excluded here: this project shape has no audio
        // track, so its typed rejection (.noOverlappingAudio) is already
        // pinned by contract 2 — the round-trip set is plan-valid actions.
        let actions: [EditingActionDSL.Action] = [
            .deleteTimelineRange(start: 2, end: 6),
            .keepTimelineRange(start: 1, end: 9),
            .splitClip(clipId: clipId, time: 3),
            .moveClip(clipId: clipId, timelineStart: 1),
            .setVolume(clipId: clipId, volume: 0.5),
            .setSpeed(clipId: clipId, rate: 1.5),
            .applyAudioPreset(clipId: clipId, preset: .voiceEnhance),
            .removeSilence(clipId: clipId),
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()

        for action in actions {
            let plans = try EditingActionDSL.plan(action, for: project)
            let data = try encoder.encode([action])
            let decoded = try decoder.decode([EditingActionDSL.Action].self, from: data)
            #expect(decoded == [action], "\(action) must round-trip Equatable")
            let plansAfter = try EditingActionDSL.plan(decoded[0], for: project)
            #expect(plansAfter == plans,
                    "\(action) round-trip must compile to the IDENTICAL command boxes")
        }
    }
}
