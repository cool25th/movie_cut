import Foundation
import Testing
@testable import MovieCutCore

/// P3 increment 3 — the local planner: ko/en instructions map to typed
/// actions (with rationale), and anything else fails closed with a typed
/// error. The destructive-safety property under test: the planner never
/// guesses a target — ordinals resolve exactly or throw, and every result
/// names the clip it will touch.
@Suite("Editing intent planner (P3 increment 3)")
struct EditingIntentPlannerTests {

    /// Three clips on one track: 0-4s, 4-10s (longest → default target),
    /// 10-12s. Ordinals are timeline order (1, 2, 3).
    private func makeProject() -> (Project, [UUID]) {
        let ids = [UUID(), UUID(), UUID()]
        let clips = ids.enumerated().map { index, id in
            let spans: [(Double, Double)] = [(0, 4), (4, 10), (10, 12)]
            let span = spans[index]
            return Clip(
                id: id,
                assetId: UUID(), kind: index == 0 ? .audio : .video,
                sourceRange: TimeRange(start: 0, duration: span.1 - span.0),
                timelineRange: TimeRange(start: span.0, duration: span.1 - span.0)
            )
        }
        let project = Project(
            name: "planner",
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V", zIndex: 0, clips: clips),
            ])
        )
        return (project, ids)
    }

    @Test("Range deletion and keep-only parse in both languages")
    func rangeIntents() throws {
        let (project, _) = makeProject()

        let deleteKo = try EditingIntentPlanner.plan(
            instruction: "2초부터 6초까지 삭제해줘", for: project)
        #expect(deleteKo.actions == [.deleteTimelineRange(start: 2, end: 6)])
        #expect(deleteKo.rationale.count == 1)

        let deleteEn = try EditingIntentPlanner.plan(
            instruction: "delete from 2s to 6s", for: project)
        #expect(deleteEn.actions == [.deleteTimelineRange(start: 2, end: 6)])

        let keepEn = try EditingIntentPlanner.plan(
            instruction: "keep only 2s to 6s", for: project)
        #expect(keepEn.actions == [.keepTimelineRange(start: 2, end: 6)])

        // 1분 30초 compound time: 90s.
        let compound = try EditingIntentPlanner.plan(
            instruction: "1분 30초부터 1분 40초까지 삭제", for: project)
        #expect(compound.actions == [.deleteTimelineRange(start: 90, end: 100)])
    }

    @Test("Split parses a single time and names the default target")
    func splitIntent() throws {
        let (project, ids) = makeProject()
        // Default target = longest clip (4-10s → ordinal 2).
        let ko = try EditingIntentPlanner.plan(instruction: "3초에서 잘라줘", for: project)
        #expect(ko.actions == [.splitClip(clipId: ids[1], time: 3)])
        #expect(ko.rationale[0].contains("#2"))

        let en = try EditingIntentPlanner.plan(instruction: "split at 5s", for: project)
        #expect(en.actions == [.splitClip(clipId: ids[1], time: 5)])
    }

    @Test("Volume, speed, and preset map with ordinals and defaults")
    func propertyIntents() throws {
        let (project, ids) = makeProject()

        // Percent, explicit ordinal ("두 번째" → marker-attached 2).
        let volumeKo = try EditingIntentPlanner.plan(
            instruction: "두 번째 클립 볼륨 50%", for: project)
        #expect(volumeKo.actions == [.setVolume(clipId: ids[1], volume: 0.5)])

        // Half-word, default target.
        let half = try EditingIntentPlanner.plan(
            instruction: "볼륨 절반으로", for: project)
        #expect(half.actions == [.setVolume(clipId: ids[1], volume: 0.5)])

        // Plain decimal ≤ 2 reads as a raw multiplier; English "clip 1".
        let volumeEn = try EditingIntentPlanner.plan(
            instruction: "set volume of clip 1 to 0.2", for: project)
        #expect(volumeEn.actions == [.setVolume(clipId: ids[0], volume: 0.2)])

        // Speed: "2배속" on the first clip ("첫 번째").
        let speedKo = try EditingIntentPlanner.plan(
            instruction: "첫 번째 클립 2배속", for: project)
        #expect(speedKo.actions == [.setSpeed(clipId: ids[0], rate: 2)])

        // Preset by name.
        let preset = try EditingIntentPlanner.plan(
            instruction: "음성 강조 적용해줘", for: project)
        #expect(preset.actions == [.applyAudioPreset(clipId: ids[1], preset: .voiceEnhance)])

        // The ordinal marker protects the operand: "clip 2 volume 50%"
        // must read 2 (marker) not 50 (operand).
        let ordinalNotOperand = try EditingIntentPlanner.plan(
            instruction: "clip 2 volume 50%", for: project)
        #expect(ordinalNotOperand.actions == [.setVolume(clipId: ids[1], volume: 0.5)])
    }

    @Test("Analysis intents plan typed actions")
    func analysisIntents() throws {
        let (project, ids) = makeProject()

        let duck = try EditingIntentPlanner.plan(
            instruction: "배경음악 덕킹해줘", for: project)
        #expect(duck.actions == [.duckBackground(speechClipId: ids[1])])

        let silence = try EditingIntentPlanner.plan(
            instruction: "remove the silence in the last clip", for: project)
        #expect(silence.actions == [.removeSilence(clipId: ids[2])])
    }

    @Test("Fail-closed: unknown instructions and out-of-range ordinals are typed errors")
    func failClosed() throws {
        let (project, _) = makeProject()

        #expect(throws: EditingIntentPlanner.PlannerError.unrecognized("오늘 날씨 어때")) {
            _ = try EditingIntentPlanner.plan(instruction: "오늘 날씨 어때", for: project)
        }
        // A delete keyword without two time literals never becomes a
        // destructive guess.
        #expect(throws: EditingIntentPlanner.PlannerError.self) {
            _ = try EditingIntentPlanner.plan(instruction: "삭제해줘", for: project)
        }
        // Ordinal 5 of 3 clips: typed range error, no fallback.
        #expect(throws: EditingIntentPlanner.PlannerError.clipOrdinal(5, count: 3)) {
            _ = try EditingIntentPlanner.plan(instruction: "5번째 클립 볼륨 50%", for: project)
        }

        // Empty timelines reject up front.
        let empty = Project(name: "empty", timeline: Timeline(
            canvasSize: CGSize(width: 320, height: 240),
            tracks: [Track(kind: .video, name: "V", zIndex: 0, clips: [])]))
        #expect(throws: EditingIntentPlanner.PlannerError.noClips) {
            _ = try EditingIntentPlanner.plan(instruction: "무음 제거", for: empty)
        }
    }

    @Test("Planner output composes with the applier end to end")
    func plannerFeedsApplier() async throws {
        let (project, ids) = makeProject()
        let session = EditorSession(project: project)

        let planned = try EditingIntentPlanner.plan(
            instruction: "2초부터 6초까지 삭제해줘", for: project)
        let report = try await EditingActionApplier.apply(planned.actions, to: session)

        #expect(report.actionCount == 1)
        #expect(report.undoUnits == 1)
        let after = await session.snapshot()
        let clips = after.timeline.tracks.flatMap(\.clips).sorted { $0.timelineRange.start < $1.timelineRange.start }
        // [2,6) removed across clips #1/#2: [0,2) + [6,10) survive, clip #3
        // ([10,12)) untouched — 3 clips, position-preserving.
        #expect(clips.count == 3)
        #expect(clips.map(\.timelineRange.start) == [0, 6, 10])
        #expect(clips.map(\.timelineRange.end) == [2, 10, 12])
        _ = ids
    }
}
