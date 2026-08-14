import Foundation

/// Product-level feature gates that define what the v1 Mac-first release exposes.
///
/// `FeatureFlag` is the single switchboard for narrowing v1 to "Mac video
/// editing, SDR Rec.709, App Store only". Features that are *implemented* but
/// deliberately *hidden* from v1 are gated here rather than deleted, so the
/// code stays available for a later release and there is one place to re-enable
/// them. Each flag documents *why* it is off for v1 so the gate is auditable.
///
/// Flags are compile-time `let`s, not runtime-toggled: v1's scope is fixed at
/// build time and should not be accidentally widened by a config change. When a
/// feature graduates, flip its flag here and update the consuming UI/logic.
public enum FeatureFlag {
    /// HDR mastering (10-bit HEVC Rec.2020/HLG export).
    ///
    /// OFF for v1 because the render pipeline is 8-bit SDR end to end
    /// (`RenderColorConfiguration`), so an HDR export would silently re-tag
    /// 8-bit pixels as HDR — the output would lie about its own depth. Re-enable
    /// only after a real 10-bit compositor + HDR preview path exist. See the
    /// Phase 1 render-reliability plan.
    public static let hdrMaster = false

    /// Standalone card-news authoring (multi-page artboard workflow).
    ///
    /// OFF for v1 to keep the release focused on video editing. The Core text /
    /// shape / layout models stay; the card-news *UI* and its entry points are
    /// hidden. Derived content from video (thumbnails, 9:16/1:1 conversion,
    /// subtitle-to-card) can still ship as multi-format *export* without this.
    public static let cardNewsStudio = false

    /// The full iOS editor.
    ///
    /// OFF for v1 (Mac App Store only). iOS can still build and share the Core,
    /// but it is not a shipping surface this release; the iOS parity gaps
    /// (`IOSExportEngine` preset approximation, no blend/transition wiring) are
    /// deferred until after the Mac launch stabilizes the render contract.
    public static let iosFullEditor = false
}
