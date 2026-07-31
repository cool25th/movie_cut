import Foundation

/// The compositing blend mode applied to a clip when it overlays another clip.
///
/// Raw values are stable identifiers persisted to project JSON, so renaming a
/// Swift case must not change its string. Defaults to `.normal` (source-over),
/// which is the historical multi-track layering behavior. Adding `.blendMode`
/// to a `Clip` therefore introduces no change for projects that predate the
/// field: the missing key decodes to `.normal` and the value is omitted on
/// encode when it equals the default.
///
/// (Requirements 4.4, 4.7 — CapCut parity for clip blending.)
public enum BlendMode: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    /// Source-over compositing. Identical to the layering behavior before this
    /// field existed; a `.normal` clip must not change export pixels.
    case normal

    /// Multiplies the overlay color with the base, darkening the result.
    case multiply

    /// Screens the overlay over the base, brightening the result.
    case screen

    /// Multiply + screen: keeps darks dark and lights light, raises contrast.
    case overlay

    /// A softer, lower-contrast variant of overlay.
    case softLight

    /// A harsher, higher-contrast variant of overlay.
    case hardLight

    /// Keeps the darker of the overlay / base per channel.
    case darken

    /// Keeps the lighter of the overlay / base per channel.
    case lighten

    /// Shows the base through the overlay where the overlay is dark.
    case colorDodge

    /// Darkens the base to reflect the overlay where the overlay is light.
    case colorBurn

    /// Adds the two images, clamped to white.
    case add

    /// Subtracts the overlay from the base, clamped to black.
    case subtract

    /// The default blend mode used when a project predates the `blendMode`
    /// field. Kept as a named accessor so the "missing key → normal" rule
    /// reads at the call site.
    public static var defaultValue: BlendMode { .normal }
}
