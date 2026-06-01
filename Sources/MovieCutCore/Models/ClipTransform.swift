import Foundation

/// Position, scale, and rotation settings applied to a timeline clip.
public struct ClipTransform: Codable, Sendable, Equatable {
    /// The clip's canvas position.
    public var position: CGPoint

    /// Additional offset applied after positioning.
    public var offset: CGPoint

    /// The horizontal and vertical scale factors.
    public var scale: CGSize

    /// The rotation angle in degrees.
    public var rotation: Double

    /// The normalized transform anchor point.
    public var anchorPoint: CGPoint

    /// Creates a clip transform.
    public init(
        position: CGPoint = .zero,
        offset: CGPoint = .zero,
        scale: CGSize = CGSize(width: 1, height: 1),
        rotation: Double = 0,
        anchorPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    ) {
        self.position = position
        self.offset = offset
        self.scale = scale
        self.rotation = rotation
        self.anchorPoint = anchorPoint
    }
}
