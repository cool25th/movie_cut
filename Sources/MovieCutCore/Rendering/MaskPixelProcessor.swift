import CoreGraphics
import CoreImage
import Foundation

/// Applies clip masks to Core Image frames for preview and export.
public enum MaskPixelProcessor {
    /// Applies a mask in rendered image pixel coordinates, preserving the input extent.
    public static func apply(_ mask: Mask, to image: CIImage, at time: TimeInterval = 0) -> CIImage {
        _ = time

        let extent = image.extent
        guard !extent.isEmpty else { return image }

        var maskImage = makeMaskImage(for: mask, in: extent).cropped(to: extent)

        if mask.feather > 0 {
            maskImage = maskImage
                .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": mask.feather * 10])
                .cropped(to: extent)
        }

        if mask.inverted {
            maskImage = maskImage
                .applyingFilter("CIColorInvert")
                .cropped(to: extent)
        }

        let clear = CIImage(color: CIColor.clear).cropped(to: extent)
        let parameters: [String: Any] = [
            "inputBackgroundImage": clear,
            "inputMaskImage": maskImage
        ]

        return image
            .applyingFilter("CIBlendWithMask", parameters: parameters)
            .cropped(to: extent)
    }

    private static func makeMaskImage(for mask: Mask, in extent: CGRect) -> CIImage {
        switch mask.shape {
        case .rectangle:
            return rectangleMask(for: mask, in: extent)
        case .ellipse:
            return ellipseMask(for: mask, in: extent)
        case .triangle:
            return pathMask(points: trianglePoints(for: mask), in: extent)
        case .diamond:
            return pathMask(points: diamondPoints(for: mask), in: extent)
        case .linear:
            return linearMask(for: mask, in: extent)
        case .brush:
            return brushMask(for: mask, in: extent)
        }
    }

    private static func rectangleMask(for mask: Mask, in extent: CGRect) -> CIImage {
        let rect = CGRect(
            x: mask.position.x - mask.size.width * 0.5,
            y: mask.position.y - mask.size.height * 0.5,
            width: max(mask.size.width, 0),
            height: max(mask.size.height, 0)
        )
        let white = CIImage(color: CIColor.white).cropped(to: rect)
        let black = blackMask(in: extent)

        if mask.rotation == 0 {
            return white.composited(over: black).cropped(to: extent)
        }

        return white
            .transformed(by: rotationTransform(degrees: mask.rotation, around: mask.position))
            .composited(over: black)
            .cropped(to: extent)
    }

    private static func ellipseMask(for mask: Mask, in extent: CGRect) -> CIImage {
        let radiusX = max(mask.size.width * 0.5, 0.001)
        let radiusY = max(mask.size.height * 0.5, 0.001)
        let circle = CIFilter(
            name: "CIRadialGradient",
            parameters: [
                "inputCenter": CIVector(x: mask.position.x, y: mask.position.y),
                "inputRadius0": radiusX,
                "inputRadius1": radiusX + 0.001,
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.black
            ]
        )?.outputImage ?? blackMask(in: extent)

        let scaled = circle.transformed(
            by: CGAffineTransform(translationX: -mask.position.x, y: -mask.position.y)
                .scaledBy(x: 1, y: radiusY / radiusX)
                .translatedBy(x: mask.position.x, y: mask.position.y)
        )

        if mask.rotation == 0 {
            return scaled.cropped(to: extent)
        }

        return scaled
            .transformed(by: rotationTransform(degrees: mask.rotation, around: mask.position))
            .cropped(to: extent)
    }

    private static func linearMask(for mask: Mask, in extent: CGRect) -> CIImage {
        let height = max(mask.size.height, 1)
        let start = CGPoint(x: mask.position.x, y: mask.position.y + height * 0.5)
        let end = CGPoint(x: mask.position.x, y: mask.position.y - height * 0.5)
        let gradient = CIFilter(
            name: "CILinearGradient",
            parameters: [
                "inputPoint0": CIVector(cgPoint: start),
                "inputPoint1": CIVector(cgPoint: end),
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.black
            ]
        )?.outputImage ?? CIImage(color: CIColor.white)

        if mask.rotation == 0 {
            return gradient.cropped(to: extent)
        }

        return gradient
            .transformed(by: rotationTransform(degrees: mask.rotation, around: mask.position))
            .cropped(to: extent)
    }

    private static func brushMask(for mask: Mask, in extent: CGRect) -> CIImage {
        guard mask.brushPoints.count > 1 else {
            return blackMask(in: extent)
        }

        let lineWidth = max(min(mask.size.width, mask.size.height), 1)
        return drawMask(in: extent) { context in
            context.setStrokeColor(CGColor(gray: 1, alpha: 1))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setLineWidth(lineWidth)
            context.beginPath()
            context.move(to: mask.brushPoints[0])
            for point in mask.brushPoints.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()
        }
    }

    private static func pathMask(points: [CGPoint], in extent: CGRect) -> CIImage {
        drawMask(in: extent) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.beginPath()
            guard let first = points.first else { return }
            context.move(to: first)
            for point in points.dropFirst() {
                context.addLine(to: point)
            }
            context.closePath()
            context.fillPath()
        }
    }

    private static func trianglePoints(for mask: Mask) -> [CGPoint] {
        let halfWidth = mask.size.width * 0.5
        let halfHeight = mask.size.height * 0.5
        let points = [
            CGPoint(x: mask.position.x, y: mask.position.y + halfHeight),
            CGPoint(x: mask.position.x - halfWidth, y: mask.position.y - halfHeight),
            CGPoint(x: mask.position.x + halfWidth, y: mask.position.y - halfHeight)
        ]
        return rotate(points: points, degrees: mask.rotation, around: mask.position)
    }

    private static func diamondPoints(for mask: Mask) -> [CGPoint] {
        let halfWidth = mask.size.width * 0.5
        let halfHeight = mask.size.height * 0.5
        let points = [
            CGPoint(x: mask.position.x, y: mask.position.y + halfHeight),
            CGPoint(x: mask.position.x + halfWidth, y: mask.position.y),
            CGPoint(x: mask.position.x, y: mask.position.y - halfHeight),
            CGPoint(x: mask.position.x - halfWidth, y: mask.position.y)
        ]
        return rotate(points: points, degrees: mask.rotation, around: mask.position)
    }

    private static func drawMask(in extent: CGRect, drawing: (CGContext) -> Void) -> CIImage {
        let width = max(Int(ceil(extent.width)), 1)
        let height = max(Int(ceil(extent.height)), 1)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return blackMask(in: extent)
        }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: -extent.minX, y: -extent.minY)
        drawing(context)

        guard let image = context.makeImage() else {
            return blackMask(in: extent)
        }

        return CIImage(cgImage: image)
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
    }

    private static func blackMask(in extent: CGRect) -> CIImage {
        CIImage(color: CIColor.black).cropped(to: extent)
    }

    private static func rotate(points: [CGPoint], degrees: Double, around center: CGPoint) -> [CGPoint] {
        guard degrees != 0 else { return points }

        let angle = CGFloat(degrees * .pi / 180)
        let cosine = cos(angle)
        let sine = sin(angle)
        return points.map { point in
            let dx = point.x - center.x
            let dy = point.y - center.y
            return CGPoint(
                x: center.x + dx * cosine - dy * sine,
                y: center.y + dx * sine + dy * cosine
            )
        }
    }

    private static func rotationTransform(degrees: Double, around center: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: CGFloat(degrees * .pi / 180))
            .translatedBy(x: -center.x, y: -center.y)
    }
}
