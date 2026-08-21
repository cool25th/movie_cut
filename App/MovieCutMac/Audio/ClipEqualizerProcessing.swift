import AVFoundation
import Foundation
import MovieCutCore

extension Clip {
    /// Returns render-ready EQ settings from the persisted clip model.
    func resolvedEqualizerPreset(fallback: EqualizerPreset? = nil) -> EqualizerPreset? {
        if let equalizer, !equalizer.isFlat {
            return equalizer.equalizerPreset
        }

        return fallback
    }
}
