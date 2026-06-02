import SwiftUI
import MovieCutCore

extension AnimatableProperty {
    var keyframeDisplayName: String {
        switch self {
        case .positionX:
            return "Position X"
        case .positionY:
            return "Position Y"
        case .scaleX:
            return "Scale X"
        case .scaleY:
            return "Scale Y"
        case .rotation:
            return "Rotation"
        case .opacity:
            return "Opacity"
        case .volume:
            return "Volume"
        }
    }

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
}

extension InterpolationMode {
    var keyframeDisplayName: String {
        switch self {
        case .linear:
            return "Linear"
        case .easeIn:
            return "Ease In"
        case .easeOut:
            return "Ease Out"
        case .easeInOut:
            return "Ease In Out"
        case .hold:
            return "Hold"
        }
    }
}
