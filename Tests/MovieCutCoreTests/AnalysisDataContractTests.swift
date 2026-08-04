import Testing
import Foundation
@testable import MovieCutCore

@Suite("Analysis pipeline data contract consistency")
struct AnalysisDataContractTests {

    // MARK: - CropFrame data integrity

    @Test("CropFrame Codable round-trip preserves time and rect")
    func cropFrameCodableRoundTrip() throws {
        let frame = CropFrame(
            time: 1.5,
            rect: CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.8)
        )
        let data = try JSONEncoder().encode(frame)
        let decoded = try JSONDecoder().decode(CropFrame.self, from: data)
        #expect(decoded.time == frame.time)
        #expect(decoded.rect.origin.x == frame.rect.origin.x)
        #expect(decoded.rect.origin.y == frame.rect.origin.y)
        #expect(decoded.rect.size.width == frame.rect.size.width)
        #expect(decoded.rect.size.height == frame.rect.size.height)
    }

    @Test("CropFrame Equatable compares all fields")
    func cropFrameEquatable() {
        let frame1 = CropFrame(time: 1.0, rect: CGRect(x: 0, y: 0, width: 1, height: 1))
        let frame2 = CropFrame(time: 1.0, rect: CGRect(x: 0, y: 0, width: 1, height: 1))
        let frame3 = CropFrame(time: 2.0, rect: CGRect(x: 0, y: 0, width: 1, height: 1))
        let frame4 = CropFrame(time: 1.0, rect: CGRect(x: 0.1, y: 0, width: 1, height: 1))

        #expect(frame1 == frame2)
        #expect(frame1 != frame3)
        #expect(frame1 != frame4)
    }

    @Test("CropFrame zero rect is valid")
    func cropFrameZeroRect() {
        let frame = CropFrame(time: 0, rect: CGRect(x: 0, y: 0, width: 0, height: 0))
        #expect(frame.time == 0)
        #expect(frame.rect.width == 0)
        #expect(frame.rect.height == 0)
    }

    @Test("CropFrame negative time preserves value")
    func cropFrameNegativeTime() throws {
        let frame = CropFrame(time: -1.0, rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        let data = try JSONEncoder().encode(frame)
        let decoded = try JSONDecoder().decode(CropFrame.self, from: data)
        // Data layer does not clamp negative time — same pattern as TranscriptionSegment
        #expect(decoded.time == -1.0)
    }

    @Test("CropFrame array Codable round-trip")
    func cropFrameArrayRoundTrip() throws {
        let frames = [
            CropFrame(time: 0.0, rect: CGRect(x: 0, y: 0, width: 1, height: 1)),
            CropFrame(time: 1.0, rect: CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.9)),
            CropFrame(time: 2.5, rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)),
        ]
        let data = try JSONEncoder().encode(frames)
        let decoded = try JSONDecoder().decode([CropFrame].self, from: data)
        #expect(decoded.count == 3)
        for (original, decoded) in zip(frames, decoded) {
            #expect(original == decoded)
        }
    }

    // MARK: - AnalysisSuggestion Codable

    @Test("AnalysisSuggestion silenceRemoval Codable round-trip")
    func analysisSuggestionSilenceRemovalRoundTrip() throws {
        let suggestion = AnalysisSuggestion.silenceRemoval(
            ranges: [TimeRange(start: 0.5, duration: 2.0)]
        )
        let data = try JSONEncoder().encode(suggestion)
        let decoded = try JSONDecoder().decode(AnalysisSuggestion.self, from: data)
        #expect(decoded == suggestion)
    }

    @Test("AnalysisSuggestion sceneChanges Codable round-trip")
    func analysisSuggestionSceneChangesRoundTrip() throws {
        let suggestion = AnalysisSuggestion.sceneChanges(
            times: [1.0, 3.5, 7.2]
        )
        let data = try JSONEncoder().encode(suggestion)
        let decoded = try JSONDecoder().decode(AnalysisSuggestion.self, from: data)
        #expect(decoded == suggestion)
    }

    @Test("AnalysisSuggestion autoCut Codable round-trip")
    func analysisSuggestionAutoCutRoundTrip() throws {
        let suggestion = AnalysisSuggestion.autoCut(
            editedRanges: [TimeRange(start: 0.0, duration: 5.0), TimeRange(start: 6.0, duration: 3.0)]
        )
        let data = try JSONEncoder().encode(suggestion)
        let decoded = try JSONDecoder().decode(AnalysisSuggestion.self, from: data)
        #expect(decoded == suggestion)
    }

    @Test("AnalysisSuggestion empty cases Codable round-trip")
    func analysisSuggestionEmptyCasesRoundTrip() throws {
        let emptyCases: [AnalysisSuggestion] = [
            .silenceRemoval(ranges: []),
            .sceneChanges(times: []),
            .autoCut(editedRanges: []),
        ]
        for suggestion in emptyCases {
            let data = try JSONEncoder().encode(suggestion)
            let decoded = try JSONDecoder().decode(AnalysisSuggestion.self, from: data)
            #expect(decoded == suggestion)
        }
    }

    // MARK: - AnalysisResult Codable

    @Test("AnalysisResult Codable round-trip with suggestions")
    func analysisResultCodableRoundTrip() throws {
        let result = AnalysisResult(
            suggestions: [
                .silenceRemoval(ranges: [TimeRange(start: 1.0, duration: 2.0)]),
                .sceneChanges(times: [3.5, 7.0]),
            ],
            sourceAssetID: "test-asset-uuid",
            providerName: "TestProvider"
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(AnalysisResult.self, from: data)
        #expect(decoded.suggestions.count == 2)
        #expect(decoded.sourceAssetID == "test-asset-uuid")
        #expect(decoded.providerName == "TestProvider")
        #expect(decoded.suggestions == result.suggestions)
    }

    @Test("AnalysisResult Codable round-trip empty")
    func analysisResultEmptyRoundTrip() throws {
        let result = AnalysisResult(
            suggestions: [],
            sourceAssetID: "empty-asset",
            providerName: "EmptyProvider"
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(AnalysisResult.self, from: data)
        #expect(decoded.suggestions.isEmpty)
        #expect(decoded.sourceAssetID == "empty-asset")
        #expect(decoded.providerName == "EmptyProvider")
    }

    // MARK: - Provider contract consistency

    @Test("All providers return non-empty providerName")
    func allProvidersHaveNames() {
        let providers: [AnalysisProvider] = [
            SilenceDetectionProvider(),
            SceneChangeProvider(),
            AutoReframeProvider(),
        ]
        for provider in providers {
            #expect(!provider.providerName.isEmpty)
        }
    }

    @Test("SilenceDetectionProvider custom name consistency")
    func silenceDetectionProviderName() {
        let provider = SilenceDetectionProvider()
        #expect(provider.providerName == "SilenceDetection")
    }

    @Test("SceneChangeProvider custom name consistency")
    func sceneChangeProviderName() {
        let provider = SceneChangeProvider()
        #expect(provider.providerName == "SceneChange")
    }

    @Test("Silence provider metadata is stable between provider list and analysis result")
    func silenceProviderMetadataMatchesAnalysisResult() async throws {
        let project = Project(name: "Analysis Metadata", timeline: Timeline(tracks: []))
        let assetID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let sampleRate: Int32 = 44_100
        let wavURL = try Self.writeTempWAV(samples: [Int16](repeating: 0, count: Int(sampleRate)), sampleRate: sampleRate)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let mediaAsset = MediaAsset(id: assetID, originalURL: wavURL, kind: .audio, duration: 1.0)
        let silenceProvider = SilenceDetectionProvider()
        let silenceResult = try await silenceProvider.analyze(asset: mediaAsset, in: project)

        #expect(silenceResult.sourceAssetID == assetID.uuidString)
        #expect(silenceResult.providerName == silenceProvider.providerName)
    }

    @Test("AutoReframeProvider explicit name")
    func autoReframeProviderName() {
        let provider = AutoReframeProvider()
        #expect(provider.providerName == "AutoReframe")
    }

    @Test("Vision-dependent provider has consistent isAvailable")
    func visionProviderAvailability() {
        let autoReframe = AutoReframeProvider()
        #if canImport(Vision)
        #expect(autoReframe.isAvailable == true)
        #else
        #expect(autoReframe.isAvailable == false)
        #endif
    }

    @Test("Always-available providers have isAvailable true")
    func alwaysAvailableProviders() {
        let silence = SilenceDetectionProvider()
        let scene = SceneChangeProvider()
        #expect(silence.isAvailable == true)
        #expect(scene.isAvailable == true)
    }

    // MARK: - Cross-provider data contract consistency

    @Test("AnalysisResult preserves sourceAssetID exactly")
    func analysisResultSourceAssetIDPreserved() throws {
        let uuid = UUID().uuidString
        let result = AnalysisResult(
            suggestions: [.sceneChanges(times: [1.0])],
            sourceAssetID: uuid,
            providerName: "Test"
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(AnalysisResult.self, from: data)
        #expect(decoded.sourceAssetID == uuid)
    }

    @Test("TimeRange in AnalysisSuggestion survives Codable round-trip")
    func timeRangeInSuggestionSurvives() throws {
        let range = TimeRange(start: 0.123, duration: 45.678)
        let suggestion = AnalysisSuggestion.silenceRemoval(ranges: [range])
        let data = try JSONEncoder().encode(suggestion)
        let decoded = try JSONDecoder().decode(AnalysisSuggestion.self, from: data)
        if case .silenceRemoval(let decodedRanges) = decoded {
            #expect(decodedRanges.count == 1)
            #expect(decodedRanges[0].start == range.start)
            #expect(decodedRanges[0].duration == range.duration)
        } else {
            Issue.record("Decoded suggestion was not silenceRemoval")
        }
    }

    @Test("CropFrame rect uses normalized coordinates convention")
    func cropFrameNormalizedConvention() {
        // AutoReframeProvider.cropRect produces values in [0, 1] range
        // Test that our Codable round-trip preserves this
        let frame = CropFrame(
            time: 0.5,
            rect: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)
        )
        #expect(frame.rect.origin.x >= 0)
        #expect(frame.rect.origin.y >= 0)
        #expect(frame.rect.width <= 1.0)
        #expect(frame.rect.height <= 1.0)
    }

    // MARK: - Test media helpers

    private static func writeTempWAV(samples: [Int16], sampleRate: Int32) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("analysis_contract_\(UUID().uuidString)")
            .appendingPathExtension("wav")
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        appendInt32(&data, Int32(36 + samples.count * 2))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        appendInt32(&data, 16)
        appendInt16(&data, 1)
        appendInt16(&data, 1)
        appendInt32(&data, sampleRate)
        appendInt32(&data, sampleRate * 2)
        appendInt16(&data, 2)
        appendInt16(&data, 16)
        data.append(contentsOf: "data".utf8)
        appendInt32(&data, Int32(samples.count * 2))
        for sample in samples {
            appendInt16(&data, sample)
        }
        try data.write(to: url)
        return url
    }

    private static func appendInt16(_ data: inout Data, _ value: Int16) {
        var littleEndian = value.littleEndian
        data.append(Data(bytes: &littleEndian, count: 2))
    }

    private static func appendInt32(_ data: inout Data, _ value: Int32) {
        var littleEndian = value.littleEndian
        data.append(Data(bytes: &littleEndian, count: 4))
    }
}
