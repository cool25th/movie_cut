import Foundation
import MovieCutCore
import Testing
@testable import MovieCutiOS

/// CODEX-18: the fps/canvas preset change must land as ONE undo step.
/// The previous two dispatches (canvas command, then export-settings
/// command) meant undo stepped twice — a single undo restored only the
/// export frame rate while the canvas and timeline kept the new fps, the
/// exact drift the lockstep was meant to prevent.
@MainActor
@Suite("iOS fps preset atomic undo (CODEX-18)")
struct IOSFpsPresetAtomicUndoTests {
    private func makeViewModel() -> IOSEditorViewModel {
        IOSEditorViewModel(autosaveDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("codex18-\(UUID().uuidString)", isDirectory: true))
    }

    @Test("a preset change undoes as a single step restoring canvas AND export fps")
    func presetUndoIsAtomic() async {
        let vm = makeViewModel()
        let before = vm.currentProject
        #expect(before.canvas != CanvasPreset(aspectRatio: .square1x1) || before.exportSettings.frameRate != .fps60,
                "fixture must start differing from the target preset")

        await vm.updateCanvasPreset(CanvasPreset(aspectRatio: .square1x1, frameRate: .fps60))
        let after = vm.currentProject
        #expect(after.canvas.aspectRatio == .square1x1)
        #expect(after.timeline.canvasSize == CGSize(width: 1080, height: 1080))
        #expect(after.exportSettings.frameRate == .fps60,
                "the export frame rate must move in lockstep with the canvas fps")
        #expect(after.timeline.frameRate.numerator == 60 && after.timeline.frameRate.denominator == 1)

        // THE regression: ONE undo must restore the entire prior state —
        // canvas, timeline rebind, AND the export frame rate together.
        await vm.undo()
        #expect(vm.currentProject.canvas == before.canvas,
                "one undo must restore the canvas")
        #expect(vm.currentProject.timeline.canvasSize == before.timeline.canvasSize,
                "one undo must restore the timeline canvas size rebind")
        #expect(vm.currentProject.exportSettings.frameRate == before.exportSettings.frameRate,
                "one undo must restore the export frame rate — the old two-step dispatch left the new fps here")
        #expect(vm.currentProject.timeline.frameRate == before.timeline.frameRate,
                "one undo must restore the timeline frame rate")
    }

    @Test("preset change then redo round-trips both fields")
    func presetRedoRoundTrip() async {
        let vm = makeViewModel()
        let target = CanvasPreset(aspectRatio: .portrait4x5)
        await vm.updateCanvasPreset(target)
        await vm.undo()
        await vm.redo()

        #expect(vm.currentProject.canvas.aspectRatio == target.aspectRatio)
        #expect(vm.currentProject.exportSettings.frameRate == target.frameRate,
                "redo must restore the lockstep export fps")
        #expect(vm.currentProject.timeline.frameRate.numerator == 30 && vm.currentProject.timeline.frameRate.denominator == 1)
    }
}
