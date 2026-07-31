import CoreImage
import Foundation

/// Composites two Core Image frames using a clip blend mode, for preview and
/// export. This is the shared Core processor both render paths route through so
/// a blended clip looks identical on the canvas and in the rendered file
/// (Requirement 4.2 / 4.7 — CapCut clip-blending parity).
///
/// The blend is applied as `overlay` onto `base`: the blending clip's pixels are
/// mixed into the frame beneath it, exactly like CapCut's per-clip blend mode.
/// The output is cropped to the `base` extent so it preserves the underlying
/// frame bounds — the same convention the other pixel processors
/// (`MaskPixelProcessor`, `ChromaKeyPixelProcessor`) use.
public enum BlendPixelProcessor {
    /// Composites `overlay` onto `base` using `mode`, preserving the `base`
    /// extent. `.normal` is plain source-over compositing and is byte-identical
    /// to a layering step that predates the blend-mode feature.
    ///
    /// Callers that only need default layering should bypass this processor and
    /// composite directly (see task 5.3): `.normal` is provided here so the
    /// processor is total and independently testable.
    public static func apply(_ overlay: CIImage, over base: CIImage, mode: BlendMode) -> CIImage {
        let extent = base.extent

        // Source-over keeps the base extent by definition; route it through the
        // plain compositor so no blend filter is involved and the output stays
        // byte-identical to the pre-feature layering step (Requirement 4.3).
        guard let filterName = coreImageFilterName(for: mode) else {
            return overlay
                .composited(over: base)
                .cropped(to: extent)
        }

        // Core Image blend filters take the foreground as `inputImage` and the
        // backdrop as `inputBackgroundImage`. The resulting extent is the union
        // of the two, so crop back to the base frame bounds.
        return overlay
            .applyingFilter(
                filterName,
                parameters: [kCIInputBackgroundImageKey: base]
            )
            .cropped(to: extent)
    }

    /// Returns the Core Image blend-mode filter name for `mode`, or `nil` for
    /// `.normal` so the caller can take the plain source-over path.
    private static func coreImageFilterName(for mode: BlendMode) -> String? {
        switch mode {
        case .normal:
            return nil
        case .multiply:
            return "CIMultiplyBlendMode"
        case .screen:
            return "CIScreenBlendMode"
        case .overlay:
            return "CIOverlayBlendMode"
        case .softLight:
            return "CISoftLightBlendMode"
        case .hardLight:
            return "CIHardLightBlendMode"
        case .darken:
            return "CIDarkenBlendMode"
        case .lighten:
            return "CILightenBlendMode"
        case .colorDodge:
            return "CIColorDodgeBlendMode"
        case .colorBurn:
            return "CIColorBurnBlendMode"
        case .add:
            return "CIAdditionBlendMode"
        case .subtract:
            return "CISubtractBlendMode"
        }
    }
}
