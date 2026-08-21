import Foundation
import Testing
@testable import MovieCutCore

@Suite("Effect Browser Catalog (G-28)")
struct EffectBrowserCatalogTests {
    @Test("catalog contains only previewable built-in visual effects")
    func catalogContainsOnlyPreviewableBuiltIns() {
        let types = Set(EffectBrowserCatalog.items.map(\.type))

        #expect(!types.contains(.fadeIn))
        #expect(!types.contains(.fadeOut))
        #expect(!types.contains(.crossDissolve))
        #expect(!types.contains(.externalLUT))

        for item in EffectBrowserCatalog.items {
            #expect(VisualEffectPixelProcessor.hasRenderableEffect(item.makeEffect()))
        }
    }

    @Test("browser presets use renderer parameter keys instead of generic intensity")
    func rendererParameterKeysAreCorrect() throws {
        let brightness = try #require(EffectBrowserCatalog.item(for: .brightness))
        let exposure = try #require(EffectBrowserCatalog.item(for: .exposure))
        let blur = try #require(EffectBrowserCatalog.item(for: .blur))
        let style = try #require(EffectBrowserCatalog.item(for: .styleTransfer))

        #expect(Set(brightness.makeEffect().parameters.keys) == ["amount"])
        #expect(Set(exposure.makeEffect().parameters.keys) == ["ev"])
        #expect(Set(blur.makeEffect().parameters.keys) == ["radius"])
        #expect(Set(style.makeEffect().parameters.keys) == ["styleIndex", "intensity"])
    }

    @Test("preview values are visible non-neutral starting points for adjustment effects")
    func previewValuesAreVisible() throws {
        let brightness = try #require(EffectBrowserCatalog.item(for: .brightness))
        let contrast = try #require(EffectBrowserCatalog.item(for: .contrast))
        let saturation = try #require(EffectBrowserCatalog.item(for: .saturation))
        let temperature = try #require(EffectBrowserCatalog.item(for: .temperature))
        let exposure = try #require(EffectBrowserCatalog.item(for: .exposure))

        #expect(brightness.initialParameters["amount"] != 0)
        #expect(contrast.initialParameters["amount"] != 1)
        #expect(saturation.initialParameters["amount"] != 1)
        #expect(temperature.initialParameters["amount"] != 0)
        #expect(exposure.initialParameters["ev"] != 0)
    }

    @Test("catalog parameter defaults and previews stay inside their UI ranges")
    func valuesStayInRange() {
        for item in EffectBrowserCatalog.items {
            for parameter in item.parameters {
                #expect(parameter.range.contains(parameter.defaultValue))
                #expect(parameter.range.contains(parameter.previewValue))
            }
        }
    }

    @Test("effect construction fills missing controls, ignores unknown keys, and clamps overrides")
    func effectConstructionNormalizesOverrides() throws {
        let style = try #require(EffectBrowserCatalog.item(for: .styleTransfer))
        let effect = style.makeEffect(parameters: [
            "styleIndex": 99,
            "unknown": 42
        ])

        #expect(effect.type == .styleTransfer)
        #expect(effect.parameters["styleIndex"] == 5)
        #expect(effect.parameters["intensity"] == 0.75)
        #expect(effect.parameters["unknown"] == nil)
    }

    @Test("preview chain preserves existing effect order and appends the draft last")
    func previewChainMatchesApplyOrder() throws {
        let contrast = try #require(EffectBrowserCatalog.item(for: .contrast))
        let existing = [
            Effect(type: .brightness, parameters: ["amount": 0.25]),
            Effect(type: .cinematicLUT, parameters: ["intensity": 0.8])
        ]

        let preview = contrast.previewEffects(
            existingEffects: existing,
            parameters: ["amount": 1.4]
        )

        #expect(preview.count == 3)
        #expect(preview[0].type == .brightness)
        #expect(preview[0].parameters["amount"] == 0.25)
        #expect(preview[1].type == .cinematicLUT)
        #expect(preview[1].parameters["intensity"] == 0.8)
        #expect(preview[2].type == .contrast)
        #expect(preview[2].parameters["amount"] == 1.4)
    }
}
