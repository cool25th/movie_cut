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
}

extension InterpolationMode {
    var keyframeDisplayName: String { displayName }
}
