import Foundation
import Testing
@testable import MovieCutCore

/// G-25 spec §9 — null-test judgment functions.
@Suite("AudioGraphNullTest (G-25 §9)")
struct AudioGraphNullTestTests {
    @Test("identical renders pass at offset 0")
    func identicalPasses() {
        let pcm = (0..<256).map { Float($0 % 7) * 0.01 }
        let result = AudioGraphNullTest.compare(reference: pcm, candidate: pcm)
        #expect(result.passed)
        #expect(result.bestOffsetSamples == 0)
        #expect(result.maxAbsoluteDeviation == 0)
    }

    @Test("a one-sample shift is re-aligned within the ±1 search and passes")
    func oneSampleShiftRealigns() {
        let reference = (0..<512).map { Float($0) * 0.001 }
        var candidate = reference
        candidate.removeFirst()          // candidate starts one sample later
        candidate.append(candidate.last ?? 0)
        let result = AudioGraphNullTest.compare(reference: reference, candidate: candidate)
        #expect(result.passed)
        #expect(abs(result.bestOffsetSamples) == 1)
    }

    @Test("deviation beyond one 16-bit LSB fails")
    func aboveLsbFails() {
        let reference = [Float](repeating: 0.5, count: 128)
        let candidate = [Float](repeating: 0.5 + Float(3.0 / 32_768.0), count: 128)
        let result = AudioGraphNullTest.compare(reference: reference, candidate: candidate)
        #expect(!result.passed)
        #expect(result.maxAbsoluteDeviation > result.lsb16)
    }

    @Test("one-LSP-level difference still passes (16-bit quantization tolerance)")
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
