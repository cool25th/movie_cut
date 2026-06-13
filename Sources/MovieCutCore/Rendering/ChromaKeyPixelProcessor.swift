import CoreImage
import Foundation

/// Applies chroma key removal to Core Image frames for preview and export.
public enum ChromaKeyPixelProcessor {
    /// Fallback key color used when persisted hex settings cannot be parsed.
    public static let defaultKeyColor = SIMD3<Float>(0, 1, 0)

    /// Applies persisted chroma key settings, preserving the input extent.
    public static func apply(_ settings: ChromaKeySettings, to image: CIImage) -> CIImage {
        apply(
            keyColor: rgbComponents(from: settings.keyColor) ?? defaultKeyColor,
            threshold: Float(settings.tolerance),
            softness: Float(settings.softness),
            spillSuppression: Float(settings.spillSuppression),
            edgeShrink: Float(settings.edgeShrink),
            to: image
        )
    }

    /// Applies legacy key color and threshold controls, preserving the input extent.
    public static func apply(
        keyColor: SIMD3<Float>,
        threshold: Float,
        softness: Float = Float(ChromaKeySettings.greenScreen().softness),
        spillSuppression: Float = Float(ChromaKeySettings.greenScreen().spillSuppression),
        edgeShrink: Float = 0,
        to image: CIImage
    ) -> CIImage {
        let extent = image.extent
        let keyColor = clamped(keyColor)
        // Edge shrink raises the keying threshold so more near-key fringe
        // pixels are removed, eroding the foreground edge inward (F-10). It is
        // orthogonal to feathering.
        let tolerance = clamped(threshold + clamped(edgeShrink) * 0.25)
        let feather = max(clamped(softness), 0.001)
        let spillStrength = clamped(spillSuppression)

        guard let kernel = chromaKeyKernel else {
            return image
        }

        let output = kernel.apply(
            extent: extent,
            arguments: [
                image,
                CIVector(x: CGFloat(keyColor.x), y: CGFloat(keyColor.y), z: CGFloat(keyColor.z)),
                tolerance,
                feather,
                spillStrength
            ]
        )

        return output?.cropped(to: extent) ?? image
    }

    /// Parses "#RRGGBB" or "RRGGBB" into normalized RGB components.
    public static func rgbComponents(from hex: String) -> SIMD3<Float>? {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else {
            return nil
        }

        return SIMD3<Float>(
            Float((value >> 16) & 0xFF) / 255,
            Float((value >> 8) & 0xFF) / 255,
            Float(value & 0xFF) / 255
        )
    }

    private static let chromaKeyKernel = CIColorKernel(source: """
        kernel vec4 chromaKey(__sample pixel, vec3 keyColor, float threshold, float softness, float spillSuppression) {
            float distanceFromKey = distance(pixel.rgb, keyColor);
            float matte = smoothstep(threshold, threshold + max(softness, 0.001), distanceFromKey);
            float outputAlpha = pixel.a * matte;
            float spill = clamp(spillSuppression * (1.0 - matte), 0.0, 1.0);
            vec3 rgb = pixel.rgb;

            if (keyColor.g >= keyColor.r && keyColor.g >= keyColor.b) {
                rgb.g = mix(rgb.g, max(rgb.r, rgb.b), spill);
            } else if (keyColor.b >= keyColor.r && keyColor.b >= keyColor.g) {
                rgb.b = mix(rgb.b, max(rgb.r, rgb.g), spill);
            } else {
                rgb.r = mix(rgb.r, max(rgb.g, rgb.b), spill);
            }

            return vec4(rgb, outputAlpha);
        }
        """)

    private static func clamped(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }

    private static func clamped(_ color: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(clamped(color.x), clamped(color.y), clamped(color.z))
    }
}
