import CoreGraphics
import CoreImage
import Foundation
import MovieCutCore
import Testing

/// F-07 transition visual fixture: every built-in transition is rendered
/// between two fixed-color fixtures through the shared TransitionPixelProcessor
/// — the exact processor both the preview and export custom compositors call —
/// and its deterministic mid/endpoint pixels are asserted. This is the
/// processor-level "export visual fixture" the spec calls for; a real
/// AVAssetExportSession E2E remains out of unit-test scope.
@Suite("Transition Export Fixture")
struct TransitionExportFixtureTests {
    private let context = CIContext()
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let bounds = CGRect(x: 0, y: 0, width: 16, height: 16)

    private var outgoing: CIImage { solidColorImage(red: 1, green: 0, blue: 0) } // red
    private var incoming: CIImage { solidColorImage(red: 0, green: 0, blue: 1) } // blue

    @Test("every transition resolves to pure endpoints and preserves extent (AC①)")
    func allTransitionsResolveToEndpoints() {
        guard rendererAvailable() else { return }

        for type in TransitionType.allCases {
            let start = TransitionPixelProcessor.apply(type: type, from: outgoing, to: incoming, progress: 0)
            let end = TransitionPixelProcessor.apply(type: type, from: outgoing, to: incoming, progress: 1)

            #expect(start.extent == bounds, "\(type) start extent")
            #expect(end.extent == bounds, "\(type) end extent")

            let startPixel = samplePixel(from: start, at: CGPoint(x: 8, y: 8))
            let endPixel = samplePixel(from: end, at: CGPoint(x: 8, y: 8))
            assertColor(startPixel, red: 255, green: 0, blue: 0, label: "\(type) progress 0 → outgoing")
            assertColor(endPixel, red: 0, green: 0, blue: 255, label: "\(type) progress 1 → incoming")
        }
    }

    @Test("every transition is deterministic for the same fixture and progress")
    func allTransitionsAreDeterministic() {
        guard rendererAvailable() else { return }

        for type in TransitionType.allCases {
            let first = pixels(from: TransitionPixelProcessor.apply(type: type, from: outgoing, to: incoming, progress: 0.5))
            let second = pixels(from: TransitionPixelProcessor.apply(type: type, from: outgoing, to: incoming, progress: 0.5))
            #expect(first == second, "\(type) should render identically for identical inputs")
        }
    }

    @Test("mid-transition fixtures match each transition's expected visual (AC①)")
    func midTransitionFixtures() {
        guard rendererAvailable() else { return }

        // none at 0.5 still shows the outgoing frame.
        assertColor(mid(.none, at: CGPoint(x: 8, y: 8)), red: 255, green: 0, blue: 0, label: "none mid")

        // crossDissolve blends both channels roughly evenly.
        let dissolve = mid(.crossDissolve, at: CGPoint(x: 8, y: 8))
        #expect(dissolve.r > 120 && dissolve.b > 120 && dissolve.g < 16, "crossDissolve mid blend")

        // fadeThroughBlack midpoint is black.
        assertColor(mid(.fadeThroughBlack, at: CGPoint(x: 8, y: 8)), red: 0, green: 0, blue: 0, label: "fadeThroughBlack mid")

        // Directional wipes reveal the incoming from a specific edge.
        assertColor(mid(.wipeRight, at: CGPoint(x: 2, y: 8)), red: 0, green: 0, blue: 255, label: "wipeRight left=incoming")
        assertColor(mid(.wipeRight, at: CGPoint(x: 14, y: 8)), red: 255, green: 0, blue: 0, label: "wipeRight right=outgoing")
        assertColor(mid(.wipeLeft, at: CGPoint(x: 14, y: 8)), red: 0, green: 0, blue: 255, label: "wipeLeft right=incoming")
        assertColor(mid(.wipeLeft, at: CGPoint(x: 2, y: 8)), red: 255, green: 0, blue: 0, label: "wipeLeft left=outgoing")
        assertColor(mid(.wipeUp, at: CGPoint(x: 8, y: 2)), red: 0, green: 0, blue: 255, label: "wipeUp")
        assertColor(mid(.wipeDown, at: CGPoint(x: 8, y: 14)), red: 0, green: 0, blue: 255, label: "wipeDown")

        // Slides differ from a plain dissolve at the leading edge.
        #expect(distance(mid(.slideLeft, at: CGPoint(x: 2, y: 8)), dissolve) > 60, "slideLeft differs from dissolve")
        #expect(distance(mid(.slideRight, at: CGPoint(x: 14, y: 8)), dissolve) > 60, "slideRight differs from dissolve")

        // Zooms preserve extent and shift the center sample across progress.
        for type in [TransitionType.zoomIn, .zoomOut] {
            let early = TransitionPixelProcessor.apply(type: type, from: outgoing, to: incoming, progress: 0.25)
            let late = TransitionPixelProcessor.apply(type: type, from: outgoing, to: incoming, progress: 0.75)
            #expect(early.extent == bounds && late.extent == bounds, "\(type) extent")
            #expect(distance(
                samplePixel(from: early, at: CGPoint(x: 8, y: 8)),
                samplePixel(from: late, at: CGPoint(x: 8, y: 8))
            ) > 60, "\(type) center changes with progress")
        }

        // Glitch is distinct from a plain dissolve.
        #expect(pixels(from: TransitionPixelProcessor.apply(type: .glitch, from: outgoing, to: incoming, progress: 0.5))
            != pixels(from: TransitionPixelProcessor.apply(type: .crossDissolve, from: outgoing, to: incoming, progress: 0.5)),
            "glitch differs from dissolve")
    }

    @Test("fixture exercises the full TransitionType.allCases set")
    func fixtureCoversAllCases() {
        // Guard: if a transition type is added, the endpoint loop above must
        // exercise it, so allCases is the canonical coverage source.
        #expect(TransitionType.allCases.count == 12)
    }

    // MARK: - Helpers

    private func mid(_ type: TransitionType, at point: CGPoint) -> Pixel {
        samplePixel(
            from: TransitionPixelProcessor.apply(type: type, from: outgoing, to: incoming, progress: 0.5),
            at: point
        )
    }

    private func rendererAvailable() -> Bool {
        let sentinel = samplePixel(from: solidColorImage(red: 0.35, green: 0.35, blue: 0.35), at: CGPoint(x: 0, y: 0))
        if sentinel.r == 0 && sentinel.g == 0 && sentinel.b == 0 && sentinel.a == 0 {
            print("Skipping transition fixture pixel assertions: renderer returned transparent black.")
            return false
        }
        return true
    }

    private func solidColorImage(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) -> CIImage {
        let pixel = [
            UInt8((red * 255).rounded()),
            UInt8((green * 255).rounded()),
            UInt8((blue * 255).rounded()),
            UInt8((alpha * 255).rounded())
        ]
        let data = Array(repeating: pixel, count: Int(bounds.width * bounds.height)).flatMap { $0 }
        return CIImage(
            bitmapData: Data(data),
            bytesPerRow: Int(bounds.width) * 4,
            size: bounds.size,
            format: .RGBA8,
            colorSpace: colorSpace
        )
    }

    private func samplePixel(from image: CIImage, at point: CGPoint) -> Pixel {
        var bytes = [UInt8](repeating: 0, count: 4)
        let pixelBounds = CGRect(x: point.x, y: point.y, width: 1, height: 1)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(
                image.cropped(to: pixelBounds),
                toBitmap: buffer.baseAddress!,
                rowBytes: 4,
                bounds: pixelBounds,
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }
        return Pixel(r: bytes[0], g: bytes[1], b: bytes[2], a: bytes[3])
    }

    private func pixels(from image: CIImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Int(bounds.width * bounds.height) * 4)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(
                image.cropped(to: bounds),
                toBitmap: buffer.baseAddress!,
                rowBytes: Int(bounds.width) * 4,
                bounds: bounds,
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }
        return bytes
    }

    private func assertColor(_ pixel: Pixel, red: Int, green: Int, blue: Int, label: String, tolerance: Int = 6) {
        #expect(abs(Int(pixel.r) - red) <= tolerance, "\(label) red \(pixel.r)")
        #expect(abs(Int(pixel.g) - green) <= tolerance, "\(label) green \(pixel.g)")
        #expect(abs(Int(pixel.b) - blue) <= tolerance, "\(label) blue \(pixel.b)")
    }

    private func distance(_ lhs: Pixel, _ rhs: Pixel) -> Int {
        abs(Int(lhs.r) - Int(rhs.r)) + abs(Int(lhs.g) - Int(rhs.g)) + abs(Int(lhs.b) - Int(rhs.b))
    }

    private struct Pixel: Equatable {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var a: UInt8
    }
}
