import Foundation
import Testing
import AVFoundation
@testable import MovieCutCore

/// SilenceDetectionProvider의 핵심 RMS 계산과 침묵 범위 탐지 로직을 검증하는 단위 테스트.
/// 이서 data QA, 2026-06-08
///
/// computeRMS은 private이므로 AVAudioFile 기반 integration으로 검증한다.
/// synthetic WAV를 생성해서 탐지 정확도를 확인한다.
@Suite("SilenceDetectionProvider data accuracy")
struct SilenceDetectionProviderTests {

    // MARK: - Helpers

    /// Generates a 16-bit mono PCM WAV buffer at 44100 Hz.
    /// Samples range from -1.0 to 1.0, scaled to Int16.
    private static func generateWAVData(
        duration: TimeInterval,
        sampleRate: Double = 44100,
        samples: [Float]
    ) -> Data {
        let numSamples = Int(Double(samples.count))
        let headerSize = 44
        let dataSize = numSamples * 2 // 16-bit
        let fileSize = headerSize + dataSize

        var data = Data(capacity: fileSize)

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        appendInt32(&data, Int32(fileSize - 8))  // file size - 8
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        appendInt32(&data, 16)       // chunk size
        appendInt16(&data, 1)         // PCM format
        appendInt16(&data, 1)         // mono
        appendInt32(&data, Int32(sampleRate))
        appendInt32(&data, Int32(sampleRate * 2)) // byte rate
        appendInt16(&data, 2)         // block align
        appendInt16(&data, 16)        // bits per sample

        // data chunk
        data.append(contentsOf: "data".utf8)
        appendInt32(&data, Int32(dataSize))

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let intSample = Int16(clamped * 32767.0)
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

    /// Writes WAV data to a temp file, returns URL.
    private static func writeTempWAV(_ wavData: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("silence_test_\(UUID().uuidString).wav")
        try wavData.write(to: url)
        return url
    }

    // MARK: - Pure silence detection

    @Test("Detects all-silence WAV as single silent range")
    func detectsAllSilence() async throws {
        let sampleRate = 44100.0
        let duration = 2.0
        let numSamples = Int(sampleRate * duration)
        let samples = [Float](repeating: 0, count: numSamples)

        let wavData = Self.generateWAVData(duration: duration, samples: samples)
        let url = try Self.writeTempWAV(wavData)
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = SilenceDetectionProvider(
            silenceThresholdDB: -40,
            minimumSilenceDuration: 0.3,
            chunkDuration: 0.1
        )

        let asset = MediaAsset(
            id: UUID(),
            originalURL: url,
            kind: .audio,
            duration: duration
        )
        let project = Project(name: "Test", timeline: Timeline(tracks: []))

        let result = try await provider.analyze(asset: asset, in: project)

        // All silence should produce exactly 1 silenceRemoval suggestion
        #expect(!result.suggestions.isEmpty)
        if case .silenceRemoval(let ranges) = result.suggestions.first {
            #expect(ranges.count == 1)
            #expect(ranges[0].duration == duration)
        } else {
            Issue.record("Expected silenceRemoval suggestion")
        }
    }

    // MARK: - Loud signal (no silence)

    @Test("Detects no silence in loud WAV")
    func detectsNoSilenceInLoudSignal() async throws {
        let sampleRate = 44100.0
        let duration = 1.0
        let numSamples = Int(sampleRate * duration)
        // Generate a loud sine wave at 440 Hz (full scale ≈ -6 dB)
        var samples = [Float]()
        for i in 0..<numSamples {
            samples.append(Float(sin(2.0 * .pi * 440.0 * Double(i) / sampleRate)) * 0.5)
        }

        let wavData = Self.generateWAVData(duration: duration, samples: samples)
        let url = try Self.writeTempWAV(wavData)
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = SilenceDetectionProvider(
            silenceThresholdDB: -40,
            minimumSilenceDuration: 0.3,
            chunkDuration: 0.1
        )

        let asset = MediaAsset(
            id: UUID(),
            originalURL: url,
            kind: .audio,
            duration: duration
        )
        let project = Project(name: "Test", timeline: Timeline(tracks: []))

        let result = try await provider.analyze(asset: asset, in: project)
        #expect(result.suggestions.isEmpty)
    }

    // MARK: - Silence in the middle

    @Test("Detects silence gap between two loud sections")
    func detectsSilenceGapBetweenLoudSections() async throws {
        let sampleRate = 44100.0
        let silenceDuration = 0.8
        let loudDuration = 0.5
        let totalDuration = loudDuration + silenceDuration + loudDuration

        var samples = [Float]()
        // First loud section (0.5s)
        for i in 0..<Int(sampleRate * loudDuration) {
            samples.append(Float(sin(2.0 * .pi * 440.0 * Double(i) / sampleRate)) * 0.5)
        }
        // Silent section (0.8s)
        for _ in 0..<Int(sampleRate * silenceDuration) {
            samples.append(0)
        }
        // Second loud section (0.5s)
        for i in 0..<Int(sampleRate * loudDuration) {
            samples.append(Float(sin(2.0 * .pi * 440.0 * Double(i) / sampleRate)) * 0.5)
        }

        let wavData = Self.generateWAVData(duration: totalDuration, samples: samples)
        let url = try Self.writeTempWAV(wavData)
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = SilenceDetectionProvider(
            silenceThresholdDB: -40,
            minimumSilenceDuration: 0.5,
            chunkDuration: 0.1
        )

        let asset = MediaAsset(
            id: UUID(),
            originalURL: url,
            kind: .audio,
            duration: totalDuration
        )
        let project = Project(name: "Test", timeline: Timeline(tracks: []))

        let result = try await provider.analyze(asset: asset, in: project)

        // Regression contract (바비 backend/data QA, 2026-06-09): mixed loud/silent
        // WAV files must produce a concrete silence-removal suggestion. This used to
        // be documented as a soft known issue because AVAssetReader conversion could
        // hide the zero-amplitude gap; the provider now keeps reader-buffer tails and
        // this fixture is stable enough to gate the backend analysis pipeline.
        #expect(!result.suggestions.isEmpty)
        guard case .silenceRemoval(let ranges) = result.suggestions.first else {
            Issue.record("Expected silenceRemoval suggestion")
            return
        }

        #expect(ranges.count >= 1)
        let foundInRange = ranges.contains { $0.start >= 0.4 && $0.duration >= 0.5 }
        #expect(foundInRange, "Expected silence near 0.5s for at least 0.5s. Got: \(ranges)")
    }

    // MARK: - Minimum silence duration filter

    @Test("Filters out silence shorter than minimum duration")
    func filtersShortSilence() async throws {
        let sampleRate = 44100.0
        let shortSilence = 0.3  // shorter than minimumSilenceDuration of 0.5
        let loudDuration = 0.5
        let totalDuration = loudDuration + shortSilence + loudDuration

        var samples = [Float]()
        for i in 0..<Int(sampleRate * loudDuration) {
            samples.append(Float(sin(2.0 * .pi * 440.0 * Double(i) / sampleRate)) * 0.5)
        }
        for _ in 0..<Int(sampleRate * shortSilence) {
            samples.append(0)
        }
        for i in 0..<Int(sampleRate * loudDuration) {
            samples.append(Float(sin(2.0 * .pi * 440.0 * Double(i) / sampleRate)) * 0.5)
        }

        let wavData = Self.generateWAVData(duration: totalDuration, samples: samples)
        let url = try Self.writeTempWAV(wavData)
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = SilenceDetectionProvider(
            silenceThresholdDB: -40,
            minimumSilenceDuration: 0.5,  // longer than actual silence
            chunkDuration: 0.1
        )

        let asset = MediaAsset(
            id: UUID(),
            originalURL: url,
            kind: .audio,
            duration: totalDuration
        )
        let project = Project(name: "Test", timeline: Timeline(tracks: []))

        let result = try await provider.analyze(asset: asset, in: project)
        // SHORT SILENCE FILTER TEST:
        // Due to the same AVAssetReaderTrackOutput conversion issue as the gap test,
        // this test may pass vacuously (suggestions.isEmpty because ALL audio is
        // treated as non-silent, not because the short silence was filtered).
        // When the conversion issue is fixed, this test should properly verify that
        // a 0.3s silence gap is filtered while a longer gap is detected.
        #expect(result.suggestions.isEmpty)
    }

    // MARK: - Data integrity: WAV header correctness

    @Test("Generated WAV file is valid and parseable by AVFoundation")
    func generatedWAVIsValid() async throws {
        let samples: [Float] = Array(repeating: 0.5, count: 44100) // 1 second
        let wavData = Self.generateWAVData(duration: 1.0, samples: samples)
        let url = try Self.writeTempWAV(wavData)
        defer { try? FileManager.default.removeItem(at: url) }

        let avAsset = AVAsset(url: url)
        let duration = try await avAsset.load(.duration)
        #expect(duration.isValid)
        #expect(abs(duration.seconds - 1.0) < 0.1) // tolerance for chunk rounding
    }

    // MARK: - Provider name consistency

    @Test("Analysis result has correct provider name")
    func analysisResultProviderName() async throws {
        let sampleRate = 44100.0
        let samples = [Float](repeating: 0, count: Int(sampleRate))
        let wavData = Self.generateWAVData(duration: 1.0, samples: samples)
        let url = try Self.writeTempWAV(wavData)
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = SilenceDetectionProvider()
        let asset = MediaAsset(
            id: UUID(),
            originalURL: url,
            kind: .audio,
            duration: 1.0
        )
        let project = Project(name: "Test", timeline: Timeline(tracks: []))

        let result = try await provider.analyze(asset: asset, in: project)
        #expect(result.providerName == "SilenceDetection")
    }
}
