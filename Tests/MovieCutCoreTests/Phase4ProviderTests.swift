import Testing
import Foundation
@testable import MovieCutCore

@Suite("Phase 4 real provider availability")
struct Phase4ProviderTests {

    @Test("Silence detection provider is available")
    func silenceDetectionProviderIsAvailable() {
        let provider = SilenceDetectionProvider()
        #expect(provider.isAvailable == true)
    }

    @Test("Silence detection provider has correct name")
    func silenceDetectionProviderName() {
        let provider = SilenceDetectionProvider()
        #expect(provider.providerName == "SilenceDetectionProvider")
    }

    @Test("Silence detection provider uses configurable thresholds")
    func silenceDetectionProviderThresholds() {
        let provider = SilenceDetectionProvider(
            silenceThresholdDB: -30,
            minimumSilenceDuration: 1.0,
            chunkDuration: 0.2
        )
        #expect(provider.silenceThresholdDB == -30)
        #expect(provider.minimumSilenceDuration == 1.0)
        #expect(provider.chunkDuration == 0.2)
    }

    @Test("Scene change provider is available")
    func sceneChangeProviderIsAvailable() {
        let provider = SceneChangeProvider()
        #expect(provider.isAvailable == true)
    }

    @Test("Scene change provider has correct name")
    func sceneChangeProviderName() {
        let provider = SceneChangeProvider()
        #expect(provider.providerName == "SceneChangeProvider")
    }

    @Test("Scene change provider uses configurable thresholds")
    func sceneChangeProviderThresholds() {
        let provider = SceneChangeProvider(
            samplingFPS: 5.0,
            changeThreshold: 0.5
        )
        #expect(provider.samplingFPS == 5.0)
        #expect(provider.changeThreshold == 0.5)
    }

    @Test("Speech transcription provider has correct name")
    func speechTranscriptionProviderName() {
        let provider = SpeechTranscriptionProvider()
        #expect(provider.providerName == "Apple Speech")
    }

    @Test("Speech transcription provider uses custom locale")
    func speechTranscriptionProviderLocale() {
        let provider = SpeechTranscriptionProvider(locale: Locale(identifier: "ko_KR"))
        #expect(provider.locale.identifier == "ko_KR")
    }

    @Test("Analysis result includes provider name")
    func analysisResultIncludesProviderName() {
        let result = AnalysisResult(
            suggestions: [],
            sourceAssetID: "test",
            providerName: "TestProvider"
        )
        #expect(result.providerName == "TestProvider")
    }

    @Test("Analysis result defaults provider name to Unknown")
    func analysisResultDefaultProviderName() {
        let result = AnalysisResult(
            suggestions: [],
            sourceAssetID: "test"
        )
        #expect(result.providerName == "Unknown")
    }
}
