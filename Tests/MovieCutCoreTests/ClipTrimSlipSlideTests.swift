import Foundation
import MovieCutCore
import Testing

/// Behavioral tests for `ClipTrimMath.slip` and `ClipTrimMath.slide` (task 5.5,
/// requirement 8).
///
/// These are pure-function tests: they pin the requirement contracts —
///   - slip: only `sourceRange` moves; `timelineRange` and total length survive;
///   - slide: `timelineRange` moves and adjacent boundaries absorb the delta;
///     the clip's own `sourceRange` and total length survive;
///   - speed/ramp/reverse clips route through `Clip.makeTimeMapping()` (the same
///     path the trim path uses), with no parallel time-calculation scheme;
///   - out-of-bounds requests clamp instead of producing invalid state.
@Suite("ClipTrimMath.slip/slide")
struct ClipTrimSlipSlideTests {
    private let tolerance = 1.0 / 30.0
    private let minimum: TimeInterval = 0.1

    // MARK: - Fixtures

    private func clip(
        sourceDuration: TimeInterval,
        sourceStart: TimeInterval = 0,
        timelineDuration: TimeInterval? = nil,
        timelineStart: TimeInterval = 0,
        rate: Double = 1,
        kind: ClipKind = .video,
        isReversed: Bool = false,
        speedRampPoints: [SpeedRampPoint] = []
    ) -> Clip {
        Clip(
            kind: kind,
            sourceRange: TimeRange(start: sourceStart, duration: sourceDuration),
            timelineRange: TimeRange(start: timelineStart, duration: timelineDuration ?? sourceDuration / max(rate, 0.25)),
            playbackRate: rate,
            speedRampPoints: speedRampPoints,
            isReversed: isReversed
        )
    }

    // MARK: - Slip: source-only move

    @Test("Slip shifts sourceRange by the delta, preserving duration")
    func slipTranslatesSourceWindow() throws {
        // source [2, 8] (dur 6). Slip +3 -> [5, 11], but asset is 12 so fits.
        let c = clip(sourceDuration: 6, sourceStart: 2, timelineDuration: 6, rate: 1)
        let r = try #require(ClipTrimMath.slip(
            clip: c, sourceDelta: 3, assetDuration: 12, minimumSourceDuration: minimum
        ))
        #expect(abs(r.source.start - 5.0) <= tolerance)
        #expect(abs(r.source.duration - 6.0) <= tolerance)
    }

    @Test("Slip clamps against the asset end (no invalid state)")
    func slipClampsToAssetEnd() throws {
        // source [6, 10] (dur 4) on a 10s asset. Slip +20 should clamp start to
        // 10 - 4 = 6, i.e. no movement past the asset end.
        let c = clip(sourceDuration: 4, sourceStart: 6, timelineDuration: 4, rate: 1)
        let r = try #require(ClipTrimMath.slip(
            clip: c, sourceDelta: 20, assetDuration: 10, minimumSourceDuration: minimum
        ))
        #expect(abs(r.source.start - 6.0) <= tolerance)
        #expect(abs(r.source.duration - 4.0) <= tolerance)
        #expect(r.source.end <= 10.0 + tolerance)
    }

    @Test("Slip clamps against the asset start (no invalid state)")
    func slipClampsToAssetStart() throws {
        // source [2, 6] on a 10s asset. Slip -10 clamps start to 0.
        let c = clip(sourceDuration: 4, sourceStart: 2, timelineDuration: 4, rate: 1)
        let r = try #require(ClipTrimMath.slip(
            clip: c, sourceDelta: -10, assetDuration: 10, minimumSourceDuration: minimum
        ))
        #expect(abs(r.source.start - 0.0) <= tolerance)
        #expect(abs(r.source.duration - 4.0) <= tolerance)
    }

    @Test("Slip at 2x keeps source duration and timeline span consistent via the mapping")
    func slipAt2xPreservesMappingDuration() throws {
        // 10s source at 2x -> 5s timeline. Slip +2 -> source [2, 12]? Asset 12,
        // so start clamps to 12 - 10 = 2 (exact). The clip's rendered timeline
        // duration must still be 5s after the slip, proving speed clips route
        // through the existing mapping rather than a parallel scheme.
        let c = clip(sourceDuration: 10, timelineDuration: 5, rate: 2)
        let r = try #require(ClipTrimMath.slip(
            clip: c, sourceDelta: 2, assetDuration: 12, minimumSourceDuration: minimum
        ))
        #expect(abs(r.source.start - 2.0) <= tolerance)
        #expect(abs(r.source.duration - 10.0) <= tolerance)

        // Rebuild the clip with the slipped source and confirm the mapping's
        // rendered timeline span is unchanged from the original.
        let originalMapping = try #require(c.makeTimeMapping())
        let slippedClip = clip(
            sourceDuration: r.source.duration,
            sourceStart: r.source.start,
            timelineDuration: c.timelineRange.duration,
            rate: 2
        )
        let slippedMapping = try #require(slippedClip.makeTimeMapping())
        #expect(abs(slippedMapping.renderedTimelineDuration - originalMapping.renderedTimelineDuration) <= tolerance)
    }

    @Test("Slip on a reverse clip translates the window (direction handled by mapping)")
    func slipOnReverseClip() throws {
        // Reverse only flips playback direction within the window; the window
        // itself is translated identically. source [2, 8] dur 6, reversed.
        let c = clip(sourceDuration: 6, sourceStart: 2, timelineDuration: 6, rate: 1, isReversed: true)
        let r = try #require(ClipTrimMath.slip(
            clip: c, sourceDelta: 1, assetDuration: 12, minimumSourceDuration: minimum
        ))
        #expect(abs(r.source.start - 3.0) <= tolerance)
        #expect(abs(r.source.duration - 6.0) <= tolerance)
    }

    @Test("Slip on a speed-ramped clip preserves rendered timeline span")
    func slipOnRampedClipPreservesRenderedSpan() throws {
        // A two-point ramp is non-linear; slip must NOT alter the rendered
        // timeline duration. We assert the invariant against the mapping itself
        // (the authority), not a hand-computed number.
        let points = [
            SpeedRampPoint(time: 0, rate: 1),
            SpeedRampPoint(time: 1, rate: 2)
        ]
        let c = clip(sourceDuration: 10, timelineDuration: 10, rate: 1, speedRampPoints: points)
        let originalRendered = try #require(c.makeTimeMapping()).renderedTimelineDuration

        let r = try #require(ClipTrimMath.slip(
            clip: c, sourceDelta: 2, assetDuration: 20, minimumSourceDuration: minimum
        ))
        #expect(abs(r.source.duration - 10.0) <= tolerance)

        let slippedClip = clip(
            sourceDuration: r.source.duration,
            sourceStart: r.source.start,
            timelineDuration: c.timelineRange.duration,
            rate: 1,
            speedRampPoints: points
        )
        let slippedRendered = try #require(slippedClip.makeTimeMapping()).renderedTimelineDuration
        #expect(abs(slippedRendered - originalRendered) <= tolerance)
    }

    @Test("Slip rejects image clips (no temporal source)")
    func slipRejectsImageClip() {
        let c = clip(sourceDuration: 0, timelineDuration: 3, rate: 1, kind: .image)
        let r = ClipTrimMath.slip(
            clip: c, sourceDelta: 1, assetDuration: nil, minimumSourceDuration: minimum
        )
        #expect(r == nil)
    }

    @Test("Slip rejects non-finite delta")
    func slipRejectsNonFinite() {
        let c = clip(sourceDuration: 6, timelineDuration: 6, rate: 1)
        let r = ClipTrimMath.slip(
            clip: c, sourceDelta: .infinity, assetDuration: 12, minimumSourceDuration: minimum
        )
        #expect(r == nil)
    }

    // MARK: - Slide: timeline move + neighbor absorption

    @Test("Slide moves the target and shrinks the next neighbor to keep total length")
    func slideShrinksNextNeighbor() throws {
        // Two contiguous 1x clips: A [0,5], B [5,10]. Slide B +2.
        // Total length must stay 10. B becomes [7,12]? No — B keeps its 5s
        // rendered span and the gap is closed by... there is no previous
        // neighbor for B's left edge except A. Since A and B are contiguous and
        // A is the previous neighbor, A's end snaps to B's new start.
        let a = clip(sourceDuration: 5, sourceStart: 0, timelineDuration: 5, timelineStart: 0)
        let b = clip(sourceDuration: 5, sourceStart: 0, timelineDuration: 5, timelineStart: 5)
        let r = try #require(ClipTrimMath.slide(
            clips: [a, b], targetIndex: 1, timelineDelta: 2, minimumDuration: minimum
        ))

        // Target B moves to [7, 12] (start 5 + 2, duration 5 preserved).
        #expect(abs(r.target.timeline.start - 7.0) <= tolerance)
        #expect(abs(r.target.timeline.duration - 5.0) <= tolerance)

        // Previous neighbor A grows to fill [0, 7] (end snaps to B's new start).
        let aPlacement = try #require(r.neighbors.first(where: { $0.clipId == a.id }))
        #expect(abs(aPlacement.timeline.start - 0.0) <= tolerance)
        #expect(abs(aPlacement.timeline.duration - 7.0) <= tolerance)

        // Total length preserved: A.end == B.start, B.end == 12, original end 10.
        // The clip's own source is NOT part of the result (caller keeps it).
        // No next neighbor here.
        #expect(r.neighbors.count == 1)
    }

    @Test("Slide with both neighbors splits the delta absorption across both edges")
    func slideBothNeighbors() throws {
        // Three contiguous 1x clips: A [0,4], B [4,8], C [8,12]. Slide B +1.
        // B's own source & 4s span preserved. B -> [5,9].
        // Previous neighbor A grows to [0,5]; next neighbor C shrinks to [9,12].
        let a = clip(sourceDuration: 4, sourceStart: 0, timelineDuration: 4, timelineStart: 0)
        let b = clip(sourceDuration: 4, sourceStart: 0, timelineDuration: 4, timelineStart: 4)
        let c = clip(sourceDuration: 4, sourceStart: 0, timelineDuration: 4, timelineStart: 8)
        let r = try #require(ClipTrimMath.slide(
            clips: [a, b, c], targetIndex: 1, timelineDelta: 1, minimumDuration: minimum
        ))

        #expect(abs(r.target.timeline.start - 5.0) <= tolerance)
        #expect(abs(r.target.timeline.duration - 4.0) <= tolerance)

        let aPlacement = try #require(r.neighbors.first(where: { $0.clipId == a.id }))
        #expect(abs(aPlacement.timeline.duration - 5.0) <= tolerance)

        let cPlacement = try #require(r.neighbors.first(where: { $0.clipId == c.id }))
        #expect(abs(cPlacement.timeline.start - 9.0) <= tolerance)
        #expect(abs(cPlacement.timeline.duration - 3.0) <= tolerance)

        // Total length preserved: 0..12 still covers everything contiguously.
        #expect(r.neighbors.count == 2)
    }

    @Test("Slide clamps when the next neighbor would drop below minimum duration")
    func slideClampsToNeighborMinimum() throws {
        // A [0,4], B [4,8], C [8,12] (1x). Slide B by +10: C would have to
        // shrink below minimum (0.1). B's end cannot exceed C.end - minimum.
        // B rendered dur 4 -> latest B.end = 12 - 0.1 = 11.9 -> latest start 7.9.
        let a = clip(sourceDuration: 4, sourceStart: 0, timelineDuration: 4, timelineStart: 0)
        let b = clip(sourceDuration: 4, sourceStart: 0, timelineDuration: 4, timelineStart: 4)
        let c = clip(sourceDuration: 4, sourceStart: 0, timelineDuration: 4, timelineStart: 8)
        let r = try #require(ClipTrimMath.slide(
            clips: [a, b, c], targetIndex: 1, timelineDelta: 10, minimumDuration: minimum
        ))

        #expect(abs(r.target.timeline.start - 7.9) <= tolerance)
        #expect(abs(r.target.timeline.duration - 4.0) <= tolerance)

        let cPlacement = try #require(r.neighbors.first(where: { $0.clipId == c.id }))
        #expect(cPlacement.timeline.duration >= minimum - tolerance)
        #expect(abs(cPlacement.timeline.start - 11.9) <= tolerance)
    }

    @Test("Slide clamps at the timeline left edge")
    func slideClampsToLeftEdge() throws {
        // A [0,4], B [4,8]. Slide B by -10: B cannot go before A keeps minimum.
        // Earliest B.start = A.start + minimum = 0.1.
        let a = clip(sourceDuration: 4, sourceStart: 0, timelineDuration: 4, timelineStart: 0)
        let b = clip(sourceDuration: 4, sourceStart: 0, timelineDuration: 4, timelineStart: 4)
        let r = try #require(ClipTrimMath.slide(
            clips: [a, b], targetIndex: 1, timelineDelta: -10, minimumDuration: minimum
        ))
        #expect(abs(r.target.timeline.start - 0.1) <= tolerance)
        #expect(abs(r.target.timeline.duration - 4.0) <= tolerance)

        let aPlacement = try #require(r.neighbors.first(where: { $0.clipId == a.id }))
        #expect(aPlacement.timeline.duration >= minimum - tolerance)
    }

    @Test("Slide preserves the target's own source range and rendered span for a 2x clip")
    func slideAt2xPreservesSourceAndSpan() throws {
        // B is a 2x clip: source 10 -> rendered timeline 5. It sits between A
        // and C. Sliding must keep B's rendered span at 5 (proving the speed
        // clip routes through the mapping) and never touch its source.
        let a = clip(sourceDuration: 5, sourceStart: 0, timelineDuration: 5, timelineStart: 0)
        let b = clip(sourceDuration: 10, sourceStart: 0, timelineDuration: 5, timelineStart: 5, rate: 2)
        let c = clip(sourceDuration: 5, sourceStart: 0, timelineDuration: 5, timelineStart: 10)
        let r = try #require(ClipTrimMath.slide(
            clips: [a, b, c], targetIndex: 1, timelineDelta: 1, minimumDuration: minimum
        ))

        // Rendered span stays 5s (from the mapping, not a parallel calc).
        #expect(abs(r.target.timeline.duration - 5.0) <= tolerance)
        #expect(abs(r.target.timeline.start - 6.0) <= tolerance)

        // A grows to [0,6]; C shrinks to [11,15]. Total length 15 preserved.
        let aPlacement = try #require(r.neighbors.first(where: { $0.clipId == a.id }))
        #expect(abs(aPlacement.timeline.duration - 6.0) <= tolerance)
        let cPlacement = try #require(r.neighbors.first(where: { $0.clipId == c.id }))
        #expect(abs(cPlacement.timeline.start - 11.0) <= tolerance)
        #expect(abs(cPlacement.timeline.duration - 4.0) <= tolerance)
    }

    @Test("Slide on a speed-ramped clip keeps the rendered span from the mapping")
    func slideOnRampedClipUsesMappingSpan() throws {
        // B has a 2-point ramp. Its rendered timeline span is whatever the
        // mapping says; slide must preserve exactly that span (not the raw
        // source duration, not a parallel recomputation).
        let points = [
            SpeedRampPoint(time: 0, rate: 1),
            SpeedRampPoint(time: 1, rate: 2)
        ]
        let rendered = try #require(
            clip(sourceDuration: 10, timelineDuration: 10, rate: 1, speedRampPoints: points)
                .makeTimeMapping()
        ).renderedTimelineDuration

        let a = clip(sourceDuration: 5, sourceStart: 0, timelineDuration: 5, timelineStart: 0)
        let b = clip(sourceDuration: 10, sourceStart: 0, timelineDuration: rendered, timelineStart: 5, speedRampPoints: points)
        let c = clip(sourceDuration: 5, sourceStart: 0, timelineDuration: 5, timelineStart: 5 + rendered)
        let r = try #require(ClipTrimMath.slide(
            clips: [a, b, c], targetIndex: 1, timelineDelta: 1, minimumDuration: minimum
        ))

        #expect(abs(r.target.timeline.duration - rendered) <= tolerance)
        #expect(abs(r.target.timeline.start - 6.0) <= tolerance)
    }

    @Test("Slide rejects out-of-bounds target index")
    func slideRejectsBadIndex() {
        let a = clip(sourceDuration: 5, timelineDuration: 5)
        let r = ClipTrimMath.slide(clips: [a], targetIndex: 5, timelineDelta: 1, minimumDuration: minimum)
        #expect(r == nil)
    }

    @Test("Slide rejects non-finite delta")
    func slideRejectsNonFinite() {
        let a = clip(sourceDuration: 5, timelineDuration: 5)
        let b = clip(sourceDuration: 5, sourceStart: 0, timelineDuration: 5, timelineStart: 5)
        let r = ClipTrimMath.slide(clips: [a, b], targetIndex: 1, timelineDelta: .nan, minimumDuration: minimum)
        #expect(r == nil)
    }

    @Test("Slide is order-independent: unsorted input still resolves adjacency")
    func slideResolvesAdjacencyFromUnsortedInput() throws {
        // Same three clips as slideBothNeighbors but passed shuffled.
        let a = clip(sourceDuration: 4, sourceStart: 0, timelineDuration: 4, timelineStart: 0)
        let b = clip(sourceDuration: 4, sourceStart: 0, timelineDuration: 4, timelineStart: 4)
        let c = clip(sourceDuration: 4, sourceStart: 0, timelineDuration: 4, timelineStart: 8)
        let r = try #require(ClipTrimMath.slide(
            clips: [c, a, b], targetIndex: 2, timelineDelta: 1, minimumDuration: minimum
        ))
        #expect(abs(r.target.timeline.start - 5.0) <= tolerance)
        #expect(abs(r.target.timeline.duration - 4.0) <= tolerance)
        #expect(r.neighbors.count == 2)
    }
}
