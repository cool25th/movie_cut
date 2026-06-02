#if canImport(UIKit)
import SwiftUI
import UIKit

/// A transient transform derived from touch gestures.
public struct GestureTransform: Sendable {
    /// Translation in canvas points.
    public var translation: CGSize

    /// Uniform gesture scale multiplier.
    public var scale: CGFloat

    /// Gesture rotation.
    public var rotation: Angle

    /// Creates a gesture transform.
    public init(
        translation: CGSize = .zero,
        scale: CGFloat = 1,
        rotation: Angle = .zero
    ) {
        self.translation = translation
        self.scale = scale
        self.rotation = rotation
    }

    /// The identity gesture transform.
    public static var identity: GestureTransform {
        GestureTransform()
    }

    /// Applies the gesture values to a persistent clip transform.
    public func applied(to transform: ClipTransform) -> ClipTransform {
        var updatedTransform = transform
        updatedTransform.position = CGPoint(
            x: transform.position.x + translation.width,
            y: transform.position.y + translation.height
        )
        updatedTransform.scale = CGSize(
            width: transform.scale.width * scale,
            height: transform.scale.height * scale
        )
        updatedTransform.rotation = transform.rotation + rotation.degrees
        return updatedTransform
    }
}
#endif
