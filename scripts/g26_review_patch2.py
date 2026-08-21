from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


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

# There are five Mac session-lifetime replacement paths in this type today:
# newProject, openProject, adoptRecoveredProject, ProjectPackage import, and
# template project creation. Advance the generation in all five, including when
# a replacement happens to decode to an equal Project value.
replacement_old = """        session = EditorSession(project: project)\n        currentProject = project\n"""
replacement_new = """        session = EditorSession(project: project)\n        currentProject = project\n        invalidateMasterLoudnessContext()\n"""
count = s.count(replacement_old)
if count != 5:
    raise SystemExit(f"session replacements: expected 5 matches, found {count}")
s = s.replace(replacement_old, replacement_new)
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
        let pattern = "session = EditorSession(project: project)\n        currentProject = project\n        invalidateMasterLoudnessContext()"
        let replacements = viewModel.components(separatedBy: pattern).count - 1

        // newProject, openProject, adoptRecoveredProject, ProjectPackage import,
        // and template creation must all break the previous measurement lifetime.
        #expect(replacements == 5)
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
