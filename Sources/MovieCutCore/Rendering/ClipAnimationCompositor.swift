import CoreGraphics
import CoreImage
import Foundation

/// Snapshot of a clip's animated transform and opacity at a composition frame.
public struct CustomCompositionAnimationState: Sendable {
    public let transform: ClipTransform
    public let opacity: Double

    public init(transform: ClipTransform, opacity: Double) {
        self.transform = transform
        self.opacity = opacity
    }
}

/// Clip transform/opacity composition shared by the Mac and iOS video compositors.
///
/// Both compositors kept byte-identical copies of `apply(animationState:to:renderSize:)`,
/// `affineTransform(for:canvasSize:)`, and `isIdentityTransform(_:)`. These touch
/// only CoreImage + the core `ClipTransform` model, so they live here once.
public enum ClipAnimationCompositor {
    /// Applies the animated transform (if non-identity) and opacity to `image`,
    /// compositing the result over a clear background cropped to `renderSize`.
    public static func apply(
        animationState: CustomCompositionAnimationState,
        to image: CIImage,
        renderSize: CGSize
    ) -> CIImage {
        let renderBounds = CGRect(x: 0, y: 0, width: renderSize.width, height: renderSize.height)
        var animatedImage = image

        if !isIdentityTransform(animationState.transform) {
            animatedImage = animatedImage.transformed(
                by: affineTransform(for: animationState.transform, canvasSize: renderSize)
            )
        }

        let opacity = min(max(animationState.opacity, 0), 1)
        if opacity < 1 {
            animatedImage = animatedImage.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)
                ]
            )
        }

        return animatedImage
            .composited(over: CIImage(color: .clear).cropped(to: renderBounds))
            .cropped(to: renderBounds)
    }

    /// Builds the affine transform for a clip relative to `canvasSize`,
    /// accounting for position, offset, rotation, scale, and anchor point.
    public static func affineTransform(for transform: ClipTransform, canvasSize: CGSize) -> CGAffineTransform {
        let anchorPoint = CGPoint(
            x: canvasSize.width * transform.anchorPoint.x,
            y: canvasSize.height * transform.anchorPoint.y
        )
        let radians = CGFloat(transform.rotation * .pi / 180)

        var affineTransform = CGAffineTransform.identity
        affineTransform = affineTransform.translatedBy(
            x: transform.position.x + transform.offset.x,
            y: transform.position.y + transform.offset.y
        )
        affineTransform = affineTransform.translatedBy(x: anchorPoint.x, y: anchorPoint.y)
        affineTransform = affineTransform.rotated(by: radians)
        affineTransform = affineTransform.scaledBy(
            x: transform.scale.width,
            y: transform.scale.height
        )
        affineTransform = affineTransform.translatedBy(x: -anchorPoint.x, y: -anchorPoint.y)
        return affineTransform
    }

    /// Whether `transform` has no visible effect (all fields at identity).
    public static func isIdentityTransform(_ transform: ClipTransform) -> Bool {
        abs(transform.position.x) <= 1.0e-9
            && abs(transform.position.y) <= 1.0e-9
            && abs(transform.offset.x) <= 1.0e-9
            && abs(transform.offset.y) <= 1.0e-9
            && abs(transform.scale.width - 1) <= 1.0e-9
            && abs(transform.scale.height - 1) <= 1.0e-9
            && abs(transform.rotation) <= 1.0e-9
    }
}
