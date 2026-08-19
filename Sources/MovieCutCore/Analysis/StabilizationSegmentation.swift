import CoreMedia
import Foundation

/// G-24 P2-G24-2 — bridges the EXISTING `SceneChangeProvider` into the
/// stabilization measurement model: the provider's detected change times
/// become `StabilizationMetrics.Frame.isSceneCut` marks, so the Vision
/// registration (P2-G24-3) segments on them and the DoD's
/// sceneCutErrors counter (P2-G24-6) can judge real boundary handling.
///
/// The bridge is PURE about its inputs — it maps times to frame indices
/// and nothing else; the provider itself owns all image analysis.
public enum StabilizationSegmentation {
    /// Maps detected scene-change times to per-frame cut flags.
    ///
    /// - Parameters:
    ///   - changeTimes: the provider's detected change instants (seconds).
    ///   - frameCount: total frames in the clip.
    ///   - frameRate: the clip's frame rate (frames/second).
    ///   - toleranceFrames: a detected time counts for the NEAREST frame
    ///     within this many frames — the plan's ±2-frame gate.
    public static func sceneCutFlags(
        changeTimes: [TimeInterval],
        frameCount: Int,
        frameRate: Double,
        toleranceFrames: Int = 2
    ) -> [Bool] {
        guard frameCount > 0, frameRate > 0 else { return Array(repeating: false, count: max(0, frameCount)) }
        var flags = Array(repeating: false, count: frameCount)
        for time in changeTimes {
            let exact = Int((time * frameRate).rounded())
            // Mark every frame within the tolerance window.
            for offset in -toleranceFrames...toleranceFrames {
                let index = exact + offset
                if index >= 0, index < frameCount {
                    flags[index] = true
                }
            }
        }
        return flags
    }

    /// Builds the stabilization measurement frames from a displacement
    /// sequence and the provider's change times — the combined input
    /// `StabilizationMetrics.report` consumes.
    public static func frames(
        displacements: [Double],
        changeTimes: [TimeInterval],
        frameRate: Double,
        toleranceFrames: Int = 2
    ) -> [StabilizationMetrics.Frame] {
        let flags = sceneCutFlags(
            changeTimes: changeTimes,
            frameCount: displacements.count,
            frameRate: frameRate,
            toleranceFrames: toleranceFrames
        )
        return zip(displacements, flags).map { StabilizationMetrics.Frame(displacement: $0, isSceneCut: $1) }
    }
}
