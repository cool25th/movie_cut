import CoreGraphics
import Foundation

/// Deterministic geometry helpers shared by the card canvas, commands, and
/// save/reload verification. Persisted normalized coordinates remain the source
/// of truth; pixel rectangles are transient presentation values.
public enum CardLayout {
    /// Canonical export size for each G-18 card format.
    public static func pixelSize(for format: CardFormat) -> CGSize {
        switch format {
        case .square:
            CGSize(width: 1080, height: 1080)
        case .portrait:
            CGSize(width: 1080, height: 1350)
        case .story:
            CGSize(width: 1080, height: 1920)
        }
    }

    /// Aspect ratio used to fit the real card canvas into its available view.
    public static func aspectRatio(for format: CardFormat) -> CGFloat {
        let size = pixelSize(for: format)
        return size.width / size.height
    }

    /// Converts a persisted normalized frame into transient canvas pixels.
    public static func pixelRect(for frame: NormalizedRect, in canvasSize: CGSize) -> CGRect {
        CGRect(
            x: frame.x * canvasSize.width,
            y: frame.y * canvasSize.height,
            width: frame.width * canvasSize.width,
            height: frame.height * canvasSize.height
        )
    }

    /// Converts a pixel rectangle back into a valid, in-bounds normalized
    /// rectangle. Out-of-bounds input is clamped rather than persisted invalidly.
    public static func normalizedRect(from pixelRect: CGRect, in canvasSize: CGSize) -> NormalizedRect? {
        guard canvasSize.width.isFinite, canvasSize.height.isFinite,
              canvasSize.width > 0, canvasSize.height > 0,
              pixelRect.origin.x.isFinite, pixelRect.origin.y.isFinite,
              pixelRect.width.isFinite, pixelRect.height.isFinite else {
            return nil
        }

        return clampedRect(
            x: pixelRect.minX / canvasSize.width,
            y: pixelRect.minY / canvasSize.height,
            width: pixelRect.width / canvasSize.width,
            height: pixelRect.height / canvasSize.height
        )
    }

    /// Moves a frame by a normalized delta while preserving size and keeping it
    /// fully inside the canvas.
    public static func moving(
        _ frame: NormalizedRect,
        deltaX: Double,
        deltaY: Double
    ) -> NormalizedRect {
        let x = min(max(0, frame.x + finiteOrZero(deltaX)), 1 - frame.width)
        let y = min(max(0, frame.y + finiteOrZero(deltaY)), 1 - frame.height)
        return NormalizedRect(x: x, y: y, width: frame.width, height: frame.height)!
    }

    /// Resizes from the bottom-trailing corner while retaining the leading/top
    /// anchor and enforcing a discoverable, non-zero minimum hit target.
    public static func resizing(
        _ frame: NormalizedRect,
        deltaWidth: Double,
        deltaHeight: Double,
        minimumSize: Double = 0.04
    ) -> NormalizedRect {
        let minimum = min(max(finiteOrZero(minimumSize), 0.001), 1)
        let width = min(max(minimum, frame.width + finiteOrZero(deltaWidth)), 1 - frame.x)
        let height = min(max(minimum, frame.height + finiteOrZero(deltaHeight)), 1 - frame.y)
        return NormalizedRect(x: frame.x, y: frame.y, width: width, height: height)!
    }

    private static func clampedRect(
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> NormalizedRect {
        let safeWidth = min(max(0, width), 1)
        let safeHeight = min(max(0, height), 1)
        let safeX = min(max(0, x), 1 - safeWidth)
        let safeY = min(max(0, y), 1 - safeHeight)
        return NormalizedRect(x: safeX, y: safeY, width: safeWidth, height: safeHeight)!
    }

    private static func finiteOrZero(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }
}
