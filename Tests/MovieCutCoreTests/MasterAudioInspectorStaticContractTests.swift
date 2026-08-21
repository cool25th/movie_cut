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

        #expect(master.contains("Text(\"Master Processing\")"))
        #expect(master.contains("Picker(\"Master processing\", selection: masterProcessingBinding)"))
        #expect(master.contains("Text(\"Off\").tag(nil as MasterAudioProcessing?)"))
        #expect(master.contains("Text(\"SNS 좋은 소리\").tag(MasterAudioProcessing.sns as MasterAudioProcessing?)"))
        #expect(master.contains(".pickerStyle(.segmented)"))
        #expect(master.contains(".accessibilityLabel(\"Master audio processing\")"))
        #expect(master.contains("viewModel.setMasterAudioProcessing(processing)"))
    }

    @Test("view model routes preset changes through a command and invalidates stale loudness")
    func viewModelUsesCommandPathAndInvalidatesMeter() throws {
        let audio = try source("App/MovieCutMac/EditorViewModel+Audio.swift")
        let setter = try section(
            in: audio,
            from: "func setMasterAudioProcessing",
            to: "    /// G-25 switchover step 2B"
        )

        #expect(setter.contains("await apply(SetMasterAudioProcessingCommand(processing: processing))"))
        #expect(setter.contains("masterLoudness = nil"))
        #expect(setter.contains("masterLoudnessError = nil"))
    }
}

private enum MasterAudioInspectorStaticContractError: Error {
    case missingMarker(String)
}
