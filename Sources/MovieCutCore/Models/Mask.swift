import CoreGraphics
import Foundation

public enum MaskShape: String, Codable, Sendable, CaseIterable {
    case rectangle
    case ellipse
    case triangle
    case diamond
    case linear
    case brush
}

public struct Mask: Codable, Sendable, Equatable {
    public var shape: MaskShape
    public var position: CGPoint
    public var size: CGSize
    public var rotation: Double
    public var feather: Double
    public var inverted: Bool
    public var brushPoints: [CGPoint]

    public init(
        shape: MaskShape,
        position: CGPoint,
        size: CGSize,
        rotation: Double = 0,
        feather: Double = 0,
        inverted: Bool = false,
        brushPoints: [CGPoint] = []
    ) {
        self.shape = shape
        self.position = position
        self.size = size
        self.rotation = rotation
        self.feather = feather
        self.inverted = inverted
        self.brushPoints = brushPoints
    }
}
