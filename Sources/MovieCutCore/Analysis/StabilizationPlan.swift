import Foundation

/// G-24 render-side payload — what the compositor consumes at render time
/// (code-review #9: the warp was implemented but nothing carried the
/// analysis output to the render chain).
///
/// The analysis pipeline (registration → smoothing → correction) produces a
/// plan ONCE per clip and attaches it to `Clip.stabilization`; preview and
/// export read the SAME plan through `CustomCompositionClipEffect`, so they
/// warp identically by construction.
///
/// Translations are stored NORMALIZED (fractions of source width/height) so
/// a plan computed on a downscaled analysis buffer (e.g. 140×100 luma)
/// applies at any render size. The sign convention is fixed where the warp
/// composes its transform (`StabilizationWarpProcessor`), not here.
public struct StabilizationPlan: Codable, Sendable, Equatable {
    /// One frame's warp: the translation to apply plus the analysis-side
    /// crop and confidence that produced it.
    public struct Correction: Codable, Sendable, Equatable {
        /// Horizontal translation as a fraction of source width (−1…1).
        public var dx: Double
        /// Vertical translation as a fraction of source height (−1…1).
        public var dy: Double
        /// The crop budget this correction consumed (0…maxCrop).
        public var cropFraction: Double
        /// Registration confidence 0…1 — below
        /// `StabilizationWarpProcessor.confidenceBypassThreshold` the warp
        /// is bypassed for that frame (the DoD's fallback path).
        public var confidence: Double

        public init(dx: Double, dy: Double, cropFraction: Double, confidence: Double) {
            self.dx = dx
            self.dy = dy
            self.cropFraction = min(max(cropFraction, 0), 1)
            self.confidence = min(max(confidence, 0), 1)
        }
    }

    /// The frame rate the corrections were sampled at (analysis FPS).
    public var frameRate: Double

    /// Per-frame corrections, indexed by frame number from the clip's
    /// timeline start. Empty means "analyzed, nothing to correct".
    public var corrections: [Correction]

    public init(frameRate: Double, corrections: [Correction]) {
        self.frameRate = max(frameRate, 0)
        self.corrections = corrections
    }

    public var isEmpty: Bool {
        corrections.isEmpty
    }

    /// The correction for a time in seconds from the clip's timeline start.
    /// Out-of-range times clamp to the nearest correction — the warp holds
    /// the boundary value rather than snapping to identity mid-clip.
    public func correction(atLocalTime seconds: TimeInterval) -> Correction? {
        guard !corrections.isEmpty, frameRate > 0 else { return nil }
        let index = Int((seconds * frameRate).rounded())
        return corrections[min(max(index, 0), corrections.count - 1)]
    }

    /// The largest per-axis translation the plan applies, normalized. The
    /// compositor derives ONE cover-zoom from this — a per-frame zoom would
    /// breathe, which is wobble reintroduced by the fix itself.
    public var maxNormalizedTranslation: (x: Double, y: Double) {
        corrections.reduce((0.0, 0.0)) { acc, correction in
            (max(acc.0, abs(correction.dx)), max(acc.1, abs(correction.dy)))
        }
    }
}
