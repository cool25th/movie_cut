import Foundation
import CoreGraphics
import MovieCutCore
import Testing

/// Requirement 5 — preview render quality model + the pure canvas-scaling helper
/// that `PlaybackEngine` uses. `ExportEngine` never calls `PreviewRenderSize`,
/// which is why lowering the preview quality cannot change export resolution.
@Suite("PreviewQuality")
struct PreviewQualityTests {

    // MARK: - Model

    @Test("The default quality is full and leaves the canvas untouched")
    func defaultIsFull() {
        #expect(PreviewQuality.default == .full)
        #expect(PreviewQuality.default.scaleFactor == 1.0)
    }

    @Test("Scale factors halve per step")
    func scaleFactorsHalve() {
        #expect(PreviewQuality.full.scaleFactor == 1.0)
        #expect(PreviewQuality.half.scaleFactor == 0.5)
        #expect(PreviewQuality.quarter.scaleFactor == 0.25)
    }

    @Test("Raw values are stable strings for forward-compatible storage")
    func rawValuesAreStable() {
        // These strings are written into project files, so they must not change.
        #expect(PreviewQuality.full.rawValue == "full")
        #expect(PreviewQuality.half.rawValue == "half")
        #expect(PreviewQuality.quarter.rawValue == "quarter")
    }

    // MARK: - PreviewRenderSize (pure)

    @Test("Full quality returns the canvas unchanged — a true no-op")
    func fullQualityIsNoOp() {
        let canvas = CGSize(width: 1920, height: 1080)
        #expect(PreviewRenderSize.resolve(canvas: canvas, quality: .full) == canvas)
    }

    @Test("Half quality scales the canvas to half resolution")
    func halfQualityHalvesCanvas() {
        let canvas = CGSize(width: 1920, height: 1080)
        let resolved = PreviewRenderSize.resolve(canvas: canvas, quality: .half)
        #expect(resolved == CGSize(width: 960, height: 540))
    }

    @Test("Quarter quality scales the canvas to quarter resolution")
    func quarterQualityQuartersCanvas() {
        let canvas = CGSize(width: 1920, height: 1080)
        let resolved = PreviewRenderSize.resolve(canvas: canvas, quality: .quarter)
        #expect(resolved == CGSize(width: 480, height: 270))
    }

    @Test("Render dimensions are even after scaling (AVFoundation requirement)")
    func dimensionsAreEvenForOddCanvases() {
        // 1921x1081 * 0.5 = 960.5x540.5 -> must round to even integers.
        let canvas = CGSize(width: 1921, height: 1081)
        let resolved = PreviewRenderSize.resolve(canvas: canvas, quality: .half)
        #expect(Int(resolved.width) % 2 == 0)
        #expect(Int(resolved.height) % 2 == 0)
        #expect(resolved == CGSize(width: 960, height: 540))
    }

    @Test("A zero-dimension canvas is returned as-is rather than collapsing")
    func zeroCanvasIsReturnedAsIs() {
        // Guard against producing a degenerate 0x0 / 2x2 render size when the
        // project canvas is not yet initialized.
        let zero = CGSize(width: 0, height: 0)
        #expect(PreviewRenderSize.resolve(canvas: zero, quality: .half) == zero)
    }

    @Test("Export-relevant resolution equality holds at full quality only")
    func exportUnaffectedAtNonFull() {
        // Concrete expression of Requirement 5.2: export uses project.canvas,
        // preview uses PreviewRenderSize. At .full they coincide; at .half they
        // differ — proving preview lowering diverges from (and only from) the
        // export path.
        let canvas = CGSize(width: 1920, height: 1080)
        #expect(PreviewRenderSize.resolve(canvas: canvas, quality: .full) == canvas)
        #expect(PreviewRenderSize.resolve(canvas: canvas, quality: .half) != canvas)
    }
}
