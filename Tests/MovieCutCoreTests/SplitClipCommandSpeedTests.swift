import Foundation
import MovieCutCore
import Testing

/// Behavioral tests for speed-aware split, focusing on speed-ramp point
/// re-normalization after a split.
///
/// Step 5 of `docs/CAPCUT_CORE_EDITING_REPAIR_HANDOFF_20260727.md`. After a
/// split, each resulting clip's `speedRampPoints` must be re-normalized to span
/// [0,1] of its own source sub-range; otherwise each curve would reference the
/// parent's source domain and render at the wrong speed.
@Suite("SplitClipCommand speed-aware")
struct SplitClipCommandSpeedTests {
    private let tolerance = 1.0 / 30.0

    private func project(with clip: Clip) -> Project {
        Project(name: "Test", timeline: Timeline(tracks: [
            Track(kind: .video, name: "V1", zIndex: 0, clips: [clip])
        ]))
    }

    @Test("Speed-ramp split re-normalizes points to each sub-range")
    func rampSplitRenormalizes() throws {
        // 10s source, 1x baseline, a ramp from 1x (t=0) to 2x (t=1).
        let ramp = [
            SpeedRampPoint(time: 0, rate: 1),
            SpeedRampPoint(time: 1, rate: 2)
        ]
        let clip = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 10),
            timelineRange: TimeRange(start: 0, duration: 10),
            playbackRate: 1,
            speedRampPoints: ramp
        )
        var project = project(with: clip)

        // Split at the source midpoint (timeline 5s == source 5s at the 1x
        // start of the ramp, close enough for the boundary).
        _ = try SplitClipCommand(clipId: clip.id, splitTime: 5.0).apply(to: &project)

        let clips = project.timeline.tracks[0].clips
        #expect(clips.count == 2)
        let first = clips[0]
        let second = clips[1]

        // Each sub-clip must have at least 2 ramp points spanning [0,1] of its
        // own source sub-range.
        #expect(first.speedRampPoints.count >= 2)
        #expect(second.speedRampPoints.count >= 2)
        // First point of each sub-clip should be at normalized time ~0, last ~1.
        #expect(abs(first.speedRampPoints.first!.time) < 0.001)
        #expect(abs(first.speedRampPoints.last!.time - 1.0) < 0.001)
        #expect(abs(second.speedRampPoints.first!.time) < 0.001)
        #expect(abs(second.speedRampPoints.last!.time - 1.0) < 0.001)
    }

    @Test("Non-ramp split leaves speedRampPoints empty on both halves")
    func nonRampSplitStaysEmpty() throws {
        let clip = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 10),
            timelineRange: TimeRange(start: 0, duration: 5),
            playbackRate: 2
        )
        var project = project(with: clip)

        _ = try SplitClipCommand(clipId: clip.id, splitTime: 2.5).apply(to: &project)

        let clips = project.timeline.tracks[0].clips
        #expect(clips[0].speedRampPoints.isEmpty)
        #expect(clips[1].speedRampPoints.isEmpty)
        // Constant rate is preserved on both halves.
        #expect(clips[0].playbackRate == 2)
        #expect(clips[1].playbackRate == 2)
    }

    @Test("2x clip split maps timeline boundary to source via the mapping")
    func constantRateSplitUsesMapping() throws {
        // 10s source at 2x -> 5s timeline. Split at timeline 2s should hit
        // source 4s.
        let clip = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 10),
            timelineRange: TimeRange(start: 0, duration: 5),
            playbackRate: 2
        )
        var project = project(with: clip)

        _ = try SplitClipCommand(clipId: clip.id, splitTime: 2.0).apply(to: &project)

        let clips = project.timeline.tracks[0].clips
        // First half covers source 0..4.
        #expect(abs(clips[0].sourceRange.end - 4.0) <= tolerance)
        // Second half covers source 4..10.
        #expect(abs(clips[1].sourceRange.start - 4.0) <= tolerance)
    }

    // MARK: - Reverse-clip split

    @Test("Reverse clip split assigns the upper source sub-range to the first half")
    func reverseClipSplitAssignsUpperSourceToFirstHalf() throws {
        // 10s source at 1x, reversed: timeline advances forward while source
        // walks 10 -> 0. Splitting at timeline 4s lands on source 6s. The
        // timeline-LEFT half has already played 10 -> 6, so it owns the UPPER
        // source sub-range [6, 10]; the timeline-RIGHT half owns [0, 6].
        // Previously the halves were swapped (first got [0,6], second [6,10]).
        let clip = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 10),
            timelineRange: TimeRange(start: 0, duration: 10),
            playbackRate: 1,
            isReversed: true
        )
        var project = project(with: clip)

        _ = try SplitClipCommand(clipId: clip.id, splitTime: 4.0).apply(to: &project)

        let clips = project.timeline.tracks[0].clips
        #expect(clips.count == 2)
        let first = clips[0]
        let second = clips[1]

        // First half: source [6, 10] (plays 10 -> 6).
        #expect(abs(first.sourceRange.start - 6.0) <= tolerance)
        #expect(abs(first.sourceRange.end - 10.0) <= tolerance)
        // Second half: source [0, 6] (plays 6 -> 0).
        #expect(abs(second.sourceRange.start - 0.0) <= tolerance)
        #expect(abs(second.sourceRange.end - 6.0) <= tolerance)
        // Both halves keep the reversed flag.
        #expect(first.isReversed)
        #expect(second.isReversed)
        // Timeline ranges still advance forward and are unaffected by reverse.
        #expect(abs(first.timelineRange.duration - 4.0) <= tolerance)
        #expect(abs(second.timelineRange.duration - 6.0) <= tolerance)
    }

    @Test("Reverse 2x clip split maps the boundary and assigns halves correctly")
    func reverseClipSplitAt2x() throws {
        // 10s source at 2x, reversed -> 5s timeline. Split at timeline 2s maps
        // to source 6 (2s of timeline at 2x = 4s of source walked down from 10).
        // First half owns [6, 10], second owns [0, 6].
        let clip = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 10),
            timelineRange: TimeRange(start: 0, duration: 5),
            playbackRate: 2,
            isReversed: true
        )
        var project = project(with: clip)

        _ = try SplitClipCommand(clipId: clip.id, splitTime: 2.0).apply(to: &project)

        let clips = project.timeline.tracks[0].clips
        #expect(abs(clips[0].sourceRange.start - 6.0) <= tolerance)
        #expect(abs(clips[0].sourceRange.end - 10.0) <= tolerance)
        #expect(abs(clips[1].sourceRange.end - 6.0) <= tolerance)
        #expect(abs(clips[1].sourceRange.start - 0.0) <= tolerance)
    }

    @Test("Reverse clip with ramp keeps [0,1]-spanning ramp points on each half")
    func reverseClipSplitPreservesRampPoints() throws {
        // 10s source, a ramp from 1x to 2x, reversed. The ramp shortens the
        // rendered timeline (source plays faster), so split at the timeline
        // midpoint maps to some source time S; we don't pin S (it depends on
        // the ramp integral). What we verify is the property the bug broke:
        // the reverse split hands the UPPER source sub-range to the first
        // (timeline-left) half and the LOWER sub-range to the second, the two
        // are contiguous, and both halves keep a ramp spanning [0,1].
        let ramp = [
            SpeedRampPoint(time: 0, rate: 1),
            SpeedRampPoint(time: 1, rate: 2)
        ]
        let clip = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 10),
            timelineRange: TimeRange(start: 0, duration: 10),
            playbackRate: 1,
            speedRampPoints: ramp,
            isReversed: true
        )
        var project = project(with: clip)

        _ = try SplitClipCommand(clipId: clip.id, splitTime: 5.0).apply(to: &project)

        let clips = project.timeline.tracks[0].clips
        let first = clips[0]
        let second = clips[1]
        let splitSourceTime = first.sourceRange.start

        // First half owns the upper source sub-range, second the lower (the
        // reverse swap), and they meet contiguously.
        #expect(abs(first.sourceRange.end - 10.0) <= tolerance)
        #expect(abs(second.sourceRange.start - 0.0) <= tolerance)
        #expect(abs(first.sourceRange.start - second.sourceRange.end) <= tolerance)
        #expect(splitSourceTime > 0)
        #expect(splitSourceTime < 10)

        // Each half keeps a renormalized ramp spanning [0,1] of its own
        // sub-range (reverse does not change the source->rate mapping, so the
        // renormalization is identical to the forward case).
        for sub in clips {
            #expect(sub.speedRampPoints.count >= 2)
            #expect(abs(sub.speedRampPoints.first!.time) < 0.001)
            #expect(abs(sub.speedRampPoints.last!.time - 1.0) < 0.001)
        }
    }

    @Test("Image clip split succeeds even though one half gets a zero-duration source range")
    func imageClipSplitAllowsZeroDurationSourceHalf() throws {
        // Pins the reason SplitClipCommand has no `duration > 0` guard on the
        // source sub-ranges. An image clip maps every timeline time to
        // `sourceRange.start`, so the timeline-left half necessarily gets a
        // zero-length source range — while both timeline halves are correct and
        // the photo renders fine, since image rendering is driven by the
        // timeline duration, not the source duration.
        //
        // A guard rejecting a zero-duration source half would look like a
        // reasonable tightening and would silently break splitting a photo.
        let clip = Clip(
            kind: .image,
            sourceRange: TimeRange(start: 0, duration: 5),
            timelineRange: TimeRange(start: 0, duration: 5),
            playbackRate: 1
        )
        var project = project(with: clip)

        _ = try SplitClipCommand(clipId: clip.id, splitTime: 2.0).apply(to: &project)

        let halves = project.timeline.tracks[0].clips
        #expect(halves.count == 2)
        // Timeline is split exactly where asked.
        #expect(abs(halves[0].timelineRange.duration - 2.0) <= tolerance)
        #expect(abs(halves[1].timelineRange.duration - 3.0) <= tolerance)
        // The zero-duration source half is expected, not a failure.
        #expect(halves[0].sourceRange.duration == 0)
        #expect(halves[1].sourceRange.duration > 0)
    }
}
