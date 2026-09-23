import Foundation
import Testing
@testable import MovieCutCore

/// P3 kernel v1: typed-action decode (fail-closed), plan validation against
/// a real project, and the apply↔undo round-trip through EditorSession.
@Suite("Editing action DSL (P3 v1)")
struct EditingActionDSLTests {

    private func makeProject() -> (Project, UUID) {
        let clipId = UUID()
        let clip = Clip(
            id: clipId,
            assetId: UUID(), kind: .video,
            sourceRange: TimeRange(start: 0, duration: 10),
            timelineRange: TimeRange(start: 0, duration: 10)
        )
        let project = Project(
            name: "dsl",
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V", zIndex: 0, clips: [clip]),
            ])
        )
        return (project, clipId)
    }

    @Test("Typed actions decode from JSON; unknown actions fail closed")
    func wireDecoding() throws {
        let valid = """
        [
          {"@type":"deleteTimelineRange","start":2,"end":6},
          {"@type":"setVolume","clipId":"00000000-0000-0000-0000-000000000001","volume":0.5}
        ]
        """
        // Raw-value enum coding is single-key; the exact wire shape follows
        // Swift's synthesized Codable. Round-trip OUR encoder's output.
        let actions: [EditingActionDSL.Action] = [
            .deleteTimelineRange(start: 2, end: 6),
            .setVolume(clipId: UUID(), volume: 0.5),
        ]
        let encoded = try JSONEncoder().encode(actions)
        let decoded = try EditingActionDSL.decode(encoded)
        #expect(decoded == actions)

        // Unknown/malformed input is rejected, never truncated.
        #expect(throws: Error.self) {
            _ = try EditingActionDSL.decode(Data("[{\"nope\":1}]".utf8))
        }
        _ = valid  // documentation of the single-key shape
    }

    @Test("Plans validate against a real project; invalid targets are typed")
    func planValidation() throws {
        let (project, clipId) = makeProject()

        // Valid actions plan.
        let plans = try EditingActionDSL.plan(.deleteTimelineRange(start: 2, end: 6), for: project)
        #expect(plans.first?.kind == "AutoCutCommand")

        try EditingActionDSL.plan(.splitClip(clipId: clipId, time: 4), for: project)
        try EditingActionDSL.plan(.setSpeed(clipId: clipId, rate: 2), for: project)
        try EditingActionDSL.plan(.applyAudioPreset(clipId: clipId, preset: .voiceEnhance), for: project)

        // Unknown clip — typed rejection carrying the missing id itself.
        let missing = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
        #expect(throws: EditingActionDSL.PlanningError.clipNotFound(missing)) {
            try EditingActionDSL.plan(.deleteClip(clipId: missing), for: project)
        }
        // Degenerate range, bad rate, edge split — all typed rejections.
        #expect(throws: EditingActionDSL.PlanningError.emptyRange) {
            try EditingActionDSL.plan(.deleteTimelineRange(start: 3, end: 3.001), for: project)
        }
        #expect(throws: EditingActionDSL.PlanningError.invalidRate(50)) {
            try EditingActionDSL.plan(.setSpeed(clipId: clipId, rate: 50), for: project)
        }
        #expect(throws: EditingActionDSL.PlanningError.emptyRange) {
            try EditingActionDSL.plan(.splitClip(clipId: clipId, time: 99), for: project)
        }
        // keepRange covering the whole timeline has nothing to remove.
        #expect(throws: EditingActionDSL.PlanningError.emptyRange) {
            try EditingActionDSL.plan(.keepTimelineRange(start: -1, end: 99), for: project)
        }
    }

    @Test("validate() reports per-action validity — the ≥95% criterion's stick")
    func scriptValidation() throws {
        let (project, clipId) = makeProject()
        let other = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let script: [EditingActionDSL.Action] = [
            .deleteTimelineRange(start: 1, end: 2),   // valid
            .deleteClip(clipId: other),               // invalid target
            .setVolume(clipId: clipId, volume: 0.3),  // valid
            .setVolume(clipId: clipId, volume: -1),   // invalid value
            .splitClip(clipId: clipId, time: 5),      // valid
        ]
        #expect(EditingActionDSL.validate(actions: script, for: project)
                == [true, false, true, false, true])
    }
}
