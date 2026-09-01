import CoreImage
import CoreVideo
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutMac

/// LF-ACTION-03 (2026-09-01 longform BLOCKER): a portrait frame aspect-fitted
/// into a landscape canvas leaves transparent pillarbox bands. The export
/// path renders that image into `renderContext.newPixelBuffer()` buffers,
/// which AVFoundation recycles from a pool — a buffer that previously held a
/// full-width landscape frame must not leak its pillars into the transparent
/// bands of the next frame. Observed in the 5/10-minute effect exports as
/// prior-scene bleed in all portrait sections.
///
/// These tests exercise the REAL output path shape: the compositor's
/// `fittedToCanvas` + `CanvasBackgroundPixelProcessor.compose` with a nil
/// project background, rendered through a shared CIContext into a pixel
/// buffer whose storage previously held the prior frame.
@Suite("Canvas contamination (LF-ACTION-01/03)")
struct CanvasContaminationPixelTests {
    private static let canvas = CGSize(width: 320, height: 180) // 16:9
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    private enum PixelError: Error { case poolCreation(OSStatus), readback }

    /// Renders `image` into a pixel buffer the way `finishRequest` does:
    /// no explicit clear of the destination storage. The buffer is created
    /// fresh each call but from the same IOSurface-backed allocation shape,
    /// mirroring `renderContext.newPixelBuffer()` recycling; the first test
    /// below proves whether prior content survives.
    private static func renderIntoBuffer(_ image: CIImage) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(canvas.width),
            Int(canvas.height),
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
            ] as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw PixelError.poolCreation(status)
        }
        ciContext.render(image, to: buffer)
        return buffer
    }

    /// A full-canvas opaque image, as a landscape source frame produces.
    private static func fullCanvasImage(red: CGFloat, green: CGFloat, blue: CGFloat) -> CIImage {
        CIImage(color: CIColor(red: red, green: green, blue: blue))
            .cropped(to: CGRect(origin: .zero, size: canvas))
    }

    /// A 9:16 portrait frame centered by the compositor's own aspect-fit.
    private static func fittedPortraitFrame(color: CIColor) -> CIImage {
        let portrait = CIImage(color: color)
            .cropped(to: CGRect(x: 0, y: 0, width: 90, height: 160))
        return CustomVideoCompositor.fittedToCanvas(portrait, canvasSize: canvas)
    }

    /// Reads one BGRA pixel from a locked buffer.
    private static func pixel(
        _ buffer: CVPixelBuffer, x: Int, y: Int
    ) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?
            .assumingMemoryBound(to: UInt8.self) else { throw PixelError.readback }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let offset = y * bytesPerRow + x * 4
        // BGRA byte order on little-endian
        return (base[offset + 2], base[offset + 1], base[offset], base[offset + 3])
    }

    /// LF-ACTION-01 invariant: the nil-background export output must have
    /// finite extent exactly equal to the canvas, and every canvas pixel must
    /// be determined by the frame itself — the pillarbox must be opaque
    /// black, not transparent. Transparency is what lets recycled codec
    /// buffer content (the previous scene) show through in pooled renders.
    /// Probed by compositing the output over a contaminating red canvas: a
    /// transparent pillar lets red through, a black pillar does not.
    @Test("Nil-background fitted frame determines every canvas pixel")
    func nilBackgroundFrameDeterminesEveryCanvasPixel() throws {
        let fitted = Self.fittedPortraitFrame(color: CIColor(red: 0, green: 1, blue: 0))
        let output = CanvasBackgroundPixelProcessor.compose(
            frame: fitted, over: nil, renderSize: Self.canvas
        )
        #expect(output.extent == CGRect(origin: .zero, size: Self.canvas))

        let contaminated = output.composited(
            over: Self.fullCanvasImage(red: 1, green: 0, blue: 0)
        )
        let buffer = try Self.renderIntoBuffer(contaminated)

        let center = try Self.pixel(buffer, x: 160, y: 90)
        #expect(center.g > 200 && center.r < 50, "portrait body lost: \(center)")

        for x in [4, 40, 80, 240, 276, 315] {
            let p = try Self.pixel(buffer, x: x, y: 90)
            #expect(
                p.r < 8 && p.g < 8 && p.b < 8,
                "pillar at x=\(x) is transparent — contaminating canvas shows through: r=\(p.r) g=\(p.g) b=\(p.b)"
            )
        }
    }

    /// LF-ACTION-03 defect root: the finished frame under a nil project
    /// background must be OPAQUE across the entire canvas. The 5/10-minute
    /// effect exports leaked the previous landscape scene into every
    /// portrait section's pillarbox because `compose(frame: nil, …)` is a
    /// pass-through that leaves the fitted frame's pillarbox fully
    /// transparent — pooled destination buffers then show whatever the
    /// storage previously held. Alpha readback catches the transparency
    /// that an RGB-only check over black cannot.
    @Test("Nil-background finished frame is opaque across the whole canvas")
    func nilBackgroundFrameIsOpaqueAcrossCanvas() throws {
        let fitted = Self.fittedPortraitFrame(color: CIColor(red: 0, green: 1, blue: 0))
        let finished = CanvasBackgroundPixelProcessor.compose(
            frame: fitted, over: nil, renderSize: Self.canvas
        )
        let buffer = try Self.renderIntoBuffer(finished)

        for x in [4, 40, 80, 160, 240, 276, 315] {
            let p = try Self.pixel(buffer, x: x, y: 90)
            #expect(
                p.a >= 250,
                "pixel at x=\(x) has alpha=\(p.a) — transparent pillar lets recycled buffer content (previous scene) show through"
            )
            if x != 160 { // pillars
                #expect(
                    p.r < 8 && p.g < 8 && p.b < 8,
                    "pillar at x=\(x) not black: r=\(p.r) g=\(p.g) b=\(p.b)"
                )
            }
        }
    }
}
