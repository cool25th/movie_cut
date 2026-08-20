import CoreImage
import Foundation

/// G-24 P2-G24-5 — the CI warp that applies a stabilization correction to
/// a rendered clip image, with the confidence fallback the plan requires:
/// a low-confidence correction BYPASSES the warp and logs the bypass
/// (never silently degrades — the DoD counts it).
///
/// The warp is a pure `CIImage → CIImage` translation (the correction's
/// dx/dy in pixels), matching the registration model's translation-only
/// estimation. When the estimation upgrades to homography, this file
/// grows a perspective path; consumers already receive a `CIImage` and
/// need no change.
public enum StabilizationWarpProcessor {
    /// The confidence below which the correction is BYPASSED (the raw
    /// frame passes through — the fallback). Tuned so the deterministic
    /// fixture's clean segments warp while noise-only frames don't.
    public static let confidenceBypassThreshold: Double = 0.15

    /// Applies a stabilization correction. Returns the warped image, or
    /// the ORIGINAL when the correction's confidence is below the
    /// threshold (the fallback — reported via `bypassed`).
    ///
    /// - Parameters:
    ///   - image: the rendered clip frame.
    ///   - correction: the per-frame correction from
    ///     `StabilizationRegistration.correction` (pixels, inverted).
    ///   - confidenceBypassThreshold: override for the fallback gate.
    /// - Returns: the warped (or bypassed) image plus whether the
    ///   fallback fired.
    public static func apply(
        _ image: CIImage,
        correction: (dx: Double, dy: Double, cropFraction: Double),
        confidence: Double,
        confidenceBypassThreshold: Double = StabilizationWarpProcessor.confidenceBypassThreshold
    ) -> (image: CIImage, bypassed: Bool) {
        // The fallback: low confidence means the registration is noise —
        // warping would ADD shake. The raw frame passes through and the
        // caller logs the bypass (the DoD's fallback metric).
        guard confidence >= confidenceBypassThreshold else {
            return (image, true)
        }

        // Identity: a zero correction is a no-op (bit-exact).
        guard correction.dx != 0 || correction.dy != 0 else {
            return (image, false)
        }

        let transform = CGAffineTransform(
            translationX: CGFloat(correction.dx),
            y: CGFloat(correction.dy)
        )
        return (image.transformed(by: transform), false)
    }
}
