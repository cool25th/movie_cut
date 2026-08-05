import Foundation

/// Clip properties that can be animated with keyframes.
public enum AnimatableProperty: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case positionX
    case positionY
    case scaleX
    case scaleY
    case rotation
    case opacity
    case volume

    /// User-visible display name, shared by the Mac and iOS keyframe editors.
    public var displayName: String {
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
}

/// Interpolation modes used between adjacent keyframes.
public enum InterpolationMode: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case hold

    /// User-visible display name, shared by the Mac and iOS keyframe editors.
    public var displayName: String {
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

/// A value for an animatable clip property at a source-relative time.
public struct Keyframe: Codable, Sendable, Equatable, Identifiable {
    /// The keyframe identifier.
    public var id: UUID

    /// The animated property.
    public var property: AnimatableProperty

    /// Time in seconds within the clip source range.
    public var time: TimeInterval

    /// The property value at `time`.
    public var value: Double

    /// The interpolation mode leaving this keyframe.
    public var interpolation: InterpolationMode

    /// Creates a keyframe.
    public init(
        id: UUID = UUID(),
        property: AnimatableProperty,
        time: TimeInterval,
        value: Double,
        interpolation: InterpolationMode = .linear
    ) {
        self.id = id
        self.property = property
        self.time = max(0, time)
        self.value = value
        self.interpolation = interpolation
    }

    /// Interpolates between two values using the selected interpolation mode.
    public static func interpolate(
        from: Double,
        to: Double,
        progress: Double,
        mode: InterpolationMode
    ) -> Double {
        let clampedProgress = min(max(progress, 0), 1)

        let easedProgress: Double
        switch mode {
        case .linear:
            easedProgress = clampedProgress
        case .easeIn:
            easedProgress = clampedProgress * clampedProgress
        case .easeOut:
            let inverse = 1 - clampedProgress
            easedProgress = 1 - (inverse * inverse)
        case .easeInOut:
            if clampedProgress < 0.5 {
                easedProgress = 2 * clampedProgress * clampedProgress
            } else {
                let inverse = -2 * clampedProgress + 2
                easedProgress = 1 - ((inverse * inverse) / 2)
            }
        case .hold:
            return clampedProgress >= 1 ? to : from
        }

        return from + ((to - from) * easedProgress)
    }

    /// Sorts keyframes by property (rawValue) then time, matching the Mac and iOS editors.
    public static func sortedByPropertyThenTime(_ keyframes: [Keyframe]) -> [Keyframe] {
        keyframes.sorted {
            if $0.property.rawValue == $1.property.rawValue {
                return $0.time < $1.time
            }
            return $0.property.rawValue < $1.property.rawValue
        }
    }
}
