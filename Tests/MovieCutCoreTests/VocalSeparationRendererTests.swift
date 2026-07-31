import Foundation
import Testing
import AVFoundation
@testable import MovieCutCore

/// Verifies the offline ``VocalSeparationRenderer`` (the App-facing
/// read → block-process → write path that wires ``CenterChannelVocalSeparator``
/// into file production, mirroring `NoiseReductionService`).
///
/// Validation is by audio measurement (per requirements.md §9.5): center-panned
/// energy must drop meaningfully while side energy is preserved, and mono input
/// must fail explicitly rather than pass through unchanged.
@Suite("Vocal Separation Renderer")
struct VocalSeparationRendererTests {

    // MARK: - Stereo removal reduces center energy and preserves side energy

    @Test("Stereo removeVocals reduces center energy while preserving side energy")
    func stereoRemoveVocalsReducesCenterPreservesSide() async throws {
        // Build a fixture with two independent components:
        //   - center component: identical in L and R (center-panned "vocal")
        //   - side component:   opposite sign in L and R (hard-panned "instrument")
        let (inputURL, centerLevel, sideLevel) = try Self.writeStereoWAV(
            centerAmplitude: 0.6,
            sideAmplitude: 0.5,
            duration: 1.0
        )
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let renderer = VocalSeparationRenderer(mode: .removeVocals, wetMix: 1)
        let outputURL = try await renderer.render(inputURL: inputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        // The renderer must have produced a real, non-empty file.
        #expect(FileManager.default.fileExists(atPath: outputURL.path))

        let (outLeft, outRight, outSampleRate) = try Self.readStereoPCM(url: outputURL)
        #expect(outLeft.count == outRight.count)
        #expect(outLeft.count > 0)

        // mid = (L+R)/2 captures center-panned content; side = (L-R)/2 captures
        // panned content. With full removeVocals, mid energy collapses toward 0
        // and side energy is preserved.
        let outMidRMS = Self.rms(of: zip(outLeft, outRight).map { ($0 + $1) * 0.5 })
        let outSideRMS = Self.rms(of: zip(outLeft, outRight).map { ($0 - $1) * 0.5 })

        // Center energy must drop by a large factor (full cancellation targets 0).
        // Input center RMS ≈ centerAmplitude / sqrt(2); require a >10x reduction.
        let inputCenterRMS = centerLevel / Float(2.squareRoot())
        #expect(outMidRMS < inputCenterRMS / 10,
                Comment(rawValue: "center RMS dropped from \(inputCenterRMS) to \(outMidRMS)"))

        // Side energy must be preserved (input side RMS ≈ sideAmplitude / sqrt(2)).
        let inputSideRMS = sideLevel / Float(2.squareRoot())
        #expect(abs(outSideRMS - inputSideRMS) / max(inputSideRMS, 1e-6) < 0.25,
                Comment(rawValue: "side RMS changed from \(inputSideRMS) to \(outSideRMS)"))

        // The renderer preserves the sample rate.
        #expect(outSampleRate == 44100)
    }

    @Test("Stereo isolateCenter keeps center energy and makes output near-mono")
    func stereoIsolateCenterKeepsCenter() async throws {
        let (inputURL, centerLevel, _) = try Self.writeStereoWAV(
            centerAmplitude: 0.7,
            sideAmplitude: 0.5,
            duration: 1.0
        )
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let renderer = VocalSeparationRenderer(mode: .isolateCenter, wetMix: 1)
        let outputURL = try await renderer.render(inputURL: inputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let (outLeft, outRight, _) = try Self.readStereoPCM(url: outputURL)

        let outMidRMS = Self.rms(of: zip(outLeft, outRight).map { ($0 + $1) * 0.5 })
        let inputCenterRMS = centerLevel / Float(2.squareRoot())
        // Isolation keeps the center estimate, so mid energy is comparable to input.
        #expect(abs(outMidRMS - inputCenterRMS) / max(inputCenterRMS, 1e-6) < 0.35,
                Comment(rawValue: "isolate center mid \(outMidRMS) vs input \(inputCenterRMS)"))

        // Isolated output is the mono center estimate on both channels.
        let diff = Self.rms(of: zip(outLeft, outRight).map { $0 - $1 })
        #expect(diff < 1e-3, Comment(rawValue: "isolate output should be mono, L-R rms \(diff)"))
    }

    // MARK: - Mono input fails explicitly (no silent passthrough)

    @Test("Mono input throws an explicit error and does not passthrough")
    func monoInputThrowsExplicitly() async throws {
        let monoURL = try Self.writeMonoWAV(amplitude: 0.4, duration: 1.0)
        defer { try? FileManager.default.removeItem(at: monoURL) }

        let renderer = VocalSeparationRenderer(mode: .removeVocals)

        await #expect(throws: VocalSeparationRendererError.monoInputUnsupported) {
            try await renderer.render(inputURL: monoURL)
        }
    }

    // MARK: - Helpers

    /// Sum-of-squares RMS over a sample array.
    private static func rms(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// Writes a 16-bit stereo PCM WAV: a 440 Hz center tone (identical L/R) plus
    /// a 988 Hz side tone (opposite sign per channel). Returns the URL plus the
    /// numeric center/side amplitudes used, for measurement expectations.
    private static func writeStereoWAV(
        centerAmplitude: Float,
        sideAmplitude: Float,
        duration: TimeInterval,
        sampleRate: Double = 44100
    ) throws -> (url: URL, centerLevel: Float, sideLevel: Float) {
        let frameCount = Int(duration * sampleRate)
        let dataSize = frameCount * 2 /* channels */ * 2 /* 16-bit */
        var data = Data(capacity: 44 + dataSize)
        data.append(contentsOf: "RIFF".utf8)
        appendInt32(&data, Int32(36 + dataSize))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        appendInt32(&data, 16)
        appendInt16(&data, 1)   // PCM
        appendInt16(&data, 2)   // stereo
        appendInt32(&data, Int32(sampleRate))
        appendInt32(&data, Int32(sampleRate * 2 * 2)) // byte rate
        appendInt16(&data, 4)   // block align (2 channels * 2 bytes)
        appendInt16(&data, 16)  // bits per sample
        data.append(contentsOf: "data".utf8)
        appendInt32(&data, Int32(dataSize))

        for index in 0..<frameCount {
            let t = Double(index) / sampleRate
            let center = Float(sin(2 * .pi * 440 * t)) * centerAmplitude
            let side = Float(sin(2 * .pi * 988 * t)) * sideAmplitude
            // L = center + side, R = center - side.
            let left = center + side
            let right = center - side
            appendInt16(&data, toInt16(left))
            appendInt16(&data, toInt16(right))
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vocalsep_stereo_\(UUID().uuidString).wav")
        try data.write(to: url)
        return (url, centerAmplitude, sideAmplitude)
    }

    /// Writes a 16-bit mono PCM WAV (a 440 Hz tone) — used to prove mono fails.
    private static func writeMonoWAV(
        amplitude: Float,
        duration: TimeInterval,
        sampleRate: Double = 44100
    ) throws -> URL {
        let frameCount = Int(duration * sampleRate)
        let dataSize = frameCount * 2
        var data = Data(capacity: 44 + dataSize)
        data.append(contentsOf: "RIFF".utf8)
        appendInt32(&data, Int32(36 + dataSize))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        appendInt32(&data, 16)
        appendInt16(&data, 1)   // PCM
        appendInt16(&data, 1)   // mono
        appendInt32(&data, Int32(sampleRate))
        appendInt32(&data, Int32(sampleRate * 2))
        appendInt16(&data, 2)
        appendInt16(&data, 16)
        data.append(contentsOf: "data".utf8)
        appendInt32(&data, Int32(dataSize))
        for index in 0..<frameCount {
            let t = Double(index) / sampleRate
            appendInt16(&data, toInt16(Float(sin(2 * .pi * 440 * t)) * amplitude))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vocalsep_mono_\(UUID().uuidString).wav")
        try data.write(to: url)
        return url
    }

    /// Reads the first two channels of any AVAudioFile-readable file as Float
    /// samples, returning per-channel arrays and the sample rate.
    private static func readStereoPCM(url: URL) throws -> (left: [Float], right: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames),
              let channels = buffer.floatChannelData, format.channelCount >= 2 else {
            throw InvalidFixture.invalidOutput
        }
        try file.read(into: buffer)
        let count = Int(buffer.frameLength)
        let left = Array(UnsafeBufferPointer(start: channels[0], count: count))
        let right = Array(UnsafeBufferPointer(start: channels[1], count: count))
        return (left, right, format.sampleRate)
    }

    private static func toInt16(_ sample: Float) -> Int16 {
        let clamped = max(-1.0, min(1.0, sample))
        return Int16(clamped * 32767.0)
    }

    private static func appendInt16(_ data: inout Data, _ value: Int16) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 2))
    }

    private static func appendInt32(_ data: inout Data, _ value: Int32) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 4))
    }

    private enum InvalidFixture: Error {
        case invalidOutput
    }
}
