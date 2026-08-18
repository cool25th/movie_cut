import AVFoundation
import Foundation
import Testing
@testable import MovieCutCore

/// G-25 spec §3.1 — the engine-adapter source normalization, exercised on
/// the REAL committed fixtures: a 44.1 kHz mono wav, an mp4 WITH embedded
/// audio (AVAssetReader path), an audio-less mp4 (explicit silence), rate
/// conversion, and pitch-preserving speed pre-render.
@Suite("AudioGraphSourceAdapter (§3.1)")
struct AudioGraphSourceAdapterTests {
    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
    }

    /// Positive-going zero crossings per second — a cheap dominant-frequency
    /// estimate for the sine fixtures (220 Hz BGM), good to a few Hz.
    private func dominantFrequencyHz(_ audio: AudioGraphSourceAudio) -> Double {
        guard audio.frameCount > 1 else { return 0 }
        var crossings = 0
        for frame in 1..<audio.frameCount
        where audio.sample(frame: frame - 1, channel: 0) <= 0
            && audio.sample(frame: frame, channel: 0) > 0 {
            crossings += 1
        }
        return Double(crossings) / (Double(audio.frameCount) / audio.sampleRate)
    }

    private func rms(_ audio: AudioGraphSourceAudio) -> Double {
        guard audio.interleaved.isEmpty == false else { return 0 }
        let energy = audio.interleaved.reduce(0) { $0 + Double($1) * Double($1) }
        return sqrt(energy / Double(audio.interleaved.count))
    }

    // MARK: - Decode

    @Test("audio-only containers decode via AVAudioFile at their native rate")
    func decodeWav() async throws {
        let audio = try await AudioGraphSourceAdapter.decode(fileAt: fixture("duck_bgm_220hz_4s_mono.wav"))
        #expect(audio.sampleRate == 44_100)
        #expect(audio.channels == 1)
        #expect(audio.frameCount == 176_400) // 4 s × 44.1 kHz
        #expect(rms(audio) > 0.05)
    }

    @Test("video containers decode their embedded audio via AVAssetReader")
    func decodeVideoWithEmbeddedAudio() async throws {
        let audio = try await AudioGraphSourceAdapter.decode(
            fileAt: fixture("solid_red_tone_320x240_2s_30fps.mp4")
        )
        #expect(audio.sampleRate == 44_100)
        // 2 s × 44.1 kHz = 88,200 valid frames (±AAC priming/padding).
        #expect(audio.frameCount > 87_000 && audio.frameCount < 89_500)
        #expect(rms(audio) > 0.02)
    }

    @Test("audio-less video decodes to an explicit silent source (§3.1)")
    func decodeAudiolessVideo() async throws {
        let audio = try await AudioGraphSourceAdapter.decode(
            fileAt: fixture("solid_red_320x240_2s_30fps.mp4")
        )
        #expect(audio.frameCount <= 1)
        #expect(rms(audio) == 0)
    }

    // MARK: - Resample

    @Test("resample 44.1k → 48k converts length exactly and keeps the tone")
    func resampleToGraphRate() async throws {
        let wav = try await AudioGraphSourceAdapter.decode(fileAt: fixture("duck_bgm_220hz_4s_mono.wav"))
        let resampled = try AudioGraphSourceAdapter.resample(wav, to: 48_000)
        #expect(resampled.sampleRate == 48_000)
        #expect(resampled.channels == wav.channels)
        // 176,400 × 48/44.1 = 192,000 (small filter-tail tolerance).
        #expect(abs(resampled.frameCount - 192_000) < 128)
        let frequency = dominantFrequencyHz(resampled)
        #expect(frequency > 212 && frequency < 228, "dominant frequency drifted: \(frequency) Hz")
    }

    @Test("resample is the identity at the target rate")
    func resampleIdentity() async throws {
        let wav = try await AudioGraphSourceAdapter.decode(fileAt: fixture("duck_bgm_220hz_4s_mono.wav"))
        let same = try AudioGraphSourceAdapter.resample(wav, to: 44_100)
        #expect(same == wav)
    }

    // MARK: - Speed pre-render

    @Test("timeStretched halves duration at 2×, preserves pitch, renders mono as dual-mono stereo")
    func timeStretchSpeed2() async throws {
        let wav = try await AudioGraphSourceAdapter.decode(fileAt: fixture("duck_bgm_220hz_4s_mono.wav"))
        let stretched = try AudioGraphSourceAdapter.timeStretched(wav, speed: 2)
        #expect(stretched.sampleRate == 44_100)
        // The offline engine's mono path attenuates by 1/√2 (measured), so
        // mono renders as dual-mono stereo — unity amplitude, L == R.
        #expect(stretched.channels == 2)
        #expect(stretched.sample(frame: 1_000, channel: 0) == stretched.sample(frame: 1_000, channel: 1))
        // 4 s at 2× → ~88,200 frames (window/ringing-tail tolerance).
        #expect(abs(stretched.frameCount - 88_200) < 4_000)
        let frequency = dominantFrequencyHz(stretched)
        #expect(frequency > 212 && frequency < 228, "pitch not preserved: \(frequency) Hz")
        #expect(rms(stretched) > 0.045)
    }

    @Test("the full §3.1 pipeline yields graph-rate speed-1 audio")
    func normalizedAudioPipeline() async throws {
        let normalized = try await AudioGraphSourceAdapter.normalizedAudio(
            fileAt: fixture("duck_bgm_220hz_4s_mono.wav"),
            graphSampleRate: 48_000
        )
        #expect(normalized.sampleRate == 48_000)
        #expect(abs(normalized.frameCount - 192_000) < 128)
        #expect(dominantFrequencyHz(normalized) > 212 && dominantFrequencyHz(normalized) < 228)
    }
}
