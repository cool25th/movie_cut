import AVFoundation
import Foundation
import MovieCutCore

/// Timeline segment carrying the exact clip EQ parameters used by preview taps.
struct ClipEqualizerTimelineSegment {
    var timeRange: CMTimeRange
    var preset: EqualizerPreset
}

extension Clip {
    /// Returns render-ready EQ settings from the persisted clip model.
    func resolvedEqualizerPreset(fallback: EqualizerPreset? = nil) -> EqualizerPreset? {
        if let equalizer, !equalizer.isFlat {
            return equalizer.equalizerPreset
        }

        return fallback
    }
}
