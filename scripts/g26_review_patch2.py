from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


def replace_all_exact(text: str, old: str, new: str, expected: int, label: str) -> str:
    count = text.count(old)
    if count != expected:
        raise SystemExit(f"{label}: expected {expected} matches, found {count}")
    return text.replace(old, new)


path = Path("App/MovieCutMac/EditorViewModel.swift")
s = path.read_text()

# Treat the counter as a committed session/mix generation, not as a value-diff
# counter. UI drag previews can pre-mutate currentProject before a command is
# dispatched, so Project equality cannot prove whether a commit happened.
s = replace_once(
    s,
    """    /// Increments whenever the committed project snapshot changes. A meter\n    /// render captures this revision so an older async result cannot overwrite\n    /// a newer edit, undo, or redo state.\n    @ObservationIgnored var masterLoudnessRevision: UInt64 = 0\n""",
    """    /// Monotonic committed session/mix generation. It advances for every\n    /// committed session refresh and every session replacement, even when the\n    /// resulting Project value compares equal to the UI's provisional snapshot.\n    /// Async meter work captures this value so stale results cannot cross an\n    /// edit, undo/redo, or project/session lifetime boundary.\n    @ObservationIgnored var masterLoudnessRevision: UInt64 = 0\n""",
    "loudness generation comment",
)

# One correctness boundary for every caller. Internal (not private) because the
# audio extension reads the same generation while an async measurement runs.
insert_after = """    func renderingEnginesHoldIdenticalTimeline() async -> Bool {\n        await FlattenedTimelineParity.bothHoldIdentical(\n            for: currentProject.id,\n            playbackEngine,\n            exportEngine\n        )\n    }\n\n"""
helper = """    /// Invalidates any measurement tied to the previous committed mix.\n    /// Call this on every EditorSession commit refresh and on every fresh\n    /// EditorSession replacement; Project equality is intentionally irrelevant.\n    func invalidateMasterLoudnessContext() {\n        masterLoudnessRevision &+= 1\n        masterLoudness = nil\n        masterLoudnessError = nil\n    }\n\n"""
s = replace_once(s, insert_after, insert_after + helper, "loudness invalidation helper")

# Every successful refresh represents a committed EditorSession state. Do not
# compare against currentProject: timeline gestures can already have copied the
# final provisional range into currentProject before dispatch.
s = replace_once(
    s,
    """    func refreshFromSession() async throws {\n        let previousProject = currentProject\n        currentProject = await session.snapshot()\n        if currentProject != previousProject {\n            masterLoudnessRevision &+= 1\n            masterLoudness = nil\n            masterLoudnessError = nil\n        }\n        await refreshFlattenedTimeline(for: currentProject)\n""",
    """    func refreshFromSession() async throws {\n        currentProject = await session.snapshot()\n        invalidateMasterLoudnessContext()\n        await refreshFlattenedTimeline(for: currentProject)\n""",
    "unconditional committed refresh invalidation",
)

# Five Mac session-lifetime replacement paths currently exist at three nesting
# levels: newProject/adoptRecoveredProject/template creation (8 spaces), package
# import (12), and openProject's timed closure (16). Pin all 3/1/1 counts so a
# future replacement path cannot silently escape the generation boundary.
for indent, expected, label in [
    ("        ", 3, "top-level session replacements"),
    ("            ", 1, "package session replacement"),
    ("                ", 1, "open-project session replacement"),
]:
    old = f"{indent}session = EditorSession(project: project)\n{indent}currentProject = project\n"
    new = old + f"{indent}invalidateMasterLoudnessContext()\n"
    s = replace_all_exact(s, old, new, expected, label)

path.write_text(s)


# Strengthen the blocking static contract around the two review regressions.
path = Path("Tests/MovieCutCoreTests/MasterAudioLoudnessFreshnessStaticContractTests.swift")
path.write_text(r'''import Foundation
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
''')
