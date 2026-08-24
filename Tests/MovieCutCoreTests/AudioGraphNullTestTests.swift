import Foundation
import Testing
@testable import MovieCutCore

/// G-25 spec §9 — null-test judgment functions.
@Suite("AudioGraphNullTest (G-25 §9)")
struct AudioGraphNullTestTests {
    @Test("identical renders pass at offset 0")
    func identicalPasses() {
        // Interleaved stereo: each pair is one timeline sample/frame.
        let pcm = (0..<128).flatMap { frame -> [Float] in
            [Float(frame % 7) * 0.01, Float((frame + 3) % 11) * 0.01]
        }
        let result = AudioGraphNullTest.compare(reference: pcm, candidate: pcm)
        #expect(result.passed)
        #expect(result.bestOffsetSamples == 0)
        #expect(result.maxAbsoluteDeviation == 0)
        #expect(result.alignedFrameCount == 128)
    }

    @Test("a one-frame stereo shift is re-aligned within the ±1 search and passes")
    func oneSampleShiftRealigns() {
        var reference = [Float]()
        for frame in 0..<256 {
            reference.append(Float(frame) * 0.001)
            reference.append(Float(1_000 - frame) * 0.0007)
        }
        var candidate = reference
        candidate.removeFirst(2) // candidate starts one stereo frame later
        candidate.append(contentsOf: Array(candidate.suffix(2)))

        let result = AudioGraphNullTest.compare(reference: reference, candidate: candidate)
        #expect(result.passed)
        #expect(abs(result.bestOffsetSamples) == 1)
        #expect(result.alignedFrameCount == 255)
    }

    @Test("a one-scalar interleaved skew is NOT accepted as a one-sample time shift")
    func scalarChannelSkewDoesNotRealign() {
        // L/R are deliberately very different. Shifting this array by one
        // Float crosses channel boundaries; a frame-based null test must fail
        // rather than treating L↔R as a valid ±1 timeline-sample alignment.
        var reference = [Float]()
        for frame in 0..<64 {
            reference.append(Float(frame) * 0.01)
            reference.append(-0.75 + Float(frame) * 0.002)
        }
        var candidate = reference
        candidate.removeFirst()
        candidate.append(0)

        let result = AudioGraphNullTest.compare(reference: reference, candidate: candidate)
        #expect(!result.passed)
        #expect(result.maxAbsoluteDeviation > result.lsb16)
    }

    @Test("deviation beyond one 16-bit LSB fails")
    func aboveLsbFails() {
        let reference = [Float](repeating: 0.5, count: 128)
        let candidate = [Float](repeating: 0.5 + Float(3.0 / 32_768.0), count: 128)
        let result = AudioGraphNullTest.compare(reference: reference, candidate: candidate)
        #expect(!result.passed)
        #expect(result.maxAbsoluteDeviation > result.lsb16)
    }

    @Test("one-LSB-level difference still passes (16-bit quantization tolerance)")
    func withinLsbPasses() {
        let reference = [Float](repeating: 0.5, count: 128)
        let candidate = [Float](repeating: 0.5 + Float(0.5 / 32_768.0), count: 128)
        let result = AudioGraphNullTest.compare(reference: reference, candidate: candidate)
        #expect(result.passed)
    }

    @Test("mismatched lengths fail safely")
    func mismatchedLengthsFail() {
        let result = AudioGraphNullTest.compare(reference: [0, 0], candidate: [0, 0, 0])
        #expect(!result.passed)
        #expect(result.alignedFrameCount == 0)
    }

    @Test("odd scalar counts fail because the contract is interleaved stereo")
    func oddInterleavedCountFails() {
        let result = AudioGraphNullTest.compare(reference: [0, 0, 0], candidate: [0, 0, 0])
        #expect(!result.passed)
        #expect(result.alignedFrameCount == 0)
    }

    @Test("60-minute mixed-rate round trip is EXACT under Int64 math (§9.4)")
    func sixtyMinuteMixedRateExact() {
        // 60 minutes of GRAPH samples (48 kHz) round-tripped through the
        // 44.1 kHz source timebase — the exactness the drift gate needs.
        #expect(AudioGraphNullTest.mixedRateRoundTripIsExact(
            timelineEnd: 172_800_000, graphRate: 48_000, otherRate: 44_100
        ))
        #expect(AudioGraphNullTest.mixedRateRoundTripIsExact(
            timelineEnd: 0, graphRate: 48_000, otherRate: 44_100
        ))
    }
}
