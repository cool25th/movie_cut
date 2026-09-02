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
    /// ON since capcut-surpass stage-3 increment B (2026-09-02): the explicit
    /// writer path now produces a VERIFIED 10-bit master — the reader requests
    /// a 420YpCbCr10BiPlanar surface, both compositors render HDR destinations
    /// through the Rec.2020 HLG color space, and the e2e probe
    /// (`run_e2e_export.sh`, `MOVIECUT_UITEST_EXPORT_PROFILE=hevcHDR`)
    /// confirmed the actual file carries Main 10 / yuv420p10le / bt2020 /
    /// arib-std-b67 / bt2020nc while SDR stays 8-bit Rec.709. Known limit:
    /// PREVIEW still renders SDR (the HDR-source preview drift is BUG-CA12-02
    /// / G-29 scope) — the flag governs the export surface only.
    public static let hdrMaster = true

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
