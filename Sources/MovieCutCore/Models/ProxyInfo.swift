import Foundation

/// Metadata about an optional proxy media file.
public struct ProxyInfo: Codable, Sendable, Equatable {
    /// The proxy media URL, when generated.
    public var proxyURL: URL?

    /// The proxy frame size.
    public var resolution: CGSize?

    /// Creates proxy metadata.
    public init(proxyURL: URL? = nil, resolution: CGSize? = nil) {
        self.proxyURL = proxyURL
        self.resolution = resolution
    }
}

/// Whether a clip shows a proxy badge, and whether that proxy is what preview
/// is actually playing.
///
/// `CAPCUT_BENCHMARK_STANDARD.md` B-I7 asks for a badge on the clip "once
/// generation completes". MovieCut splits generation (per asset) from
/// consumption (the project-wide `PlaybackSettings.useProxyPlayback` toggle) —
/// a split CapCut's single Proxy Mode does not have. A badge that only meant
/// "a proxy file exists" would leave a user wondering why preview is still
/// slow, so the badge carries both facts: it appears as soon as a proxy exists
/// (matching B-I7) and distinguishes whether that proxy is in effect.
public enum ProxyBadgeState: String, Sendable, Equatable, CaseIterable {
    /// A proxy file exists but preview is still playing the original.
    case idle
    /// The proxy is what preview is playing.
    case active
    /// The proxy is what preview is playing because of thermal pressure (S7).
    /// Distinct from `.active` so the UI can show *why* the quality dropped —
    /// an unexplained drop reads as a bug.
    case thermalActive
    /// Preview is rendering below full canvas resolution because the user chose
    /// a performance-priority preview quality (Requirement 5). This is the
    /// lowest-priority quality-degradation cause; a simultaneously-active proxy
    /// or thermal cause takes the badge instead. Like `.active`, it carries a
    /// reason for a visible quality drop rather than a "proxy ready" hint.
    case previewQualityReduced

    /// Resolves the badge state for one media asset.
    ///
    /// - Parameters:
    ///   - proxy: the asset's proxy metadata, if any.
    ///   - useProxyPlayback: the project's proxy-playback setting.
    /// - Returns: `nil` when no proxy file exists, meaning no badge is shown.
    ///   `ProxyInfo` with a `nil` `proxyURL` counts as no proxy — the struct can
    ///   exist before generation finishes.
    public static func resolve(proxy: ProxyInfo?, useProxyPlayback: Bool) -> ProxyBadgeState? {
        guard proxy?.proxyURL != nil else { return nil }
        return useProxyPlayback ? .active : .idle
    }

    /// Resolves the badge state, distinguishing a thermal-driven auto-downgrade.
    /// `autoDowngraded` is true only when the engine dropped to the proxy
    /// because of heat (not because the user toggled proxy playback). (S7)
    public static func resolve(
        proxy: ProxyInfo?,
        useProxyPlayback: Bool,
        autoDowngraded: Bool
    ) -> ProxyBadgeState? {
        guard proxy?.proxyURL != nil else { return nil }
        if useProxyPlayback { return .active }
        return autoDowngraded ? .thermalActive : .idle
    }
}

/// The distinct reasons preview quality can be below full (Requirement 5.4).
///
/// More than one cause can be active at once — e.g. the user picked a reduced
/// preview quality *and* a thermal downgrade fired. The badge must show a single
/// cause (the highest-priority one) so it never stacks icons, while the full set
/// is surfaced in the accessibility label / tooltip so a screen-reader user
/// hears every active reason.
public enum QualityDegradeCause: String, Sendable, Equatable, CaseIterable {
    /// The engine auto-dropped to a proxy under serious/critical thermal
    /// pressure (S7). Highest priority: heat is involuntary and urgent.
    case thermalDowngrade
    /// The engine clamped the preview render size (e.g. to 1/2) under thermal
    /// pressure (.fair+) — the first, gentler rung of gradual degradation
    /// before the proxy flip. Same glyph as a manual quality reduction, but
    /// listed as its own cause so the tooltip explains WHY.
    case thermalPreviewScale
    /// The user turned on proxy playback manually (B-I7).
    case manualProxy
    /// The user lowered the preview render quality manually (Requirement 5).
    /// Lowest priority: it is the user's own, deliberate choice.
    case manualPreviewQuality
}

/// Resolved quality-degradation display state for a clip's preview badge
/// (Requirement 5.4).
///
/// Carries two things at once:
/// - `primaryState`: the **single** `ProxyBadgeState` the badge glyph draws —
///   the highest-priority active cause, so icons never stack.
/// - `activeCauses`: **every** simultaneously-active cause, in priority order,
///   which the accessibility label / tooltip enumerates verbatim.
public struct QualityDegradeDisplayState: Sendable, Equatable {
    /// The one badge state to draw. `nil` means no quality-degradation badge at
    /// all (no causes active, or the asset has no proxy and no reduced quality).
    public let primaryState: ProxyBadgeState?

    /// Every active cause, highest priority first. Empty when there is nothing
    /// to report. The badge shows only `primaryState`; this list is for the
    /// spoken/tooltip description so a user hears all reasons, not just the top
    /// one.
    public let activeCauses: [QualityDegradeCause]

    public init(primaryState: ProxyBadgeState?, activeCauses: [QualityDegradeCause]) {
        self.primaryState = primaryState
        self.activeCauses = activeCauses
    }
}

extension ProxyBadgeState {
    /// Resolves the full quality-degradation display state across all causes
    /// (Requirement 5.4). Pure and device-free so it is unit-testable in Core.
    ///
    /// Priority (badge shows exactly one cause): thermal downgrade > manual
    /// proxy > manual preview quality. The full set of active causes is returned
    /// in `activeCauses` for the accessibility label / tooltip — the badge glyph
    /// itself never stacks icons.
    ///
    /// - Parameters:
    ///   - proxy: the asset's proxy metadata, if any. `ProxyInfo` with a `nil`
    ///     `proxyURL` counts as no proxy.
    ///   - useProxyPlayback: the project's proxy-playback setting (manual proxy).
    ///   - autoDowngraded: true only when the engine dropped to the proxy
    ///     because of heat (S7), not because of the user toggle.
    ///   - previewQuality: the project's preview render quality. Anything other
    ///     than `.full` counts as a manual preview-quality reduction.
    /// - Returns: A `QualityDegradeDisplayState` with the single primary badge
    ///   state and the full ordered list of active causes. When nothing is
    ///   active but a proxy file exists and is unused, the result is the legacy
    ///   `.idle` hint (no quality drop, just "proxy ready"). When no proxy
    ///   exists and quality is full, `primaryState` is `nil` and the badge is
    ///   not drawn.
    public static func resolve(
        proxy: ProxyInfo?,
        useProxyPlayback: Bool,
        autoDowngraded: Bool,
        previewQuality: PreviewQuality,
        thermalPreviewScale: Bool = false
    ) -> QualityDegradeDisplayState {
        let hasProxy = proxy?.proxyURL != nil
        let reducedPreview = previewQuality != .full

        // Gather every active cause, then order them by priority. Building the
        // list first (rather than short-circuiting) is what lets the
        // accessibility label report simultaneous causes.
        var causes: [QualityDegradeCause] = []
        if autoDowngraded { causes.append(.thermalDowngrade) }
        if thermalPreviewScale { causes.append(.thermalPreviewScale) }
        if useProxyPlayback { causes.append(.manualProxy) }
        if reducedPreview { causes.append(.manualPreviewQuality) }
        // Keep the list in canonical priority order regardless of input order.
        let priorityOrder: [QualityDegradeCause] = [.thermalDowngrade, .thermalPreviewScale, .manualProxy, .manualPreviewQuality]
        let orderedCauses = priorityOrder.filter { causes.contains($0) }

        // The badge draws exactly one state: the highest-priority cause, or a
        // legacy idle/nil hint when no degradation is active.
        let primaryState: ProxyBadgeState?
        if let top = orderedCauses.first {
            primaryState = Self.state(for: top, hasProxy: hasProxy)
        } else if hasProxy {
            // Proxy exists but nothing is degrading quality — the "ready but
            // not in use" hint, not a quality drop.
            primaryState = .idle
        } else {
            primaryState = nil
        }

        return QualityDegradeDisplayState(primaryState: primaryState, activeCauses: orderedCauses)
    }

    /// Maps a single cause to the badge state that represents it. Proxy-derived
    /// causes require a proxy file to actually exist; if the cause is active but
    /// the asset has no proxy file (e.g. thermal downgrade requested but
    /// generation not finished), the badge still shows the cause so the user
    /// sees *why* quality dropped rather than a silent gap.
    private static func state(for cause: QualityDegradeCause, hasProxy: Bool) -> ProxyBadgeState {
        switch cause {
        case .thermalDowngrade:
            return .thermalActive
        case .thermalPreviewScale:
            return .previewQualityReduced
        case .manualProxy:
            return .active
        case .manualPreviewQuality:
            return .previewQualityReduced
        }
    }
}
