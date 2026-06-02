import Foundation
import MovieCutCore
import Observation

@MainActor
@Observable
final class TranscriptionService {
    var isTranscribing = false
    var progress: Double = 0
    var currentProvider: any TranscriptionProvider
    var availableProviders: [any TranscriptionProvider]

    init() {
        let stubProvider = StubTranscriptionProvider()
        let speechProvider = SpeechTranscriptionProvider()
        self.availableProviders = [speechProvider, stubProvider]
        self.currentProvider = speechProvider
    }

    func transcribe(asset: MediaAsset) async throws -> TranscriptionResult {
        guard asset.kind == .audio || asset.kind == .video else {
            throw TranscriptionError.assetNotReady
        }

        isTranscribing = true
        progress = 0
        defer {
            isTranscribing = false
            progress = 1
        }

        return try await currentProvider.transcribe(audioURL: asset.originalURL, language: nil)
    }

    func subtitles(from result: TranscriptionResult, in project: Project) -> [Clip] {
        let trackId = project.timeline.tracks.first { $0.kind == .text }?.id ?? UUID()
        return SubtitleGenerator.generateClips(from: result, trackId: trackId)
    }
}
