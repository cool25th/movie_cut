import Foundation
import Testing

@Suite("G-26 Master Loudness Freshness StaticContract")
struct MasterAudioLoudnessFreshnessStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("every committed session refresh invalidates regardless of Project equality")
    func committedRefreshAlwaysAdvancesGeneration() throws {
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")

        #expect(viewModel.contains(
            "currentProject = await session.snapshot()\n        invalidateMasterLoudnessContext()"
        ))
        #expect(!viewModel.contains("if currentProject != previousProject"))
        #expect(viewModel.contains("masterLoudnessRevision &+= 1"))
        #expect(viewModel.contains("masterLoudness = nil"))
        #expect(viewModel.contains("masterLoudnessError = nil"))
    }

    @Test("all five project session replacement paths advance the meter generation")
    func projectReplacementAdvancesGeneration() throws {
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
        let occurrences = viewModel.components(separatedBy: "invalidateMasterLoudnessContext()").count - 1

        // One declaration + one committed refresh call + five fresh-session
        // replacement calls. The count intentionally makes new replacement
        // paths fail this contract until they join the same generation boundary.
        #expect(occurrences == 7)
    }

    @Test("async measurement commits only for its captured project generation")
    func asyncMeasurementHasRevisionGuard() throws {
        let audio = try source("App/MovieCutMac/EditorViewModel+Audio.swift")
        #expect(audio.contains("let measuredProject = currentProject"))
        #expect(audio.contains("let measuredRevision = masterLoudnessRevision"))
        #expect(audio.contains("measuredRevision == masterLoudnessRevision && measuredProject == currentProject"))
        #expect(audio.contains("guard isStillCurrent() else { return }"))
    }
}
