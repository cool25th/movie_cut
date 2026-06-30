import CoreGraphics
import Foundation

/// Coarse animation primitive used by a text animation preset.
public enum TextAnimationPhase: String, Codable, Sendable, Equatable, Hashable {
    case none
    case fade
    case slide
    case typewriter
    case bounce
    case zoom
    case pop
    case wave
}

/// Direction associated with directional text animation presets.
public enum TextAnimationDirection: String, Codable, Sendable, Equatable, Hashable {
    case none
    case left
    case right
    case up
    case down
}

/// CapCut-style text animation presets.
public enum TextAnimationPreset: String, Codable, Sendable, CaseIterable, Equatable, Hashable {
    case none
    case fadeIn
    case fadeOut
    case fadeInOut
    case slideInLeft
    case slideInRight
    case slideInUp
    case slideInDown
    case typewriter
    case bounceIn
    case zoomIn
    case popIn
    case wave

    public var enterAnimation: TextAnimationPhase {
        switch self {
        case .none, .fadeOut:
            return .none
        case .fadeIn, .fadeInOut:
            return .fade
        case .slideInLeft, .slideInRight, .slideInUp, .slideInDown:
            return .slide
        case .typewriter:
            return .typewriter
        case .bounceIn:
            return .bounce
        case .zoomIn:
            return .zoom
        case .popIn:
            return .pop
        case .wave:
            return .wave
        }
    }

    public var exitAnimation: TextAnimationPhase? {
        switch self {
        case .fadeOut, .fadeInOut:
            return .fade
        case .none,
             .fadeIn,
             .slideInLeft,
             .slideInRight,
             .slideInUp,
             .slideInDown,
             .typewriter,
             .bounceIn,
             .zoomIn,
             .popIn,
             .wave:
            return nil
        }
    }

    /// Default preset duration in seconds. Individual clips may override it.
    public var duration: TimeInterval {
        switch self {
        case .none:
            return 0.5
        case .fadeIn, .fadeOut, .fadeInOut:
            return 0.5
        case .slideInLeft, .slideInRight, .slideInUp, .slideInDown:
            return 0.6
        case .typewriter:
            return 1.2
        case .bounceIn:
            return 0.75
        case .zoomIn:
            return 0.5
        case .popIn:
            return 0.4
        case .wave:
            return 1.0
        }
    }

    public var direction: TextAnimationDirection {
        switch self {
        case .slideInLeft:
            return .left
        case .slideInRight:
            return .right
        case .slideInUp:
            return .up
        case .slideInDown:
            return .down
        case .none,
             .fadeIn,
             .fadeOut,
             .fadeInOut,
             .typewriter,
             .bounceIn,
             .zoomIn,
             .popIn,
             .wave:
            return .none
        }
    }
}

/// Legacy animation type retained for source and project compatibility.
public enum TextAnimationType: String, Codable, Sendable, CaseIterable, Equatable, Hashable {
    case fadeIn
    case fadeOut
    case typewriter
    case bounce
    case slideUp
    case slideDown
    case scale

    public var preset: TextAnimationPreset {
        switch self {
        case .fadeIn:
            return .fadeIn
        case .fadeOut:
            return .fadeOut
        case .typewriter:
            return .typewriter
        case .bounce:
            return .bounceIn
        case .slideUp:
            return .slideInUp
        case .slideDown:
            return .slideInDown
        case .scale:
            return .zoomIn
        }
    }

    public init?(preset: TextAnimationPreset) {
        switch preset {
        case .fadeIn:
            self = .fadeIn
        case .fadeOut:
            self = .fadeOut
        case .typewriter:
            self = .typewriter
        case .bounceIn:
            self = .bounce
        case .slideInUp:
            self = .slideUp
        case .slideInDown:
            self = .slideDown
        case .zoomIn:
            self = .scale
        case .none,
             .fadeInOut,
             .slideInLeft,
             .slideInRight,
             .popIn,
             .wave:
            return nil
        }
    }
}

/// Transform and visibility values produced by a text animation at a point in a clip.
public struct TextAnimationRenderState: Sendable, Equatable {
    public var visibleText: String
    public var opacity: Double
    public var translation: CGPoint
    public var scale: CGFloat
    public var rotationDegrees: Double

    public init(
        visibleText: String,
        opacity: Double = 1,
        translation: CGPoint = .zero,
        scale: CGFloat = 1,
        rotationDegrees: Double = 0
    ) {
        self.visibleText = visibleText
        self.opacity = opacity
        self.translation = translation
        self.scale = scale
        self.rotationDegrees = rotationDegrees
    }
}

public struct TextAnimation: Codable, Sendable, Equatable {
    public var preset: TextAnimationPreset
    public var duration: TimeInterval
    public var delay: TimeInterval

    /// Legacy source compatibility for callers that still use `TextAnimationType`.
    public var type: TextAnimationType {
        get { TextAnimationType(preset: preset) ?? .fadeIn }
        set { preset = newValue.preset }
    }

    public init(
        preset: TextAnimationPreset,
        duration: TimeInterval? = nil,
        delay: TimeInterval = 0
    ) {
        self.preset = preset
        self.duration = duration ?? preset.duration
        self.delay = delay
    }

    public init(
        type: TextAnimationType,
        duration: TimeInterval = 0.5,
        delay: TimeInterval = 0
    ) {
        self.preset = type.preset
        self.duration = duration
        self.delay = delay
    }

    public static func presets() -> [TextAnimation] {
        TextAnimationPreset.allCases.map { preset in
            TextAnimation(preset: preset, duration: preset.duration)
        }
    }

    public func renderState(
        for text: String,
        clipProgress: Double,
        clipDuration: TimeInterval,
        canvasSize: CGSize = .zero
    ) -> TextAnimationRenderState {
        let progress = min(max(clipProgress.isFinite ? clipProgress : 0, 0), 1)
        let resolvedDuration = clipDuration.isFinite && clipDuration > 0
            ? clipDuration
            : max(duration + delay, duration, 1.0e-6)
        return renderState(
            for: text,
            localTime: progress * resolvedDuration,
            clipDuration: resolvedDuration,
            canvasSize: canvasSize
        )
    }

    public func renderState(
        for text: String,
        localTime: TimeInterval,
        clipDuration: TimeInterval,
        canvasSize: CGSize = .zero
    ) -> TextAnimationRenderState {
        guard preset != .none else {
            return TextAnimationRenderState(visibleText: text)
        }

        let localTime = localTime.isFinite ? max(0, localTime) : 0
        let clipDuration = clipDuration.isFinite && clipDuration > 0 ? clipDuration : .infinity
        let animationDuration = max(duration, 1.0e-6)
        let delay = max(delay, 0)
        let enterProgress = clamp((localTime - delay) / animationDuration)
        let exitStart = clipDuration.isFinite
            ? max(0, clipDuration - animationDuration)
            : delay
        let exitProgress = clamp((localTime - exitStart) / animationDuration)
        let lifetimeProgress = clipDuration.isFinite
            ? clamp(localTime / max(clipDuration, 1.0e-6))
            : enterProgress

        var state = TextAnimationRenderState(visibleText: text)

        applyEnterAnimation(to: &state, text: text, progress: enterProgress, canvasSize: canvasSize)
        applyExitAnimation(to: &state, progress: exitProgress)

        if preset == .wave {
            let wavePhase = lifetimeProgress * .pi * 4
            state.translation.y += CGFloat(sin(wavePhase) * 8)
            state.rotationDegrees += sin(wavePhase) * 3
        }

        state.opacity = clamp(state.opacity)
        state.scale = max(state.scale, 0.001)
        return state
    }

    private enum CodingKeys: String, CodingKey {
        case preset
        case type
        case duration
        case delay
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedPreset = Self.decodePreset(from: container) ?? .none
        preset = decodedPreset
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? decodedPreset.duration
        delay = try container.decodeIfPresent(TimeInterval.self, forKey: .delay) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preset, forKey: .preset)
        if let legacyType = TextAnimationType(preset: preset) {
            try container.encode(legacyType, forKey: .type)
        }
        try container.encode(duration, forKey: .duration)
        try container.encode(delay, forKey: .delay)
    }

    private static func decodePreset(from container: KeyedDecodingContainer<CodingKeys>) -> TextAnimationPreset? {
        if let rawPreset = try? container.decodeIfPresent(String.self, forKey: .preset),
           let preset = TextAnimationPreset(rawValue: rawPreset) {
            return preset
        }

        if let rawType = try? container.decodeIfPresent(String.self, forKey: .type) {
            if let legacyType = TextAnimationType(rawValue: rawType) {
                return legacyType.preset
            }
            if let preset = TextAnimationPreset(rawValue: rawType) {
                return preset
            }
        }

        return nil
    }

    private func applyEnterAnimation(
        to state: inout TextAnimationRenderState,
        text: String,
        progress: Double,
        canvasSize: CGSize
    ) {
        switch preset.enterAnimation {
        case .none:
            break
        case .fade:
            state.opacity *= easeOutCubic(progress)
        case .slide:
            let eased = easeOutCubic(progress)
            state.opacity *= eased
            state.translation = slideTranslation(progress: eased, canvasSize: canvasSize)
        case .typewriter:
            let characterCount = Int(floor(progress * Double(text.count)))
            state.visibleText = String(text.prefix(characterCount))
        case .bounce:
            let eased = easeOutBack(progress)
            state.opacity *= min(progress * 1.6, 1)
            state.scale *= max(CGFloat(eased), 0.001)
            state.translation.y -= CGFloat((1 - progress) * travelDistance(canvasSize) * 0.18)
        case .zoom:
            let eased = easeOutCubic(progress)
            state.opacity *= eased
            state.scale *= CGFloat(0.35 + eased * 0.65)
        case .pop:
            state.opacity *= min(progress * 2, 1)
            state.scale *= CGFloat(popScale(progress))
        case .wave:
            state.opacity *= easeOutCubic(progress)
        }
    }

    private func applyExitAnimation(to state: inout TextAnimationRenderState, progress: Double) {
        guard preset.exitAnimation == .fade else { return }
        state.opacity *= 1 - easeInCubic(progress)
    }

    private func slideTranslation(progress: Double, canvasSize: CGSize) -> CGPoint {
        let offset = CGFloat(travelDistance(canvasSize) * (1 - progress))
        switch preset.direction {
        case .left:
            return CGPoint(x: -offset, y: 0)
        case .right:
            return CGPoint(x: offset, y: 0)
        case .up:
            return CGPoint(x: 0, y: -offset)
        case .down:
            return CGPoint(x: 0, y: offset)
        case .none:
            return .zero
        }
    }

    private func travelDistance(_ canvasSize: CGSize) -> Double {
        let largestEdge = max(canvasSize.width, canvasSize.height)
        guard largestEdge.isFinite, largestEdge > 0 else {
            return 80
        }
        return min(max(Double(largestEdge) * 0.18, 48), 240)
    }

    private func popScale(_ progress: Double) -> Double {
        let progress = clamp(progress)
        if progress < 0.72 {
            let phaseProgress = progress / 0.72
            return 0.45 + easeOutCubic(phaseProgress) * 0.72
        }

        let settleProgress = (progress - 0.72) / 0.28
        return 1.17 - easeOutCubic(settleProgress) * 0.17
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value.isFinite ? value : 0, 0), 1)
    }

    private func easeOutCubic(_ progress: Double) -> Double {
        let p = clamp(progress)
        return 1 - pow(1 - p, 3)
    }

    private func easeInCubic(_ progress: Double) -> Double {
        let p = clamp(progress)
        return p * p * p
    }

    private func easeOutBack(_ progress: Double) -> Double {
        let p = clamp(progress)
        let c1 = 1.70158
        let c3 = c1 + 1
        return 1 + c3 * pow(p - 1, 3) + c1 * pow(p - 1, 2)
    }
}
