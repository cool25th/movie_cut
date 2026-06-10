import CoreGraphics
import CoreImage
import Foundation

/// Applies built-in two-source transition effects to Core Image frames.
public enum TransitionPixelProcessor {
    /// Applies a transition from the outgoing image to the incoming image.
    ///
    /// The returned image always uses the outgoing image extent. `progress` is clamped to `0...1`.
    public static func apply(
        type: TransitionType,
        from outgoing: CIImage,
        to incoming: CIImage,
        progress: Double
    ) -> CIImage {
        let extent = outgoing.extent
        guard !extent.isEmpty else { return outgoing }

        let progress = clamped(progress)
        let outgoing = outgoing.cropped(to: extent)
        let incoming = incoming.cropped(to: extent)

        let output: CIImage
        switch type {
        case .none:
            output = progress < 1 ? outgoing : incoming
        case .crossDissolve:
            output = dissolve(from: outgoing, to: incoming, progress: progress, in: extent)
        case .fadeThroughBlack:
            output = fadeThroughBlack(from: outgoing, to: incoming, progress: progress, in: extent)
        case .wipeRight:
            output = wipe(from: outgoing, to: incoming, progress: progress, direction: .right, in: extent)
        case .wipeLeft:
            output = wipe(from: outgoing, to: incoming, progress: progress, direction: .left, in: extent)
        case .wipeUp:
            output = wipe(from: outgoing, to: incoming, progress: progress, direction: .up, in: extent)
        case .wipeDown:
            output = wipe(from: outgoing, to: incoming, progress: progress, direction: .down, in: extent)
        case .slideLeft:
            output = slide(from: outgoing, to: incoming, progress: progress, direction: .left, in: extent)
        case .slideRight:
            output = slide(from: outgoing, to: incoming, progress: progress, direction: .right, in: extent)
        case .zoomIn:
            output = zoomIn(from: outgoing, to: incoming, progress: progress, in: extent)
        case .zoomOut:
            output = zoomOut(from: outgoing, to: incoming, progress: progress, in: extent)
        case .glitch:
            output = glitch(from: outgoing, to: incoming, progress: progress, in: extent)
        }

        return output.cropped(to: extent)
    }

    private enum Direction {
        case left
        case right
        case up
        case down
    }

    private static func clamped(_ progress: Double) -> Double {
        min(max(progress.isFinite ? progress : 0, 0), 1)
    }

    private static func dissolve(
        from outgoing: CIImage,
        to incoming: CIImage,
        progress: Double,
        in extent: CGRect
    ) -> CIImage {
        guard progress > 0 else { return outgoing }
        guard progress < 1 else { return incoming }

        return blend(top: incoming, over: outgoing, alpha: progress, in: extent)
    }

    private static func fadeThroughBlack(
        from outgoing: CIImage,
        to incoming: CIImage,
        progress: Double,
        in extent: CGRect
    ) -> CIImage {
        let black = CIImage(color: CIColor.black).cropped(to: extent)

        if progress < 0.5 {
            return blend(top: black, over: outgoing, alpha: progress * 2, in: extent)
        }

        return blend(top: incoming, over: black, alpha: (progress - 0.5) * 2, in: extent)
    }

    private static func wipe(
        from outgoing: CIImage,
        to incoming: CIImage,
        progress: Double,
        direction: Direction,
        in extent: CGRect
    ) -> CIImage {
        guard progress > 0 else { return outgoing }
        guard progress < 1 else { return incoming }

        let progress = CGFloat(progress)
        let revealRect: CGRect
        switch direction {
        case .right:
            revealRect = CGRect(
                x: extent.minX,
                y: extent.minY,
                width: extent.width * progress,
                height: extent.height
            )
        case .left:
            let width = extent.width * progress
            revealRect = CGRect(
                x: extent.maxX - width,
                y: extent.minY,
                width: width,
                height: extent.height
            )
        case .up:
            revealRect = CGRect(
                x: extent.minX,
                y: extent.minY,
                width: extent.width,
                height: extent.height * progress
            )
        case .down:
            let height = extent.height * progress
            revealRect = CGRect(
                x: extent.minX,
                y: extent.maxY - height,
                width: extent.width,
                height: height
            )
        }

        return incoming
            .cropped(to: revealRect)
            .composited(over: outgoing)
            .cropped(to: extent)
    }

    private static func slide(
        from outgoing: CIImage,
        to incoming: CIImage,
        progress: Double,
        direction: Direction,
        in extent: CGRect
    ) -> CIImage {
        guard progress > 0 else { return outgoing }
        guard progress < 1 else { return incoming }

        let progress = CGFloat(progress)
        let width = extent.width
        let outgoingOffset: CGFloat
        let incomingOffset: CGFloat

        switch direction {
        case .left:
            outgoingOffset = -width * progress
            incomingOffset = width * (1 - progress)
        case .right:
            outgoingOffset = width * progress
            incomingOffset = -width * (1 - progress)
        case .up, .down:
            outgoingOffset = 0
            incomingOffset = 0
        }

        let movedOutgoing = outgoing
            .transformed(by: CGAffineTransform(translationX: outgoingOffset, y: 0))
            .cropped(to: extent)
        let movedIncoming = incoming
            .transformed(by: CGAffineTransform(translationX: incomingOffset, y: 0))
            .cropped(to: extent)

        return movedIncoming
            .composited(over: movedOutgoing)
            .cropped(to: extent)
    }

    private static func zoomIn(
        from outgoing: CIImage,
        to incoming: CIImage,
        progress: Double,
        in extent: CGRect
    ) -> CIImage {
        guard progress > 0 else { return outgoing }
        guard progress < 1 else { return incoming }

        let scaleFactor = 0.82 + (0.18 * progress)
        let zoomedIncoming = scaled(incoming, by: scaleFactor, around: extent.center)
            .cropped(to: extent)
        return blend(top: zoomedIncoming, over: outgoing, alpha: progress, in: extent)
    }

    private static func zoomOut(
        from outgoing: CIImage,
        to incoming: CIImage,
        progress: Double,
        in extent: CGRect
    ) -> CIImage {
        guard progress > 0 else { return outgoing }
        guard progress < 1 else { return incoming }

        let scaleFactor = 1 - (0.18 * progress)
        let zoomedOutgoing = scaled(outgoing, by: scaleFactor, around: extent.center)
            .cropped(to: extent)
        return blend(top: zoomedOutgoing, over: incoming, alpha: 1 - progress, in: extent)
    }

    private static func glitch(
        from outgoing: CIImage,
        to incoming: CIImage,
        progress: Double,
        in extent: CGRect
    ) -> CIImage {
        guard progress > 0 else { return outgoing }
        guard progress < 1 else { return incoming }

        let bandCount = 8
        let bandHeight = extent.height / CGFloat(bandCount)
        let peak = sin(progress * .pi)
        let maxOffset = extent.width * CGFloat(0.25 * peak)
        var glitchedIncoming = CIImage(color: CIColor.clear).cropped(to: extent)

        for band in 0..<bandCount {
            let y = extent.minY + CGFloat(band) * bandHeight
            let height = band == bandCount - 1 ? extent.maxY - y : bandHeight
            let pattern = Double(((band * 37) % 7) - 3) / 3.0
            let progressBias = ((band % 2 == 0) ? 1.0 : -1.0) * (progress - 0.5)
            let offset = CGFloat(pattern + progressBias) * maxOffset
            let bandRect = CGRect(x: extent.minX, y: y, width: extent.width, height: height)
            let strip = incoming
                .cropped(to: bandRect)
                .transformed(by: CGAffineTransform(translationX: offset, y: 0))
                .cropped(to: extent)
            glitchedIncoming = strip.composited(over: glitchedIncoming)
        }

        return blend(top: glitchedIncoming, over: outgoing, alpha: progress, in: extent)
    }

    private static func blend(
        top: CIImage,
        over background: CIImage,
        alpha: Double,
        in extent: CGRect
    ) -> CIImage {
        guard alpha > 0 else { return background.cropped(to: extent) }
        guard alpha < 1 else { return top.cropped(to: extent) }

        return background
            .cropped(to: extent)
            .applyingFilter(
                "CIDissolveTransition",
                parameters: [
                    kCIInputTargetImageKey: top.cropped(to: extent),
                    kCIInputTimeKey: alpha
                ]
            )
            .cropped(to: extent)
    }

    private static func scaled(_ image: CIImage, by scale: Double, around center: CGPoint) -> CIImage {
        image.transformed(
            by: CGAffineTransform(translationX: center.x, y: center.y)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -center.x, y: -center.y)
        )
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
