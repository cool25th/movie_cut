import CoreGraphics
import CoreImage
import Foundation
import Testing

/// Deterministic, sandbox-safe pixel rendering for golden tests.
///
/// **Why this exists.** The legacy pixel tests call a `coreImageRenderingAvailable()`
/// sentinel and *silently skip* their pixel assertions when the default,
/// GPU-backed `CIContext` returns transparent black in a headless / sandboxed
/// runner. That turns golden coverage into false confidence — the assertions
/// never actually run in CI, which is exactly how the drag-and-drop runtime
/// regression slipped past a "passing" suite.
///
/// `GoldenPixel` renders through a **software** `CIContext`, which produces
/// real, reproducible pixels in headless environments (empirically identical to
/// the GPU path for these fixtures), and exposes ``assertRendererFunctional()``
/// so a broken renderer **fails loudly** instead of being skipped. Values are
/// deterministic across machines within a small rounding tolerance, so they can
/// be committed as goldens.
///
/// CoreImage applies `CIColorControls` in linear light, so the committed golden
/// values reflect sRGB→linear→sRGB round-tripping rather than naive byte math.
enum GoldenPixel {
    /// Software renderer: deterministic and functional in headless environments.
    /// `CIContext` is documented thread-safe, so static sharing is sound.
    nonisolated(unsafe) static let context = CIContext(options: [.useSoftwareRenderer: true])

    struct RGBA: Equatable, CustomStringConvertible {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var a: UInt8

        init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
            self.r = r
            self.g = g
            self.b = b
            self.a = a
        }

        var description: String { "RGBA(\(r),\(g),\(b),\(a))" }
    }

    /// A 1×1 solid-color source image in device RGB.
    static func solid(_ color: RGBA) -> CIImage {
        CIImage(
            bitmapData: Data([color.r, color.g, color.b, color.a]),
            bytesPerRow: 4,
            size: CGSize(width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
    }

    /// Renders and samples the pixel at the image origin.
    static func sample(_ image: CIImage) -> RGBA {
        let bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(
                image.cropped(to: bounds),
                toBitmap: buffer.baseAddress!,
                rowBytes: 4,
                bounds: bounds,
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }
        return RGBA(bytes[0], bytes[1], bytes[2], bytes[3])
    }

    /// Fails the current test — loudly, never skips — when the software renderer
    /// cannot reproduce a known mid-gray sentinel. Call at the top of a golden
    /// test so a non-functional renderer is reported instead of hidden.
    static func assertRendererFunctional() {
        let s = sample(solid(RGBA(89, 89, 89)))
        let transparentBlack = s.r == 0 && s.g == 0 && s.b == 0 && s.a == 0
        #expect(
            !transparentBlack,
            "Software CIContext returned transparent black for a non-black sentinel; golden pixel tests cannot run reliably in this environment."
        )
        #expect(
            abs(Int(s.r) - 89) <= 6 && abs(Int(s.g) - 89) <= 6 && abs(Int(s.b) - 89) <= 6 && s.a == 255,
            "Software CIContext sentinel out of range (got \(s), expected ~RGBA(89,89,89,255))."
        )
    }

    /// Asserts each channel of `actual` is within `tolerance` of the committed
    /// `golden`. Tolerance absorbs cross-machine rounding while still catching a
    /// real regression in the processor output.
    static func expectClose(
        _ actual: RGBA,
        _ golden: RGBA,
        tolerance: Int = 2,
        _ label: String = ""
    ) {
        func near(_ a: UInt8, _ g: UInt8) -> Bool { abs(Int(a) - Int(g)) <= tolerance }
        #expect(
            near(actual.r, golden.r)
                && near(actual.g, golden.g)
                && near(actual.b, golden.b)
                && near(actual.a, golden.a),
            "\(label) golden mismatch: got \(actual), expected \(golden) (±\(tolerance))"
        )
    }
}
