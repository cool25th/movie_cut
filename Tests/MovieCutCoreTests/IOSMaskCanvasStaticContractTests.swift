import Foundation
import Testing

/// iOS 26.5 platform is not installed in the current runner, so these tests guard the
/// source-level UI contract that must remain true until device build/VoiceOver QA is available.
@Suite("iOS Mask Canvas Static Contract")
struct IOSMaskCanvasStaticContractTests {
    private var source: String {
        get throws {
            let path = "App/MovieCutiOS/Views/IOSMaskCanvasView.swift"
            return try String(contentsOfFile: path, encoding: .utf8)
        }
    }

    @Test("iOS mask canvas exposes direct rotation touch affordance")
    func rotationAffordanceContract() throws {
        let source = try source

        #expect(source.contains("rotationHandle(for: currentMask, metrics: metrics)"))
        #expect(source.contains("rotationGesture(currentMask: currentMask, metrics: metrics)"))
        #expect(source.contains("normalizedDegrees"))
        #expect(source.contains("Drag to rotate the mask"))
    }

    @Test("iOS mask canvas keeps VoiceOver labels for every editing affordance")
    func voiceOverEditingAffordanceContract() throws {
        let source = try source

        #expect(source.contains("Mask visual editor"))
        #expect(source.contains("Move the center handle, resize with corner handles, rotate with the top handle, or choose a mask shape from the toolbar."))
        #expect(source.contains("Mask center"))
        #expect(source.contains("Rotate mask"))
        #expect(source.contains("Invert mask"))
        #expect(source.contains("Drag to move the mask on the canvas, or use VoiceOver actions to nudge the mask one percent at a time"))
        #expect(source.contains("Drag to resize the mask"))
    }

    @Test("iOS mask canvas exposes VoiceOver nudge actions for precise center movement")
    func voiceOverNudgeActionContract() throws {
        let source = try source

        #expect(source.contains("Nudge mask left"))
        #expect(source.contains("Nudge mask right"))
        #expect(source.contains("Nudge mask up"))
        #expect(source.contains("Nudge mask down"))
        #expect(source.contains("accessibilityNudgeStepX"))
        #expect(source.contains("accessibilityNudgeStepY"))
        #expect(source.contains("nudgeMask(currentMask"))
        #expect(source.contains("offset(currentMask.brushPoints, by: appliedDelta)"))
    }

    @Test("iOS mask canvas keeps deterministic VoiceOver traversal order")
    func voiceOverTraversalOrderContract() throws {
        let source = try source

        #expect(source.contains(".accessibilitySortPriority(4)"))
        #expect(source.contains(".accessibilitySortPriority(3)"))
        #expect(source.contains(".accessibilitySortPriority(2)"))
        #expect(source.contains(".accessibilitySortPriority(1)"))
        #expect(source.contains(".accessibilitySortPriority(0)"))
    }
}
