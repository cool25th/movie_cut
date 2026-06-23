import CoreImage
import Foundation

/// Applies a 3-way ``ColorGrade`` (lift / gamma / gain) to rendered pixels,
/// shared by preview and export.
///
/// ASC CDL `out = (in * slope + offset) ^ power`:
/// - slope (gain) + offset (lift) map to a single `CIColorMatrix` (per-channel
///   diagonal slope, offset as the bias vector),
/// - power (gamma) maps to `CIGammaAdjust`.
public enum ColorGradePixelProcessor {
    public static func apply(_ grade: ColorGrade, to image: CIImage) -> CIImage {
        guard !grade.isIdentity else { return image }

        var output = image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: grade.gain.red, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: grade.gain.green, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: grade.gain.blue, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: grade.lift.red, y: grade.lift.green, z: grade.lift.blue, w: 0)
            ]
        )

        if grade.gamma != 1 {
            output = output.applyingFilter("CIGammaAdjust", parameters: ["inputPower": grade.gamma])
        }

        return output
    }

    public static func isIdentity(_ grade: ColorGrade) -> Bool { grade.isIdentity }
}
