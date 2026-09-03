import SwiftUI
import MovieCutCore

extension AnimatableProperty {
    var keyframeDisplayName: String { displayName }

    var keyframeColor: Color {
        switch self {
        case .positionX, .positionY:
            return .blue
        case .scaleX, .scaleY:
            return .purple
        case .rotation:
            return .orange
        case .opacity:
            return .teal
        case .volume:
            return .green
        }
    }

    /// Whether the rendered value is clamped to a fixed range. Overshoot bezier
    /// presets are only meaningful on unclamped properties — opacity/volume
    /// clip to [0,1] at the compositor, so an overshoot curve is misleading.
    var isValueClamped: Bool {
        switch self {
        case .opacity, .volume:
            return true
        case .positionX, .positionY, .scaleX, .scaleY, .rotation:
            return false
        }
    }
}

extension InterpolationMode {
    var keyframeDisplayName: String { displayName }
}
