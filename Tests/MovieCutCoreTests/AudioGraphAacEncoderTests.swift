import Foundation
import Testing
@testable import MovieCutCore

/// G-25 switchover 2C — the graph PCM → AAC export encoder: real encode,
/// real re-decode, measured fidelity (length within codec padding, RMS/LUFS
/// preserved). These tests run against actual CoreAudio AAC, so they gate
/// the encoder contract the §8 export path leans on.
@Suite("AudioGraphAacEncoder (G-25 2C)")
struct AudioGraphAacEncoderTests {
    private func sine(
        frames: Int, sampleRate: Double, amplitude: Double = 0.5
    ) -> AudioGraphSourceAudio {
        AudioGraphSourceAudio(
            sampleRate: sampleRate, channels: 2,
            interleaved: (0..<frames * 2).map {
                Float(sin(Double($0 / 2) * 2 * .pi * 440 / sampleRate) * amplitude)
            }
        )
    }

    @Test("encoded m4a decodes as AAC stereo at the graph rate, length within codec padding")
    func encodesValidAac() throws {
        let source = sine(frames: 48_000, sampleRate: 48_000)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("moviecut-aac-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }

        try AudioGraphAacEncoder.encode(source, to: url)

        let decoded = try AudioGraphExportPostCheck.decode(fileAt: url)
        #expect(decoded.sampleRate == 48_000)
        #expect(decoded.channels == 2)
        // AAC priming/padding adds a bounded number of frames (measured on
        // this pipeline: a couple of 1024-frame packets).
        #expect(decoded.frameCount >= source.frameCount)
        #expect(decoded.frameCount - source.frameCount <= 8_192)
    }

    @Test("RMS and loudness survive the round trip within codec tolerance")
    func fidelityWithinTolerance() throws {
        let source = sine(frames: 96_000, sampleRate: 48_000)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("moviecut-aac-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }

        try AudioGraphAacEncoder.encode(source, to: url)
        let decoded = try AudioGraphExportPostCheck.decode(fileAt: url)

        func rms(_ audio: AudioGraphSourceAudio) -> Double {
            let overlap = min(audio.frameCount, source.frameCount)
            var energy = 0.0
            for frame in 0..<overlap {
                for channel in 0..<min(audio.channels, 2) {
                    let value = Double(audio.sample(frame: frame, channel: channel))
                    energy += value * value
                }
            }
            return sqrt(energy / Double(overlap * 2))
        }
        let deltaDb = 20 * log10(rms(decoded) / rms(source))
        #expect(abs(deltaDb) < 1.0)

        let sourceLufs = AudioGraphLoudness.measure(source).integratedLufs
        let decodedLufs = AudioGraphLoudness.measure(decoded).integratedLufs
        if let sourceLufs, let decodedLufs {
            #expect(abs(decodedLufs - sourceLufs) < 1.0)
        }
    }

    @Test("empty PCM is an explicit failure, never an empty file")
    func emptyPcmThrows() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("moviecut-aac-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        let empty = AudioGraphSourceAudio(sampleRate: 48_000, channels: 2, interleaved: [])
        #expect(throws: AudioGraphAacEncoder.EncodeError.self) {
            try AudioGraphAacEncoder.encode(empty, to: url)
        }
    }
}
