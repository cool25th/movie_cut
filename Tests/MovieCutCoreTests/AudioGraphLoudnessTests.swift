import AVFoundation
import Foundation
import Testing
@testable import MovieCutCore

/// G-25 Inc 9 (Core half) — §7 meter math (BS.1770-4 integrated loudness,
/// 4× true peak) and the §8 export post-check, pinned to analytic anchors:
/// the ITU reference tone (997 Hz, 0 dBFS, one channel = −3.01 LUFS),
/// channel summation (+3.01 LU), level linearity, gating, DC-exact true
/// peak, and inter-sample-peak detection.
@Suite("AudioGraphLoudness + ExportPostCheck (G-25 Inc 9 Core)")
struct AudioGraphLoudnessTests {
    // MARK: - Fixtures

    private func sine(
        amplitude: Double,
        frequency: Double = 997,
        seconds: Double = 1.5,
        sampleRate: Double = 48_000,
        channels: Int = 2,
        phase: Double = 0
    ) -> AudioGraphSourceAudio {
        let frames = Int(seconds * sampleRate)
        var samples = [Float]()
        samples.reserveCapacity(frames * channels)
        for frame in 0..<frames {
            let value = amplitude * sin(2 * .pi * frequency * Double(frame) / sampleRate + phase)
            for _ in 0..<channels { samples.append(Float(value)) }
        }
        return AudioGraphSourceAudio(sampleRate: sampleRate, channels: channels, interleaved: samples)
    }

    // MARK: - Integrated loudness (BS.1770-4)

    @Test("ITU anchor: full-scale 997 Hz in ONE channel measures -3.01 LUFS")
    func ituAnchor() {
        // The K-weighting calibration anchor: 0 dBFS 997 Hz in a single
        // channel reads −3.01 LUFS on a conforming meter.
        let measurement = AudioGraphLoudness.measure(sine(amplitude: 1.0, channels: 1))
        #expect(abs((measurement.integratedLufs ?? 0) - (-3.01)) < 0.1)
        #expect(abs(measurement.samplePeakDbFs - 0.0) < 0.01)
        #expect(abs(measurement.truePeakDbTp - 0.0) < 0.1)
    }

    @Test("both channels sum to +3.01 LU over one channel")
    func channelSummation() {
        let mono = AudioGraphLoudness.measure(sine(amplitude: 0.5, channels: 1))
        let dual = AudioGraphLoudness.measure(sine(amplitude: 0.5, channels: 2))
        #expect(abs(((dual.integratedLufs ?? 0) - (mono.integratedLufs ?? 0)) - 3.01) < 0.05)
    }

    @Test("loudness is level-linear: -20 dB in level is -20 LU")
    func levelLinearity() {
        let loud = AudioGraphLoudness.measure(sine(amplitude: 0.5))
        let quiet = AudioGraphLoudness.measure(sine(amplitude: 0.05))
        #expect(abs(((loud.integratedLufs ?? 0) - (quiet.integratedLufs ?? 0)) - 20.0) < 0.05)
    }

    @Test("the relative gate excludes trailing silence")
    func gatingExcludesSilence() {
        let loudFrames = Int(2.0 * 48_000)
        let silentFrames = Int(8.0 * 48_000)
        var samples = [Float]()
        for frame in 0..<(loudFrames + silentFrames) {
            let value: Double = frame < loudFrames
                ? 0.1 * sin(2 * .pi * 997 * Double(frame) / 48_000)
                : 0
            samples.append(Float(value))
            samples.append(Float(value))
        }
        let gated = AudioGraphLoudness.measure(
            AudioGraphSourceAudio(sampleRate: 48_000, channels: 2, interleaved: samples)
        )
        let loudOnly = AudioGraphLoudness.measure(sine(amplitude: 0.1, seconds: 2))
        #expect(abs((gated.integratedLufs ?? 0) - (loudOnly.integratedLufs ?? 0)) < 0.5)
    }

    @Test("silence and sub-block signals have no integrated loudness")
    func silenceHasNoLoudness() {
        let silence = AudioGraphLoudness.measure(
            AudioGraphSourceAudio(sampleRate: 48_000, channels: 2, interleaved: [Float](repeating: 0, count: 96_000 * 2))
        )
        #expect(silence.integratedLufs == nil)
        #expect(silence.truePeakDbTp == AudioGraphLoudness.silenceFloorDb)

        // Shorter than one 400 ms block: no measurement is possible.
        let tooShort = AudioGraphLoudness.measure(sine(amplitude: 0.5, seconds: 0.1))
        #expect(tooShort.integratedLufs == nil)
        // The peaks are still exact on any length.
        #expect(abs(tooShort.samplePeakDbFs - (-6.0206)) < 0.01)
    }

    // MARK: - True peak (4x oversampled)

    @Test("DC true peak is exact: 0.5 reads -6.02 dBTP")
    func dcTruePeakIsExact() {
        let dc = AudioGraphLoudness.measure(
            AudioGraphSourceAudio(sampleRate: 48_000, channels: 2, interleaved: [Float](repeating: 0.5, count: 96_000 * 2))
        )
        #expect(abs(dc.truePeakDbTp - (-6.0206)) < 0.05)
    }

    @Test("true peak catches inter-sample peaks the sample peak misses")
    func interSamplePeakDetection() {
        // 6 kHz at π/8 phase: the crest falls between samples, so the
        // oversampled peak sits measurably above the sample peak.
        let isp = AudioGraphLoudness.measure(sine(amplitude: 0.95, frequency: 6_000, phase: .pi / 8))
        #expect(isp.truePeakDbTp > isp.samplePeakDbFs)
        #expect((isp.truePeakDbTp - isp.samplePeakDbFs) > 0.4)
        #expect((isp.truePeakDbTp - isp.samplePeakDbFs) < 1.2)
    }

    // MARK: - Clipping (§8.3)

    @Test("clipping counts runs of consecutive full-scale samples")
    func clippingRuns() {
        func audio(_ samples: [Float]) -> AudioGraphSourceAudio {
            AudioGraphSourceAudio(sampleRate: 48_000, channels: 1, interleaved: samples)
        }
        // A 3-sample plateau at full scale: one clipping run.
        var clipped = [Float](repeating: 0.3, count: 64)
        clipped[32...34] = [1.0, 1.0, 1.0]
        #expect(AudioGraphLoudness.clippingRuns(in: audio(clipped)) == (runCount: 1, maxRunLength: 3))

        // A single full-scale sample is not clipping.
        var single = [Float](repeating: 0.3, count: 64)
        single[32] = 1.0
        #expect(AudioGraphLoudness.clippingRuns(in: audio(single)) == (runCount: 0, maxRunLength: 1))

        // Alternating ±1 IS clipping: "consecutive full-scale samples"
        // counts time-adjacent samples regardless of sign.
        var alternating = [Float](repeating: 0.3, count: 64)
        alternating[32] = 1.0
        alternating[33] = -1.0
        #expect(AudioGraphLoudness.clippingRuns(in: audio(alternating)) == (runCount: 1, maxRunLength: 2))
    }

    // MARK: - Export post-check (§8)

    @Test("an identical reference/decoded pair passes with zero deviation")
    func identicalPairPasses() {
        let reference = sine(amplitude: 0.1)
        let report = AudioGraphExportPostCheck.check(reference: reference, decoded: reference)
        #expect(report.lengthWithinOneSample)
        #expect(report.passed)
        #expect(abs(report.rmsDifferenceDb) < 0.001)
        #expect(report.warnings.isEmpty)
        #expect(report.clippingRunCount == 0)
    }

    @Test("a length mismatch beyond one sample fails the gate and warns")
    func lengthMismatchFails() {
        let reference = sine(amplitude: 0.1, seconds: 1)
        var trimmed = reference.interleaved
        trimmed.removeLast(20 * 2) // 20 frames short — beyond ±1
        let decoded = AudioGraphSourceAudio(
            sampleRate: reference.sampleRate, channels: reference.channels, interleaved: trimmed
        )
        let report = AudioGraphExportPostCheck.check(reference: reference, decoded: decoded)
        #expect(!report.lengthWithinOneSample)
        #expect(!report.passed)
        #expect(report.warnings.contains { $0.contains("length") })
    }

    @Test("an RMS difference is REPORTED, never gated (§8.1)")
    func rmsDifferenceIsReported() {
        let reference = sine(amplitude: 0.1)
        let quieter = AudioGraphSourceAudio(
            sampleRate: reference.sampleRate,
            channels: reference.channels,
            interleaved: reference.interleaved.map { $0 * 0.5 }
        )
        let report = AudioGraphExportPostCheck.check(reference: reference, decoded: quieter)
        #expect(report.passed)
        #expect(abs(report.rmsDifferenceDb - 6.0206) < 0.1)
        #expect(!report.warnings.contains { $0.contains("length") })
    }

    @Test("clipping and loudness produce warnings but never block (§8.2·§8.3)")
    func warningsNeverBlock() {
        let reference = sine(amplitude: 0.1, seconds: 1)
        var clipped = reference.interleaved
        for frame in 100...103 {
            clipped[frame * 2] = 1.0
            clipped[frame * 2 + 1] = 1.0
        }
        let decoded = AudioGraphSourceAudio(
            sampleRate: reference.sampleRate, channels: reference.channels, interleaved: clipped
        )
        let report = AudioGraphExportPostCheck.check(
            reference: reference, decoded: decoded, targetLoudnessLufs: -15
        )
        // Clipping and the loudness miss are WARNINGS; the gate stays green
        // because the length matches (stage-1 policy, spec §8).
        #expect(report.passed)
        #expect(report.clippingRunCount == 1)
        #expect(report.maxClippingRunLength == 4)
        #expect(report.warnings.contains { $0.contains("clipping") })
        #expect(report.warnings.contains { $0.contains("LUFS") })
        #expect(report.withinLoudnessGuideline == false)
    }

    @Test("a loudness on-target export raises no loudness warnings")
    func onTargetLoudnessIsQuiet() {
        // The dual-channel anchor is 0 dBFS = 0 LUFS (the −3.01 anchor is
        // single-channel), so −15 dBFS dual-mono sits at −15 LUFS — inside
        // both the target band (+1/−2 LU) and the §7 guideline band.
        let tone = sine(amplitude: 0.1778) // −15 dBFS
        let report = AudioGraphExportPostCheck.check(
            reference: tone, decoded: tone, targetLoudnessLufs: -15
        )
        #expect(report.warnings.isEmpty)
        #expect(report.withinLoudnessGuideline == true)
    }

    // MARK: - Re-decode (§8: the actual encoded file)

    @Test("decode reads a real audio container back as PCM")
    func decodeRoundTrip() throws {
        let tone = sine(amplitude: 0.2, seconds: 0.5)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("g25-postcheck-roundtrip.caf")
        try? FileManager.default.removeItem(at: url)
        let format = AVAudioFormat(standardFormatWithSampleRate: tone.sampleRate, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(tone.frameCount))!
        let channelData = buffer.floatChannelData!
        for frame in 0..<tone.frameCount {
            channelData[0][frame] = tone.sample(frame: frame, channel: 0)
            channelData[1][frame] = tone.sample(frame: frame, channel: 1)
        }
        buffer.frameLength = AVAudioFrameCount(tone.frameCount)
        try file.write(from: buffer)
        defer { try? FileManager.default.removeItem(at: url) }

        let decoded = try AudioGraphExportPostCheck.decode(fileAt: url)
        #expect(decoded.channels == 2)
        #expect(abs(decoded.sampleRate - tone.sampleRate) < 0.1)
        #expect(abs(decoded.frameCount - tone.frameCount) <= 1)
        let direct = AudioGraphLoudness.measure(tone)
        let fromFile = AudioGraphLoudness.measure(decoded)
        #expect(abs((direct.integratedLufs ?? 0) - (fromFile.integratedLufs ?? 0)) < 0.05)
    }
}
