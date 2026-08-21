from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


def replace_between(text: str, start: str, end: str, replacement: str, label: str) -> str:
    i = text.find(start)
    if i < 0:
        raise SystemExit(f"{label}: start marker missing")
    j = text.find(end, i)
    if j < 0:
        raise SystemExit(f"{label}: end marker missing")
    return text[:i] + replacement + text[j:]


# 1) Persistent queue state belongs to the MainActor view model.
path = Path("App/MovieCutMac/EditorViewModel.swift")
s = path.read_text()
storage_old = """    @ObservationIgnored var masterLoudnessRevision: UInt64 = 0\n    var lastExportURL: URL?\n"""
storage_new = """    @ObservationIgnored var masterLoudnessRevision: UInt64 = 0\n    /// Latest user intent for the project master preset. Picker events update\n    /// this synchronously on MainActor; one worker drains/coalesces them so\n    /// rapid selections cannot commit out of order.\n    @ObservationIgnored var desiredMasterAudioProcessing: MasterAudioProcessing?\n    @ObservationIgnored var masterAudioProcessingMutationGeneration: UInt64 = 0\n    @ObservationIgnored var masterAudioProcessingMutationTask: Task<Void, Never>?\n    var lastExportURL: URL?\n"""
s = replace_once(s, storage_old, storage_new, "master preset queue storage")

# Session replacement is a boundary for both meter work and pending preset
# mutations. Advance the queue generation and make the fresh project's own
# value the desired baseline; an old worker then coalesces onto the new lifetime
# instead of replaying old-project intent.
helper_anchor = """    func invalidateMasterLoudnessContext() {\n        masterLoudnessRevision &+= 1\n        masterLoudness = nil\n        masterLoudnessError = nil\n    }\n\n"""
queue_reset = """    /// Re-bases the serialized master-preset queue on a fresh project session.\n    func resetMasterAudioProcessingMutationContext(to processing: MasterAudioProcessing?) {\n        masterAudioProcessingMutationGeneration &+= 1\n        desiredMasterAudioProcessing = processing\n    }\n\n"""
s = replace_once(s, helper_anchor, helper_anchor + queue_reset, "preset queue reset helper")

# Add the queue reset immediately after each of the five loudness/session
# invalidation calls in fresh-session replacement paths. The committed-refresh
# call is deliberately excluded: normal edits must not rebase user preset intent.
replacement_marker = "invalidateMasterLoudnessContext()\n"
positions = []
start = 0
while True:
    idx = s.find(replacement_marker, start)
    if idx < 0:
        break
    positions.append(idx)
    start = idx + len(replacement_marker)
# declaration body does not match marker; calls are five replacements + refresh = 6.
if len(positions) != 6:
    raise SystemExit(f"loudness invalidation calls: expected 6, found {len(positions)}")

# Identify fresh-session calls by the immediately preceding currentProject = project.
needle_by_indent = []
for indent, expected in [("        ", 3), ("            ", 1), ("                ", 1)]:
    old = f"{indent}currentProject = project\n{indent}invalidateMasterLoudnessContext()\n"
    new = old + f"{indent}resetMasterAudioProcessingMutationContext(to: project.masterAudioProcessing)\n"
    count = s.count(old)
    if count != expected:
        raise SystemExit(f"preset queue replacement {len(indent)} spaces: expected {expected}, found {count}")
    s = s.replace(old, new)
path.write_text(s)


# 2) Synchronous enqueue + one async drain worker. No UI event is discarded
# just because currentProject still reflects the value before an older request.
path = Path("App/MovieCutMac/EditorViewModel+Audio.swift")
s = path.read_text()
start = "    /// G-26 inspector control: routes the project-level master preset through\n"
end = "    /// G-25 switchover step 2B"
replacement = """    /// G-26 inspector control. Picker events enqueue synchronously on MainActor\n    /// so their order matches the user's order. A single worker drains the\n    /// latest desired value and coalesces intermediate selections while an\n    /// EditorSession dispatch is suspended.\n    func setMasterAudioProcessing(_ processing: MasterAudioProcessing?) {\n        desiredMasterAudioProcessing = processing\n        masterAudioProcessingMutationGeneration &+= 1\n\n        guard masterAudioProcessingMutationTask == nil else { return }\n        masterAudioProcessingMutationTask = Task { @MainActor [weak self] in\n            await self?.drainMasterAudioProcessingMutations()\n        }\n    }\n\n    private func drainMasterAudioProcessingMutations() async {\n        while !Task.isCancelled {\n            let requestGeneration = masterAudioProcessingMutationGeneration\n            let processing = desiredMasterAudioProcessing\n\n            if currentProject.masterAudioProcessing != processing {\n                await apply(SetMasterAudioProcessingCommand(processing: processing))\n            }\n\n            // A newer picker event or project/session replacement arrived while\n            // dispatch/refresh was suspended. Loop once more using only the\n            // newest desired state; never let an older request win last.\n            guard requestGeneration == masterAudioProcessingMutationGeneration else {\n                continue\n            }\n\n            masterAudioProcessingMutationTask = nil\n            guard currentProject.masterAudioProcessing == processing else { return }\n\n            switch processing {\n            case .sns:\n                lastStatusMessage = \"Master audio processing set to SNS 좋은 소리.\"\n            case nil:\n                lastStatusMessage = \"Master audio processing turned off.\"\n            }\n            return\n        }\n\n        masterAudioProcessingMutationTask = nil\n    }\n\n"""
s = replace_between(s, start, end, replacement, "serialized master preset setter")
path.write_text(s)


# 3) Binding must enqueue synchronously rather than wrapping each event in an
# independently scheduled Task.
path = Path("App/MovieCutMac/InspectorPanel.swift")
s = path.read_text()
s = replace_once(
    s,
    """            set: { processing in\n                Task { await viewModel.setMasterAudioProcessing(processing) }\n            }\n""",
    """            set: { processing in\n                viewModel.setMasterAudioProcessing(processing)\n            }\n""",
    "synchronous master processing binding",
)
path.write_text(s)


# 4) Update the blocking UI/command contract to pin serialization/coalescing.
path = Path("Tests/MovieCutCoreTests/MasterAudioInspectorStaticContractTests.swift")
path.write_text(r'''import Foundation
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
        #expect(!master.contains("Task { await viewModel.setMasterAudioProcessing(processing) }"))
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
''')
