import Foundation
import Testing

@Suite("G-26 Master Audio Inspector StaticContract")
struct MasterAudioInspectorStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw MasterAudioInspectorStaticContractError.missingMarker(start)
        }
        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw MasterAudioInspectorStaticContractError.missingMarker(end)
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("audio master exposes off and SNS preset through an accessible segmented picker")
    func audioMasterExposesPresetPicker() throws {
        let panel = try source("App/MovieCutMac/InspectorPanel.swift")
        let master = try section(
            in: panel,
            from: "private struct MasterLoudnessSection",
            to: "private struct ProjectOverviewInspectorView"
        )

        #expect(master.contains("Text(NSLocalizedString(\"Master Processing\", comment: \"\"))"))
        #expect(master.contains("Picker(\"Master processing\", selection: masterProcessingBinding)"))
        #expect(master.contains("Text(NSLocalizedString(\"Off\", comment: \"\")).tag(nil as MasterAudioProcessing?)"))
        #expect(master.contains("Text(\"SNS 좋은 소리\").tag(MasterAudioProcessing.sns as MasterAudioProcessing?)"))
        #expect(master.contains(".pickerStyle(.segmented)"))
        #expect(master.contains(".accessibilityLabel(Text(NSLocalizedString(\"Master audio processing\", comment: \"\")))"))
        #expect(master.contains("viewModel.setMasterAudioProcessing(processing)"))
        #expect(!master.contains("Task { await viewModel.setMasterAudioProcessing(processing) }"))
        // sourceLanguage=en: user-facing G-26 chrome must use English keys
        // (the picker's preset NAME stays a locale-invariant literal).
        #expect(master.contains("NSLocalizedString(\"SNS guideline: −16…−14 LUFS-I, ≤ −1 dBTP (§7)\", comment: \"\")"))
    }

    @Test("preset changes enqueue synchronously and one worker coalesces rapid selections")
    func viewModelSerializesPresetMutations() throws {
        let audio = try source("App/MovieCutMac/EditorViewModel+Audio.swift")
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
        let setterAndWorker = try section(
            in: audio,
            from: "func setMasterAudioProcessing",
            to: "    /// G-25 switchover step 2B"
        )

        #expect(setterAndWorker.contains("desiredMasterAudioProcessing = processing"))
        #expect(setterAndWorker.contains("masterAudioProcessingMutationGeneration &+= 1"))
        #expect(setterAndWorker.contains("guard masterAudioProcessingMutationTask == nil else { return }"))
        #expect(setterAndWorker.contains("await self?.drainMasterAudioProcessingMutations()"))
        #expect(setterAndWorker.contains("await apply(SetMasterAudioProcessingCommand(processing: processing))"))
        #expect(setterAndWorker.contains("guard requestGeneration == masterAudioProcessingMutationGeneration else"))
        #expect(!setterAndWorker.contains("guard previous != processing"))

        #expect(viewModel.contains("resetMasterAudioProcessingMutationContext(to: project.masterAudioProcessing)"))
    }
}

private enum MasterAudioInspectorStaticContractError: Error {
    case missingMarker(String)
}
