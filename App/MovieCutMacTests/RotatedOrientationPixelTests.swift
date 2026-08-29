import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutMac

/// BUG-07 (CA-04 audit): a source carrying rotation metadata must render
/// UPRIGHT through every render path. The custom compositor orients its
/// storage frames via `orientedForDisplay` before the canvas fit — these
/// tests render an asymmetric buffer (left half red / right half blue, the
/// `ca04_rotated_asym` fixture's layout) through the compositor's real
/// CIImage pipeline and MEASURE the resulting pixels, pinning the
/// rotation-direction mapping for +90°, −90°, and 180° metadata.
@Suite("Rotated source orientation (BUG-07)")
struct RotatedOrientationPixelTests {
    /// A 320×240 BGRA buffer with the left half red and the right half blue.
    private func asymmetricBuffer() throws -> CVPixelBuffer {
        var maybe: CVPixelBuffer?
        CVPixelBufferCreate(nil, 320, 240, kCVPixelFormatType_32BGRA, nil, &maybe)
        let buffer = try #require(maybe)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = CVPixelBufferGetBaseAddress(buffer)!
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for row in 0..<240 {
            let line = base + row * rowBytes
            let pixels = UnsafeMutableRawBufferPointer(start: line, count: 320 * 4)
            for column in 0..<320 {
                // BGRA byte order, little-endian.
                let redSide = column < 160
                pixels[column * 4 + 0] = redSide ? 20 : 230  // B
                pixels[column * 4 + 1] = 20                   // G
                pixels[column * 4 + 2] = redSide ? 230 : 20   // R
                pixels[column * 4 + 3] = 255                  // A
            }
        }
        return buffer
    }

    /// Renders the buffer through the compositor's exact pipeline
    /// (sourceImage → orientedForDisplay → fittedToCanvas) into raw BGRA.
    private func renderCanvas(
        preferredTransform: CGAffineTransform,
        canvasSize: CGSize
    ) throws -> (pixels: [UInt8], width: Int, height: Int) {
        let image = CustomVideoCompositor.fittedToCanvas(
            CustomVideoCompositor.orientedForDisplay(
                RenderColorConfiguration.sourceImage(from: try asymmetricBuffer()),
                preferredTransform: preferredTransform
            ),
            canvasSize: canvasSize
        )
        let width = Int(canvasSize.width)
        let height = Int(canvasSize.height)
        var maybe: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &maybe)
        let output = try #require(maybe)
        CIContext().render(image, to: output)
        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }
        let base = CVPixelBufferGetBaseAddress(output)!
        let rowBytes = CVPixelBufferGetBytesPerRow(output)
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * 4)
        for row in 0..<height {
            let line = UnsafeRawBufferPointer(start: base + row * rowBytes, count: width * 4)
            pixels.append(contentsOf: line)
        }
        return (pixels, width, height)
    }

    /// Mean (B, R) channel values for a horizontal band of the canvas.
    private func bandMeans(
        _ pixels: [UInt8], width: Int, height: Int, fromY: Int, toY: Int
    ) -> (blue: Double, red: Double) {
        var blue = 0.0, red = 0.0, count = 0.0
        for row in fromY..<toY {
            for column in stride(from: 0, to: width, by: 4) {
                let offset = (row * width + column) * 4
                blue += Double(pixels[offset + 0])
                red += Double(pixels[offset + 2])
                count += 1
            }
        }
        return (blue / count, red / count)
    }

    @Test("+90° metadata renders upright: red on top, blue on bottom (fixture layout)")
    func uprightForPlus90() throws {
        // The exact transform the ca04 fixture generator writes
        // (translationX: 240, rotated by π/2).
        let transform = CGAffineTransform(translationX: 240, y: 0).rotated(by: .pi / 2)
        let rendered = try renderCanvas(preferredTransform: transform, canvasSize: CGSize(width: 240, height: 320))
        let top = bandMeans(rendered.pixels, width: rendered.width, height: rendered.height, fromY: 20, toY: 140)
        let bottom = bandMeans(rendered.pixels, width: rendered.width, height: rendered.height, fromY: 180, toY: 300)
        #expect(top.red > 150 && top.blue < 90, "+90° upright must show RED on top; got R=\(top.red) B=\(top.blue)")
        #expect(bottom.blue > 150 && bottom.red < 90, "+90° upright must show BLUE on bottom; got B=\(bottom.blue) R=\(bottom.red)")
    }

    @Test("−90° metadata renders upright: blue on top, red on bottom")
    func uprightForMinus90() throws {
        let transform = CGAffineTransform(translationX: 0, y: 320).rotated(by: -.pi / 2)
        let rendered = try renderCanvas(preferredTransform: transform, canvasSize: CGSize(width: 240, height: 320))
        let top = bandMeans(rendered.pixels, width: rendered.width, height: rendered.height, fromY: 20, toY: 140)
        let bottom = bandMeans(rendered.pixels, width: rendered.width, height: rendered.height, fromY: 180, toY: 300)
        #expect(top.blue > 150 && top.red < 90, "−90° upright must show BLUE on top; got B=\(top.blue) R=\(top.red)")
        #expect(bottom.red > 150 && bottom.blue < 90, "−90° upright must show RED on bottom; got R=\(bottom.red) B=\(bottom.blue)")
    }

    @Test("180° metadata renders upright: blue on left, red on right")
    func uprightFor180() throws {
        let transform = CGAffineTransform(translationX: 320, y: 240).rotated(by: .pi)
        let rendered = try renderCanvas(preferredTransform: transform, canvasSize: CGSize(width: 320, height: 240))
        // Vertical center band, split at the horizontal midpoint.
        let width = rendered.width
        var leftBlue = 0.0, leftRed = 0.0, rightBlue = 0.0, rightRed = 0.0, count = 0.0
        for row in stride(from: 20, to: 220, by: 4) {
            for column in stride(from: 20, to: 300, by: 4) {
                let offset = (row * width + column) * 4
                let blue = Double(rendered.pixels[offset + 0])
                let red = Double(rendered.pixels[offset + 2])
                if column < 160 { leftBlue += blue; leftRed += red } else { rightBlue += blue; rightRed += red }
                count += 1
            }
        }
        let half = count / 2
        #expect(leftBlue / half > 150 && leftRed / half < 90, "180° upright must show BLUE on the left")
        #expect(rightRed / half > 150 && rightBlue / half < 90, "180° upright must show RED on the right")
    }

    @Test("identity metadata leaves the frame untouched (left red / right blue)")
    func identityIsNoOp() throws {
        let rendered = try renderCanvas(preferredTransform: .identity, canvasSize: CGSize(width: 320, height: 240))
        let left = bandMeans(rendered.pixels, width: rendered.width, height: rendered.height, fromY: 20, toY: 220)
        // Left half of the mid rows: sample only the left columns.
        var red = 0.0, blue = 0.0, count = 0.0
        for row in stride(from: 20, to: 220, by: 4) {
            for column in stride(from: 20, to: 150, by: 4) {
                let offset = (row * rendered.width + column) * 4
                blue += Double(rendered.pixels[offset + 0])
                red += Double(rendered.pixels[offset + 2])
                count += 1
            }
        }
        #expect(red / count > 150 && blue / count < 90, "identity must keep RED on the left; unused band \(left)")
    }
}
