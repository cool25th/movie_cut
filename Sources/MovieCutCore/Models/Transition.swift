import Foundation

/// High-level groups for built-in transition identifiers.
public enum TransitionCategory: String, Codable, Sendable, Equatable, Hashable {
    case basic
    case wipe
    case slide
    case zoom
    case stylized
}

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

    /// A wipe from right to left.
    case wipeLeft

    /// A wipe from bottom to top.
    case wipeUp

    /// A wipe from top to bottom.
    case wipeDown

    /// A slide where the outgoing clip exits left and the incoming clip enters from the right.
    case slideLeft

    /// A slide where the outgoing clip exits right and the incoming clip enters from the left.
    case slideRight

    /// A zooming incoming transition.
    case zoomIn

    /// A zooming outgoing transition.
    case zoomOut

    /// A deterministic strip-offset glitch transition.
    case glitch

    /// The transition group used for UI organization and renderer contracts.
    public var category: TransitionCategory {
        switch self {
        case .none, .crossDissolve, .fadeThroughBlack:
            .basic
        case .wipeRight, .wipeLeft, .wipeUp, .wipeDown:
            .wipe
        case .slideLeft, .slideRight:
            .slide
        case .zoomIn, .zoomOut:
            .zoom
        case .glitch:
            .stylized
        }
    }

    /// True when the transition has a directional variant.
    public var isDirectional: Bool {
        switch self {
        case .wipeRight, .wipeLeft, .wipeUp, .wipeDown, .slideLeft, .slideRight:
            true
        case .none, .crossDissolve, .fadeThroughBlack, .zoomIn, .zoomOut, .glitch:
            false
        }
    }

    /// True when full rendering requires both outgoing and incoming images for each transition frame.
    ///
    /// All visible transitions render through the shared `TransitionPixelProcessor`
    /// two-source path so preview and export match (F-07). Only `.none` (a no-op
    /// boundary) stays single-source.
    public var requiresTwoSourcePixelProcessing: Bool {
        switch self {
        case .crossDissolve, .fadeThroughBlack, .wipeRight,
             .wipeLeft, .wipeUp, .wipeDown, .slideLeft, .slideRight, .zoomIn, .zoomOut, .glitch:
            true
        case .none:
            false
        }
    }
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
