import Foundation

/// A coarse thermal state, decoupled from `ProcessInfo.ProcessInfo.ThermalState`
/// so the downgrade policy is unit-testable without a device under pressure.
///
/// Mirrors `ProcessInfo.ThermalState`: `.nominal` (cool), `.fair` (warm but ok),
/// `.serious` / `.critical` (the system is throttling and preview should shed
/// work). (S7 of `docs/PRO_SPEC_GAP_WORKORDER_20260730.md`.)
public enum ThermalState: String, Sendable, Equatable, CaseIterable {
    case nominal
    case fair
    case serious
    case critical

    /// Whether playback should drop to a proxy under this thermal state.
    /// `.nominal`/`.fair` keep the original; `.serious`/`.critical` downgrade.
    public var shouldDowngradeToProxy: Bool {
        switch self {
        case .nominal, .fair:
            return false
        case .serious, .critical:
            return true
        }
    }

    /// Whether an export should be REFUSED before it starts under this thermal
    /// state. `.critical` only: exporting under critical thermal pressure risks a
    /// thermal shutdown mid-write, which truncates or corrupts the output file
    /// the user picked. `.serious` proceeds (the system throttles but a full
    /// export is still safe to complete, just slower — the user is warned via
    /// the log). `.nominal`/`.fair` are unrestricted.
    public var shouldBlockExport: Bool {
        self == .critical
    }

    /// The current thermal state from `ProcessInfo`, mapped to this enum so the
    /// policy is testable without a device under pressure. `.critical`/`.serious`
    /// flow from the real system; `@unknown default` falls back to `.nominal`
    /// (fail-open on a future state we don't recognize, rather than blocking work).
    public static var current: ThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }
}

/// Pure decision logic for thermal-driven proxy downgrades. Extracted from the
/// engine so the transition table is unit-testable without `ProcessInfo` or a
/// GUI. (S7)
public enum ProxyDowngradePolicy {
    /// Decides whether preview should use the proxy given the thermal state and
    /// the user's auto-downgrade preference.
    ///
    /// - Returns: `true` only when the user allows auto-downgrade **and** the
    ///   thermal state is serious/critical. The user's explicit
    ///   `useProxyPlayback` setting is honoured separately by the caller
    ///   (`useProxyPlayback || shouldAutoDowngrade(...)`), so this never
    ///   overrides an intentional proxy-on — it only adds the thermal safety net.
    public static func shouldAutoDowngrade(
        thermalState: ThermalState,
        autoProxyOnThermalPressure: Bool
    ) -> Bool {
        guard autoProxyOnThermalPressure else { return false }
        return thermalState.shouldDowngradeToProxy
    }
}
