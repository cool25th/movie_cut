import CoreGraphics
import CoreImage
import Foundation

/// G-03 adjustment layers — the DESIGN NOTE the plan's risk register asks
/// to fix before the rendering lands (EXECUTION_PLAN Inc 10):
///
/// - **Model**: an adjustment layer is a CLIP FLAG (`Clip.isAdjustmentLayer`),
///   not a `Track.kind` — ranges, transitions machinery, undo, and the save
///   round-trip all ride the existing clip pipeline unchanged. v1 scope:
///   the flag is only honored on VIDEO-kind tracks (enforced HERE, the single
///   consumption point), spanning the full canvas width by definition.
/// - **Render order (locked)**: every visible clip first renders through its
///   OWN chain (intrinsic color correction/grade → effects), THEN the
///   adjustment chain applies: bottom-most adjustment track first, top-most
///   last (zIndex ascending) — the compositing convention an editor expects.
/// - **Outside the range = no change**: an adjustment clip only affects the
///   timeline span it covers; partial-clip application and nested (stacked
///   ADJUSTMENT-on-adjustment) effects are Phase-2 (plan's OUT list).
/// - **Adjustment clips render nothing themselves** — renderers skip them as
///   content (`isAdjustmentContent`).
public enum AdjustmentLayerChain {
    /// The adjustment clips active at `time`, in application order
    /// (bottom-most track's adjustment first). Only video-kind tracks'
    /// flags are honored (v1 scope).
    public static func activeAdjustments(at time: TimeInterval, in tracks: [Track]) -> [Clip] {
        tracks
            .filter { $0.kind == .video }
            .sorted { $0.zIndex < $1.zIndex }
            .flatMap(\.clips)
            .filter { clip in
                clip.isAdjustmentLayer
                    && time >= clip.timelineRange.start
                    && time < clip.timelineRange.start + clip.timelineRange.duration
            }
    }

    /// Whether a clip is adjustment CONTENT (carries no pixels of its own)
    /// — renderers skip these in the visible layer stack.
    public static func isAdjustmentContent(_ clip: Clip) -> Bool {
        clip.isAdjustmentLayer
    }

    /// The visible (non-adjustment) clips active at `time` on video tracks —
    /// the clips the adjustment chain applies TO.
    public static func visibleClips(at time: TimeInterval, in tracks: [Track]) -> [Clip] {
        tracks
            .filter { $0.kind == .video }
            .sorted { $0.zIndex < $1.zIndex }
            .flatMap(\.clips)
            .filter { clip in
                clip.isAdjustmentLayer == false
                    && time >= clip.timelineRange.start
                    && time < clip.timelineRange.start + clip.timelineRange.duration
            }
    }
}

extension AdjustmentLayerChain {
    /// Applies the adjustment chain's color correction/grade to an already-
    /// rendered clip image — AFTER the clip's own chain (the locked order):
    /// bottom-most adjustment first, each contributing its colorCorrection
    /// then colorGrade. Runs on the shared Core Image context pair the
    /// pixel processors use.
    public static func applyAdjustments(_ adjustments: [Clip], to image: CIImage) -> CIImage {
        var result = image
        for adjustment in adjustments {
            if let correction = adjustment.colorCorrection {
                result = ColorCorrectionPixelProcessor.apply(correction, to: result)
            }
            if let grade = adjustment.colorGrade {
                result = ColorGradePixelProcessor.apply(grade, to: result)
            }
        }
        return result
    }
}
