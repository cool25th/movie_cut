import Foundation
import MovieCutCore
import Testing

/// Envelope composition for the legacy preview audioMix path
/// (AI-03a M1). The invariants that matter to AVFoundation:
/// segments are ordered, contiguous or disjoint, never overlapping,
/// and cover the clip — so one input-parameters object per track can
/// never receive overlapping volume ramps.
@Suite("TrackGainEnvelope")
struct TrackGainEnvelopeTests {

    private func makeClip(
        start: TimeInterval = 0,
        duration: TimeInterval = 4,
        volume: Double = 1.0,
        fadeIn: TimeInterval = 0,
        fadeOut: TimeInterval = 0,
        duckingLevel: Double? = nil,
        duckingRanges: [TimeRange] = []
    ) -> Clip {
        var clip = Clip(
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: duration),
            timelineRange: TimeRange(start: start, duration: duration)
        )
        clip.volume = volume
        clip.fadeInDuration = fadeIn
        clip.fadeOutDuration = fadeOut
        clip.duckingLevel = duckingLevel
        clip.duckingRanges = duckingRanges
        return clip
    }

    private func assertEnvelopeInvariants(
        _ segments: [TrackGainEnvelope.Segment],
        source: @autoclosure () -> String
    ) {
        let label = Comment(stringLiteral: source())
        #expect(!segments.isEmpty, label)
        for (index, segment) in segments.enumerated() {
            #expect(segment.end > segment.start, "zero-length segment at \(index): \(source())")
            if index > 0 {
                #expect(
                    segments[index - 1].end <= segment.start + 0.000001,
                    "segment \(index) overlaps its predecessor: \(source()) — \(segments)"
                )
            }
            #expect(segment.startGain >= 0 && segment.startGain <= 2, label)
            #expect(segment.endGain >= 0 && segment.endGain <= 2, label)
        }
        // Contiguity: within a clip the envelope has no uncovered gap.
        for (a, b) in zip(segments, segments.dropFirst()) {
            #expect(abs(a.end - b.start) < 0.000001, "envelope gap between \(a) and \(b): \(source())")
        }
    }

    // MARK: - Minimal repro of the E2E failure shape

    @Test("Montage music clip: fadeIn inside a full-length duck no longer overlaps")
    func fadeInPlusDuckRepro() {
        // The E2E crash: clip0's fadeIn ramp [0, 0.5] landed inside the
        // global ducking block's full-span constant ramp. The envelope
        // composes both into ONE curve, so the emitted segments can never
        // overlap. Here the same shape is expressed as baked ducking over
        // the whole clip plus a fade-in.
        let clip = makeClip(
            duration: 4,
            fadeIn: 0.5,
            duckingLevel: 0.3,
            duckingRanges: [TimeRange(start: 0, duration: 4)]
        )
        let segments = TrackGainEnvelope.segments(for: clip, timelineStart: 0, timelineDuration: 4)
        assertEnvelopeInvariants(segments, source: "fadeIn+duck repro")

        // The duck hold applies for the middle of the clip, fade multiplies
        // on top: gain at t=0 is 0 (fade), at t≥0.5 is volume×0.3.
        #expect(segments.first?.startGain == 0)
        let hold = segments.first { $0.start >= 0.5 && $0.start < 3 }
        #expect(hold != nil)
        if let hold {
            #expect(abs(hold.startGain - 0.3) < 0.02)
        }
    }

    // MARK: - Fades

    @Test("Fade-in only: exact linear ramp then constant")
    func fadeInOnly() {
        let clip = makeClip(start: 4, duration: 4, volume: 0.8, fadeIn: 0.5)
        let segments = TrackGainEnvelope.segments(for: clip, timelineStart: 4, timelineDuration: 4)
        assertEnvelopeInvariants(segments, source: "fadeIn only")

        #expect(segments[0].start == 4)
        #expect(abs(segments[0].end - 4.5) < 1e-9)
        #expect(segments[0].startGain == 0)
        #expect(abs(segments[0].endGain - 0.8) < 1e-9)
        #expect(abs(segments[1].startGain - 0.8) < 1e-9)
        #expect(abs(segments[1].endGain - 0.8) < 1e-9)
        #expect(abs(segments[1].end - 8) < 1e-9)
    }

    @Test("Fade-out only: constant then linear ramp down")
    func fadeOutOnly() {
        let clip = makeClip(duration: 3, volume: 0.5, fadeOut: 1.5)
        let segments = TrackGainEnvelope.segments(for: clip, timelineStart: 12, timelineDuration: 3)
        assertEnvelopeInvariants(segments, source: "fadeOut only")

        let last = segments.last!
        #expect(abs(last.start - 13.5) < 1e-9)
        #expect(abs(last.end - 15) < 1e-9)
        #expect(abs(last.startGain - 0.5) < 1e-9)
        #expect(last.endGain == 0)
    }

    @Test("Fade longer than clip clamps to the clip span")
    func fadeLongerThanClip() {
        let clip = makeClip(duration: 2, fadeIn: 5, fadeOut: 5)
        let segments = TrackGainEnvelope.segments(for: clip, timelineStart: 0, timelineDuration: 2)
        assertEnvelopeInvariants(segments, source: "fades longer than clip")
        #expect(abs(segments[0].startGain - 0) < 1e-9)
        #expect(segments.last!.endGain == 0)
    }

    @Test("No automation: one constant segment at clip volume")
    func constantOnly() {
        let clip = makeClip(volume: 1.2)
        let segments = TrackGainEnvelope.segments(for: clip, timelineStart: 8, timelineDuration: 4)
        assertEnvelopeInvariants(segments, source: "constant")
        #expect(segments.count == 1)
        #expect(abs(segments[0].startGain - 1.2) < 1e-9)
        #expect(abs(segments[0].endGain - 1.2) < 1e-9)
    }

    @Test("Zero volume clip is silence across the whole span")
    func zeroVolume() {
        let clip = makeClip(volume: 0, fadeIn: 1, duckingLevel: 0.3, duckingRanges: [TimeRange(start: 2, duration: 1)])
        let segments = TrackGainEnvelope.segments(for: clip, timelineStart: 0, timelineDuration: 4)
        assertEnvelopeInvariants(segments, source: "zero volume")
        for segment in segments {
            #expect(segment.startGain == 0)
            #expect(segment.endGain == 0)
        }
    }

    // MARK: - Ducking

    /// Linearly interpolated envelope gain at an arbitrary clip-local time —
    /// the value AVFoundation will render at that instant.
    private func envelopeGain(
        _ segments: [TrackGainEnvelope.Segment], at t: TimeInterval
    ) -> Double? {
        guard let segment = segments.first(where: { $0.start <= t && $0.end > t }) else {
            return t == segments.last?.end ? segments.last?.endGain : nil
        }
        let span = segment.end - segment.start
        let fraction = span > 0 ? (t - segment.start) / span : 0
        return segment.startGain + (segment.endGain - segment.startGain) * fraction
    }

    @Test("Baked ducking: attack/hold/release breakpoints at planner timing")
    func duckAttackHoldRelease() {
        let clip = makeClip(duration: 4, duckingLevel: 0.5, duckingRanges: [TimeRange(start: 1, duration: 2)])
        let segments = TrackGainEnvelope.segments(for: clip, timelineStart: 0, timelineDuration: 4)
        assertEnvelopeInvariants(segments, source: "duck attack/hold/release")

        let attack = AudioDuckingPlanner.attackDuration
        let release = AudioDuckingPlanner.releaseDuration

        func gain(at t: TimeInterval) -> Double? {
            segments.first { abs($0.start - t) < 1e-9 }?.startGain
        }
        // At range boundaries: base before, ducked inside, base after.
        #expect(abs((gain(at: 1.0) ?? -1) - 1.0) < 1e-9)
        #expect(abs((gain(at: 1.0 + attack) ?? -1) - 0.5) < 0.02)
        #expect(abs((gain(at: 3.0 - release) ?? -1) - 0.5) < 0.02)
        #expect(abs((gain(at: 3.0) ?? -1) - 1.0) < 1e-9)
    }

    @Test("Duck range too short for attack+release ducks nothing")
    func duckRangeTooShort() {
        let clip = makeClip(duration: 4, duckingLevel: 0.5, duckingRanges: [TimeRange(start: 1, duration: 0.2)])
        let segments = TrackGainEnvelope.segments(for: clip, timelineStart: 0, timelineDuration: 4)
        assertEnvelopeInvariants(segments, source: "duck range too short")
        for segment in segments {
            #expect(abs(segment.startGain - 1) < 1e-9)
            #expect(abs(segment.endGain - 1) < 1e-9)
        }
    }

    @Test("Ducking level 0 means silence during the hold, not 'no ducking'")
    func duckLevelZeroIsSilence() {
        let clip = makeClip(duration: 4, duckingLevel: 0, duckingRanges: [TimeRange(start: 1, duration: 2)])
        let segments = TrackGainEnvelope.segments(for: clip, timelineStart: 0, timelineDuration: 4)
        assertEnvelopeInvariants(segments, source: "duck level 0")
        let holdGain = envelopeGain(segments, at: 1.5)
        #expect(holdGain != nil && holdGain! < 0.01)
    }

    @Test("Overlapping duck ranges merge (planner semantics)")
    func overlappingDuckRanges() {
        let clip = makeClip(
            duration: 4,
            duckingLevel: 0.5,
            duckingRanges: [
                TimeRange(start: 1, duration: 1),
                TimeRange(start: 1.5, duration: 1),
            ]
        )
        let segments = TrackGainEnvelope.segments(for: clip, timelineStart: 0, timelineDuration: 4)
        assertEnvelopeInvariants(segments, source: "overlapping duck ranges")
        // Merged range [1, 2.5]: the middle of the merged span holds the
        // ducked level once — not twice (no double attenuation).
        let mergedHoldGain = envelopeGain(segments, at: 1.7)
        #expect(mergedHoldGain != nil && abs(mergedHoldGain! - 0.5) < 0.02)
    }

    // MARK: - Composition invariants

    @Test("Fade and duck overlapping windows compose without double-shape loss")
    func fadeOverDuckComposition() {
        // Fade-in window [0,1] fully inside duck range [0,2]: the composed
        // gain at any point is volume × fade × duck — at the fade's end the
        // duck is still attacking, so the level is below the plain ducked
        // level; the invariant that matters is ONE non-overlapping envelope.
        let clip = makeClip(duration: 4, volume: 1, fadeIn: 1, duckingLevel: 0.3, duckingRanges: [TimeRange(start: 0, duration: 2)])
        let segments = TrackGainEnvelope.segments(for: clip, timelineStart: 0, timelineDuration: 4)
        assertEnvelopeInvariants(segments, source: "fade over duck")

        #expect(segments.first?.startGain == 0)
        // After the duck range ends, level returns to the fade's constant 1.
        let tailGain = envelopeGain(segments, at: 3)
        #expect(tailGain != nil && abs(tailGain! - 1) < 0.02)
    }

    @Test("Sequential clips emit disjoint envelopes in track time")
    func sequentialClipsDisjoint() {
        // The montage layout: music chunks at [0,4], [4,8], [8,12], [12,15],
        // fadeIn on the first, fadeOut on the last.
        let first = makeClip(start: 0, duration: 4, fadeIn: 0.5)
        let last = makeClip(start: 12, duration: 3, fadeOut: 1.5)
        let firstSegments = TrackGainEnvelope.segments(for: first, timelineStart: 0, timelineDuration: 4)
        let lastSegments = TrackGainEnvelope.segments(for: last, timelineStart: 12, timelineDuration: 3)
        assertEnvelopeInvariants(firstSegments, source: "chunk 1")
        assertEnvelopeInvariants(lastSegments, source: "chunk 4")
        #expect(firstSegments.allSatisfy { $0.end <= 4 + 1e-9 })
        #expect(lastSegments.allSatisfy { $0.start >= 12 - 1e-9 })
    }

    @Test("Non-finite duration yields no segments")
    func nonFiniteDuration() {
        let clip = makeClip(duration: 4)
        #expect(TrackGainEnvelope.segments(for: clip, timelineStart: 0, timelineDuration: .infinity).isEmpty)
        #expect(TrackGainEnvelope.segments(for: clip, timelineStart: 0, timelineDuration: .nan).isEmpty)
        #expect(TrackGainEnvelope.segments(for: clip, timelineStart: 0, timelineDuration: 0).isEmpty)
    }
}
