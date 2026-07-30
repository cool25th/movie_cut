import Foundation

/// Timeline editing tool modes (S9 of `docs/PRO_SPEC_GAP_WORKORDER_20260730.md`).
///
/// In selection mode (the default) clicks select/move clips; in blade mode a
/// click on a clip splits it at the playhead (reusing `SplitClipCommand`). Kept
/// in Core so iOS can share the concept and the state is unit-testable.
public enum EditTool: String, Sendable, Equatable, CaseIterable {
    case select
    case blade
}

/// J/K/L shuttle control helpers. (S9)
///
/// Pro NLE convention: J = reverse, K = stop, L = forward; repeated taps of J or
/// L raise the speed step (1× → 2× → 4×). This enum holds the pure speed-step
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
