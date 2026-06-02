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
