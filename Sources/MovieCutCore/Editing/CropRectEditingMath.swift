import Foundation

/// Pure geometry for the G-23 canvas crop editor. The editor overlays the
/// uncropped source frame with a crop window; every handle gesture reduces to
/// "move or resize a normalized rect, clamped to the unit frame, with an
/// optional aspect lock and a minimum size". Keeping the math here (rather
/// than in the view) makes the gesture behavior unit-testable and lets a
/// future iOS canvas crop editor reuse the exact same semantics.
public enum CropRectEditingMath {
    /// Smallest crop edge allowed, in normalized units of the source frame.
    /// Mirrors the mask canvas's minimum-size floor so a stray drag cannot
    /// collapse the window to a line.
    public static let minimumEdge: Double = 0.05

    /// Which handle of the crop window a gesture is dragging. Corners move two
    /// edges; edges move one; `.interior` moves the whole window.
    public enum Handle: CaseIterable, Sendable {
        case topLeft
        case top
        case topRight
        case right
        case bottomRight
        case bottom
        case bottomLeft
        case left
        case interior

        var movesLeadingEdge: Bool {
            self == .left || self == .topLeft || self == .bottomLeft
        }

        var movesTrailingEdge: Bool {
            self == .right || self == .topRight || self == .bottomRight
        }

        var movesTopEdge: Bool {
            self == .top || self == .topLeft || self == .topRight
        }

        var movesBottomEdge: Bool {
            self == .bottom || self == .bottomLeft || self == .bottomRight
        }
    }

    /// Moves `rect` by the normalized delta, keeping the whole window inside
    /// the unit frame (slides along the boundary instead of leaving it).
    public static func move(_ rect: NormalizedRect, dx: Double, dy: Double) -> NormalizedRect {
        let clampedX = min(max(rect.x + dx, 0), 1 - rect.width)
        let clampedY = min(max(rect.y + dy, 0), 1 - rect.height)
        return NormalizedRect(x: clampedX, y: clampedY, width: rect.width, height: rect.height)
            ?? rect
    }

    /// Resizes `rect` from `handle` by the normalized delta. The edge(s) the
    /// handle does not control stay anchored; the moving edge(s) are clamped
    /// to the unit frame and may not cross the anchor. When `aspect` is
    /// provided (the pixel aspect the crop must keep, e.g. the canvas ratio)
    /// the resize is aspect-locked: the gesture's dominant axis picks the
    /// size and the other axis is derived, then both are clamped to the frame
    /// so the locked rect stays fully inside the source.
    public static func resize(
        _ rect: NormalizedRect,
        from handle: Handle,
        dx: Double,
        dy: Double,
        aspect: Double? = nil
    ) -> NormalizedRect {
        guard handle != .interior else {
            return move(rect, dx: dx, dy: dy)
        }

        // Anchor bounds: the span each axis may occupy. For a leading/top
        // handle the trailing/bottom edge is fixed; for a trailing/bottom
        // handle the leading/top edge is fixed; a perpendicular handle locks
        // the axis entirely.
        let maxWidth: Double
        if handle.movesLeadingEdge {
            maxWidth = rect.maxX
        } else if handle.movesTrailingEdge {
            maxWidth = 1 - rect.x
        } else {
            maxWidth = rect.width
        }

        let maxHeight: Double
        if handle.movesTopEdge {
            maxHeight = rect.maxY
        } else if handle.movesBottomEdge {
            maxHeight = 1 - rect.y
        } else {
            maxHeight = rect.height
        }

        var width = min(max(rect.width + resizeWidthDelta(handle, dx: dx), 0), maxWidth)
        var height = min(max(rect.height + resizeHeightDelta(handle, dy: dy), 0), maxHeight)

        if let aspect, aspect.isFinite, aspect > 0, width > 0, height > 0 {
            // The dominant axis follows the gesture; the other is derived.
            // Left/right handles drag the X axis (width drives), top/bottom
            // drag the Y axis (height drives), corners keep whichever axis
            // moved farther from the anchor.
            let prefersWidth: Bool
            switch handle {
            case .left, .right:
                prefersWidth = true
            case .top, .bottom:
                prefersWidth = false
            default:
                let widthChange = abs((width - rect.width) * aspect)
                let heightChange = abs(height - rect.height)
                prefersWidth = widthChange >= heightChange
            }

            if prefersWidth {
                height = width / aspect
                if height > maxHeight {
                    height = maxHeight
                    width = height * aspect
                }
            } else {
                width = height * aspect
                if width > maxWidth {
                    width = maxWidth
                    height = width / aspect
                }
            }
        }

        // Minimum-size floor, clamped to whatever room the frame actually has.
        let floorWidth = min(minimumEdge, maxWidth)
        let floorHeight = min(minimumEdge, maxHeight)
        width = max(width, floorWidth)
        height = max(height, floorHeight)

        let minX = handle.movesLeadingEdge ? rect.maxX - width : rect.x
        let minY = handle.movesTopEdge ? rect.maxY - height : rect.y

        return NormalizedRect(x: minX, y: minY, width: width, height: height)
            ?? rect
    }

    private static func resizeWidthDelta(_ handle: Handle, dx: Double) -> Double {
        if handle.movesLeadingEdge { return -dx }
        if handle.movesTrailingEdge { return dx }
        return 0
    }

    private static func resizeHeightDelta(_ handle: Handle, dy: Double) -> Double {
        if handle.movesTopEdge { return -dy }
        if handle.movesBottomEdge { return dy }
        return 0
    }
}
