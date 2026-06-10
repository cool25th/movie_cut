import Foundation

/// Built-in effect identifiers for Phase 1 editing.
public enum EffectType: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    /// Brightness adjustment.
    case brightness

    /// Contrast adjustment.
    case contrast

    /// Saturation adjustment.
    case saturation

    /// Color temperature adjustment.
    case temperature

    /// Exposure adjustment.
    case exposure

    /// Fade-in effect.
    case fadeIn

    /// Fade-out effect.
    case fadeOut

    /// Cross-dissolve transition effect.
    case crossDissolve

    /// Grayscale color effect.
    case grayscale

    /// Sepia color effect.
    case sepia

    /// Blur effect.
    case blur

    /// Stylized color remapping effect.
    case styleTransfer

    /// Procedural cinematic LUT-style color remapping.
    case cinematicLUT

    /// Procedural vintage LUT-style color remapping.
    case vintageLUT

    /// Procedural noir LUT-style color remapping.
    case noirLUT

    /// Procedural vivid LUT-style color remapping.
    case vividLUT

    /// Procedural cool LUT-style color remapping.
    case coolLUT
}

/// An effect instance and its numeric parameters.
public struct Effect: Codable, Sendable, Equatable, Identifiable {
    /// The effect instance identifier.
    public var id: UUID

    /// The built-in effect type.
    public var type: EffectType

    /// Named effect parameters.
    public var parameters: [String: Double]

    /// Creates an effect instance.
    public init(
        id: UUID = UUID(),
        type: EffectType,
        parameters: [String: Double] = [:]
    ) {
        self.id = id
        self.type = type
        self.parameters = parameters
    }
}

public extension Effect {
    /// A grayscale effect instance.
    static var grayscale: Effect {
        Effect(type: .grayscale)
    }

    /// A sepia effect instance.
    static var sepia: Effect {
        Effect(type: .sepia, parameters: ["intensity": 0.9])
    }

    /// A blur effect instance.
    static var blur: Effect {
        Effect(type: .blur, parameters: ["radius": 1])
    }

    /// A stylized color remapping effect instance.
    static var styleTransfer: Effect {
        Effect(type: .styleTransfer, parameters: ["styleIndex": 1, "intensity": 0.75])
    }

    /// A procedural cinematic LUT effect instance.
    static var cinematicLUT: Effect {
        Effect(type: .cinematicLUT, parameters: ["intensity": 0.85])
    }

    /// A procedural vintage LUT effect instance.
    static var vintageLUT: Effect {
        Effect(type: .vintageLUT, parameters: ["intensity": 0.8])
    }

    /// A procedural noir LUT effect instance.
    static var noirLUT: Effect {
        Effect(type: .noirLUT, parameters: ["intensity": 0.9])
    }

    /// A procedural vivid LUT effect instance.
    static var vividLUT: Effect {
        Effect(type: .vividLUT, parameters: ["intensity": 0.8])
    }

    /// A procedural cool LUT effect instance.
    static var coolLUT: Effect {
        Effect(type: .coolLUT, parameters: ["intensity": 0.8])
    }
}
