import CoreImage
import CoreVideo
import Foundation

/// The color-management contract for every render surface in MovieCut.
///
/// `RenderColorConfiguration` is the single source of truth for the working and
/// destination color spaces of every `CIContext` that produces visible pixels or
/// encodes an export. Prior to this type, each `CIContext()` call site left the
/// working/output color space implicit, so Core Image picked one heuristically
/// (often DisplayP3 on macOS, sRGB on iOS, and differently across GPU vs.
/// software renderers). Live preview went through `AVPlayerLayer` (Apple's
/// color-managed path) while export went through an unmanaged default context,
/// so the two pipelines could not produce identical pixels for any non-trivial
/// source — the root cause of preview↔export drift.
///
/// Pinning a single explicit configuration here makes the "same project → same
/// pixels" claim true by construction: every render surface evaluates filters in
/// the same working space and writes into the same destination space. v1 ships
/// **SDR Rec.709 only**; widening to DisplayP3 / HDR is a change to
/// ``RenderColorConfiguration`` alone, not a sweep of call sites.
public enum RenderColorConfiguration {
    /// The working color space every render `CIContext` must use.
    ///
    /// Filters (color correction, grade, chroma key, …) are evaluated in this
    /// space, so a value computed against it in preview must reproduce it in
    /// export. sRGB Rec.709 is the v1 contract.
    public static let workingColorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// The destination color space rendered pixels land in.
    ///
    /// Equal to the working space for v1: the SDR pipeline is end-to-end Rec.709.
    public static let destinationColorSpace: CGColorSpace = workingColorSpace

    /// The pixel format rendered frames are carried in through the pipeline.
    ///
    /// v1 is an 8-bit SDR pipeline; this is the format every compositor, scope,
    /// sampler, and overlay target must request. HDR/10-bit is out of scope for
    /// v1 (see the HDR feature flag), so a single fixed format here also prevents
    /// an 8-bit compositor from silently quantizing a 10-bit signal and then
    /// re-tagging the output as HDR.
    public static let renderedPixelFormat: OSType = kCVPixelFormatType_32BGRA

    /// The Core Image context options that pin the working + destination spaces.
    ///
    /// Pass these to `CIContext(options:)` (merged with any site-specific
    /// options such as `.useSoftwareRenderer`) so no context is ever constructed
    /// with an implicit color space. A non-nil `workingColorSpace` disables Core
    /// Image's per-context heuristic; setting `outputColorSpace` ensures
    /// `render(_:to:)` destinations are tagged consistently. Computed so each
    /// call site gets a fresh dictionary (the option type carries `Any` values).
    public static var contextOptions: [CIContextOption: Any] {
        [
            .workingColorSpace: workingColorSpace,
            .outputColorSpace: destinationColorSpace
        ]
    }

    /// Creates the compositor input image for a decoded source frame, pinned to
    /// the working color space.
    ///
    /// AVFoundation's two composition legs tag their decoded BGRA source
    /// buffers differently: AVPlayer (preview) attaches an ICC color space —
    /// "Composite NTSC" for untagged BT.601 SD, for example — while
    /// AVAssetExportSession (export) leaves `kCVImageBufferCGColorSpaceKey`
    /// unset. A bare `CIImage(cvPixelBuffer:)` therefore color-managed the
    /// preview render from the decoder's ICC space into the pinned sRGB working
    /// space but passed export values through, rotating hues on the preview leg
    /// only (pure red (254,0,0) → (247,36,0), parity MAD 10.25 on the
    /// crop-rect video scenario). Overriding the input color space here makes
    /// both legs interpret source bytes identically — the "same project → same
    /// pixels" contract this type exists to enforce.
    public static func sourceImage(from pixelBuffer: CVPixelBuffer) -> CIImage {
        CIImage(cvPixelBuffer: pixelBuffer, options: [.colorSpace: workingColorSpace])
    }
}
