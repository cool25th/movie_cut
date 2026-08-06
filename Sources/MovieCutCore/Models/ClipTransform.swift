import CoreGraphics
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

/// The reference size a clip transform's normalized anchor point resolves
/// against. Preview and export historically computed the anchor against
/// DIFFERENT sizes (source frame vs canvas), which produced different pixels for
/// the same transform. This enum makes that choice explicit at the call site so
/// both engines resolve it deliberately through the shared
/// ``ClipTransform/affineTransform(for:anchorSize:base:)`` helper.
public enum ClipTransformAnchor {
    /// Anchor is resolved against the source frame's pixel dimensions, and the
    /// source's `preferredTransform` (rotation/flip metadata) is composed in as
    /// the base. This is the preview path's convention.
    case sourceFrame(preferredTransform: CGAffineTransform, size: CGSize)
    /// Anchor is resolved against the project canvas size, with an identity
    /// base. This is the export path's convention.
    case canvas(size: CGSize)
}

public extension ClipTransform {
    /// Whether this transform has no visible effect (identity position/offset,
    /// unit scale, zero rotation). Uses epsilon comparisons for robustness
    /// against accumulated float error; this supersedes the two drifted private
    /// copies (`point.x == 0` in preview vs `abs(x) <= 1e-9` in export) that
    /// disagreed on the boundary.
    var isIdentity: Bool {
        abs(position.x) <= 1.0e-9
            && abs(position.y) <= 1.0e-9
            && abs(offset.x) <= 1.0e-9
            && abs(offset.y) <= 1.0e-9
            && abs(scale.width - 1) <= 1.0e-9
            && abs(scale.height - 1) <= 1.0e-9
            && abs(rotation) <= 1.0e-9
    }

    /// Builds the affine transform for this clip, with an explicit anchor
    /// reference so preview and export compute it identically when given the
    /// same anchor.
    ///
    /// The transform order is: base → position+offset → anchor → rotate → scale
    /// → unanchor. This matches the historical preview/export behavior; the
    /// helper merely consolidates the two duplicated implementations into one
    /// so they cannot silently drift apart again.
    func affineTransform(for anchor: ClipTransformAnchor) -> CGAffineTransform {
        let anchorSize: CGSize
        var base: CGAffineTransform
        switch anchor {
        case let .sourceFrame(preferredTransform, size):
            anchorSize = size
            base = preferredTransform
        case let .canvas(size):
            anchorSize = size
            base = .identity
        }

        let anchorPoint = CGPoint(
            x: anchorSize.width * anchorPoint.x,
            y: anchorSize.height * anchorPoint.y
        )
        let radians = CGFloat(rotation * .pi / 180)

        base = base.translatedBy(x: position.x + offset.x, y: position.y + offset.y)
        base = base.translatedBy(x: anchorPoint.x, y: anchorPoint.y)
        base = base.rotated(by: radians)
        base = base.scaledBy(x: scale.width, y: scale.height)
        base = base.translatedBy(x: -anchorPoint.x, y: -anchorPoint.y)
        return base
    }
}
