#if canImport(CoreImage)
import CoreImage
import Foundation

/// Shared source-space preview pipeline for G-28 effect discovery.
///
/// The browser drafts a new visual effect, but the displayed preview must also
/// include every clip-local processor that runs after/before the effect array
/// in the product compositor. The background-removal Vision request remains an
/// app-layer concern and is injected as a closure; the ordering itself stays in
/// Core so it is behavior-testable and cannot drift from the browser silently.
public enum EffectBrowserPreviewPipeline {
    public static func apply(
        clip: Clip,
        effects: [Effect],
        to sourceImage: CIImage,
        at localTime: Double = 0,
        backgroundRemoval: ((CIImage) -> CIImage)? = nil
    ) -> CIImage {
        var image = sourceImage

        // Match CustomVideoCompositor.applyClipEffects ordering for the
        // source-space processors relevant to an effect preview.
        if let cropRect = clip.cropRect {
            image = CropPixelProcessor.apply(
                cropRect,
                to: image,
                renderSize: image.extent.size
            )
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
            image = MaskPixelProcessor.apply(mask, to: image, at: localTime)
        }

        return image
    }
}
#endif
