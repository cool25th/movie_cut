import CoreImage
import Foundation

/// Applies the implemented per-clip color correction controls to rendered pixels.
///
/// Brightness, contrast, and saturation are intentionally mapped to Core Image's
/// `CIColorControls` semantics so preview and export can share the same pixel
/// processor. Warmth and tint are currently unsupported and are ignored here.
public enum ColorCorrectionPixelProcessor {
    public static func apply(_ colorCorrection: ColorCorrection, to image: CIImage) -> CIImage {
        guard hasSupportedAdjustments(in: colorCorrection) else {
            return image
        }

        return image.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputBrightnessKey: colorCorrection.brightness,
                kCIInputContrastKey: colorCorrection.contrast,
                kCIInputSaturationKey: colorCorrection.saturation
            ]
        )
    }

    public static func isIdentity(_ colorCorrection: ColorCorrection) -> Bool {
        colorCorrection.brightness == 0
            && colorCorrection.contrast == 1
            && colorCorrection.saturation == 1
            && colorCorrection.warmth == 0
            && colorCorrection.tint == 0
    }

    public static func hasSupportedAdjustments(in colorCorrection: ColorCorrection) -> Bool {
        colorCorrection.brightness != 0
            || colorCorrection.contrast != 1
            || colorCorrection.saturation != 1
    }
}
