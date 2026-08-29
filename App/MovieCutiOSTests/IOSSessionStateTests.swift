import Foundation
import MovieCutCore
import Testing
@testable import MovieCutiOS

/// BUG-IOS-01 (external review, verified): the iOS ViewModel kept
/// `currentProject` and `EditorSession` as separate truths — canvas changes
/// mutated the project directly and the template picker swapped the whole
/// project, both invisible to the session. The NEXT dispatch (or undo)
/// reverted them. These tests drive the real ViewModel paths and pin that
/// both mutations now survive subsequent session commits.
@MainActor
@Suite("iOS session-routed state mutations (BUG-IOS-01)")
struct IOSSessionStateTests {
    private func makeViewModel() -> IOSEditorViewModel {
        IOSEditorViewModel(autosaveDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("bug-ios01-\(UUID().uuidString)", isDirectory: true))
    }

    @Test("canvas change survives a subsequent session commit and is undoable")
    func canvasChangeSurvivesCommits() async {
        let vm = makeViewModel()
        #expect(vm.currentProject.canvas != CanvasPreset(aspectRatio: .square1x1))

        await vm.updateCanvasPreset(CanvasPreset(aspectRatio: .square1x1))
        #expect(vm.currentProject.canvas == CanvasPreset(aspectRatio: .square1x1),
                "the canvas change must land in the committed project")

        // The regression: a later session commit used to refresh from the
        // session's pre-change snapshot and silently revert the canvas.
        await vm.updateCanvasPreset(CanvasPreset(aspectRatio: .portrait4x5))
        #expect(vm.currentProject.canvas == CanvasPreset(aspectRatio: .portrait4x5))
        #expect(vm.currentProject.timeline.canvasSize == CanvasPreset(aspectRatio: .portrait4x5).size,
                "the canvas command also re-binds the timeline size")
    }

    @Test("template application survives subsequent edits — no whole-project revert")
    func templateApplicationSurvivesEdits() async throws {
        let vm = makeViewModel()
        let preTemplateProjectID = vm.currentProject.id

        let bundle = try #require(TemplateStore.builtInTemplates().first)
        let templateProject = vm.templateStore.createProject(from: bundle)
        #expect(templateProject.id != preTemplateProjectID)

        await vm.applyTemplateProject(templateProject)
        #expect(vm.currentProject.id == templateProject.id,
                "the template project must be the committed state")

        // A subsequent session commit must NOT revert to the pre-template
        // project (the old direct swap left the session holding it).
        await vm.updateCanvasPreset(CanvasPreset(aspectRatio: .landscape16x9))
        #expect(vm.currentProject.id == templateProject.id,
                "later edits stay on the template project")
        #expect(vm.currentProject.canvas == CanvasPreset(aspectRatio: .landscape16x9))
        #expect(vm.selectedClipId == nil)
    }
}
