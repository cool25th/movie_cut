import Foundation
import Testing

@Suite("G-26 Master Loudness Freshness StaticContract")
struct MasterAudioLoudnessFreshnessStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("session refresh invalidates measurements across edits undo and redo")
    func refreshInvalidatesMeasurement() throws {
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
        #expect(viewModel.contains("let previousProject = currentProject"))
        #expect(viewModel.contains("masterLoudnessRevision &+= 1"))
        #expect(viewModel.contains("masterLoudness = nil"))
        #expect(viewModel.contains("masterLoudnessError = nil"))
    }

    @Test("async measurement commits only for its captured project revision")
    func asyncMeasurementHasRevisionGuard() throws {
        let audio = try source("App/MovieCutMac/EditorViewModel+Audio.swift")
        #expect(audio.contains("let measuredProject = currentProject"))
        #expect(audio.contains("let measuredRevision = masterLoudnessRevision"))
        #expect(audio.contains("measuredRevision == masterLoudnessRevision && measuredProject == currentProject"))
        #expect(audio.contains("guard isStillCurrent() else { return }"))
    }
}
