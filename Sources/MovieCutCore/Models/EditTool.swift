import Foundation

/// Timeline editing tool modes (S9).
///
/// - `select` (V): Default mode. Clicks select/move clips, drag handles trim.
/// - `blade` (C): Blade/Razor tool. Clicking a clip splits it at the playhead or click position.
/// - `slip` (Y): Slip tool. Dragging a clip adjusts its internal sourceRange while keeping timelineRange fixed.
/// - `slide` (U): Slide tool. Dragging a clip adjusts its timelineRange and adjacent clip boundaries.
public enum EditTool: String, Sendable, Equatable, CaseIterable, Identifiable {
    case select
    case blade
    case slip
    case slide

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .select: return "Selection Tool"
        case .blade: return "Blade Tool"
        case .slip: return "Slip Tool"
        case .slide: return "Slide Tool"
        }
    }

    public var shortcutKey: Character {
        switch self {
        case .select: return "v"
        case .blade: return "c"
        case .slip: return "y"
        case .slide: return "u"
        }
    }

    public var systemImage: String {
        switch self {
        case .select: return "arrow.up.left"
        case .blade: return "scissors"
        case .slip: return "arrow.left.and.right.square"
        case .slide: return "arrow.left.and.right"
        }
    }
}

/// J/K/L shuttle control helpers. (S9)
///
/// Pro NLE convention: J = reverse, K = stop, L = forward; repeated taps of J or
/// L raise the speed step (1× → 2× → 4× → 8×). This enum holds the pure speed-step
/// arithmetic so it is unit-testable without a player.
public enum ShuttleRate {
    /// The forward speed step for a given tap count: 1× at 1 tap, 2× at 2, 4×
    /// at 3+. Caps at 4× (matches the player's `setRate` clamp of 0.25–4.0).
    public static func forwardStep(forTapCount taps: Int) -> Float {
        switch taps {
        case 0, 1: return 1.0
        case 2: return 2.0
        default: return 4.0
        }
    }

    /// The reverse speed step for a given tap count, mirrored from forward.
    /// Negative to signal direction to the caller (the caller drives the actual
    /// back-step cadence, since AVPlayer cannot play at a negative rate).
    public static func reverseStep(forTapCount taps: Int) -> Float {
        -forwardStep(forTapCount: taps)
    }
}
