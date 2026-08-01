import CoreGraphics
import Foundation

/// Canvas overlay alignment axes used by multi-select alignment operations.
public enum CanvasOverlayAlignment: Sendable {
    case leading
    case centerX
    case trailing
    case top
    case centerY
    case bottom
}

/// Pure canvas / overlay geometry math shared by the Mac and iOS editors.
///
/// Every member is a pure function of its arguments — there is no project or
/// view-model state. The Mac `EditorViewModel` and iOS view layer supply the
/// canvas size (or `Project`) at the call site.
public enum CanvasGeometry {
    /// The effective render/edit canvas size, preferring a timeline override
    /// and falling back to the project's canvas preset size.
    public static func effectiveCanvasSize(in project: Project) -> CGSize {
        let timelineSize = project.timeline.canvasSize
        if timelineSize.width > 0, timelineSize.height > 0 {
            return timelineSize
        }

        return project.canvas.size
    }

    /// The geometric center of a canvas size, or zero when the size is empty.
    public static func canvasCenter(in canvasSize: CGSize) -> CGPoint {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return CGPoint(x: 0, y: 0)
        }

        return CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
    }

    /// The social-platform "safe area" rect inset from the canvas edges so
    /// overlays avoid UI chrome on portrait/landscape social targets.
    public static func socialSafeAreaRect(in canvasSize: CGSize) -> CGRect {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return CGRect(x: 0, y: 0, width: 0, height: 0)
        }

        let horizontalInset = canvasSize.width * 0.12
        let verticalInset = canvasSize.height * 0.18
        return CGRect(origin: CGPoint(x: 0, y: 0), size: canvasSize)
            .insetBy(dx: horizontalInset, dy: verticalInset)
    }

    /// Resolves a clip's effective transform position, defaulting an unset
    /// (zero) position to the text-content position or the canvas center.
    public static func resolvedCanvasOverlayTransform(
        for clip: Clip,
        fallbackCenter: CGPoint
    ) -> ClipTransform {
        var transform = clip.transform
        guard isZeroPoint(transform.position) else {
            return transform
        }

        if let textContent = clip.textContent, !isZeroPoint(textContent.position) {
            transform.position = textContent.position
        } else {
            transform.position = fallbackCenter
        }

        return transform
    }

    /// The visual center of a clip's transform (position + offset).
    public static func canvasOverlayVisualCenter(
        for clip: Clip,
        fallbackCenter: CGPoint
    ) -> CGPoint {
        let transform = resolvedCanvasOverlayTransform(for: clip, fallbackCenter: fallbackCenter)
        return CGPoint(
            x: transform.position.x + transform.offset.x,
            y: transform.position.y + transform.offset.y
        )
    }

    /// The bounding-box center of a set of points, falling back to
    /// `fallbackCenter` when the set is empty.
    public static func boundingCenter(for points: [CGPoint], fallback: CGPoint) -> CGPoint {
        guard let first = points.first else {
            return fallback
        }

        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y

        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        return CGPoint(x: (minX + maxX) * 0.5, y: (minY + maxY) * 0.5)
    }

    /// The alignment target coordinate for the given alignment and centers.
    /// When `isMultiple` is false, single-selection snaps to the safe area.
    public static func alignmentTarget(
        for alignment: CanvasOverlayAlignment,
        centers: [CGPoint],
        canvasSize: CGSize,
        isMultiple: Bool
    ) -> CGFloat {
        guard isMultiple, let first = centers.first else {
            let safeRect = socialSafeAreaRect(in: canvasSize)
            switch alignment {
            case .leading:
                return safeRect.minX
            case .centerX:
                return canvasSize.width * 0.5
            case .trailing:
                return safeRect.maxX
            case .top:
                return safeRect.maxY
            case .centerY:
                return canvasSize.height * 0.5
            case .bottom:
                return safeRect.minY
            }
        }

        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y

        for center in centers.dropFirst() {
            minX = min(minX, center.x)
            maxX = max(maxX, center.x)
            minY = min(minY, center.y)
            maxY = max(maxY, center.y)
        }

        switch alignment {
        case .leading:
            return minX
        case .centerX:
            return (minX + maxX) * 0.5
        case .trailing:
            return maxX
        case .top:
            return maxY
        case .centerY:
            return (minY + maxY) * 0.5
        case .bottom:
            return minY
        }
    }

    /// Clamps a point to the canvas bounds [0, canvasSize].
    public static func clampedCanvasPoint(_ point: CGPoint, canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), canvasSize.width),
            y: min(max(point.y, 0), canvasSize.height)
        )
    }

    /// True when a point is at (or near) the origin.
    public static func isZeroPoint(_ point: CGPoint) -> Bool {
        pointsEqual(point, CGPoint(x: 0, y: 0))
    }

    /// Returns the point unless it is the origin, in which case `nil`.
    public static func nonZeroPoint(_ point: CGPoint) -> CGPoint? {
        pointsEqual(point, CGPoint(x: 0, y: 0)) ? nil : point
    }

    /// Approximate point equality (within 1e-9) for transform-position bookkeeping.
    public static func pointsEqual(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) <= 1.0e-9 && abs(lhs.y - rhs.y) <= 1.0e-9
    }

    /// Scales a 1920×1080-normalized template position into the canvas size,
    /// defaulting an unset (zero) position to the canvas center.
    public static func scaledTemplatePosition(_ position: CGPoint, in canvasSize: CGSize) -> CGPoint {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return position
        }

        if abs(position.x) <= 1.0e-9 && abs(position.y) <= 1.0e-9 {
            return CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
        }

        return CGPoint(
            x: position.x / 1920 * canvasSize.width,
            y: position.y / 1080 * canvasSize.height
        )
    }

    /// A deterministic placement (corner anchor + scales) for a sticker,
    /// cycling through four positions so repeated drops don't stack.
    public static func defaultStickerPlacement(
        for sticker: StickerAsset
    ) -> (xRatio: CGFloat, yRatio: CGFloat, fontScale: Double, transformScale: CGFloat) {
        let builtInStickers = StickerLibrary.builtIn().stickers
        let stickerIndex = builtInStickers.firstIndex {
            $0.id == sticker.id || ($0.name == sticker.name && $0.emoji == sticker.emoji)
        } ?? 0
        let placements: [(xRatio: CGFloat, yRatio: CGFloat, fontScale: Double, transformScale: CGFloat)] = [
            (0.78, 0.32, 0.12, 1.00),
            (0.24, 0.30, 0.11, 0.95),
            (0.72, 0.68, 0.13, 1.08),
            (0.30, 0.70, 0.10, 0.92)
        ]

        return placements[stickerIndex % placements.count]
    }
}
