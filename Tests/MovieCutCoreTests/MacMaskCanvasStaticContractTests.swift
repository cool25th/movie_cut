import Foundation
import Testing

/// The macOS app target is exercised by xcodebuild, but this SwiftPM test keeps
/// source-level accessibility/editing affordances visible to the faster core QA loop.
@Suite("macOS Mask Canvas Static Contract")
struct MacMaskCanvasStaticContractTests {
    private var source: String {
        get throws {
            let path = "App/MovieCutMac/Effects/MaskCanvasView.swift"
            return try String(contentsOfFile: path, encoding: .utf8)
        }
    }

    @Test("macOS mask canvas keeps the same editing affordances as the iOS static contract")
    func editingAffordanceContract() throws {
        let source = try source

        #expect(source.contains("Mask visual editor"))
        #expect(source.contains("Move the center handle, resize with corner handles, rotate with the top handle, or choose a mask shape from the toolbar."))
        #expect(source.contains("Mask center"))
        #expect(source.contains("Rotate mask"))
        #expect(source.contains("Invert mask"))
        #expect(source.contains("Drag to move the mask on the canvas, or use VoiceOver actions to nudge the mask one percent at a time"))
        #expect(source.contains("Drag to resize the mask"))
        #expect(source.contains("Drag to rotate the mask, or use VoiceOver actions to rotate five degrees at a time"))
    }

    @Test("macOS mask canvas exposes VoiceOver nudge actions for precise center movement")
    func voiceOverNudgeActionContract() throws {
        let source = try source

        #expect(source.contains("Nudge mask left"))
        #expect(source.contains("Nudge mask right"))
        #expect(source.contains("Nudge mask up"))
        #expect(source.contains("Nudge mask down"))
        #expect(source.contains("accessibilityNudgeStepX"))
        #expect(source.contains("accessibilityNudgeStepY"))
        #expect(source.contains("nudgeMask(currentMask"))
    }

    @Test("macOS mask canvas exposes VoiceOver rotation actions for precise angle adjustment")
    func voiceOverRotationActionContract() throws {
        let source = try source

        #expect(source.contains("Rotate mask counterclockwise"))
        #expect(source.contains("Rotate mask clockwise"))
        #expect(source.contains("rotateMask(currentMask, by: -5)"))
        #expect(source.contains("rotateMask(currentMask, by: 5)"))
        #expect(source.contains("private func rotateMask(_ currentMask: Mask, by deltaDegrees: Double)"))
        #expect(source.contains("normalizedDegrees(currentMask.rotation + deltaDegrees)"))
    }

    @Test("macOS mask canvas exposes VoiceOver resize actions for precise size adjustment")
    func voiceOverResizeActionContract() throws {
        let source = try source

        #expect(source.contains("Increase mask width"))
        #expect(source.contains("Decrease mask width"))
        #expect(source.contains("Increase mask height"))
        #expect(source.contains("Decrease mask height"))
        #expect(source.contains("accessibilityResizeStepX"))
        #expect(source.contains("accessibilityResizeStepY"))
        #expect(source.contains("private func resizeMask(_ currentMask: Mask, by deltaSize: CGSize, metrics: MaskCanvasMetrics)"))
        #expect(source.contains("scaleBrushPoints("))
    }

    @Test("macOS mask canvas exposes position, size, rotation, and selected toolbar state to VoiceOver")
    func accessibilityValueContract() throws {
        let source = try source

        #expect(source.contains(".accessibilityValue(maskAccessibilityValue(for: currentMask))"))
        #expect(source.contains(".accessibilityValue(positionAccessibilityValue(for: currentMask.position))"))
        #expect(source.contains(".accessibilityValue(sizeAccessibilityValue(for: currentMask.size))"))
        #expect(source.contains(".accessibilityValue(rotationAccessibilityValue(for: currentMask.rotation))"))
        #expect(source.contains(".accessibilityValue(isSelected ? \"Selected\" : \"Not selected\")"))
    }

    @Test("macOS mask canvas keeps deterministic VoiceOver traversal order")
    func voiceOverTraversalOrderContract() throws {
        let source = try source

        #expect(source.contains(".accessibilitySortPriority(4)"))
        #expect(source.contains(".accessibilitySortPriority(3)"))
        #expect(source.contains(".accessibilitySortPriority(2)"))
        #expect(source.contains(".accessibilitySortPriority(1)"))
        #expect(source.contains(".accessibilitySortPriority(0)"))
    }
}
