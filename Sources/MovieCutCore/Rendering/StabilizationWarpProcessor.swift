import CoreImage
import Foundation

/// G-24 P2-G24-5 — the CI warp that applies a stabilization correction to
/// a rendered clip image, with the confidence fallback the plan requires:
/// a low-confidence correction BYPASSES the translation and the bypass is
/// reported (never silently degrades — the DoD counts it).
///
/// The warp is a `CIImage → CIImage` translation (the correction's dx/dy
/// in pixels) composed with a CONSTANT cover scale that the caller derives
/// once from the whole plan (`1 + 2·max normalized translation`): a pure
/// translation would expose uncovered edges, and a per-frame zoom would
/// breathe — wobble reintroduced by the fix itself. The cover scale applies
/// even on bypassed frames for the same reason. When the estimation
/// upgrades to homography, this file grows a perspective path; consumers
/// already receive a `CIImage` and need no change.
public enum StabilizationWarpProcessor {
    /// The confidence below which the correction's TRANSLATION is BYPASSED
    /// (the raw frame passes through — the fallback). Calibrated from the
    /// #9 real-render gate's measured distribution on the multi-frequency
    /// wobble fixture: genuine sub-pixel-refined registrations score
    /// 0.08–0.95 (median 0.18) while noise-only frames score ≈0.00–0.02 —
    /// the original 0.15 cut into the real-motion band and bypassed 31% of
    /// frames, whose translate/no-translate ALTERNATION added more jitter
    /// than it removed (residual/input = 1.23). 0.05 sits inside the gap.
    public static let confidenceBypassThreshold: Double = 0.05

    /// Applies a stabilization correction.
    ///
    /// - Parameters:
    ///   - image: the rendered clip frame.
    ///   - correction: the per-frame correction in PIXELS (dx/dy) plus the
    ///     crop fraction the analysis consumed.
    ///   - confidence: the registration confidence for this frame.
    ///   - coverScale: a constant zoom ≥ 1 derived from the whole plan,
    ///     applied about the image center so the translated frame still
    ///     covers the render extent. Defaults to 1 (no cover).
    ///   - confidenceBypassThreshold: override for the fallback gate.
    /// - Returns: the warped image plus whether the translation fallback
    ///   fired (the caller logs the bypass — the DoD's fallback metric).
    public static func apply(
        _ image: CIImage,
        correction: (dx: Double, dy: Double, cropFraction: Double),
        confidence: Double,
        coverScale: Double = 1,
        confidenceBypassThreshold: Double = StabilizationWarpProcessor.confidenceBypassThreshold
    ) -> (image: CIImage, bypassed: Bool) {
        var result = image

        // The cover zoom: derived from the WHOLE plan by the caller, so it
        // is identical on every frame — zooming per-frame would breathe.
        // It applies before the bypass gate on purpose: a bypassed frame
        // that skipped the zoom would pump against its warped neighbors.
        let scale = max(coverScale, 1)
        if scale > 1 {
            let extent = result.extent
            // Scale about the image center: x ↦ s·(x − c) + c. The
            // CGAffineTransform helpers PREPEND (t.scaledBy = S·t) and
            // CIImage.transformed(by:) applies row-vector order — the
            // rightmost matrix acts first, so the builder starts with the
            // UNDO translation and ends with the pre-translation.
            result = result.transformed(by: CGAffineTransform(
                translationX: extent.midX,
                y: extent.midY
            )
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -extent.midX, y: -extent.midY))
        }

        // The fallback: low confidence means the registration is noise —
        // translating would ADD shake. The frame (already cover-scaled)
        // passes through and the caller logs the bypass.
        guard confidence >= confidenceBypassThreshold else {
            return (result, true)
        }

        // Identity: a zero correction leaves the (cover-scaled) image as is.
        guard correction.dx != 0 || correction.dy != 0 else {
            return (result, false)
        }

        let transform = CGAffineTransform(
            translationX: CGFloat(correction.dx),
            y: CGFloat(correction.dy)
        )
        return (result.transformed(by: transform), false)
    }
}
