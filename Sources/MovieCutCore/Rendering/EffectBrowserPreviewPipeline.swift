#if canImport(CoreImage)
import CoreImage
import Foundation

/// Shared preview pipeline for G-28 effect discovery.
///
/// The source thumbnail is rendered into a bounded surface with the same aspect
/// ratio as the project canvas. This preserves the product compositor's crop
/// geometry while allowing canvas-space masks to be scaled down deterministically.
/// Stabilization uses the representative thumbnail's local time (normally 0),
/// then the remaining clip-local processors follow compositor order.
public enum EffectBrowserPreviewPipeline {
    public static func apply(
        clip: Clip,
        effects: [Effect],
        to sourceImage: CIImage,
        canvasSize: CGSize,
        renderSize: CGSize,
        at localTime: Double = 0,
        backgroundRemoval: ((CIImage) -> CIImage)? = nil
    ) -> CIImage {
        guard canvasSize.width > 0,
              canvasSize.height > 0,
              renderSize.width > 0,
              renderSize.height > 0
        else {
            return sourceImage
        }

        var image = sourceImage

        // Match CustomVideoCompositor.applyClipEffects: stabilization must see
        // the raw source before crop/color/effects. The browser thumbnail is a
        // representative first-frame asset, so callers normally pass localTime 0.
        if let plan = clip.stabilization,
           !plan.isEmpty,
           let correction = plan.correction(atLocalTime: localTime) {
            let extent = image.extent
            let maxTranslation = plan.maxNormalizedTranslation
            image = StabilizationWarpProcessor.apply(
                image,
                correction: (
                    dx: correction.dx * Double(extent.width),
                    dy: -correction.dy * Double(extent.height),
                    cropFraction: correction.cropFraction
                ),
                confidence: correction.confidence,
                coverScale: 1 + 2 * max(maxTranslation.x, maxTranslation.y)
            ).image
        }

        if let cropRect = clip.cropRect {
            image = CropPixelProcessor.apply(
                cropRect,
                to: image,
                renderSize: renderSize
            )
        } else {
            image = aspectFill(image, to: renderSize)
        }

        if !effects.isEmpty {
            image = VisualEffectPixelProcessor.apply(effects, to: image)
        }

        if clip.isBackgroundRemoved, let backgroundRemoval {
            image = backgroundRemoval(image)
        }

        if let colorCorrection = clip.colorCorrection {
            image = ColorCorrectionPixelProcessor.apply(colorCorrection, to: image)
        }

        if let colorGrade = clip.colorGrade {
            image = ColorGradePixelProcessor.apply(colorGrade, to: image)
        }

        if let chromaKey = clip.chromaKey {
            image = ChromaKeyPixelProcessor.apply(chromaKey, to: image)
        }

        if let mask = clip.mask {
            image = MaskPixelProcessor.apply(
                scaledMask(mask, from: canvasSize, to: renderSize),
                to: image,
                at: localTime
            )
        }

        return image.cropped(to: CGRect(origin: .zero, size: renderSize))
    }

    /// Scales a canvas-pixel mask onto the bounded effect-browser surface.
    public static func scaledMask(_ mask: Mask, from canvasSize: CGSize, to renderSize: CGSize) -> Mask {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return mask }
        let scaleX = renderSize.width / canvasSize.width
        let scaleY = renderSize.height / canvasSize.height
        // The preview surface preserves the canvas aspect ratio, so both axes
        // should have the same scale apart from pixel rounding. Feather is a
        // pixel-space blur radius in MaskPixelProcessor and must follow the same
        // downscale to keep edge softness proportional to playback/export.
        let distanceScale = min(scaleX, scaleY)
        return Mask(
            shape: mask.shape,
            position: CGPoint(x: mask.position.x * scaleX, y: mask.position.y * scaleY),
            size: CGSize(width: mask.size.width * scaleX, height: mask.size.height * scaleY),
            rotation: mask.rotation,
            feather: mask.feather * distanceScale,
            inverted: mask.inverted,
            brushPoints: mask.brushPoints.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) }
        )
    }

    private static func aspectFill(_ image: CIImage, to renderSize: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let scale = max(renderSize.width / extent.width, renderSize.height / extent.height)
        let scaledWidth = extent.width * scale
        let scaledHeight = extent.height * scale
        let transform = CGAffineTransform.identity
            .translatedBy(x: (renderSize.width - scaledWidth) / 2, y: (renderSize.height - scaledHeight) / 2)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -extent.minX, y: -extent.minY)
        return image
            .transformed(by: transform)
            .cropped(to: CGRect(origin: .zero, size: renderSize))
    }
}
#endif
