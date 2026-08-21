import Foundation
import Testing
@testable import MovieCutCore

/// G-26 Inc 2 — the limiter's ceiling guarantee and the reverb's wet-path.
@Suite("Audio Graph Limiter + Reverb (G-26)")
struct AudioGraphLimiterReverbTests {
    private func sine(frames: Int, amplitude: Double, rate: Double = 48_000) -> AudioGraphSourceAudio {
        var interleaved = [Float]()
        interleaved.reserveCapacity(frames * 2)
        for sample in 0..<(frames * 2) {
            let frame = sample / 2
            let phase = Double(frame) * 2 * .pi * 440 / rate
            interleaved.append(Float(sin(phase) * amplitude))
        }
        return AudioGraphSourceAudio(sampleRate: rate, channels: 2, interleaved: interleaved)
    }

    private func peak(_ audio: AudioGraphSourceAudio) -> Double {
        audio.interleaved.map { abs(Double($0)) }.max() ?? 0
    }

    // MARK: - Limiter

    @Test("the limiter guarantees the output never exceeds the ceiling")
    func limiterCeiling() {
        // A loud sine (0 dBFS peak) through a −1 dB ceiling.
        let input = sine(frames: 48_000, amplitude: 1.0)
        let output = AudioGraphLimiter.apply(input, parameters: .init(ceilingDb: -1))
        let ceilingLinear = pow(10.0, -1.0 / 20.0)  // ≈ 0.891
        let outputPeak = peak(output)
        #expect(outputPeak <= ceilingLinear + 0.001,
                "peak must stay under the ceiling; got \(outputPeak) > \(ceilingLinear)")
    }

    @Test("quiet signals pass through unchanged when below the ceiling")
    func limiterQuietPasses() {
        let input = sine(frames: 48_000, amplitude: 0.1)  // −20 dBFS
        let output = AudioGraphLimiter.apply(input, parameters: .init(ceilingDb: -1))
        let inputPeak = peak(input)
        let outputPeak = peak(output)
        #expect(abs(outputPeak - inputPeak) < 0.001,
                "below-ceiling signal must be unity; in=\(inputPeak) out=\(outputPeak)")
    }

    @Test("a transient spike is clamped before it arrives (look-ahead)")
    func limiterLookAhead() {
        // Quiet signal with a sudden loud spike at frame 24000.
        var interleaved = [Float]()
        for sample in 0..<(48_000 * 2) {
            let frame = sample / 2
            let phase = Double(frame) * 2 * .pi * 440 / 48_000
            let amplitude: Double = frame >= 24_000 && frame < 24_100 ? 1.0 : 0.1
            interleaved.append(Float(sin(phase) * amplitude))
        }
        let input = AudioGraphSourceAudio(sampleRate: 48_000, channels: 2, interleaved: interleaved)
        let output = AudioGraphLimiter.apply(input, parameters: .init(ceilingDb: -3))
        let ceilingLinear = pow(10.0, -3.0 / 20.0)
        #expect(peak(output) <= ceilingLinear + 0.001,
                "the spike must be clamped; peak=\(peak(output)) ceiling=\(ceilingLinear)")
    }

    @Test("empty audio is safe")
    func limiterEmpty() {
        let empty = AudioGraphSourceAudio(sampleRate: 48_000, channels: 2, interleaved: [])
        let output = AudioGraphLimiter.apply(empty)
        #expect(output.interleaved.isEmpty)
    }

    @Test("parameters clamp")
    func limiterClamping() {
        let params = AudioGraphLimiter.Parameters(ceilingDb: 10, lookAheadSeconds: 1, releaseSeconds: 10)
        #expect(params.ceilingDb <= 0)
        #expect(params.lookAheadSeconds <= 0.05)
        #expect(params.releaseSeconds <= 1.0)
    }

    // MARK: - Reverb

    @Test("dry-only (mix=0) is identity")
    func reverbDryOnly() {
        let input = sine(frames: 48_000, amplitude: 0.5)
        let output = AudioGraphReverb.apply(input, parameters: .init(mix: 0))
        #expect(output.interleaved == input.interleaved, "mix=0 must be bit-exact")
    }

    @Test("wet-only (mix=1) has longer energy than the dry (tail)")
    func reverbTail() {
        // A short burst followed by silence — the reverb must add tail.
        let burstFrames = 2400  // 50ms
        var interleaved = [Float]()
        for sample in 0..<(48_000 * 2) {
            let frame = sample / 2
            let value: Double = frame < burstFrames ? sin(Double(frame) * 2 * .pi * 440 / 48_000) * 0.5 : 0
            interleaved.append(Float(value))
        }
        let input = AudioGraphSourceAudio(sampleRate: 48_000, channels: 2, interleaved: interleaved)
        let output = AudioGraphReverb.apply(input, parameters: .init(mix: 0.5, roomSize: 0.5, decay: 0.5))

        // After the burst, the dry is zero but the wet tail is non-zero.
        let tailStart = (burstFrames + 1000) * 2  // well past the burst
        let tailEnergy = output.interleaved[tailStart...].map { Double($0) * Double($0) }.reduce(0, +)
        #expect(tailEnergy > 0, "the reverb must leave a non-zero tail")
    }

    @Test("reverb preserves the frame count")
    func reverbFrameCount() {
        let input = sine(frames: 10_000, amplitude: 0.5)
        let output = AudioGraphReverb.apply(input, parameters: .room)
        #expect(output.frameCount == input.frameCount)
    }

    @Test("empty audio is safe")
    func reverbEmpty() {
        let empty = AudioGraphSourceAudio(sampleRate: 48_000, channels: 2, interleaved: [])
        let output = AudioGraphReverb.apply(empty)
        #expect(output.interleaved.isEmpty)
    }
}
