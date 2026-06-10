import Foundation
import Testing
import AVFoundation
@testable import MovieCutCore

/// WaveformGenerator의 AVAssetReader 기반 bin 계산 정확성과 edge case 동작을 검증하는 단위 테스트.
/// 이서 data QA, 2026-06-08
///
/// WaveformGenerator.generate(for:)는 private static method로 MediaAsset을 필요로 하므로
/// synthetic WAV 파일 + MediaAsset을 조합해 integration으로 검증한다.
@Suite("WaveformGenerator data accuracy")
struct WaveformGeneratorTests {

    // MARK: - Helpers

    /// Generates a 16-bit mono PCM WAV buffer at given sampleRate.
    private static func generateWAVData(
        sampleRate: Double = 44100,
        samples: [Float]
    ) -> Data {
        let numSamples = samples.count
        let headerSize = 44
        let dataSize = numSamples * 2
        let fileSize = headerSize + dataSize

        var data = Data(capacity: fileSize)

        data.append(contentsOf: "RIFF".utf8)
        appendInt32(&data, Int32(fileSize - 8))
        data.append(contentsOf: "WAVE".utf8)

        data.append(contentsOf: "fmt ".utf8)
        appendInt32(&data, 16)
        appendInt16(&data, 1)         // PCM
        appendInt16(&data, 1)         // mono
        appendInt32(&data, Int32(sampleRate))
        appendInt32(&data, Int32(sampleRate * 2))
        appendInt16(&data, 2)
        appendInt16(&data, 16)

        data.append(contentsOf: "data".utf8)
        appendInt32(&data, Int32(dataSize))

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let intSample = Int16(clamped * Float(Int16.max))
            appendInt16(&data, intSample)
        }

        return data
    }

    private static func appendInt16(_ data: inout Data, _ value: Int16) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 2))
    }

    private static func appendInt32(_ data: inout Data, _ value: Int32) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 4))
    }

    private static func writeTempWAV(_ wavData: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("waveform_test_\(UUID().uuidString).wav")
        try wavData.write(to: url)
        return url
    }

    // MARK: - Silence waveform

    @Test("All-silence WAV produces bins near zero")
    func allSilenceProducesNearZeroBins() async throws {
        let sampleRate = 44100.0
        // 0.5 seconds of silence = 22050 samples
        let samples = [Float](repeating: 0, count: 22050)
        let wavData = Self.generateWAVData(sampleRate: sampleRate, samples: samples)
        let url = try Self.writeTempWAV(wavData)
        defer { try? FileManager.default.removeItem(at: url) }

        let asset = MediaAsset(originalURL: url, kind: .audio, duration: 0.5)
        let waveform = WaveformGenerator.generate(for: asset)

        #expect(waveform != nil)
        guard let waveform else { return }

        #expect(waveform.sampleCount > 0)
        // All bins should be exactly 0 for silence
        for (i, bin) in waveform.samples.enumerated() {
            #expect(bin == 0.0, "Bin \(i) should be 0 for silence, got \(bin)")
        }
    }

    // MARK: - Full amplitude waveform

    @Test("Max amplitude WAV produces bins near 1.0")
    func maxAmplitudeProducesNearOneBins() async throws {
        let sampleRate = 44100.0
        // 0.25 seconds of max amplitude sine-like samples
        let numSamples = Int(sampleRate * 0.25)
        var samples = [Float](repeating: 0, count: numSamples)
        for i in 0..<numSamples {
            samples[i] = Float.random(in: 0.7...1.0)  // high amplitude
        }

        let wavData = Self.generateWAVData(sampleRate: sampleRate, samples: samples)
        let url = try Self.writeTempWAV(wavData)
        defer { try? FileManager.default.removeItem(at: url) }

        let asset = MediaAsset(originalURL: url, kind: .audio, duration: 0.25)
        let waveform = WaveformGenerator.generate(for: asset)

        #expect(waveform != nil)
        guard let waveform else { return }

        #expect(waveform.sampleCount == numSamples)
        #expect(waveform.samples.count == 200)

        // All bins should be > 0.5 since all samples are high amplitude
        for (i, bin) in waveform.samples.enumerated() {
            #expect(bin > 0.5, "Bin \(i) should be high amplitude, got \(bin)")
        }
    }

    // MARK: - Pattern waveform (silence-loud-silence)

    @Test("Silence-loud-silence pattern reflects in waveform bins")
    func silenceLoudSilencePattern() async throws {
        let sampleRate = 44100.0
        // 0.3s silence + 0.3s loud + 0.3s silence = 39690 total samples
        let chunkSamples = Int(sampleRate * 0.3)
        var allSamples = [Float](repeating: 0, count: chunkSamples)
        allSamples.append(contentsOf: [Float](repeating: 1.0, count: chunkSamples))
        allSamples.append(contentsOf: [Float](repeating: 0, count: chunkSamples))

        let wavData = Self.generateWAVData(sampleRate: sampleRate, samples: allSamples)
        let url = try Self.writeTempWAV(wavData)
        defer { try? FileManager.default.removeItem(at: url) }

        let asset = MediaAsset(originalURL: url, kind: .audio, duration: 0.9)
        let waveform = WaveformGenerator.generate(for: asset)

        #expect(waveform != nil)
        guard let waveform else { return }

        // Bins in the middle third should be near 1.0
        let thirdStart = 200 / 3
        let thirdEnd = 2 * 200 / 3

        var hasLoudMiddle = false
        for i in thirdStart..<thirdEnd {
            if waveform.samples[i] > 0.5 {
                hasLoudMiddle = true
                break
            }
        }
        #expect(hasLoudMiddle, "Middle bins should show loud amplitude")

        // First and last few bins should be 0
        for i in 0..<10 {
            #expect(waveform.samples[i] == 0.0, "Early bin \(i) should be silence")
        }
    }

    // MARK: - Very short waveform

    @Test("Very short WAV (100 samples) still produces valid waveform")
    func veryShortWAV() async throws {
        let sampleRate = 44100.0
        let samples = [Float](repeating: 0.5, count: 100)
        let wavData = Self.generateWAVData(sampleRate: sampleRate, samples: samples)
        let url = try Self.writeTempWAV(wavData)
        defer { try? FileManager.default.removeItem(at: url) }

        let asset = MediaAsset(originalURL: url, kind: .audio)
        let waveform = WaveformGenerator.generate(for: asset)

        #expect(waveform != nil)
        guard let waveform else { return }

        #expect(waveform.sampleCount == 100)
        #expect(waveform.samples.count == 200)
        // All 100 samples fit in the first bin (100 * 200 / 100 = 200), so only bin 0 should be non-zero
        #expect(waveform.samples[0] > 0, "First bin should capture the samples")
    }

    // MARK: - Non-existent file

    @Test("Returns nil for non-existent file")
    func nonExistentFile() {
        let asset = MediaAsset(
            originalURL: URL(fileURLWithPath: "/tmp/nonexistent_waveform_\(UUID().uuidString).wav"),
            kind: .audio
        )
        let waveform = WaveformGenerator.generate(for: asset)
        #expect(waveform == nil)
    }

    // MARK: - WaveformData Codable round-trip

    @Test("WaveformData round-trips through Codable")
    func waveformDataCodableRoundTrip() throws {
        let original = WaveformData(
            samples: [0.0, 0.25, 0.5, 0.75, 1.0, 0.0, 0.1, 0.2],
            sampleCount: 44100
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WaveformData.self, from: encoded)
        #expect(decoded == original)
        #expect(decoded.samples.count == 8)
        #expect(decoded.sampleCount == 44100)
    }

    // MARK: - WaveformData equality

    @Test("WaveformData equality compares all fields")
    func waveformDataEquality() {
        let a = WaveformData(samples: [0.5, 0.75], sampleCount: 100)
        let b = WaveformData(samples: [0.5, 0.75], sampleCount: 100)
        let c = WaveformData(samples: [0.5, 0.74], sampleCount: 100)  // different sample
        let d = WaveformData(samples: [0.5, 0.75], sampleCount: 99)   // different count

        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
    }

    // MARK: - Bin count consistency

    @Test("Always produces exactly 200 bins")
    func alwaysProduces200Bins() async throws {
        // Various durations should all produce 200 bins
        for durationSecs: Double in [0.01, 0.1, 0.5, 2.0] {
            let sampleCount = Int(44100.0 * durationSecs)
            let samples = [Float](repeating: 0.3, count: sampleCount)
            let wavData = Self.generateWAVData(samples: samples)
            let url = try Self.writeTempWAV(wavData)
            defer { try? FileManager.default.removeItem(at: url) }

            let asset = MediaAsset(originalURL: url, kind: .audio, duration: durationSecs)
            let waveform = WaveformGenerator.generate(for: asset)

            #expect(waveform != nil, "Failed for duration \(durationSecs)s")
            #expect(waveform?.samples.count == 200, "Expected 200 bins for duration \(durationSecs)s, got \(waveform?.samples.count ?? -1)")
        }
    }
}
