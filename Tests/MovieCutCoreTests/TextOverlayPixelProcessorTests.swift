import CoreGraphics
import CoreImage
import Foundation
import MovieCutCore
import Testing

@Suite("Text Overlay Pixel Processor")
struct TextOverlayPixelProcessorTests {
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let imageBounds = CGRect(x: 0, y: 0, width: 160, height: 80)

    @Test("text overlay changes sampled pixels over a solid background")
    func textOverlayChangesSampledPixelsOverSolidBackground() {
        guard coreImageRenderingAvailable() else { return }

        let image = solidColorImage(red: 0.85, green: 0.12, blue: 0.08)
        let textContent = TextClipContent(
            text: "TEXT",
            fontFamily: "Helvetica Neue",
            fontSize: 42,
            fontColor: "#FFFFFF",
            alignment: .center,
            backgroundColor: "#000000",
            position: CGPoint(x: 80, y: 40)
        )
        let original = samplePixel(from: image, at: CGPoint(x: 80, y: 40))
        let processed = TextOverlayPixelProcessor.apply(textContent, to: image, at: 0)
        let rendered = samplePixel(from: processed, at: CGPoint(x: 80, y: 40))

        #expect(pixelDistance(original, rendered) > 20)
        #expect(rendered.a > 240)
    }

    @Test("background color draws a non-transparent rectangle")
    func backgroundColorDrawsNonTransparentRectangle() {
        guard coreImageRenderingAvailable() else { return }

        let image = solidColorImage(red: 0, green: 0, blue: 0, alpha: 0)
        let textContent = TextClipContent(
            text: "I",
            fontFamily: "Helvetica Neue",
            fontSize: 36,
            fontColor: "#FFFFFF",
            alignment: .center,
            backgroundColor: "#00FF00",
            position: CGPoint(x: 80, y: 40)
        )
        let processed = TextOverlayPixelProcessor.apply(textContent, to: image, at: 0)
        let rendered = samplePixel(from: processed, at: CGPoint(x: 12, y: 40))

        #expect(rendered.a > 180)
        #expect(Int(rendered.g) > Int(rendered.r) + 40)
        #expect(Int(rendered.g) > Int(rendered.b) + 40)
    }

    @Test("fade in animation increases visible overlay over time")
    func fadeInAnimationIncreasesVisibleOverlayOverTime() {
        guard coreImageRenderingAvailable() else { return }

        let image = solidColorImage(red: 0, green: 0, blue: 0, alpha: 0)
        let textContent = TextClipContent(
            text: "FADE",
            fontFamily: "Helvetica Neue",
            fontSize: 42,
            fontColor: "#FFFFFF",
            alignment: .center,
            backgroundColor: "#FFFFFF",
            position: CGPoint(x: 80, y: 40),
            animation: TextAnimation(type: .fadeIn, duration: 1)
        )

        let nearStart = TextOverlayPixelProcessor.apply(textContent, to: image, at: 0.1)
        let afterDuration = TextOverlayPixelProcessor.apply(textContent, to: image, at: 1.0)

        let nearStartAlpha = totalAlpha(in: nearStart)
        let afterDurationAlpha = totalAlpha(in: afterDuration)
        #expect(afterDurationAlpha > nearStartAlpha)
        #expect(afterDurationAlpha > 0)
    }

    @Test("typewriter animation emits less overlay before full progress")
    func typewriterAnimationEmitsLessOverlayBeforeFullProgress() {
        guard coreImageRenderingAvailable() else { return }

        let image = solidColorImage(red: 0, green: 0, blue: 0, alpha: 0)
        let textContent = TextClipContent(
            text: "MMMMMMMMMMMM",
            fontFamily: "Helvetica Neue",
            fontSize: 42,
            fontColor: "#FFFFFF",
            alignment: .center,
            position: CGPoint(x: 80, y: 40),
            animation: TextAnimation(type: .typewriter, duration: 1)
        )

        let early = TextOverlayPixelProcessor.apply(textContent, to: image, at: 0.2)
        let late = TextOverlayPixelProcessor.apply(textContent, to: image, at: 1.0)

        let earlyAlpha = totalAlpha(in: early)
        let lateAlpha = totalAlpha(in: late)
        #expect(earlyAlpha > 0)
        #expect(lateAlpha > earlyAlpha)
    }

    @Test("output extent equals input extent")
    func outputExtentEqualsInputExtent() {
        let image = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1))
            .cropped(to: CGRect(x: 12, y: 34, width: 64, height: 48))
        let textContent = TextClipContent(
            text: "Extent",
            fontSize: 24,
            backgroundColor: "#000000"
        )
        let processed = TextOverlayPixelProcessor.apply(textContent, to: image, at: 0)

        #expect(processed.extent == image.extent)
    }

    @Test("karaoke disabled renders identically to a uniform single color")
    func karaokeDisabledMatchesUniformBaseline() {
        guard coreImageRenderingAvailable() else { return }

        let image = solidColorImage(red: 0, green: 0, blue: 0, alpha: 0)
        let baseContent = TextClipContent(
            text: "ONE TWO",
            fontFamily: "Helvetica Neue",
            fontSize: 42,
            fontColor: "#FFFFFF",
            alignment: .center,
            position: CGPoint(x: 80, y: 40),
            wordTimings: [
                WordTiming(text: "ONE", startTime: 0, endTime: 0.5, confidence: 1),
                WordTiming(text: "TWO", startTime: 0.5, endTime: 1.0, confidence: 1)
            ]
        )
        // karaokeEnabled stays at its default of false, so word timings must be
        // ignored and the output must match the no-timings baseline exactly.
        let baseline = TextOverlayPixelProcessor.apply(
            TextClipContent(
                text: "ONE TWO",
                fontFamily: "Helvetica Neue",
                fontSize: 42,
                fontColor: "#FFFFFF",
                alignment: .center,
                position: CGPoint(x: 80, y: 40)
            ),
            to: image,
            at: 0.25
        )
        let processed = TextOverlayPixelProcessor.apply(baseContent, to: image, at: 0.25)

        #expect(totalAlpha(in: baseline) == totalAlpha(in: processed))
    }

    @Test("karaoke highlight recolors pixels as playback crosses each word")
    func karaokeHighlightRecolorsPixelsAcrossWords() {
        guard coreImageRenderingAvailable() else { return }

        let image = solidColorImage(red: 0, green: 0, blue: 0, alpha: 0)
        // Base font white (#FFFFFF), highlight red (#FF0000). The red channel is
        // identical for both colors, so the tell is the green channel: white
        // glyphs carry full green, red glyphs carry none.
        let content = TextClipContent(
            text: "AAA BBB",
            fontFamily: "Helvetica Neue",
            fontSize: 42,
            fontColor: "#FFFFFF",
            alignment: .center,
            position: CGPoint(x: 80, y: 40),
            wordTimings: [
                WordTiming(text: "AAA", startTime: 1.0, endTime: 1.5, confidence: 1),
                WordTiming(text: "BBB", startTime: 2.0, endTime: 2.5, confidence: 1)
            ],
            karaokeEnabled: true,
            highlightFontColor: "#FF0000"
        )

        // Before either word starts, every glyph is white → lots of green.
        let beforeWords = TextOverlayPixelProcessor.apply(content, to: image, at: 0.1)
        // After both words have started, every glyph is red → little green.
        let afterWords = TextOverlayPixelProcessor.apply(content, to: image, at: 2.1)

        let beforeGreen = totalGreen(in: beforeWords)
        let afterGreen = totalGreen(in: afterWords)
        // Highlighting in red strips green; a uniform-white renderer would leave
        // both sums equal.
        #expect(beforeGreen > afterGreen + 50, "karaoke highlight did not recolor glyphs (beforeGreen=\(beforeGreen), afterGreen=\(afterGreen))")
    }

    @Test("karaoke with highlight equal to base color matches uniform baseline pixel-for-pixel")
    func karaokeWithHighlightEqualToBaseColorMatchesUniformBaseline() {
        // R1 acceptance criterion: when the highlight color equals the base
        // color, the only possible difference between the karaoke path and the
        // uniform path is layout. With whitespace correctly preserved the two
        // outputs must be pixel-identical. A passing-green-sum test cannot
        // catch whitespace loss (the glyphs are identical), so this compares
        // the full RGBA byte buffer.
        guard coreImageRenderingAvailable() else { return }

        let image = solidColorImage(red: 0, green: 0, blue: 0, alpha: 0)
        let text = "ONE TWO"
        let karaokeContent = TextClipContent(
            text: text,
            fontFamily: "Helvetica Neue",
            fontSize: 42,
            fontColor: "#FFFFFF",
            alignment: .center,
            position: CGPoint(x: 80, y: 40),
            wordTimings: [
                WordTiming(text: "ONE", startTime: 0, endTime: 0.5, confidence: 1),
                WordTiming(text: "TWO", startTime: 0.5, endTime: 1.0, confidence: 1)
            ],
            karaokeEnabled: true,
            highlightFontColor: "#FFFFFF"
        )
        let uniformContent = TextClipContent(
            text: text,
            fontFamily: "Helvetica Neue",
            fontSize: 42,
            fontColor: "#FFFFFF",
            alignment: .center,
            position: CGPoint(x: 80, y: 40)
        )

        // localTime well past every word's start so the karaoke path exercises
        // its per-word recoloring loop rather than the fallback branch.
        let karaokeRendered = TextOverlayPixelProcessor.apply(karaokeContent, to: image, at: 0.75)
        let uniformRendered = TextOverlayPixelProcessor.apply(uniformContent, to: image, at: 0.75)

        #expect(
            renderBytes(in: karaokeRendered) == renderBytes(in: uniformRendered),
            "karaoke layout diverged from uniform when highlight == base color (whitespace lost)"
        )
    }

    @Test("karaoke whitespace preservation holds with double spaces and newlines")
    func karaokePreservesWhitespaceWithDoubleSpacesAndNewlines() {
        // R1 acceptance criterion #3: a single space is not the only whitespace
        // that must survive. Two spaces and an embedded newline must round-trip
        // through the karaoke path unchanged, so it still matches the uniform
        // baseline pixel-for-pixel.
        guard coreImageRenderingAvailable() else { return }

        let image = solidColorImage(red: 0, green: 0, blue: 0, alpha: 0)
        // "AA  BB\nCC" — two words on line one separated by a double space, one
        // word on line two. The whitespace-split token count is 3.
        let text = "AA  BB\nCC"
        let karaokeContent = TextClipContent(
            text: text,
            fontFamily: "Helvetica Neue",
            fontSize: 28,
            fontColor: "#FFFFFF",
            alignment: .leading,
            position: CGPoint(x: 80, y: 40),
            wordTimings: [
                WordTiming(text: "AA", startTime: 0, endTime: 0.3, confidence: 1),
                WordTiming(text: "BB", startTime: 0.3, endTime: 0.6, confidence: 1),
                WordTiming(text: "CC", startTime: 0.6, endTime: 0.9, confidence: 1)
            ],
            karaokeEnabled: true,
            highlightFontColor: "#FFFFFF"
        )
        let uniformContent = TextClipContent(
            text: text,
            fontFamily: "Helvetica Neue",
            fontSize: 28,
            fontColor: "#FFFFFF",
            alignment: .leading,
            position: CGPoint(x: 80, y: 40)
        )

        let karaokeRendered = TextOverlayPixelProcessor.apply(karaokeContent, to: image, at: 0.8)
        let uniformRendered = TextOverlayPixelProcessor.apply(uniformContent, to: image, at: 0.8)

        #expect(
            renderBytes(in: karaokeRendered) == renderBytes(in: uniformRendered),
            "karaoke layout diverged from uniform for multi-whitespace text"
        )
    }

    @Test("karaoke falls back to uniform color when token count disagrees with timings")
    func karaokeFallsBackWhenTokenCountDisagrees() {
        guard coreImageRenderingAvailable() else { return }

        let image = solidColorImage(red: 0, green: 0, blue: 0, alpha: 0)
        // Three words in text but only two timings: the feature must give up and
        // render uniform white, so the red highlight never strips green.
        let content = TextClipContent(
            text: "ONE TWO THREE",
            fontFamily: "Helvetica Neue",
            fontSize: 42,
            fontColor: "#FFFFFF",
            alignment: .center,
            position: CGPoint(x: 80, y: 40),
            wordTimings: [
                WordTiming(text: "ONE", startTime: 0, endTime: 0.5, confidence: 1),
                WordTiming(text: "TWO", startTime: 0.5, endTime: 1.0, confidence: 1)
            ],
            karaokeEnabled: true,
            highlightFontColor: "#FF0000"
        )

        let processed = TextOverlayPixelProcessor.apply(content, to: image, at: 0.75)
        // Uniform-white fallback means the green channel stays high (white text),
        // rather than dropping toward zero (red highlight).
        #expect(totalGreen(in: processed) > 200_000)
    }

    private func coreImageRenderingAvailable() -> Bool {
        GoldenPixel.assertRendererFunctional()
        return true
    }

    private func solidColorImage(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat = 1
    ) -> CIImage {
        let pixel = [
            UInt8((red * 255).rounded()),
            UInt8((green * 255).rounded()),
            UInt8((blue * 255).rounded()),
            UInt8((alpha * 255).rounded())
        ]
        let pixels = Array(repeating: pixel, count: Int(imageBounds.width * imageBounds.height)).flatMap { $0 }
        return CIImage(
            bitmapData: Data(pixels),
            bytesPerRow: Int(imageBounds.width) * 4,
            size: imageBounds.size,
            format: .RGBA8,
            colorSpace: colorSpace
        )
    }

    private func samplePixel(from image: CIImage, at point: CGPoint) -> Pixel {
        var bytes = [UInt8](repeating: 0, count: 4)
        let bounds = CGRect(x: point.x, y: point.y, width: 1, height: 1)
        bytes.withUnsafeMutableBytes { buffer in
            GoldenPixel.context.render(
                image.cropped(to: bounds),
                toBitmap: buffer.baseAddress!,
                rowBytes: 4,
                bounds: bounds,
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }
        return Pixel(r: bytes[0], g: bytes[1], b: bytes[2], a: bytes[3])
    }

    private func totalAlpha(in image: CIImage) -> Int {
        var bytes = [UInt8](repeating: 0, count: Int(imageBounds.width * imageBounds.height) * 4)
        bytes.withUnsafeMutableBytes { buffer in
            GoldenPixel.context.render(
                image.cropped(to: imageBounds),
                toBitmap: buffer.baseAddress!,
                rowBytes: Int(imageBounds.width) * 4,
                bounds: imageBounds,
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }

        return stride(from: 3, to: bytes.count, by: 4).reduce(0) { total, offset in
            total + Int(bytes[offset])
        }
    }

    private func totalGreen(in image: CIImage) -> Int {
        var bytes = [UInt8](repeating: 0, count: Int(imageBounds.width * imageBounds.height) * 4)
        bytes.withUnsafeMutableBytes { buffer in
            GoldenPixel.context.render(
                image.cropped(to: imageBounds),
                toBitmap: buffer.baseAddress!,
                rowBytes: Int(imageBounds.width) * 4,
                bounds: imageBounds,
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }

        return stride(from: 1, to: bytes.count, by: 4).reduce(0) { total, offset in
            total + Int(bytes[offset])
        }
    }

    /// Renders the full RGBA byte buffer of an image cropped to the suite's
    /// fixed bounds. Used by the R1 whitespace-preservation tests to compare
    /// karaoke and uniform outputs pixel-for-pixel: a green-sum comparison
    /// cannot catch whitespace loss because the glyphs themselves are identical.
    private func renderBytes(in image: CIImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Int(imageBounds.width * imageBounds.height) * 4)
        bytes.withUnsafeMutableBytes { buffer in
            GoldenPixel.context.render(
                image.cropped(to: imageBounds),
                toBitmap: buffer.baseAddress!,
                rowBytes: Int(imageBounds.width) * 4,
                bounds: imageBounds,
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }
        return bytes
    }

    private func pixelDistance(_ lhs: Pixel, _ rhs: Pixel) -> Int {
        abs(Int(lhs.r) - Int(rhs.r))
            + abs(Int(lhs.g) - Int(rhs.g))
            + abs(Int(lhs.b) - Int(rhs.b))
            + abs(Int(lhs.a) - Int(rhs.a))
    }

    private struct Pixel {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var a: UInt8
    }
}
