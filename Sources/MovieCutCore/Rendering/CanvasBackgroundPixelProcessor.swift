import CoreImage
import Foundation

/// Renders the canvas background layer that sits under composited video
/// frames. Preview and export compositors share this processor so letterbox
/// fills look identical in both paths (A2/A3).
public enum CanvasBackgroundPixelProcessor {
    // NSCache is documented thread-safe; strict concurrency cannot see that.
    private nonisolated(unsafe) static let imageCache = NSCache<NSURL, CIImage>()

    /// Builds the background image for the given canvas render size.
    ///
    /// - Parameters:
    ///   - background: The configured fill. Nil produces opaque black,
    ///     matching the historical canvas.
    ///   - sourceFrame: The current video frame, used by `.sourceBlur`.
    ///   - renderSize: The canvas/render size in pixels.
    public static func backgroundImage(
        for background: CanvasBackground?,
        sourceFrame: CIImage,
        renderSize: CGSize
    ) -> CIImage {
        let canvasRect = CGRect(origin: .zero, size: renderSize)

        switch background {
        case nil:
            return solid(color: CIColor.black, in: canvasRect)

        case .color(let hex):
            let color = ciColor(fromHex: hex) ?? CIColor.black
            return solid(color: color, in: canvasRect)

        case .sourceBlur(let radius):
            let filled = aspectFill(sourceFrame, into: canvasRect)
            let blurred = filled
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: max(0, radius)
                ])
            return blurred
                .cropped(to: canvasRect)
                .composited(over: solid(color: CIColor.black, in: canvasRect))

        case .image(let url):
            guard let image = cachedImage(at: url) else {
                return solid(color: CIColor.black, in: canvasRect)
            }
            return aspectFill(image, into: canvasRect)
                .composited(over: solid(color: CIColor.black, in: canvasRect))
        }
    }

    /// How the canvas treats pixels the composited frame does not decide
    /// (aspect-fit letter/pillarbox bands, alpha-keyed holes).
    ///
    /// `.opaqueDelivery` fills them with the opaque canvas color so every
    /// output pixel is determined by the current frame — recycled codec
    /// buffers cannot leak the previous scene through transparent bands
    /// (LF-ACTION-01, 2026-09-01 longform blocker).
    ///
    /// `.alphaPreserving` keeps the frame's transparency for alpha-capable
    /// codecs (ProRes 4444 mastering).
    public enum CanvasFillPolicy: Sendable, Equatable {
        case opaqueDelivery
        case alphaPreserving
    }

    /// Composites a frame over the configured background. With no background
    /// configured, the `fillPolicy` decides: `.opaqueDelivery` composites the
    /// frame over an opaque black canvas (the invariant that every output
    /// pixel is decided by the current frame — LF-ACTION-01);
    /// `.alphaPreserving` returns the frame unchanged so alpha-capable
    /// exports keep their transparency.
    public static func compose(
        frame: CIImage,
        over background: CanvasBackground?,
        renderSize: CGSize,
        fillPolicy: CanvasFillPolicy = .opaqueDelivery
    ) -> CIImage {
        guard background != nil else {
            if fillPolicy == .alphaPreserving {
                return frame
            }
            let canvasRect = CGRect(origin: .zero, size: renderSize)
            return frame
                .composited(over: solid(color: CIColor.black, in: canvasRect))
                .cropped(to: canvasRect)
        }

        let backgroundImage = backgroundImage(
            for: background,
            sourceFrame: frame,
            renderSize: renderSize
        )
        return frame.composited(over: backgroundImage)
    }

    /// Scales an image so it completely covers the target rect, centered, and
    /// crops the overflow.
    static func aspectFill(_ image: CIImage, into rect: CGRect) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, rect.width > 0, rect.height > 0 else {
            return image.cropped(to: rect)
        }

        let scale = max(rect.width / extent.width, rect.height / extent.height)
        let scaled = image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let offsetX = (rect.width - extent.width * scale) / 2
        let offsetY = (rect.height - extent.height * scale) / 2
        return scaled
            .transformed(by: CGAffineTransform(translationX: rect.minX + offsetX, y: rect.minY + offsetY))
            .cropped(to: rect)
    }

    static func ciColor(fromHex hex: String) -> CIColor? {
        guard let rgb = HexColorMath.rgb(fromHex: hex) else { return nil }
        return CIColor(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private static func solid(color: CIColor, in rect: CGRect) -> CIImage {
        CIImage(color: color).cropped(to: rect)
    }

    private static func cachedImage(at url: URL) -> CIImage? {
        if let cached = imageCache.object(forKey: url as NSURL) {
            return cached
        }
        guard let image = CIImage(contentsOf: url) else {
            return nil
        }
        imageCache.setObject(image, forKey: url as NSURL)
        return image
    }
}
