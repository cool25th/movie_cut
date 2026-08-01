import Foundation
import MovieCutCore

// Canvas / overlay geometry thin wrappers around the pure `CanvasGeometry`
// helper in MovieCutCore. Each instance method supplies `currentProject` to
// the argument-based Core functions so the rest of the VM (and the views that
// bind to it) keeps a parameter-free call site.
//
// `CanvasOverlayAlignment` now lives in Core
// (Sources/MovieCutCore/Models/CanvasGeometry.swift), shared by Mac and iOS.

extension EditorViewModel {
    func effectiveCanvasSize(in project: Project) -> CGSize {
        CanvasGeometry.effectiveCanvasSize(in: project)
    }

    func canvasCenter() -> CGPoint {
        CanvasGeometry.canvasCenter(in: effectiveCanvasSize(in: currentProject))
    }

    func socialSafeAreaRect() -> CGRect {
        CanvasGeometry.socialSafeAreaRect(in: effectiveCanvasSize(in: currentProject))
    }

    func resolvedCanvasOverlayTransform(for clip: Clip) -> ClipTransform {
        CanvasGeometry.resolvedCanvasOverlayTransform(
            for: clip,
            fallbackCenter: canvasCenter()
        )
    }

    func canvasOverlayVisualCenter(for clip: Clip) -> CGPoint {
        CanvasGeometry.canvasOverlayVisualCenter(
            for: clip,
            fallbackCenter: canvasCenter()
        )
    }

    func boundingCenter(for points: [CGPoint]) -> CGPoint {
        CanvasGeometry.boundingCenter(for: points, fallback: canvasCenter())
    }

    func alignmentTarget(
        for alignment: CanvasOverlayAlignment,
        centers: [CGPoint],
        canvasSize: CGSize,
        isMultiple: Bool
    ) -> CGFloat {
        CanvasGeometry.alignmentTarget(
            for: alignment,
            centers: centers,
            canvasSize: canvasSize,
            isMultiple: isMultiple
        )
    }

    func clampedCanvasPoint(_ point: CGPoint, canvasSize: CGSize) -> CGPoint {
        CanvasGeometry.clampedCanvasPoint(point, canvasSize: canvasSize)
    }

    func isZeroPoint(_ point: CGPoint) -> Bool {
        CanvasGeometry.isZeroPoint(point)
    }

    func nonZeroPoint(_ point: CGPoint) -> CGPoint? {
        CanvasGeometry.nonZeroPoint(point)
    }

    func pointsEqual(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        CanvasGeometry.pointsEqual(lhs, rhs)
    }

    func scaledTemplatePosition(_ position: CGPoint) -> CGPoint {
        CanvasGeometry.scaledTemplatePosition(position, in: effectiveCanvasSize(in: currentProject))
    }

    func defaultStickerPlacement(
        for sticker: StickerAsset
    ) -> (xRatio: CGFloat, yRatio: CGFloat, fontScale: Double, transformScale: CGFloat) {
        CanvasGeometry.defaultStickerPlacement(for: sticker)
    }
}
