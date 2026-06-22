import CoreImage
import Foundation

/// Applies the per-clip color correction controls to rendered pixels.
///
/// Brightness, contrast, and saturation map to Core Image's `CIColorControls`;
/// warmth and tint map to `CITemperatureAndTint`. Both stages run through this
/// shared processor so preview and export match. Warmth/tint use the
/// grading-intuitive sign: positive warmth is warmer (redder), positive tint is
/// more magenta.
public enum ColorCorrectionPixelProcessor {
    public static func apply(_ colorCorrection: ColorCorrection, to image: CIImage) -> CIImage {
        var output = image

        if hasColorControlAdjustments(in: colorCorrection) {
            output = output.applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputBrightnessKey: colorCorrection.brightness,
                    kCIInputContrastKey: colorCorrection.contrast,
                    kCIInputSaturationKey: colorCorrection.saturation
                ]
            )
        }

        if hasTemperatureAdjustments(in: colorCorrection) {
            // Lower target temperature renders warmer (redder); the negative
            // signs make positive warmth = warmer and positive tint = magenta,
            // over CITemperatureAndTint's neutral/target convention.
            let targetTemperature = 6500 - colorCorrection.warmth * 2_000
            let targetTint = -colorCorrection.tint * 150
            output = output.applyingFilter(
                "CITemperatureAndTint",
                parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: targetTemperature, y: targetTint)
                ]
            )
        }

        return output
    }

    public static func isIdentity(_ colorCorrection: ColorCorrection) -> Bool {
        colorCorrection.brightness == 0
            && colorCorrection.contrast == 1
            && colorCorrection.saturation == 1
            && colorCorrection.warmth == 0
            && colorCorrection.tint == 0
    }

    public static func hasSupportedAdjustments(in colorCorrection: ColorCorrection) -> Bool {
        hasColorControlAdjustments(in: colorCorrection)
            || hasTemperatureAdjustments(in: colorCorrection)
    }

    private static func hasColorControlAdjustments(in colorCorrection: ColorCorrection) -> Bool {
        colorCorrection.brightness != 0
            || colorCorrection.contrast != 1
            || colorCorrection.saturation != 1
    }

    private static func hasTemperatureAdjustments(in colorCorrection: ColorCorrection) -> Bool {
        colorCorrection.warmth != 0 || colorCorrection.tint != 0
    }
}
