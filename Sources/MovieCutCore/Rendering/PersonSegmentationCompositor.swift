#if canImport(CoreImage)
import CoreImage
import Foundation

/// Composites a person-segmentation mask onto a frame to make the background
/// transparent (F-08). The Vision request itself lives in the app-layer
/// compositor; this shared, platform-neutral helper performs the mask
/// alignment and alpha composite so preview and export match and the logic is
/// unit-testable with synthetic masks.
public enum PersonSegmentationCompositor {
    /// Scales the mask to the image extent and blends, replacing the
    /// background (mask black) with transparency while keeping the foreground
    /// (mask white).
    ///
    /// - Parameters:
    ///   - image: The source frame.
    ///   - mask: A single-channel-ish mask image (white = keep, black = drop).
    public static func removeBackground(from image: CIImage, mask: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0,
              !mask.extent.isEmpty, mask.extent.width > 0, mask.extent.height > 0 else {
            return image
        }

        let alignedMask = align(mask, to: extent)
        let transparentBackground = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: extent)

        return image.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputMaskImageKey: alignedMask,
                kCIInputBackgroundImageKey: transparentBackground
            ]
        ).cropped(to: extent)
    }

    /// Scales and translates a mask so it covers `extent` exactly.
    public static func align(_ mask: CIImage, to extent: CGRect) -> CIImage {
        guard mask.extent.width > 0, mask.extent.height > 0 else { return mask }
        let scaleX = extent.width / mask.extent.width
        let scaleY = extent.height / mask.extent.height
        var scaled = mask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        scaled = scaled.transformed(by: CGAffineTransform(
            translationX: extent.minX - scaled.extent.minX,
            y: extent.minY - scaled.extent.minY
        ))
        return scaled.cropped(to: extent)
    }

    /// Whether `maskImage` contains any foreground (non-black) pixels within `extent`.
    ///
    /// Renders a 1×1 area-maximum sample through `ciContext` and checks whether any
    /// channel exceeds the foreground threshold. Returns `true` when the filter is
    /// unavailable so callers fall back to keeping the frame.
    public static func maskContainsForeground(
        _ maskImage: CIImage,
        extent: CGRect,
        in ciContext: CIContext
    ) -> Bool {
        guard let maximumImage = CIFilter(
            name: "CIAreaMaximum",
            parameters: [
                kCIInputImageKey: maskImage,
                kCIInputExtentKey: CIVector(cgRect: extent)
            ]
        )?.outputImage else {
            return true
        }

        var maximumPixel = [UInt8](repeating: 0, count: 4)
        maximumPixel.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            ciContext.render(
                maximumImage,
                toBitmap: baseAddress,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }

        return maximumPixel[0] > 8 || maximumPixel[1] > 8 || maximumPixel[2] > 8
    }

    /// A center-biased vignette fallback used when Vision cannot produce a person mask.
    ///
    /// Builds a radial gradient mask (bright center, dark edges) and blends the image
    /// over transparency so the frame edges fade out.
    public static func applyBackgroundRemoval(to image: CIImage) -> CIImage {
        let size = image.extent.size
        guard size.width > 0, size.height > 0 else { return image }

        let maskImage = CIImage(color: .white).cropped(to: image.extent)
        let vignetteRadius = min(size.width, size.height) * 0.4
        let backgroundColor = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: image.extent)

        let gradientMask = CIFilter(
            name: "CIRadialGradient",
            parameters: [
                "inputCenter": CIVector(x: size.width / 2, y: size.height / 2),
                "inputRadius0": NSNumber(value: Float(vignetteRadius)),
                "inputRadius1": NSNumber(value: Float(max(size.width, size.height) * 0.7)),
                "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
                "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0)
            ]
        )?.outputImage?.cropped(to: image.extent) ?? maskImage

        return image.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputMaskImageKey: gradientMask,
                kCIInputBackgroundImageKey: backgroundColor
            ]
        )
    }
}
#endif
