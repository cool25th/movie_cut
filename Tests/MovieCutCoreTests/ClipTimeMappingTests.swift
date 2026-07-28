import Foundation
import MovieCutCore
import Testing

/// Behavioral tests for the centralized timeline<->source time mapping.
///
/// These are the non-skippable mapping tests required by Step 3 of
/// `docs/CAPCUT_CORE_EDITING_REPAIR_HANDOFF_20260727.md`. They are pure value
/// tests (no CIContext, no AVFoundation, no source-string StaticContract) and
/// run under `swift test`. They pin the constant-speed, speed-ramp, reverse,
/// freeze, and image policies so the ten downstream call sites that consume
/// `ClipTimeMapping` all share one verified definition.
@Suite("ClipTimeMapping")
struct ClipTimeMappingTests {
    private let fps30 = 30.0
    private let fps29_97 = 30000.0 / 1001.0
    private let fps60 = 60.0

    private func mapping(
        sourceStart: TimeInterval = 0,
        sourceDuration: TimeInterval,
        timelineStart: TimeInterval = 0,
        timelineDuration: TimeInterval? = nil,
        rate: Double = 1,
        ramp: [SpeedRampPoint] = [],
        reversed: Bool = false,
        kind: ClipKind = .video
    ) -> ClipTimeMapping {
        ClipTimeMapping(
            sourceRange: TimeRange(start: sourceStart, duration: sourceDuration),
            timelineStart: timelineStart,
            timelineDuration: timelineDuration ?? sourceDuration / max(rate, 0.25),
            playbackRate: rate,
            speedRampPoints: ramp,
            isReversed: reversed,
            kind: kind
        )
    }

    // MARK: - Constant speed round-trip (handoff: 0.5x/1x/2x/4x within 1 frame)

    @Test("Constant speed round-trip within one frame at 30fps", arguments: [0.5, 1.0, 2.0, 4.0])
    func constantSpeedRoundTrip(rate: Double) throws {
        // 10s of source at the given rate.
        let m = mapping(sourceDuration: 10, rate: rate)
        let rendered = m.renderedTimelineDuration
        #expect(rendered.isFinite && rendered > 0)

        // Sample at start, 25%, 50%, 75%, end of the rendered timeline.
        let fractions: [Double] = [0, 0.25, 0.5, 0.75, 1.0]
        for f in fractions {
            let t = m.timelineStart + rendered * f
            let source = m.sourceTime(forTimelineTime: t)
            let back = m.timelineTime(forSourceTime: source)
            #expect(
                ClipTimeMapping.isWithinFrames(back, t, frames: 1, fps: fps30),
                "rate=\(rate) fraction=\(f): round-trip \(back) != \(t) within 1 frame"
            )
        }
    }

    @Test("Constant 2x maps timeline 2s to source 4s")
    func constantSpeedBoundaryMapping() throws {
        let m = mapping(sourceDuration: 10, timelineStart: 0, rate: 2.0)
        // Timeline 2s into a 2x clip should hit source 4s.
        let source = m.sourceTime(forTimelineTime: 2.0)
        #expect(ClipTimeMapping.isWithinFrames(source, 4.0, frames: 1, fps: fps30))
        // And the inverse: source 4s -> timeline 2s.
        let timeline = m.timelineTime(forSourceTime: 4.0)
        #expect(ClipTimeMapping.isWithinFrames(timeline, 2.0, frames: 1, fps: fps30))
    }

    @Test("Constant 0.5x maps timeline 2s to source 1s")
    func constantSpeedHalfRate() throws {
        let m = mapping(sourceDuration: 10, rate: 0.5)
        let source = m.sourceTime(forTimelineTime: 2.0)
        #expect(ClipTimeMapping.isWithinFrames(source, 1.0, frames: 1, fps: fps30))
    }

    // MARK: - Speed ramp

    @Test("Speed ramp mapping is strictly increasing (no saturation)")
    func speedRampMonotonic() throws {
        // A ramp from 1x to 2x across the source.
        let ramp = [
            SpeedRampPoint(time: 0, rate: 1),
            SpeedRampPoint(time: 1, rate: 2)
        ]
        let m = mapping(sourceDuration: 10, rate: 1, ramp: ramp)
        let rendered = m.renderedTimelineDuration
        #expect(rendered > 0)

        // Non-decreasing alone cannot catch a clamping bug: a saturated (flat)
        // mapping is also non-decreasing. Require that interior timeline steps
        // advance source time by more than a frame, so a clamp that collapses
        // the clip tail onto one frame fails this assertion.
        let steps = 20
        let frame = 1.0 / fps30
        var previousSource: TimeInterval?
        for i in 0...steps {
            let t = m.timelineStart + rendered * Double(i) / Double(steps)
            let source = m.sourceTime(forTimelineTime: t)
            if let previous = previousSource {
                #expect(source >= previous, "ramp not monotonic at step \(i): \(source) < \(previous)")
                #expect(
                    (source - previous) > frame,
                    "ramp saturated at step \(i): source advanced only \(source - previous)s (<= 1 frame), expected real progression"
                )
            }
            previousSource = source
        }
    }

    @Test("Speed ramp round-trip within one frame")
    func speedRampRoundTrip() throws {
        // A ramp with a steep rate transition (1x -> 3x -> 0.5x) exercises the
        // non-linear inverse. The ramp curve operates in source-scale units, so
        // the round-trip should match within one frame once the mapping routes
        // both directions through the same scale.
        let ramp = [
            SpeedRampPoint(time: 0, rate: 1),
            SpeedRampPoint(time: 0.5, rate: 3),
            SpeedRampPoint(time: 1, rate: 0.5)
        ]
        let m = mapping(sourceDuration: 10, rate: 1, ramp: ramp)
        let rendered = m.renderedTimelineDuration

        for f in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let t = m.timelineStart + rendered * f
            let source = m.sourceTime(forTimelineTime: t)
            let back = m.timelineTime(forSourceTime: source)
            #expect(
                ClipTimeMapping.isWithinFrames(back, t, frames: 1, fps: fps30),
                "ramp fraction=\(f): round-trip \(back) != \(t) within 1 frame"
            )
        }
    }

    @Test("Net slow-mo ramp does not collapse the clip tail to one source frame")
    func speedRampNetSlowMoNotSaturated() throws {
        // A pure 0.5x ramp over 10s of source. The ramp integrates 1/rate, so
        // source 1.0 -> output 2.0 and the clip renders to 20s on the timeline.
        // Before the fix, sourceOffsetForLocalTimelineOffset clamped the
        // normalized output to 1 (instead of the ramp's output span 2.0), so
        // every timeline time beyond 10s collapsed onto source 5s, and
        // timelineTime(forSourceTime: 10) returned 10s instead of 20s.
        let ramp = [
            SpeedRampPoint(time: 0, rate: 0.5),
            SpeedRampPoint(time: 1, rate: 0.5)
        ]
        let m = mapping(sourceDuration: 10, rate: 1, ramp: ramp)

        #expect(m.renderedTimelineDuration == 20.0)

        // Timeline midpoint of a 0.5x clip -> source 7.5s (not 5.0).
        #expect(ClipTimeMapping.isWithinFrames(m.sourceTime(forTimelineTime: 15), 7.5, frames: 1, fps: fps30))
        // Timeline end -> source 10s (the full source range), not 5.0.
        #expect(ClipTimeMapping.isWithinFrames(m.sourceTime(forTimelineTime: 20), 10.0, frames: 1, fps: fps30))
        // Source end -> timeline 20s (the full rendered span), not 10.0.
        #expect(ClipTimeMapping.isWithinFrames(m.timelineTime(forSourceTime: 10), 20.0, frames: 1, fps: fps30))

        // Whole-timeline round-trip within one frame across the slow span.
        for f in stride(from: 0.0, through: 1.0, by: 0.1) {
            let t = m.timelineStart + m.renderedTimelineDuration * f
            let source = m.sourceTime(forTimelineTime: t)
            let back = m.timelineTime(forSourceTime: source)
            #expect(
                ClipTimeMapping.isWithinFrames(back, t, frames: 1, fps: fps30),
                "slow-mo fraction=\(f): round-trip \(back) != \(t) within 1 frame"
            )
        }
    }

    // MARK: - Trimmed source range offset

    @Test("Trimmed source range offset is respected")
    func trimmedSourceRangeOffset() throws {
        // Source starts at 5s (trimmed), 1x, 4s duration. Timeline starts at 0.
        let m = mapping(sourceStart: 5, sourceDuration: 4, timelineStart: 0, rate: 1)
        // Timeline 0 -> source 5 (the trim start).
        #expect(ClipTimeMapping.isWithinFrames(m.sourceTime(forTimelineTime: 0), 5.0, frames: 1, fps: fps30))
        // Timeline 2 -> source 7.
        #expect(ClipTimeMapping.isWithinFrames(m.sourceTime(forTimelineTime: 2), 7.0, frames: 1, fps: fps30))
    }

    // MARK: - Invalid input fail-closed

    @Test("NaN and infinity timeline time fail closed to source start")
    func invalidInputFailClosed() throws {
        let m = mapping(sourceStart: 3, sourceDuration: 10, rate: 2)
        #expect(m.sourceTime(forTimelineTime: Double.nan) == 3.0)
        #expect(m.sourceTime(forTimelineTime: Double.infinity) == 3.0)
        #expect(m.sourceTime(forTimelineTime: -Double.infinity) == 3.0)
    }

    @Test("Non-positive rate falls back to identity (fail closed, not crash)")
    func nonPositiveRateFallback() throws {
        let m = mapping(sourceDuration: 10, rate: 0)
        // Sanitized to >= 0.25 internally; must not divide by zero or return NaN.
        let source = m.sourceTime(forTimelineTime: 1.0)
        #expect(source.isFinite)
        #expect(source >= 0)
    }

    // MARK: - Frame tolerance at common fps

    @Test("Frame tolerance helper respects fps")
    func frameToleranceHelper() throws {
        // At 30fps, one frame = 1/30s.
        #expect(ClipTimeMapping.isWithinFrames(0, 1.0 / 30.0, frames: 1, fps: fps30))
        #expect(!ClipTimeMapping.isWithinFrames(0, 2.0 / 30.0, frames: 1, fps: fps30))
        // At 60fps, one frame = 1/60s — finer tolerance.
        #expect(ClipTimeMapping.isWithinFrames(0, 1.0 / 60.0, frames: 1, fps: fps60))
        #expect(!ClipTimeMapping.isWithinFrames(0, 2.0 / 60.0, frames: 1, fps: fps60))
        // 29.97 fps fractional frame duration handled.
        let frame2997 = 1.0 / fps29_97
        #expect(ClipTimeMapping.isWithinFrames(0, frame2997, frames: 1, fps: fps29_97))
    }

    // MARK: - Reverse policy

    @Test("Reverse maps timeline forward to source backward from end")
    func reversePolicy() throws {
        // 4s source, 1x, reversed. Timeline 0 -> source end (4); timeline 4 -> source 0.
        let m = mapping(sourceDuration: 4, rate: 1, reversed: true)
        let sourceAtStart = m.sourceTime(forTimelineTime: 0)
        let sourceAtEnd = m.sourceTime(forTimelineTime: 4)
        #expect(ClipTimeMapping.isWithinFrames(sourceAtStart, 4.0, frames: 1, fps: fps30))
        #expect(ClipTimeMapping.isWithinFrames(sourceAtEnd, 0.0, frames: 1, fps: fps30))
        // Midpoint: timeline 2 -> source 2 (symmetric for constant rate).
        let sourceAtMid = m.sourceTime(forTimelineTime: 2)
        #expect(ClipTimeMapping.isWithinFrames(sourceAtMid, 2.0, frames: 1, fps: fps30))
    }

    // MARK: - Freeze-frame policy

    @Test("Freeze-frame holds a single source instant across the timeline")
    func freezeFramePolicy() throws {
        // Tiny source (40ms) held over a 2s timeline span => freeze.
        let m = mapping(sourceDuration: 0.04, timelineStart: 0, timelineDuration: 2.0, rate: 1)
        #expect(m.sourceTime(forTimelineTime: 0) == 0)
        #expect(m.sourceTime(forTimelineTime: 1.0) == 0)
        #expect(m.sourceTime(forTimelineTime: 2.0) == 0)
        // Timeline time for any source time collapses to the timeline start.
        #expect(m.timelineTime(forSourceTime: 0) == 0)
    }

    // MARK: - Image clip policy

    @Test("Image clip always maps to the source start (still)")
    func imageClipPolicy() throws {
        let m = mapping(sourceDuration: 0, timelineStart: 5, timelineDuration: 3.0, rate: 1, kind: .image)
        // Any timeline time within the clip returns the source start.
        #expect(m.sourceTime(forTimelineTime: 5) == 0)
        #expect(m.sourceTime(forTimelineTime: 6.5) == 0)
        #expect(m.sourceTime(forTimelineTime: 8) == 0)
        // Any source time maps to the timeline start.
        #expect(m.timelineTime(forSourceTime: 0) == 5)
    }

    // MARK: - Clip.makeTimeMapping factory

    @Test("Clip.makeTimeMapping builds a mapping from clip fields")
    func clipFactory() throws {
        let clip = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 2, duration: 8),
            timelineRange: TimeRange(start: 10, duration: 4),
            playbackRate: 2.0
        )
        let m = try #require(clip.makeTimeMapping())
        // Timeline 12 (clip-local 2s at 2x) -> source 6.
        #expect(ClipTimeMapping.isWithinFrames(m.sourceTime(forTimelineTime: 12), 6.0, frames: 1, fps: fps30))
        // Source 6 -> timeline 12.
        #expect(ClipTimeMapping.isWithinFrames(m.timelineTime(forSourceTime: 6), 12.0, frames: 1, fps: fps30))
    }

    @Test("Clip.makeTimeMapping returns nil for non-finite ranges")
    func clipFactoryFailClosed() throws {
        var clip = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 5),
            timelineRange: TimeRange(start: 0, duration: 5),
            playbackRate: 1
        )
        clip.sourceRange.duration = .nan
        #expect(clip.makeTimeMapping() == nil)
    }
}
