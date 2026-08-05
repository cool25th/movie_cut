import CoreGraphics
import Foundation

public enum MaskShape: String, Codable, Sendable, CaseIterable {
    case rectangle
    case ellipse
    case triangle
    case diamond
    case linear
    case brush

    /// SF Symbol name for this shape, shared by the Mac and iOS mask canvases.
    public var systemImage: String {
        switch self {
        case .rectangle:
            return "rectangle"
        case .ellipse:
            return "circle"
        case .triangle:
            return "triangle"
        case .diamond:
            return "diamond"
        case .linear:
            return "line.diagonal"
        case .brush:
            return "paintbrush"
        }
    }
}

/// A corner of a mask's resize handles, shared by the Mac and iOS mask canvases.
public enum MaskCorner: CaseIterable, Sendable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft

    public var xSign: CGFloat {
        switch self {
        case .topLeft, .bottomLeft:
            return -1
        case .topRight, .bottomRight:
            return 1
        }
    }

    public var ySign: CGFloat {
        switch self {
        case .topLeft, .topRight:
            return 1
        case .bottomRight, .bottomLeft:
            return -1
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .topLeft:
            return "Top left resize handle"
        case .topRight:
            return "Top right resize handle"
        case .bottomRight:
            return "Bottom right resize handle"
        case .bottomLeft:
            return "Bottom left resize handle"
        }
    }
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
