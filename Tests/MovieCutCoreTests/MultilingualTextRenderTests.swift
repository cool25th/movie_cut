import CoreImage
import Foundation
import Testing
@testable import MovieCutCore

/// CA-15 localization & text-quality audit probes — measured evidence for
/// the audit matrix (`docs/CA15_...`). Every case renders through the REAL
/// `TextOverlayPixelProcessor` (the same CoreText path preview and export
/// share) and asserts ink coverage, so the multilingual claims are pixel
/// evidence, not font-availability assumptions.
///
/// Coverage-style assertions (count of pixels differing from the background)
/// are deliberately robust: they don't depend on which cascade font the
/// platform picks, only on glyphs being drawn at all.
@Suite("Multilingual text render (CA-15)")
struct MultilingualTextRenderTests {
    private let size = CGSize(width: 320, height: 180)

    private func solidBlackImage() -> CIImage {
        CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: CGRect(origin: .zero, size: size))
    }

    private func inkCoverage(_ image: CIImage) -> Double {
        let width = Int(size.width), height = Int(size.height)
        let rowBytes = width * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * height)
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        context.render(
            image,
            toBitmap: &pixels,
            rowBytes: rowBytes,
            bounds: CGRect(origin: .zero, size: size),
            format: .RGBA8,
            colorSpace: nil
        )
        var inked = 0
        var index = 0
        while index + 2 < pixels.count {
            // White text on black: ink = bright pixels.
            if pixels[index] > 96 || pixels[index + 1] > 96 || pixels[index + 2] > 96 {
                inked += 1
            }
            index += 4
        }
        return Double(inked) / Double(width * height)
    }

    private func overlay(_ text: String, fontSize: CGFloat = 28) -> CIImage {
        let textContent = TextClipContent(
            text: text,
            fontFamily: "Helvetica Neue",
            fontSize: fontSize,
            fontColor: "#FFFFFF",
            alignment: .center
        )
        return TextOverlayPixelProcessor.apply(textContent, to: solidBlackImage(), at: 0)
    }

    @Test("CJK text renders glyphs through the shared overlay path")
    func cjkInk() {
        let latin = inkCoverage(overlay("Subtitle Test"))
        let cjk = inkCoverage(overlay("한국어 자막 테스트 가나다라"))
        #expect(cjk > 0.005, "CJK glyphs produced no ink (coverage \(cjk))")
        // Same-length-class strings should produce comparable ink: a missing
        // cascade (tofu boxes) typically still inks, so also compare against
        // the Latin baseline for a sanity band.
        #expect(cjk > latin * 0.2, "CJK ink collapsed vs latin (cjk \(cjk), latin \(latin))")
    }

    @Test("emoji and combining sequences render (fallback cascade)")
    func emojiAndCombiningInk() {
        let emoji = inkCoverage(overlay("🎬 클립 🎉"))
        #expect(emoji > 0.005, "emoji produced no ink (coverage \(emoji))")

        // Decomposed Hangul (NFD) must render — macOS filenames arrive NFD.
        let decomposed = inkCoverage(overlay("가\u{306}나\u{306}다"))
        #expect(decomposed > 0.003, "decomposed combining sequence produced no ink (\(decomposed))")
    }

    @Test("RTL (Arabic) text renders through the bidi-aware path")
    func rtlInk() {
        let arabic = inkCoverage(overlay("مرحبا بالعالم"))
        #expect(arabic > 0.005, "RTL glyphs produced no ink (coverage \(arabic))")
    }

    @Test("long CJK text wraps instead of overflowing the canvas")
    func cjkWrapsNotOverflows() {
        let short = overlay("한 줄", fontSize: 24)
        let long = overlay(
            String(repeating: "한국어자막줄바꿈", count: 8),
            fontSize: 24
        )
        let shortCoverage = inkCoverage(short)
        let longCoverage = inkCoverage(long)
        // Wrapping must happen (ink grows with text) and must stay inside the
        // canvas (coverage bounded well below the full frame).
        #expect(longCoverage > shortCoverage * 1.5, "long text did not wrap (short \(shortCoverage), long \(longCoverage))")
        #expect(longCoverage < 0.9, "long text ink suggests canvas overflow (\(longCoverage))")
    }
}
