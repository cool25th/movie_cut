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
}
#endif
