#if canImport(CoreGraphics)
import CoreGraphics
import Foundation

/// Samples a pixel color from a `CGImage` at a normalized point. Used by the
/// chroma-key eyedropper (F-10): a preview click maps to a normalized
/// coordinate, and the color under it becomes the key color.
public enum PixelSampler {
    /// Returns the RGB (0...1) color at `normalizedPoint` (origin top-left,
    /// 0...1 in each axis), or nil if the point or image is invalid.
    public static func color(
        in image: CGImage,
        atNormalizedPoint normalizedPoint: CGPoint
    ) -> SIMD3<Float>? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              normalizedPoint.x >= 0, normalizedPoint.x <= 1,
              normalizedPoint.y >= 0, normalizedPoint.y <= 1 else {
            return nil
        }

        let x = min(width - 1, max(0, Int(normalizedPoint.x * CGFloat(width))))
        let y = min(height - 1, max(0, Int(normalizedPoint.y * CGFloat(height))))

        // Render the single pixel into a known RGBA8 buffer so the sample is
        // independent of the source image's color space and alpha layout.
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixel,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        // Translate so the target pixel lands at (0,0) of the 1x1 context.
        context.draw(image, in: CGRect(x: -x, y: -(height - 1 - y), width: width, height: height))

        return SIMD3<Float>(
            Float(pixel[0]) / 255,
            Float(pixel[1]) / 255,
            Float(pixel[2]) / 255
        )
    }

    /// Formats an RGB color as an uppercase "#RRGGBB" hex string.
    public static func hexString(from color: SIMD3<Float>) -> String {
        let r = Int((min(max(color.x, 0), 1) * 255).rounded())
        let g = Int((min(max(color.y, 0), 1) * 255).rounded())
        let b = Int((min(max(color.z, 0), 1) * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
#endif
