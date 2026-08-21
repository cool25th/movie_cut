import Foundation
import Testing
@testable import MovieCutCore

/// G-26 Inc 1 — the compressor's static transfer curve and dynamic
/// behavior on synthetic signals.
@Suite("Audio Graph Compressor (G-26)")
struct AudioGraphCompressorTests {
    // MARK: - Static curve

    @Test("below the threshold is unity (no compression)")
    func unityBelowThreshold() {
        let output = AudioGraphCompressor.staticOutputDb(
            inputDb: -40, thresholdDb: -24, ratio: 3
        )
        #expect(abs(output - (-40)) < 0.01)
    }

    @Test("at the threshold is the knee (unity)")
    func kneeAtThreshold() {
        let output = AudioGraphCompressor.staticOutputDb(
            inputDb: -24, thresholdDb: -24, ratio: 3
        )
        #expect(abs(output - (-24)) < 0.01)
    }

    @Test("above the threshold compresses by the ratio")
    func compressionByRatio() {
        // Input −14 dB, threshold −24 dB, ratio 3:1 → excess 10 dB →
        // output −24 + 10/3 ≈ −20.67 dB.
        let output = AudioGraphCompressor.staticOutputDb(
            inputDb: -14, thresholdDb: -24, ratio: 3
        )
        #expect(abs(output - (-24 + 10.0 / 3.0)) < 0.01)
    }

    @Test("makeup gain shifts the output")
    func makeupGain() {
        let output = AudioGraphCompressor.staticOutputDb(
            inputDb: -14, thresholdDb: -24, ratio: 3, makeupGainDb: 6
        )
        #expect(abs(output - (-24 + 10.0 / 3.0 + 6.0)) < 0.01)
    }

    @Test("ratio 1:1 is unity everywhere; ratio 20:1 is near-limiting")
    func ratioExtremes() {
        let unity = AudioGraphCompressor.staticOutputDb(
            inputDb: -10, thresholdDb: -24, ratio: 1
        )
        #expect(abs(unity - (-10)) < 0.01)

        let limiting = AudioGraphCompressor.staticOutputDb(
            inputDb: -10, thresholdDb: -24, ratio: 20
        )
        // −24 + 14/20 ≈ −23.3 dB — nearly clamped to the threshold.
        #expect(abs(limiting - (-23.3)) < 0.1)
    }

    // MARK: - Dynamic behavior

    @Test("a loud signal is measurably attenuated")
    func loudSignalAttenuated() {
        // 1s of −6 dBFS sine (well above the −24 dB threshold).
        let frames = 48_000
        var interleaved = [Float]()
        interleaved.reserveCapacity(frames * 2)
        for sample in 0..<(frames * 2) {
            let frame = sample / 2
            let phase = Double(frame) * 2 * .pi * 440 / 48_000
            interleaved.append(Float(sin(phase) * 0.5))  // ≈ −6 dBFS
        }
        let input = AudioGraphSourceAudio(sampleRate: 48_000, channels: 2, interleaved: interleaved)
        let output = AudioGraphCompressor.apply(input, parameters: .init(thresholdDb: -24, ratio: 4))

        func rms(_ audio: AudioGraphSourceAudio) -> Double {
            var sum: Double = 0
            for i in 0..<min(audio.interleaved.count, 48_000 * 2) {
                sum += Double(audio.interleaved[i]) * Double(audio.interleaved[i])
            }
            return (sum / Double(48_000 * 2)).squareRoot()
        }

        let inputRms = rms(input)
        let outputRms = rms(output)
        let reductionDb = 20 * log10(outputRms / inputRms)
        // 4:1 on −6 dB above −24 → excess 18 dB → 18/4 = 4.5 dB output
        // excess → 18−4.5 = 13.5 dB reduction (steady-state).
        #expect(reductionDb < -6, "must reduce by at least 6 dB; got \(reductionDb) dB")
        #expect(reductionDb > -20, "must not crush to silence; got \(reductionDb) dB")
    }

    @Test("a quiet signal passes through essentially unchanged")
    func quietSignalPasses() {
        let frames = 48_000
        var interleaved = [Float]()
        for sample in 0..<(frames * 2) {
            let frame = sample / 2
            let phase = Double(frame) * 2 * .pi * 440 / 48_000
            interleaved.append(Float(sin(phase) * 0.01))  // ≈ −40 dBFS (below threshold)
        }
        let input = AudioGraphSourceAudio(sampleRate: 48_000, channels: 2, interleaved: interleaved)
        let output = AudioGraphCompressor.apply(input)

        func rms(_ audio: AudioGraphSourceAudio) -> Double {
            var sum: Double = 0
            for i in 0..<min(audio.interleaved.count, 48_000 * 2) {
                sum += Double(audio.interleaved[i]) * Double(audio.interleaved[i])
            }
            return (sum / Double(48_000 * 2)).squareRoot()
        }

        let ratio = rms(output) / rms(input)
        #expect(abs(ratio - 1.0) < 0.05, "quiet signal must be near unity; got \(ratio)")
    }

    @Test("empty audio is a safe no-op")
    func emptyAudio() {
        let empty = AudioGraphSourceAudio(sampleRate: 48_000, channels: 2, interleaved: [])
        let output = AudioGraphCompressor.apply(empty)
        #expect(output.interleaved.isEmpty)
    }

    // MARK: - Parameters

    @Test("parameters clamp to valid ranges")
    func parameterClamping() {
        let params = AudioGraphCompressor.Parameters(
            thresholdDb: -100, ratio: 50, attackSeconds: 0, releaseSeconds: 0, makeupGainDb: 100
        )
        #expect(params.thresholdDb >= -60)
        #expect(params.ratio <= 20)
        #expect(params.attackSeconds >= 0.001)
        #expect(params.releaseSeconds >= 0.01)
        #expect(params.makeupGainDb <= 24)
    }
}
