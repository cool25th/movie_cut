import Foundation

/// Built-in transition identifiers for Phase 1 editing.
public enum TransitionType: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    /// No transition.
    case none

    /// A cross-dissolve between adjacent clips.
    case crossDissolve

    /// A fade through black between adjacent clips.
    case fadeThroughBlack

    /// A wipe from left to right.
    case wipeRight
}

/// A transition instance and duration applied to a clip boundary.
public struct Transition: Codable, Sendable, Equatable, Identifiable {
    /// The transition instance identifier.
    public var id: UUID

    /// The built-in transition type.
    public var type: TransitionType

    /// The transition duration in seconds.
    public var duration: TimeInterval

    /// Creates a transition.
    public init(
        id: UUID = UUID(),
        type: TransitionType,
        duration: TimeInterval = 0.5
    ) {
        self.id = id
        self.type = type
        self.duration = duration
    }
}
