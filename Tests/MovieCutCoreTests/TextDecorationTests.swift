import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import MovieCutCore

/// F-12R text decorations: stroke/shadow/bold rendering through the shared
/// overlay processor, model persistence, and user style presets.
@Suite("Text Decorations")
struct TextDecorationTests {
    private let context = CIContext()
    private let renderSize = CGSize(width: 220, height: 120)

    private func baseContent() -> TextClipContent {
        TextClipContent(
            text: "AG",
            fontFamily: "Helvetica Neue",
            fontSize: 64,
            fontColor: "#FFFFFF",
            alignment: .center,
            position: CGPoint(x: 110, y: 60)
        )
    }

    private func render(_ content: TextClipContent) -> [UInt8] {
        let base = CIImage(color: CIColor.black)
            .cropped(to: CGRect(origin: CGPoint(x: 0, y: 0), size: renderSize))
        let item = TextOverlayRenderItem(textContent: content)
        let composed = TextOverlayPixelProcessor.apply([item], to: base, at: 0)

        let width = Int(renderSize.width)
        let height = Int(renderSize.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(
                composed,
                toBitmap: buffer.baseAddress!,
                rowBytes: width * 4,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
            )
        }
        return bytes
    }

    private func countPixels(_ bytes: [UInt8], where predicate: (UInt8, UInt8, UInt8) -> Bool) -> Int {
        var count = 0
        var index = 0
        while index + 3 < bytes.count {
            if predicate(bytes[index], bytes[index + 1], bytes[index + 2]) {
                count += 1
            }
            index += 4
        }
        return count
    }

    private var rendererIsAvailable: Bool {
        // Mirror the guarded-pixel pattern: skip assertions when the sandbox
        // CIContext renders transparent black for non-black fixtures.
        let bytes = render(baseContent())
        return countPixels(bytes) { r, g, b in r > 200 && g > 200 && b > 200 } > 0
    }

    @Test("red outline adds red-dominant edge pixels around white glyphs")
    func strokeAddsOutlinePixels() {
        guard rendererIsAvailable else {
            print("Skipping pixel assertion: CIContext unavailable.")
            return
        }

        var stroked = baseContent()
        stroked.strokeColor = "#FF0000"
        stroked.strokeWidth = 3

        let plainRed = countPixels(render(baseContent())) { r, g, b in
            r > 150 && g < 90 && b < 90
        }
        let strokedRed = countPixels(render(stroked)) { r, g, b in
            r > 150 && g < 90 && b < 90
        }

        #expect(plainRed < 10)
        #expect(strokedRed > plainRed + 30)
    }

    @Test("shadow adds offset colored pixels")
    func shadowAddsPixels() {
        guard rendererIsAvailable else {
            print("Skipping pixel assertion: CIContext unavailable.")
            return
        }

        var shadowed = baseContent()
        shadowed.shadowColor = "#FF0000"
        shadowed.shadowOffset = CGPoint(x: 6, y: 6)
        shadowed.shadowBlur = 0.5

        let plainRed = countPixels(render(baseContent())) { r, g, b in
            r > 120 && g < 90 && b < 90
        }
        let shadowRed = countPixels(render(shadowed)) { r, g, b in
            r > 120 && g < 90 && b < 90
        }

        #expect(shadowRed > plainRed + 30)
    }

    @Test("bold trait increases glyph coverage")
    func boldIncreasesCoverage() {
        guard rendererIsAvailable else {
            print("Skipping pixel assertion: CIContext unavailable.")
            return
        }

        var bold = baseContent()
        bold.isBold = true

        let plainWhite = countPixels(render(baseContent())) { r, g, b in
            r > 180 && g > 180 && b > 180
        }
        let boldWhite = countPixels(render(bold)) { r, g, b in
            r > 180 && g > 180 && b > 180
        }

        #expect(boldWhite > plainWhite)
    }

    // MARK: - Model persistence

    @Test("legacy text content decodes with no decorations")
    func legacyDecodesWithoutDecorations() throws {
        let content = baseContent()
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(content)) as! [String: Any]
        for key in ["strokeColor", "strokeWidth", "shadowColor", "shadowOffset", "shadowBlur", "isBold", "isItalic"] {
            json.removeValue(forKey: key)
        }
        let decoded = try JSONDecoder().decode(
            TextClipContent.self,
            from: JSONSerialization.data(withJSONObject: json)
        )

        #expect(decoded.strokeColor == nil)
        #expect(decoded.strokeWidth == nil)
        #expect(decoded.shadowColor == nil)
        #expect(decoded.shadowOffset == nil)
        #expect(decoded.isBold == false)
        #expect(decoded.isItalic == false)
    }

    @Test("decorations round-trip through encoding")
    func decorationsRoundTrip() throws {
        var content = baseContent()
        content.strokeColor = "#112233"
        content.strokeWidth = 2.5
        content.shadowColor = "#000000"
        content.shadowOffset = CGPoint(x: 3, y: -2)
        content.shadowBlur = 6
        content.isBold = true
        content.isItalic = true

        let decoded = try JSONDecoder().decode(TextClipContent.self, from: JSONEncoder().encode(content))
        #expect(decoded.strokeColor == "#112233")
        #expect(decoded.strokeWidth == 2.5)
        #expect(decoded.shadowColor == "#000000")
        #expect(decoded.shadowOffset?.x == 3 && decoded.shadowOffset?.y == -2)
        #expect(decoded.shadowBlur == 6)
        #expect(decoded.isBold == true)
        #expect(decoded.isItalic == true)
    }

    // MARK: - User presets

    @Test("preset captures style and applies it without touching text or position")
    func presetCapturesAndApplies() {
        var styled = baseContent()
        styled.strokeColor = "#FF00FF"
        styled.strokeWidth = 4
        styled.isBold = true
        let preset = UserTextStylePreset(name: "Neon", capturing: styled)

        var target = TextClipContent(
            text: "Different text",
            fontSize: 20,
            position: CGPoint(x: 5, y: 7)
        )
        target.contentKind = .text
        let applied = preset.applying(to: target)

        #expect(applied.text == "Different text")
        #expect(applied.position.x == 5 && applied.position.y == 7)
        #expect(applied.strokeColor == "#FF00FF")
        #expect(applied.strokeWidth == 4)
        #expect(applied.isBold == true)
        #expect(applied.fontSize == styled.fontSize)
    }

    @Test("preset store round-trips and tolerates missing files")
    func presetStoreRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextStyles-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(UserTextStylePresetStore.load(from: url).isEmpty)

        let presets = [
            UserTextStylePreset(name: "A", capturing: baseContent()),
            UserTextStylePreset(name: "B", capturing: baseContent())
        ]
        try UserTextStylePresetStore.save(presets, to: url)
        let loaded = UserTextStylePresetStore.load(from: url)
        #expect(loaded == presets)
    }
}

/// Wiring visibility for the decoration UI (not a completion criterion by
/// itself — see spec DoD §1.3).
@Suite("Text Decoration Static Contract")
struct TextDecorationStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("inspector exposes bold, italic, outline, shadow, and presets")
    func inspectorExposesDecorations() throws {
        let inspector = try source("App/MovieCutMac/Inspector/InspectorBasicSection.swift")
        #expect(inspector.contains("textDecorationControls"))
        #expect(inspector.contains("isBold"))
        #expect(inspector.contains("strokeWidth"))
        #expect(inspector.contains("shadowBlur"))
        #expect(inspector.contains("userStylePresetControls"))
        #expect(inspector.contains("saveSelectedTextStyleAsPreset"))
    }

    @Test("view model persists presets through the shared store")
    func viewModelPersistsPresets() throws {
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
        #expect(viewModel.contains("UserTextStylePresetStore"))
        #expect(viewModel.contains("func applyUserTextStylePreset"))
        #expect(viewModel.contains("func deleteUserTextStylePreset"))
    }
}
