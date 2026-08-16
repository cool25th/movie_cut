import CoreGraphics
import CoreImage
import Foundation

/// Dedicated crop support (G-23). A crop selects a normalized sub-rect of the
/// source frame; the selected region is then scaled to FILL the render canvas
/// (aspect-fill, centered) so the cropped clip keeps covering the frame the
/// same way the uncropped clip did — never letterboxed, never distorted.
///
/// Shared by the Mac and iOS video compositors so preview and export crop with
/// identical pixels by construction (same processor, same inputs).
public enum CropPixelProcessor {
    /// Whether `rect` covers the full unit frame, i.e. cropping to it would be
    /// a visual no-op. Used by callers to skip the pixel pass entirely.
    public static func isFullFrame(_ rect: NormalizedRect) -> Bool {
        abs(rect.x) <= 1.0e-9
            && abs(rect.y) <= 1.0e-9
            && abs(rect.width - 1) <= 1.0e-9
            && abs(rect.height - 1) <= 1.0e-9
    }

    /// Largest centered crop whose PIXEL aspect equals `targetAspect`
    /// (width/height), inside a source frame whose pixel aspect is
    /// `sourceAspect`. Returns nil for non-finite or non-positive aspects.
    ///
    /// The rect is normalized in source coordinates (top-leading origin), so
    /// the pixel aspect of a normalized rect is
    /// `(rect.width * sourceAspect) / rect.height`.
    public static func centeredCropRect(sourceAspect: Double, targetAspect: Double) -> NormalizedRect? {
        guard sourceAspect.isFinite, sourceAspect > 0,
              targetAspect.isFinite, targetAspect > 0 else {
            return nil
        }

        // Width-limited: the source is wider than the target ratio, so the
        // crop spans the full height and narrows the width. Otherwise the
        // crop spans the full width and narrows the height.
        let width: Double
        let height: Double
        if sourceAspect > targetAspect {
            height = 1
            width = targetAspect / sourceAspect
        } else {
            width = 1
            height = sourceAspect / targetAspect
        }

        return NormalizedRect(
            x: (1 - width) / 2,
            y: (1 - height) / 2,
            width: width,
            height: height
        )
    }

    /// Crops `image` to the normalized `rect` and scales the selected region
    /// to fill `renderSize` (aspect-fill, centered), returning an image whose
    /// extent is exactly `CGRect(origin: .zero, size: renderSize)`.
    ///
    /// `rect` uses top-leading normalized coordinates (the `NormalizedRect`
    /// convention); CIImage's extent uses a bottom-left origin, so the y axis
    /// is flipped once here rather than at every call site.
    public static func apply(_ rect: NormalizedRect, to image: CIImage, renderSize: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        guard renderSize.width > 0, renderSize.height > 0 else { return image }

        if isFullFrame(rect) {
            // Visual no-op: keep the caller's pixels untouched (the pixel
            // identity gate for never-cropped projects).
            return image
        }

        // Clamp the normalized rect into the unit frame so a slightly
        // out-of-bounds rect (float drift from an editor gesture) cannot
        // produce a pixel rect outside the source extent.
        let unitX = min(max(rect.x, 0), 1)
        let unitY = min(max(rect.y, 0), 1)
        let unitWidth = min(max(min(rect.width, 1 - unitX), 0), 1)
        let unitHeight = min(max(min(rect.height, 1 - unitY), 0), 1)
        guard unitWidth > 0, unitHeight > 0 else { return image }

        // NormalizedRect counts y from the top; CIImage counts from the bottom.
        let pixelRect = CGRect(
            x: extent.minX + unitX * extent.width,
            y: extent.minY + (1 - unitY - unitHeight) * extent.height,
            width: unitWidth * extent.width,
            height: unitHeight * extent.height
        )

        let renderBounds = CGRect(origin: .zero, size: renderSize)
        let scale = max(
            renderSize.width / pixelRect.width,
            renderSize.height / pixelRect.height
        )
        let scaledWidth = pixelRect.width * scale
        let scaledHeight = pixelRect.height * scale

        // Order (right-to-left when applied): move the crop region to the
        // origin, scale it to cover the canvas, center it on the canvas.
        let transform = CGAffineTransform.identity
            .translatedBy(x: (renderSize.width - scaledWidth) / 2, y: (renderSize.height - scaledHeight) / 2)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -pixelRect.minX, y: -pixelRect.minY)

        return image
            .transformed(by: transform)
            .cropped(to: renderBounds)
    }
}
