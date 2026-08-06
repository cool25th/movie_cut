import CoreGraphics
import Foundation

/// A Ken Burns (pan-and-zoom) motion applied to a still image clip.
///
/// Unlike per-frame `ClipTransform` keyframes — which transform the
/// pre-rasterized, letterboxed image frame and reveal black when panning past
/// its edges — this effect is baked into the image-to-video rasterization
/// (`ImageVideoRenderService`) using an **aspect-fill** draw at each frame's
/// interpolated zoom level. That keeps pixels under the pan path at all times,
/// so a slow zoom-in or pan-across never exposes canvas background.
///
/// The motion is defined by a start and end state on a normalized 0...1
/// progress axis (0 = first frame, 1 = last frame of the clip). Interpolation
/// is linear by default; the runtime resolves a frame's progress from its time
/// within the clip and samples the transform at that point.
public struct KenBurnsEffect: Codable, Sendable, Equatable {
    /// Per-axis zoom at the start of the clip, where 1.0 fills the canvas at
    /// aspect-fill (no overscan). Values > 1 zoom in further.
    public var startScale: CGFloat

    /// Per-axis zoom at the end of the clip.
    public var endScale: CGFloat

    /// Normalized pan origin (0...1, 0 = left/top edge, 1 = right/bottom edge)
    /// at the start of the clip. The image is panned so this point sits at the
    /// canvas center at progress 0.
    public var startFocus: CGPoint

    /// Normalized pan origin at the end of the clip.
    public var endFocus: CGPoint

    /// Creates a Ken Burns effect.
    public init(
        startScale: CGFloat = 1.0,
        endScale: CGFloat = 1.1,
        startFocus: CGPoint = CGPoint(x: 0.5, y: 0.5),
        endFocus: CGPoint = CGPoint(x: 0.5, y: 0.5)
    ) {
        self.startScale = startScale
        self.endScale = endScale
        self.startFocus = startFocus
        self.endFocus = endFocus
    }

    /// A subtle, pleasing default: a slow zoom-in from 1.0x to 1.12x with no
    /// pan. Good for most slideshow photos without per-image tuning.
    public static func defaultZoomIn() -> KenBurnsEffect {
        KenBurnsEffect(startScale: 1.0, endScale: 1.12, startFocus: .center, endFocus: .center)
    }

    /// Linearly interpolates the zoom and focus at a given normalized progress.
    ///
    /// - Parameter progress: 0...1 within the clip. Values are clamped so the
    ///   motion holds at the endpoints beyond the clip boundaries.
    /// - Returns: The resolved scale and focus point at that progress.
    public func transform(at progress: Double) -> (scale: CGFloat, focus: CGPoint) {
        let t = min(max(progress, 0), 1)
        let scale = CGFloat.interpolate(from: startScale, to: endScale, progress: t)
        let focus = CGPoint(
            x: CGFloat.interpolate(from: startFocus.x, to: endFocus.x, progress: t),
            y: CGFloat.interpolate(from: startFocus.y, to: endFocus.y, progress: t)
        )
        return (scale, focus)
    }
}

extension CGFloat {
    /// Linear interpolation between two values at a 0...1 progress.
    fileprivate static func interpolate(from start: CGFloat, to end: CGFloat, progress: Double) -> CGFloat {
        let t = CGFloat(progress)
        return start + (end - start) * t
    }
}

extension CGPoint {
    /// The geometric center (0.5, 0.5).
    fileprivate static var center: CGPoint { CGPoint(x: 0.5, y: 0.5) }
}
