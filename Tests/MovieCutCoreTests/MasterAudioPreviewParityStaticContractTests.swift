import Foundation
import Testing

@Suite("G-26 Master Audio Preview Parity StaticContract")
struct MasterAudioPreviewParityStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("master-enabled preview installs the graph mix as one audio track")
    func masterEnabledPreviewUsesGraphMix() throws {
        let playback = try source("App/MovieCutMac/Playback/PlaybackEngine.swift")

        #expect(playback.contains("let usesGraphMasterAudio = project.masterAudioProcessing != nil"))
        #expect(playback.contains("let graphAudioURL = try await renderGraphPreviewAudio"))
        #expect(playback.contains("GraphMixRenderer.renderMix("))
        #expect(playback.contains("tracks: tracks"))
        #expect(playback.contains("MovieCutGraphPreview-"))
        #expect(playback.contains("try previewAudioTrack.insertTimeRange(trackRange, of: graphAudioTrack, at: .zero)"))
    }

    @Test("master-enabled preview suppresses legacy audio while Off retains it")
    func masterGateSeparatesGraphAndLegacyPaths() throws {
        let playback = try source("App/MovieCutMac/Playback/PlaybackEngine.swift")

        #expect(playback.contains("if usesGraphMasterAudio || track.isMuted || (anyTrackSoloed && !track.isSolo)"))
        #expect(playback.contains("guard !usesGraphMasterAudio else { continue }"))
        #expect(playback.contains("applyAudioVolumeAndFades("))
        #expect(playback.contains("let mutableAudioMix = AVMutableAudioMix()"))
    }

    @Test("stale composition build releases graph preview temporary media")
    func staleBuildReleasesTemporaryAudio() throws {
        let playback = try source("App/MovieCutMac/Playback/PlaybackEngine.swift")
        #expect(playback.contains("guard requestedGeneration == compositionGeneration else {"))
        #expect(playback.contains("removeTemporaryReverseRenderURLs(temporaryReverseRenderURLs)"))
    }
}
