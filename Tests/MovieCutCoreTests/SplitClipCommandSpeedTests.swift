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
}
