import Foundation
import Testing
@testable import MovieCutCore

@Suite("Vocal Separation")
struct VocalSeparationTests {
    private func approxEqual(_ a: [Float], _ b: [Float], tolerance: Float = 1e-6) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
    }

    @Test("Removing vocals cancels dead-center content")
    func removeVocalsCancelsCenter() {
        // Identical L/R = perfectly center-panned (vocal-like) signal.
        let center: [Float] = [0.5, -0.3, 0.8, -0.6]
        let frames = StereoFrames(left: center, right: center)
        let result = CenterChannelVocalSeparator(wetMix: 1).process(frames, mode: .removeVocals)

        #expect(approxEqual(result.left, [0, 0, 0, 0]))
        #expect(approxEqual(result.right, [0, 0, 0, 0]))
    }

    @Test("Removing vocals preserves panned (off-center) content")
    func removeVocalsKeepsPanned() {
        // Hard-panned left: appears only in L.
        let frames = StereoFrames(left: [0.8, -0.4], right: [0, 0])
        let result = CenterChannelVocalSeparator(wetMix: 1).process(frames, mode: .removeVocals)

        // Fully wet: L' = (L−R)/2, R' = (R−L)/2 — the panned content survives.
        #expect(approxEqual(result.left, [0.4, -0.2]))
        #expect(approxEqual(result.right, [-0.4, 0.2]))
    }

    @Test("Isolating center keeps a center signal and is mono")
    func isolateCenterKeepsCenter() {
        let center: [Float] = [0.5, -0.3, 0.8]
        let frames = StereoFrames(left: center, right: center)
        let result = CenterChannelVocalSeparator(wetMix: 1).process(frames, mode: .isolateCenter)

        #expect(approxEqual(result.left, center))
        #expect(approxEqual(result.right, center))
        // Output is mono (left == right).
        #expect(approxEqual(result.left, result.right))
    }

    @Test("Isolating center attenuates hard-panned content")
    func isolateCenterAttenuatesPanned() {
        let frames = StereoFrames(left: [1.0], right: [0.0])
        let result = CenterChannelVocalSeparator(wetMix: 1).process(frames, mode: .isolateCenter)
        // mid = (1 + 0)/2 = 0.5 on both channels — panned energy halved and centered.
        #expect(approxEqual(result.left, [0.5]))
        #expect(approxEqual(result.right, [0.5]))
    }

    @Test("A zero wet mix is a passthrough for both modes")
    func zeroWetIsPassthrough() {
        let frames = StereoFrames(left: [0.2, -0.7], right: [0.1, 0.9])
        let separator = CenterChannelVocalSeparator(wetMix: 0)

        let removed = separator.process(frames, mode: .removeVocals)
        #expect(approxEqual(removed.left, frames.left))
        #expect(approxEqual(removed.right, frames.right))

        let isolated = separator.process(frames, mode: .isolateCenter)
        #expect(approxEqual(isolated.left, frames.left))
        #expect(approxEqual(isolated.right, frames.right))
    }

    @Test("Wet mix scales the effect linearly")
    func partialWetMix() {
        // Center signal, half-strength removal: L' = L − 0.5*mid = L − 0.5*L = 0.5*L.
        let center: [Float] = [0.4]
        let frames = StereoFrames(left: center, right: center)
        let result = CenterChannelVocalSeparator(wetMix: 0.5).process(frames, mode: .removeVocals)
        #expect(approxEqual(result.left, [0.2]))
        #expect(approxEqual(result.right, [0.2]))
    }

    @Test("Wet mix is clamped to the unit range")
    func wetMixClamped() {
        #expect(CenterChannelVocalSeparator(wetMix: 5).wetMix == 1)
        #expect(CenterChannelVocalSeparator(wetMix: -2).wetMix == 0)
    }

    @Test("Mismatched channel lengths use the shorter channel")
    func mismatchedLengths() {
        let frames = StereoFrames(left: [0.5, 0.5, 0.5], right: [0.5])
        #expect(frames.frameCount == 1)
        let result = CenterChannelVocalSeparator(wetMix: 1).process(frames, mode: .removeVocals)
        #expect(result.left.count == 1)
        #expect(approxEqual(result.left, [0]))
    }

    @Test("Empty input yields empty output")
    func emptyInput() {
        let result = CenterChannelVocalSeparator().process(StereoFrames(left: [], right: []), mode: .removeVocals)
        #expect(result.left.isEmpty)
        #expect(result.right.isEmpty)
    }
}
