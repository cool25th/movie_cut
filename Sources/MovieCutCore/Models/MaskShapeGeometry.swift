import CoreGraphics

/// Pure mask shape geometry shared by the Mac and iOS mask canvases.
///
/// Both apps kept near-verbatim copies of the shape-point generators and
/// rotation/offset math. These touch only CoreGraphics + the core `Mask`
/// model, so they live here once. Each canvas keeps the handle-sizing and
/// view-coordinate mapping that genuinely differs per platform.
public enum MaskShapeGeometry {
    /// Rectangle outline points in mask-local space, then rotated/translated to the mask position.
    public static func rectanglePoints(for currentMask: Mask) -> [CGPoint] {
        let halfWidth = max(currentMask.size.width * 0.5, 1)
        let halfHeight = max(currentMask.size.height * 0.5, 1)
        return transformed(
            [
                CGPoint(x: -halfWidth, y: halfHeight),
                CGPoint(x: halfWidth, y: halfHeight),
                CGPoint(x: halfWidth, y: -halfHeight),
                CGPoint(x: -halfWidth, y: -halfHeight)
            ],
            for: currentMask
        )
    }

    /// Ellipse outline points (72 samples) in mask-local space, then placed at the mask position.
    public static func ellipsePoints(for currentMask: Mask) -> [CGPoint] {
        let halfWidth = max(currentMask.size.width * 0.5, 1)
        let halfHeight = max(currentMask.size.height * 0.5, 1)
        let sampleCount = 72

        return transformed(
            (0 ..< sampleCount).map { index in
                let angle = (CGFloat(index) / CGFloat(sampleCount)) * 2 * .pi
                return CGPoint(x: cos(angle) * halfWidth, y: sin(angle) * halfHeight)
            },
            for: currentMask
        )
    }

    /// Triangle outline points, then placed at the mask position.
    public static func trianglePoints(for currentMask: Mask) -> [CGPoint] {
        let halfWidth = max(currentMask.size.width * 0.5, 1)
        let halfHeight = max(currentMask.size.height * 0.5, 1)
        return transformed(
            [
                CGPoint(x: 0, y: halfHeight),
                CGPoint(x: -halfWidth, y: -halfHeight),
                CGPoint(x: halfWidth, y: -halfHeight)
            ],
            for: currentMask
        )
    }

    /// Diamond outline points, then placed at the mask position.
    public static func diamondPoints(for currentMask: Mask) -> [CGPoint] {
        let halfWidth = max(currentMask.size.width * 0.5, 1)
        let halfHeight = max(currentMask.size.height * 0.5, 1)
        return transformed(
            [
                CGPoint(x: 0, y: halfHeight),
                CGPoint(x: halfWidth, y: 0),
                CGPoint(x: 0, y: -halfHeight),
                CGPoint(x: -halfWidth, y: 0)
            ],
            for: currentMask
        )
    }

    /// Brush points for the mask: the stored points when present, otherwise a default horizontal pair.
    public static func brushPoints(for currentMask: Mask) -> [CGPoint] {
        if currentMask.brushPoints.count > 1 {
            return currentMask.brushPoints
        }
        let halfWidth = max(currentMask.size.width * 0.5, 1)
        return [
            CGPoint(x: currentMask.position.x - halfWidth, y: currentMask.position.y),
            CGPoint(x: currentMask.position.x + halfWidth, y: currentMask.position.y)
        ]
    }

    /// Rotates local points by the mask's rotation and translates them to the mask position.
    public static func transformed(_ localPoints: [CGPoint], for currentMask: Mask) -> [CGPoint] {
        localPoints.map { point in
            let rotated = rotate(CGVector(dx: point.x, dy: point.y), degrees: currentMask.rotation)
            return CGPoint(
                x: currentMask.position.x + rotated.dx,
                y: currentMask.position.y + rotated.dy
            )
        }
    }

    /// Rotates a vector by `degrees` (clockwise in a y-down coordinate space).
    public static func rotate(_ vector: CGVector, degrees: Double) -> CGVector {
        let angle = CGFloat(degrees) * .pi / 180
        let cosine = cos(angle)
        let sine = sin(angle)
        return CGVector(
            dx: vector.dx * cosine - vector.dy * sine,
            dy: vector.dx * sine + vector.dy * cosine
        )
    }

    /// Rotates a vector by `-degrees`.
    public static func inverseRotate(_ vector: CGVector, degrees: Double) -> CGVector {
        rotate(vector, degrees: -degrees)
    }

    /// Rotates each point around `center` by `degrees`.
    public static func rotate(_ points: [CGPoint], degrees: Double, around center: CGPoint) -> [CGPoint] {
        points.map { point in
            let rotated = rotate(
                CGVector(dx: point.x - center.x, dy: point.y - center.y),
                degrees: degrees
            )
            return CGPoint(x: center.x + rotated.dx, y: center.y + rotated.dy)
        }
    }

    /// Translates each point by `delta`.
    public static func offset(_ points: [CGPoint], by delta: CGVector) -> [CGPoint] {
        points.map { point in
            CGPoint(x: point.x + delta.dx, y: point.y + delta.dy)
        }
    }

    /// Scales brush points around `center` from `oldSize` to `newSize`.
    public static func scaleBrushPoints(
        _ points: [CGPoint],
        around center: CGPoint,
        from oldSize: CGSize,
        to newSize: CGSize
    ) -> [CGPoint] {
        let scaleX = newSize.width / max(oldSize.width, 1)
        let scaleY = newSize.height / max(oldSize.height, 1)

        return points.map { point in
            CGPoint(
                x: center.x + ((point.x - center.x) * scaleX),
                y: center.y + ((point.y - center.y) * scaleY)
            )
        }
    }

    /// Wraps `degrees` into the -180...180 range.
    public static func normalizedDegrees(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 {
            value -= 360
        } else if value < -180 {
            value += 360
        }
        return value
    }
}
