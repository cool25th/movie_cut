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

    // MARK: - Codec-delay trim (G-25 2C-3, §8.1 strict gate)

    @Test("codec-delay trim recovers the encoder input at exact length (±1)")
    func codecDelayTrimRoundTrip() throws {
        // Content that starts loud at frame 0 plus a quiet tail: onset
        // detection can't cheat this — only correlation aligns it.
        let frames = 96_000
        var interleaved = [Float]()
        interleaved.reserveCapacity(frames * 2)
        for sample in 0..<(frames * 2) {
            let frame = sample / 2
            let envelope = frame < 72_000 ? 0.5 : 0.05
            let phase = Double(frame) * 2 * .pi * 440 / 48_000
            interleaved.append(Float(sin(phase) * envelope))
        }
        let source = AudioGraphSourceAudio(
            sampleRate: 48_000, channels: 2, interleaved: interleaved
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("moviecut-aac-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }

        try AudioGraphAacEncoder.encode(source, to: url)
        let decoded = try AudioGraphExportPostCheck.decode(fileAt: url)
        let (trimmed, delay) = AudioGraphExportPostCheck.trimCodecDelay(
            reference: source, decoded: decoded
        )

        // The trim IS the §8.1 caller contract: measured delay is a
        // plausible priming, and the trimmed stream matches the encoder
        // input's length within ±1 (the strict gate `check` then judges).
        #expect(delay >= 0)
        #expect(delay <= AudioGraphExportPostCheck.maxCodecDelaySamples)
        #expect(abs(trimmed.frameCount - source.frameCount) <= 1)
        let report = AudioGraphExportPostCheck.check(reference: source, decoded: trimmed)
        #expect(report.lengthWithinOneSample)
        #expect(report.passed)
        #expect(abs(report.rmsDifferenceDb) < 1.0)
    }
}
