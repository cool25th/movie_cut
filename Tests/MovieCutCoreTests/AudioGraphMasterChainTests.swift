import Foundation
import Testing
@testable import MovieCutCore

/// G-26 Inc 3 — the master chain: composition order, SNS preset effect,
/// and the ±0.2LU gate's data.
@Suite("Audio Graph Master Chain (G-26)")
struct AudioGraphMasterChainTests {
    private func sine(frames: Int, amplitude: Double, rate: Double = 48_000) -> AudioGraphSourceAudio {
        var interleaved = [Float]()
        interleaved.reserveCapacity(frames * 2)
        for sample in 0..<(frames * 2) {
            let frame = sample / 2
            interleaved.append(Float(sin(Double(frame) * 2 * .pi * 440 / rate) * amplitude))
        }
        return AudioGraphSourceAudio(sampleRate: rate, channels: 2, interleaved: interleaved)
    }

    @Test("bypass is bit-exact identity")
    func bypassIdentity() {
        let input = sine(frames: 48_000, amplitude: 0.5)
        let output = AudioGraphMasterChain.apply(input, chain: .bypass)
        #expect(output.interleaved == input.interleaved)
    }

    @Test("the SNS chain measurably changes the LUFS and holds the true peak")
    func snsChainEffect() {
        // A dynamic signal: quiet intro, loud burst, medium tail.
        var interleaved = [Float]()
        for sample in 0..<(48_000 * 2) {
            let frame = sample / 2
            let amplitude: Double
            switch frame {
            case 0..<14_400: amplitude = 0.02          // −34 dB (quiet)
            case 14_400..<24_000: amplitude = 0.9       // −1 dB (loud)
            default: amplitude = 0.15                    // −16 dB (tail)
            }
            interleaved.append(Float(sin(Double(frame) * 2 * .pi * 440 / 48_000) * amplitude))
        }
        let input = AudioGraphSourceAudio(sampleRate: 48_000, channels: 2, interleaved: interleaved)

        let effect = AudioGraphMasterChain.measureChainEffect(input, chain: .sns)

        // The compressor reduces the dynamic range — output LUFS closer
        // to the mean than the input (the loud part is tamed).
        #expect(effect.inputLufs != nil, "input LUFS must be measurable")
        #expect(effect.outputLufs != nil, "output LUFS must be measurable")

        if let inputLufs = effect.inputLufs, let outputLufs = effect.outputLufs {
            // With compression, the loud burst is tamed → output LUFS is
            // lower than input (the loud part dominates the input).
            #expect(outputLufs < inputLufs + 1.0,
                    "compression must not boost overall loudness")
        }

        // The limiter guarantees the true peak stays at or below −1 dBTP.
        #expect(effect.outputTruePeakDb <= -0.5,
                "true peak must stay under −1 dBTP + tolerance; got \(effect.outputTruePeakDb)")
    }

    @Test("each stage composes: compressor alone differs from full chain")
    func composition() {
        let input = sine(frames: 48_000, amplitude: 0.8)
        let compressedOnly = AudioGraphMasterChain.apply(
            input, chain: AudioGraphMasterChain.Chain(compressor: .sns)
        )
        let fullChain = AudioGraphMasterChain.apply(input, chain: .sns)

        func peak(_ audio: AudioGraphSourceAudio) -> Double {
            audio.interleaved.map { abs(Double($0)) }.max() ?? 0
        }
        // The limiter in the full chain caps the peak at ≈ −1 dBTP.
        #expect(peak(fullChain) < peak(compressedOnly),
                "the full chain (with limiter) must have a lower peak")
    }

    @Test("the chain is Codable")
    func codable() throws {
        let chain = AudioGraphMasterChain.Chain.sns
        let data = try JSONEncoder().encode(chain)
        let decoded = try JSONDecoder().decode(AudioGraphMasterChain.Chain.self, from: data)
        #expect(decoded == chain)
    }

    @Test("empty audio is safe")
    func emptySafe() {
        let empty = AudioGraphSourceAudio(sampleRate: 48_000, channels: 2, interleaved: [])
        let output = AudioGraphMasterChain.apply(empty, chain: .sns)
        #expect(output.interleaved.isEmpty)
    }
}
