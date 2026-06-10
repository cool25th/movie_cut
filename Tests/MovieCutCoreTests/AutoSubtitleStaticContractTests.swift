import Foundation
import Testing
@testable import MovieCutCore

/// The macOS app target is built by xcodebuild. These checks keep the P0
/// auto-subtitle/STT wiring visible in SwiftPM's faster core test loop.
@Suite("Auto Subtitle Static Contract")
struct AutoSubtitleStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw StaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw StaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("UI subtitle generation aligns pending clips to the selected timeline clip")
    func uiSubtitleGenerationAlignsPendingClips() throws {
        let source = try source("App/MovieCutMac/EditorViewModel.swift")
        let body = try section(
            in: source,
            from: "func prepareSubtitles() async",
            to: "func applyGeneratedSubtitles() async"
        )

        #expect(body.contains("selectedSubtitleSource(in: snapshot)"))
        #expect(body.contains("subtitleClips(from: result, alignedTo: clip)"))
        #expect(body.contains("pendingSubtitleClips = subtitleClips"))
        #expect(body.contains("transcriptionService.subtitles(from: result, in: snapshot)"))
        #expect(body.contains("starting at 00:00 because no timeline clip is selected"))
    }

    @Test("clip quick action uses the selected transcription service provider")
    func clipQuickActionUsesSelectedProvider() throws {
        let source = try source("App/MovieCutMac/EditorViewModel.swift")
        let body = try section(
            in: source,
            from: "func prepareSubtitles(for clipId: UUID) async throws",
            to: "func prepareSubtitles() async"
        )

        #expect(body.contains("transcriptionService.currentProvider.providerName"))
        #expect(body.contains("transcriptionService.transcribe(asset: asset)"))
        #expect(!body.contains("SpeechTranscriptionProvider()"))
    }

    @Test("Speech provider exports video audio as supported M4A instead of passthrough wav")
    func speechProviderUsesM4AExtraction() throws {
        let source = try source("Sources/MovieCutCore/Transcription/SpeechTranscriptionProvider.swift")

        #expect(source.contains("AVAssetExportPresetAppleM4A"))
        #expect(source.contains("supportedFileTypes.contains(.m4a)"))
        #expect(source.contains("outputFileType = .m4a"))
        #expect(!source.contains("AVAssetExportPresetPassthrough"))
        #expect(!source.contains("outputFileType = .wav"))
    }

    @Test("AutoSubtitlesView keeps preview, apply, and progress controls")
    func autoSubtitlesViewKeepsGenerateApplyAndProgress() throws {
        let source = try source("App/MovieCutMac/Transcription/AutoSubtitlesView.swift")

        #expect(source.contains("Button(\"Generate Subtitles\")"))
        #expect(source.contains("Task { await viewModel.prepareSubtitles() }"))
        #expect(source.contains("ProgressView(value: viewModel.transcriptionService.progress)"))
        #expect(source.contains("Button(\"Apply to Timeline\")"))
        #expect(source.contains("Task { await viewModel.applyGeneratedSubtitles() }"))
    }

    @Test("transcription errors expose useful localized descriptions")
    func transcriptionErrorsHaveLocalizedDescriptions() {
        let error = TranscriptionError.transcriptionFailed("Speech recognition permission is denied.")

        #expect(error.localizedDescription == "Speech recognition permission is denied.")
        #expect(TranscriptionError.assetNotReady.localizedDescription.contains("audio or video"))
        #expect(TranscriptionError.notSupported.localizedDescription.contains("unavailable"))
    }
}

private enum StaticContractError: Error {
    case missingMarker(String)
}
