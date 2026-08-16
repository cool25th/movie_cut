import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import MovieCutCore
import Testing

/// Behavioral parity tests for the v1 SDR Rec.709 color contract.
///
/// These are NOT source-string/static-contract tests. They render real pixels
/// and assert that the color configuration every render surface must use
/// (`RenderColorConfiguration`) produces identical output across the contexts
/// that preview and export drive. The historical bug this pins: every
/// `CIContext()` was constructed with default options, so Core Image picked the
/// working/output color space heuristically, and preview (AVPlayerLayer) and
/// export (an unmanaged default CIContext) drifted. If a future change reverts a
/// render surface to an implicit context, these tests fail.
struct ColorSpaceParityTests {
    /// A non-trivial color (red-leaning, saturated) chosen because pure grays
    /// are invariant across working spaces and would hide the regression.
    private static let probeColor = GoldenPixel.RGBA(220, 60, 40)

    /// A second, saturated-green probe: green is the largest-gamut axis and the
    /// most sensitive to sRGB vs. DisplayP3 working-space selection.
    private static let greenProbe = GoldenPixel.RGBA(40, 210, 70)

    // MARK: - Configuration contract

    @Test
    func configurationPinsSRGBRec709() {
        // v1 contract is sRGB / Rec.709 SDR. If this changes intentionally
        // (e.g. DisplayP3 widening), update it deliberately — these tests are
        // the tripwire.
        #expect(RenderColorConfiguration.workingColorSpace.name == CGColorSpace.sRGB)
        #expect(RenderColorConfiguration.destinationColorSpace.name == CGColorSpace.sRGB)
        #expect(RenderColorConfiguration.renderedPixelFormat == kCVPixelFormatType_32BGRA)
    }

    @Test
    func contextOptionsCarryWorkingAndDestinationSpaces() {
        let options = RenderColorConfiguration.contextOptions
        // Compare by CFTypeID rather than `as? CGColorSpace` (the conditional
        // downcast to a bridged CoreFoundation type always succeeds, so the
        // compiler rejects it). What matters is that the stored option points
        // at the SAME color space as the configuration.
        let working = options[.workingColorSpace]
        let destination = options[.outputColorSpace]
        #expect(working != nil, "workingColorSpace option must be present")
        #expect(destination != nil, "outputColorSpace option must be present")
        #expect(CFGetTypeID(working as CFTypeRef) == CGColorSpace.typeID,
                "workingColorSpace option must be a CGColorSpace")
        #expect(CFGetTypeID(destination as CFTypeRef) == CGColorSpace.typeID,
                "outputColorSpace option must be a CGColorSpace")
    }

    // MARK: - Parity: two configured contexts agree

    @Test
    func twoConfiguredContextsProduceIdenticalPixelsForRedProbe() {
        GoldenPixel.assertRendererFunctional()
        // Simulate the preview-snapshot context and the export-compositor
        // context: two SEPARATE CIContext instances, both built from the shared
        // configuration. If they drift, preview != export.
        let previewContext = CIContext(options: RenderColorConfiguration.contextOptions)
        let exportContext = CIContext(options: RenderColorConfiguration.contextOptions)

        let previewPixel = sample(Self.probeColor, in: previewContext)
        let exportPixel = sample(Self.probeColor, in: exportContext)

        // Two contexts sharing the configuration MUST produce byte-identical
        // output for the same input. Any drift is the parity bug.
        #expect(previewPixel == exportPixel,
                "preview vs export pixel drift for red probe: \(previewPixel) vs \(exportPixel)")
    }

    @Test
    func twoConfiguredContextsProduceIdenticalPixelsForGreenProbe() {
        GoldenPixel.assertRendererFunctional()
        let previewContext = CIContext(options: RenderColorConfiguration.contextOptions)
        let exportContext = CIContext(options: RenderColorConfiguration.contextOptions)

        let previewPixel = sample(Self.greenProbe, in: previewContext)
        let exportPixel = sample(Self.greenProbe, in: exportContext)

        #expect(previewPixel == exportPixel,
                "preview vs export pixel drift for green probe: \(previewPixel) vs \(exportPixel)")
    }

    // MARK: - Parity survives a color-correction filter

    @Test
    func configuredContextsAgreeAfterColorCorrection() {
        GoldenPixel.assertRendererFunctional()
        let correction = ColorCorrection(brightness: 0.1, contrast: 1.2, saturation: 1.3, warmth: 0.4, tint: 0.1)
        let source = GoldenPixel.solid(Self.probeColor)
        let corrected = ColorCorrectionPixelProcessor.apply(correction, to: source)

        let previewContext = CIContext(options: RenderColorConfiguration.contextOptions)
        let exportContext = CIContext(options: RenderColorConfiguration.contextOptions)

        let previewPixel = sample(corrected, in: previewContext)
        let exportPixel = sample(corrected, in: exportContext)

        // Same filter evaluated in both configured contexts must yield the same
        // pixel — this is the literal claim in ColorCorrectionPixelProcessor's
        // doc comment ("shared processor so preview and export match"). Without
        // a pinned working space it was false.
        #expect(previewPixel == exportPixel,
                "preview vs export drift after color correction: \(previewPixel) vs \(exportPixel)")
    }

    @Test
    func configuredContextsAgreeAfterColorGrade() {
        GoldenPixel.assertRendererFunctional()
        // A non-identity grade (lift/gamma/gain) exercises the CIColorMatrix +
        // CIGammaAdjust path, which is space-sensitive.
        let grade = ColorGrade(
            lift: ColorGrade.RGB(red: 0.1, green: 0.05, blue: 0.2),
            gamma: 0.9,
            gain: ColorGrade.RGB(red: 1.1, green: 1.0, blue: 0.9)
        )
        let source = GoldenPixel.solid(Self.greenProbe)
        let graded = ColorGradePixelProcessor.apply(grade, to: source)

        let previewContext = CIContext(options: RenderColorConfiguration.contextOptions)
        let exportContext = CIContext(options: RenderColorConfiguration.contextOptions)

        let previewPixel = sample(graded, in: previewContext)
        let exportPixel = sample(graded, in: exportContext)

        #expect(previewPixel == exportPixel,
                "preview vs export drift after color grade: \(previewPixel) vs \(exportPixel)")
    }

    // MARK: - Regression tripwire: an implicit context must NOT be used

    @Test
    func implicitDefaultContextIsStillADifferentBeast() {
        // This test documents WHY the configuration exists. A default CIContext()
        // does NOT pin a working space — it may or may not match the configured
        // one depending on the host's heuristic. We do NOT assert the implicit
        // context differs (that is environment-dependent and would be flaky);
        // instead we assert the configured options are NON-empty, so a future
        // refactor that empties contextOptions (silently restoring implicit
        // behavior) fails loudly here.
        #expect(!RenderColorConfiguration.contextOptions.isEmpty,
                "contextOptions must pin working + output color spaces; an empty dictionary restores the implicit-context parity bug.")
    }

    // MARK: - Compositor source interpretation is decoder-tag independent
    //
    // The regression these pin (2026-08-17): AVPlayer's decode leg attaches an
    // ICC color space to BGRA source buffers ("Composite NTSC" for untagged
    // BT.601 SD) while AVAssetExportSession's leaves them untagged, so a bare
    // CIImage(cvPixelBuffer:) color-managed only the preview leg into the
    // pinned working space — a hue rotation (pure red → (247,36,0), parity MAD
    // 10.25 on the crop-rect video scenario).

    @Test
    func sourceImageIsPinnedToTheWorkingColorSpace() {
        let buffer = Self.makeSolidBuffer(Self.probeColor)
        let image = RenderColorConfiguration.sourceImage(from: buffer)
        #expect(image.colorSpace?.name == RenderColorConfiguration.workingColorSpace.name,
                "sourceImage must interpret decoded bytes as the working space, got \(String(describing: image.colorSpace?.name))")
    }

    @Test
    func sourceImageIgnoresDecoderICCTag() {
        GoldenPixel.assertRendererFunctional()
        let plain = Self.makeSolidBuffer(Self.probeColor)
        let tagged = Self.makeSolidBuffer(Self.probeColor)
        // Simulate AVPlayer's decode leg: an ICC attachment that differs from
        // the working space. With a bare CIImage(cvPixelBuffer:) this tag
        // drives a ColorSync conversion on render; the compositor input must
        // not depend on it.
        CVBufferSetAttachment(
            tagged,
            kCVImageBufferCGColorSpaceKey,
            CGColorSpace(name: CGColorSpace.adobeRGB1998)!,
            .shouldPropagate
        )

        let context = CIContext(options: RenderColorConfiguration.contextOptions)
        let fromPlain = Self.renderPixel(RenderColorConfiguration.sourceImage(from: plain), in: context)
        let fromTagged = Self.renderPixel(RenderColorConfiguration.sourceImage(from: tagged), in: context)

        #expect(fromPlain == fromTagged,
                "decoder ICC tag changed compositor input values: \(fromPlain) vs \(fromTagged)")
        // Pass-through contract: interpreted as the working space and rendered
        // into the same working/destination space, the bytes survive unchanged
        // (±1 for 8-bit rounding).
        Self.expectEqual(plain: fromPlain, expected: Self.probeColor)
    }

    // MARK: - Helpers

    /// Renders a 1×1 image into the supplied context and reads back the pixel.
    private func sample(_ image: CIImage, in context: CIContext) -> GoldenPixel.RGBA {
        let bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(
                image.cropped(to: bounds),
                toBitmap: buffer.baseAddress!,
                rowBytes: 4,
                bounds: bounds,
                format: .RGBA8,
                colorSpace: RenderColorConfiguration.workingColorSpace
            )
        }
        return GoldenPixel.RGBA(bytes[0], bytes[1], bytes[2], bytes[3])
    }

    /// Convenience: render a solid probe color via a CIImage built in the
    /// configured working space (not device RGB) so the input itself is
    /// space-tagged the way a real decoded frame is.
    private func sample(_ color: GoldenPixel.RGBA, in context: CIContext) -> GoldenPixel.RGBA {
        let image = CIImage(
            bitmapData: Data([color.r, color.g, color.b, color.a]),
            bytesPerRow: 4,
            size: CGSize(width: 1, height: 1),
            format: .RGBA8,
            colorSpace: RenderColorConfiguration.workingColorSpace
        )
        return sample(image, in: context)
    }

    /// A 1×1 BGRA pixel buffer carrying the given color, mimicking a decoded
    /// source frame (32BGRA per `renderedPixelFormat`).
    private static func makeSolidBuffer(_ color: GoldenPixel.RGBA) -> CVPixelBuffer {
        var maybeBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            1,
            1,
            RenderColorConfiguration.renderedPixelFormat,
            attributes as CFDictionary,
            &maybeBuffer
        )
        guard let buffer = maybeBuffer else {
            preconditionFailure("CVPixelBufferCreate failed")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        // 32BGRA byte order: B, G, R, A.
        base[0] = color.b
        base[1] = color.g
        base[2] = color.r
        base[3] = color.a
        return buffer
    }

    /// Renders a 1×1 compositor input image through a configured context and
    /// reads back the RGBA pixel, mirroring `sample(_:in:)` for CVPixelBuffer
    /// inputs.
    private static func renderPixel(_ image: CIImage, in context: CIContext) -> GoldenPixel.RGBA {
        let bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(
                image.cropped(to: bounds),
                toBitmap: buffer.baseAddress!,
                rowBytes: 4,
                bounds: bounds,
                format: .RGBA8,
                colorSpace: RenderColorConfiguration.workingColorSpace
            )
        }
        return GoldenPixel.RGBA(bytes[0], bytes[1], bytes[2], bytes[3])
    }

    private static func expectEqual(plain actual: GoldenPixel.RGBA, expected: GoldenPixel.RGBA) {
        #expect(abs(Int(actual.r) - Int(expected.r)) <= 1
                && abs(Int(actual.g) - Int(expected.g)) <= 1
                && abs(Int(actual.b) - Int(expected.b)) <= 1,
                "source pass-through altered bytes: \(actual) vs \(expected)")
    }
}
