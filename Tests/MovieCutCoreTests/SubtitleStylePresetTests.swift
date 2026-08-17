import CoreGraphics
import CoreImage
import Foundation
import MovieCutCore
import Testing

/// Golden + contract coverage for the built-in subtitle style presets
/// (G-01 Inc 3). Each preset must apply a renderer-visible feature
/// combination through the shared `TextOverlayPixelProcessor`, one command
/// upstream; these tests pin that the preset payloads actually reach the
/// pixels (not just the model).
@Suite("Subtitle Style Presets")
struct SubtitleStylePresetTests {
    private static let canvasSize = CGSize(width: 320, height: 240)
    private static let bounds = CGRect(x: 0, y: 0, width: 320, height: 240)

    private func baseContent() -> TextClipContent {
        TextClipContent(
            text: "STYLE PROBE",
            fontFamily: "Helvetica Neue",
            fontSize: 24,
            fontColor: "#FFFFFF",
            alignment: .center,
            position: CGPoint(x: 160, y: 120)
        )
    }

    private func bytes(rendering content: TextClipContent) -> [UInt8] {
        GoldenPixel.assertRendererFunctional()
        // Transparent base with a finite extent — the overlay processor takes
        // its render bounds from the input image's extent.
        let base = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: Self.bounds)
        let image = TextOverlayPixelProcessor.apply(
            content,
            to: base,
            at: 0.25
        )
        var buffer = [UInt8](repeating: 0, count: 320 * 240 * 4)
        buffer.withUnsafeMutableBytes { pointer in
            GoldenPixel.context.render(
                image.cropped(to: Self.bounds),
                toBitmap: pointer.baseAddress!,
                rowBytes: 320 * 4,
                bounds: Self.bounds,
                format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
            )
        }
        return buffer
    }

    /// Count of painted (alpha > 0) pixels within `tolerance` per channel of
    /// the target color. The alpha gate matters: the transparent base renders
    /// as (0,0,0,0) in the RGB buffer and would otherwise swamp every
    /// dark-color probe.
    private func pixelsNear(_ bytes: [UInt8], hex: String, tolerance: UInt8 = 24) -> Int {
        guard let rgb = HexColorMath.rgb(fromHex: hex) else { return 0 }
        let target = (
            UInt8(rgb.red * 255), UInt8(rgb.green * 255), UInt8(rgb.blue * 255)
        )
        var count = 0
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            guard bytes[offset + 3] > 40 else { continue }
            if abs(Int(bytes[offset]) - Int(target.0)) <= Int(tolerance),
               abs(Int(bytes[offset + 1]) - Int(target.1)) <= Int(tolerance),
               abs(Int(bytes[offset + 2]) - Int(target.2)) <= Int(tolerance) {
                count += 1
            }
        }
        return count
    }

    private func preset(named name: String) -> SubtitleStylePreset {
        guard let preset = SubtitleStylePresets.builtins.first(where: { $0.name == name }) else {
            preconditionFailure("missing builtin preset \(name)")
        }
        return preset
    }

    // MARK: - Contract

    @Test("builtins are six, uniquely identified, distinctly styled")
    func builtinsAreUniqueAndDistinct() {
        let builtins = SubtitleStylePresets.builtins
        #expect(builtins.count == 6)
        #expect(Set(builtins.map(\.id)).count == 6)
        #expect(Set(builtins.map(\.name)).count == 6)
        // Every preset applies a different payload to the same base content.
        let applied = builtins.map { $0.applying(to: baseContent(), canvasSize: Self.canvasSize) }
        #expect(Set(applied.map { "\($0)" }).count == 6)
    }

    @Test("preset applies relative position and highlight but never flips the karaoke flag")
    func presetAppliesPositionAndHighlightWithoutKaraokeFlag() {
        var content = baseContent()
        content.karaokeEnabled = false
        content.highlightFontColor = nil

        let updated = preset(named: "Clean White").applying(to: content, canvasSize: Self.canvasSize)
        #expect(updated.position == CGPoint(x: 160, y: 240 * 0.86))
        #expect(updated.highlightFontColor == "#FFD60A")
        #expect(updated.karaokeEnabled == false,
                "a preset must not silently enable/disable karaoke — that is the toggle's decision")
        #expect(updated.text == "STYLE PROBE", "a preset never rewrites the caption text")
    }

    // MARK: - Pixel goldens (preset → shared renderer)

    @Test("Clean White renders white glyphs with a black outline")
    func cleanWhiteRendersStrokeAndFill() {
        let bytes = bytes(rendering: preset(named: "Clean White").applying(
            to: baseContent(),
            canvasSize: Self.canvasSize
        ))
        #expect(pixelsNear(bytes, hex: "#FFFFFF") > 50, "white glyphs missing")
        #expect(pixelsNear(bytes, hex: "#000000") > 20, "black outline missing")
    }

    @Test("Bold Box renders a filled background box larger than bare glyphs")
    func boldBoxRendersBackgroundBox() {
        let boxed = bytes(rendering: preset(named: "Bold Box").applying(
            to: baseContent(),
            canvasSize: Self.canvasSize
        ))
        let outlined = bytes(rendering: preset(named: "Clean White").applying(
            to: baseContent(),
            canvasSize: Self.canvasSize
        ))
        let boxBlack = pixelsNear(boxed, hex: "#000000")
        let outlineBlack = pixelsNear(outlined, hex: "#000000")
        // The background box paints a solid black region far larger than the
        // glyph outline pass — roughly the whole text box, thousands of pixels.
        #expect(boxBlack > outlineBlack * 8, "background box missing (box=\(boxBlack) outline=\(outlineBlack))")
        #expect(boxBlack > 2000)
    }

    @Test("Yellow Pop renders yellow glyphs")
    func yellowPopRendersYellowGlyphs() {
        let bytes = bytes(rendering: preset(named: "Yellow Pop").applying(
            to: baseContent(),
            canvasSize: Self.canvasSize
        ))
        #expect(pixelsNear(bytes, hex: "#FFD60A") > 50, "yellow glyphs missing")
    }

    @Test("Mint Outline renders the mint font color")
    func mintOutlineRendersMintGlyphs() {
        let bytes = bytes(rendering: preset(named: "Mint Outline").applying(
            to: baseContent(),
            canvasSize: Self.canvasSize
        ))
        #expect(pixelsNear(bytes, hex: "#66D4CF") > 50, "mint glyphs missing")
    }
}
