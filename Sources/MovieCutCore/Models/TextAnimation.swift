import Foundation

public enum TextAnimationType: String, Codable, Sendable, CaseIterable {
    case fadeIn
    case fadeOut
    case typewriter
    case bounce
    case slideUp
    case slideDown
    case scale
}

public struct TextAnimation: Codable, Sendable, Equatable {
    public var type: TextAnimationType
    public var duration: TimeInterval
    public var delay: TimeInterval

    public init(
        type: TextAnimationType,
        duration: TimeInterval = 0.5,
        delay: TimeInterval = 0
    ) {
        self.type = type
        self.duration = duration
        self.delay = delay
    }

    public static func presets() -> [TextAnimation] {
        TextAnimationType.allCases.map { type in
            switch type {
            case .fadeIn, .fadeOut, .slideUp, .slideDown:
                return TextAnimation(type: type, duration: 0.5)
            case .typewriter:
                return TextAnimation(type: type, duration: 1.5)
            case .bounce:
                return TextAnimation(type: type, duration: 0.6)
            case .scale:
                return TextAnimation(type: type, duration: 0.45)
            }
        }
    }
}
