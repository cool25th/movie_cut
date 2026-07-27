import Foundation
import MovieCutCore
import Testing

/// Behavioral tests for the atomic speed-change command.
///
/// Step 4 of `docs/CAPCUT_CORE_EDITING_REPAIR_HANDOFF_20260727.md`. A speed
/// change must update the clip's rendered timeline duration, ripple the
/// magnetic main video track, leave free tracks untouched, and clamp stale
/// clip-local time fields — all in one undo step. These are pure command tests
/// (no CIContext, no StaticContract) and run under `swift test`.
@Suite("SetClipSpeedCommand")
struct SetClipSpeedCommandTests {
    private let minimumFrameTolerance = 1.0 / 30.0

    private func clip(
        sourceDuration: TimeInterval = 10,
        timelineDuration: TimeInterval? = nil,
        rate: Double = 1,
        start: TimeInterval = 0,
        kind: ClipKind = .video
    ) -> Clip {
        Clip(
            kind: kind,
            sourceRange: TimeRange(start: 0, duration: sourceDuration),
            timelineRange: TimeRange(start: start, duration: timelineDuration ?? sourceDuration / max(rate, 0.25)),
            playbackRate: rate
        )
    }

    private func project(clips: [Clip], trackKind: TrackKind = .video, extraTracks: [Track] = []) -> Project {
        var tracks = extraTracks
        // Prepend the main video track so it's the first .video track (magnetic).
        if trackKind == .video {
            tracks.insert(Track(kind: .video, name: "V1", zIndex: 0, clips: clips), at: 0)
        } else {
            tracks.append(Track(kind: trackKind, name: "T1", zIndex: 0, clips: clips))
        }
        return Project(name: "Test", timeline: Timeline(tracks: tracks))
    }

    // MARK: - Duration consistency (handoff acceptance)

    @Test("2x speed on a 10s source clip yields a 5s timeline duration")
    func constantRate2xDuration() throws {
        let c = clip(sourceDuration: 10, rate: 1)
        var project = project(clips: [c])
        let cmd = SetClipSpeedCommand(clipId: c.id, change: .constantRate(2.0))
        _ = try cmd.apply(to: &project)

        let updated = project.timeline.tracks[0].clips[0]
        #expect(updated.playbackRate == 2.0)
        #expect(abs(updated.timelineRange.duration - 5.0) <= minimumFrameTolerance)
    }

    @Test("0.5x speed on a 10s source clip yields a 20s timeline duration")
    func constantRateHalfDuration() throws {
        let c = clip(sourceDuration: 10, rate: 1)
        var project = project(clips: [c])
        let cmd = SetClipSpeedCommand(clipId: c.id, change: .constantRate(0.5))
        _ = try cmd.apply(to: &project)

        let updated = project.timeline.tracks[0].clips[0]
        #expect(abs(updated.timelineRange.duration - 20.0) <= minimumFrameTolerance)
    }

    @Test("Speed ramp duration matches the ClipTimeMapping rendered duration")
    func rampDurationMatchesMapping() throws {
        let ramp = [
            SpeedRampPoint(time: 0, rate: 1),
            SpeedRampPoint(time: 1, rate: 2)
        ]
        let c = clip(sourceDuration: 10, rate: 1)
        var project = project(clips: [c])
        let cmd = SetClipSpeedCommand(clipId: c.id, change: .rampPoints(ramp))
        _ = try cmd.apply(to: &project)

        let updated = project.timeline.tracks[0].clips[0]
        let mapping = try #require(updated.makeTimeMapping())
        #expect(abs(updated.timelineRange.duration - mapping.renderedTimelineDuration) <= minimumFrameTolerance)
    }

    // MARK: - Magnetic main-track ripple vs free-track preservation (Step 2 interplay)

    @Test("Main magnetic track ripples subsequent clips after a speed change")
    func mainTrackRipples() throws {
        let first = clip(sourceDuration: 10, rate: 1, start: 0)
        let second = clip(sourceDuration: 4, rate: 1, start: 10) // packed right after first
        var project = project(clips: [first, second])

        // Speed up the first clip to 2x -> its duration shrinks 10 -> 5; the
        // second clip should ripple from start 10 to start 5.
        _ = try SetClipSpeedCommand(clipId: first.id, change: .constantRate(2.0)).apply(to: &project)

        let clips = project.timeline.tracks[0].clips
        #expect(clips[0].id == first.id)
        #expect(abs(clips[0].timelineRange.duration - 5.0) <= minimumFrameTolerance)
        #expect(clips[1].id == second.id)
        #expect(abs(clips[1].timelineRange.start - 5.0) <= minimumFrameTolerance)
    }

    @Test("Free (non-main) track does not ripple subsequent clips")
    func freeTrackPreservesOffsets() throws {
        // A video track exists so the main track is well-defined, plus a text
        // track (free) with two clips.
        let mainVideo = clip(sourceDuration: 2, rate: 1, start: 0)
        let textFirst = clip(sourceDuration: 3, rate: 1, start: 0, kind: .text)
        let textSecond = clip(sourceDuration: 2, rate: 1, start: 5, kind: .text)
        var project = project(
            clips: [mainVideo],
            extraTracks: [Track(kind: .text, name: "T1", zIndex: 1, clips: [textFirst, textSecond])]
        )
        let textTrackId = project.timeline.tracks[1].id

        // Change the first text clip's speed to 2x -> its duration shrinks 3 -> 1.5;
        // the second text clip must NOT move (free track).
        _ = try SetClipSpeedCommand(
            clipId: textFirst.id,
            trackId: textTrackId,
            change: .constantRate(2.0)
        ).apply(to: &project)

        let textClips = project.timeline.tracks[1].clips
        #expect(abs(textClips[0].timelineRange.duration - 1.5) <= minimumFrameTolerance)
        // Second text clip keeps its 5s start.
        #expect(abs(textClips[1].timelineRange.start - 5.0) <= minimumFrameTolerance)
    }

    // MARK: - Stale field clamping

    @Test("Fade and ducking fields clamp to the new (smaller) duration")
    func staleFieldsClampOnShrink() throws {
        var c = clip(sourceDuration: 10, rate: 1)
        c.fadeInDuration = 8
        c.fadeOutDuration = 9
        c.duckingRanges = [
            TimeRange(start: 0, duration: 10),   // straddles the new end
            TimeRange(start: 6, duration: 6)      // past the new end
        ]
        var project = project(clips: [c])

        // 2x shrinks duration 10 -> 5; fades must clamp to 5, ducking to [0,5].
        _ = try SetClipSpeedCommand(clipId: c.id, change: .constantRate(2.0)).apply(to: &project)

        let updated = project.timeline.tracks[0].clips[0]
        #expect(updated.fadeInDuration <= 5.0)
        #expect(updated.fadeOutDuration <= 5.0)
        // Straddling range clamped to end at 5; the past-end range dropped.
        #expect(updated.duckingRanges.count == 1)
        #expect(updated.duckingRanges[0].end <= 5.0)
    }

    // MARK: - Undo/redo via session snapshot

    @Test("Undo restores the exact pre-change clip and track layout")
    func undoRestoresExactSnapshot() async throws {
        let first = clip(sourceDuration: 10, rate: 1, start: 0)
        let second = clip(sourceDuration: 4, rate: 1, start: 10)
        var project = project(clips: [first, second])
        let session = EditorSession(project: project)

        let before = await session.snapshot()

        try await session.dispatch(SetClipSpeedCommand(clipId: first.id, change: .constantRate(2.0)))
        let after = await session.snapshot()
        #expect(after.timeline.tracks[0].clips[0].playbackRate == 2.0)

        try await session.undo()
        let restored = await session.snapshot()
        // Whole-project snapshot undo: clip AND ripple must be exact.
        #expect(restored.timeline.tracks[0].clips == before.timeline.tracks[0].clips)
    }
}
