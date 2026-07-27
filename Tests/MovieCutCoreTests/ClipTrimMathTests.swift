import Foundation
import MovieCutCore
import Testing

/// Behavioral tests for the shared trim math.
///
/// Step 5 of `docs/CAPCUT_CORE_EDITING_REPAIR_HANDOFF_20260727.md`. The same
/// `ClipTrimMath.compute` drives both the keyboard trim and the drag trim, so
/// these tests pin the speed-aware source mapping, the asset-duration guard,
/// the image-clip unbounded extension, and the minimum-duration policy that
/// both UI paths now share.
@Suite("ClipTrimMath")
struct ClipTrimMathTests {
    private let minimum: TimeInterval = 0.1
    private let tolerance = 1.0 / 30.0

    private func clip(
        sourceDuration: TimeInterval,
        timelineDuration: TimeInterval? = nil,
        rate: Double = 1,
        sourceStart: TimeInterval = 0,
        timelineStart: TimeInterval = 0,
        kind: ClipKind = .video
    ) -> Clip {
        Clip(
            kind: kind,
            sourceRange: TimeRange(start: sourceStart, duration: sourceDuration),
            timelineRange: TimeRange(start: timelineStart, duration: timelineDuration ?? sourceDuration / max(rate, 0.25)),
            playbackRate: rate
        )
    }

    // MARK: - Speed-aware right trim

    @Test("2x clip right trim: timeline 2s shorter removes 4s of source")
    func rightTrimAt2x() throws {
        // 10s source at 2x -> 5s timeline. Trim the end to timeline 3s (2s
        // shorter): at 2x, 2s of timeline = 4s of source, so source shrinks
        // 10 -> 6.
        let c = clip(sourceDuration: 10, timelineDuration: 5, rate: 2)
        let result = try #require(ClipTrimMath.compute(
            clip: c, edge: .end, targetTimelineTime: 3.0,
            assetDuration: 10, minimumDuration: minimum
        ))
        #expect(abs(result.source.duration - 6.0) <= tolerance)
        #expect(abs(result.timeline.duration - 3.0) <= tolerance)
    }

    @Test("0.5x clip right trim: timeline 1s shorter removes 0.5s of source")
    func rightTrimAtHalfRate() throws {
        // 10s source at 0.5x -> 20s timeline. Trim the end to timeline 19s
        // (1s shorter): at 0.5x, 1s of timeline = 0.5s of source, so source
        // shrinks 10 -> 9.5.
        let c = clip(sourceDuration: 10, timelineDuration: 20, rate: 0.5)
        let result = try #require(ClipTrimMath.compute(
            clip: c, edge: .end, targetTimelineTime: 19.0,
            assetDuration: 10, minimumDuration: minimum
        ))
        #expect(abs(result.source.duration - 9.5) <= tolerance)
    }

    // MARK: - Speed-aware left trim

    @Test("2x clip left trim advances source by 2x the timeline delta")
    func leftTrimAt2x() throws {
        // 10s source at 2x -> 5s timeline (start 0). Trim the start to
        // timeline 1s: source start should advance by 2s (to source 2).
        let c = clip(sourceDuration: 10, timelineDuration: 5, rate: 2)
        let result = try #require(ClipTrimMath.compute(
            clip: c, edge: .start, targetTimelineTime: 1.0,
            assetDuration: 10, minimumDuration: minimum
        ))
        #expect(abs(result.source.start - 2.0) <= tolerance)
        #expect(abs(result.timeline.start - 1.0) <= tolerance)
    }

    // MARK: - Asset-duration guard

    @Test("Video end trim clamps source to the asset duration")
    func videoEndTrimClampsToAsset() throws {
        // Asset is 10s; the clip currently uses source 0..8. Try to extend the
        // timeline end far enough that the mapped source would exceed 10s.
        let c = clip(sourceDuration: 8, timelineDuration: 8, rate: 1)
        // timeline end -> 12 maps to source 12 (>10); must clamp to source 10.
        let result = try #require(ClipTrimMath.compute(
            clip: c, edge: .end, targetTimelineTime: 12.0,
            assetDuration: 10, minimumDuration: minimum
        ))
        #expect(result.source.duration <= 10.0 + tolerance)
        #expect(result.source.start == 0)
    }

    @Test("Image clip end trim is unbounded (no asset clamp)")
    func imageEndTrimUnbounded() throws {
        // Image clip: assetDuration nil, extend freely.
        let c = clip(sourceDuration: 0, timelineDuration: 3, rate: 1, kind: .image)
        let result = try #require(ClipTrimMath.compute(
            clip: c, edge: .end, targetTimelineTime: 10.0,
            assetDuration: nil, minimumDuration: minimum
        ))
        #expect(abs(result.timeline.duration - 10.0) <= tolerance)
    }

    // MARK: - Minimum duration

    @Test("End trim enforces minimum duration")
    func endTrimEnforcesMinimum() {
        let c = clip(sourceDuration: 5, timelineDuration: 5, rate: 1)
        // Try to trim the end below the minimum: should clamp or return nil.
        let result = ClipTrimMath.compute(
            clip: c, edge: .end, targetTimelineTime: 0.01,
            assetDuration: 5, minimumDuration: minimum
        )
        if let result {
            #expect(result.timeline.duration >= minimum - tolerance)
        }
        // Either nil (rejected) or clamped to >= minimum; both are acceptable.
    }

    @Test("Start trim rejects targets that would shrink below minimum")
    func startTrimRejectsTooShort() {
        let c = clip(sourceDuration: 5, timelineDuration: 5, rate: 1)
        // Move the start so close to the end that remaining duration < minimum.
        let result = ClipTrimMath.compute(
            clip: c, edge: .start, targetTimelineTime: 4.99,
            assetDuration: 5, minimumDuration: minimum
        )
        // Should be nil (rejected) — cannot leave < 0.1s.
        #expect(result == nil)
    }

    // MARK: - Drag/keyboard parity (same function => same result)

    @Test("Same inputs always yield the same output (parity contract)")
    func deterministicForSameInputs() throws {
        let c = clip(sourceDuration: 10, timelineDuration: 5, rate: 2)
        let r1 = ClipTrimMath.compute(
            clip: c, edge: .end, targetTimelineTime: 4.0,
            assetDuration: 10, minimumDuration: minimum
        )
        let r2 = ClipTrimMath.compute(
            clip: c, edge: .end, targetTimelineTime: 4.0,
            assetDuration: 10, minimumDuration: minimum
        )
        #expect(r1?.source == r2?.source)
        #expect(r1?.timeline == r2?.timeline)
    }
}
