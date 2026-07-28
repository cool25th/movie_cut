import CoreGraphics
import CoreImage
import Foundation
import MovieCutCore
import Testing

@Suite("Visual Effect Pixel Processor")
struct VisualEffectPixelProcessorTests {
    // Software renderer (deterministic in headless envs) via GoldenPixelHarness.
    // The previous GPU-backed CIContext() returned transparent black in
    // headless runs, which the coreImageRenderingAvailable() sentinel then
    // silently skipped — masking real regressions. Step 6 of the core-editing
    // repair handoff.
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let pixelBounds = CGRect(x: 0, y: 0, width: 1, height: 1)

    @Test("empty effect array returns the original image")
    func emptyEffectArrayReturnsOriginalImage() {
        let image = solidColor(red: 0.42, green: 0.51, blue: 0.63)
        let processed = VisualEffectPixelProcessor.apply([], to: image)

        #expect(processed === image)
        #expect(!VisualEffectPixelProcessor.hasRenderableEffects([]))
    }

    @Test("implemented visual effects are renderable")
    func implementedVisualEffectsAreRenderable() {
        let effects = [
            Effect.grayscale,
            Effect.sepia,
            Effect(type: .exposure, parameters: ["amount": 0.5]),
            Effect(type: .temperature, parameters: ["amount": 0.6]),
            Effect(type: .styleTransfer, parameters: ["styleIndex": 1, "intensity": 0.8]),
            Effect.cinematicLUT,
            Effect.vintageLUT,
            Effect.noirLUT,
            Effect.vividLUT,
            Effect.coolLUT
        ]

        for effect in effects {
            #expect(VisualEffectPixelProcessor.hasRenderableEffects([effect]))
            #expect(VisualEffectPixelProcessor.hasRenderableEffect(effect))
        }

        #expect(!VisualEffectPixelProcessor.hasRenderableEffects([Effect(type: .crossDissolve)]))
    }

    @Test("blur preserves the input extent")
    func blurPreservesInputExtent() {
        let image = solidColor(red: 0.2, green: 0.4, blue: 0.8)
            .cropped(to: CGRect(x: 12, y: 34, width: 64, height: 48))
        let processed = VisualEffectPixelProcessor.apply(
            [Effect(type: .blur, parameters: ["radius": 8])],
            to: image
        )

        #expect(processed.extent == image.extent)
    }

    @Test("procedural filters change sampled pixels when Core Image renders")
    func proceduralFiltersChangeSampledPixels() {
        // Loud-failure renderer check (no silent skip). Step 6.
        GoldenPixel.assertRendererFunctional()

        let image = solidColor(red: 0.26, green: 0.42, blue: 0.72)
        let original = samplePixel(from: image)
        let effects = [
            Effect.sepia,
            Effect(type: .exposure, parameters: ["amount": 0.6]),
            Effect(type: .temperature, parameters: ["amount": -0.7]),
            Effect.vividLUT,
            Effect.coolLUT
        ]

        for effect in effects {
            let processed = samplePixel(from: VisualEffectPixelProcessor.apply([effect], to: image))
            #expect(pixelDistance(original, processed) > 2)
        }
    }

    private func coreImageRenderingAvailable() -> Bool {
        // Retained as a no-op shim for any external callers; the suite now uses
        // GoldenPixel.assertRendererFunctional() (loud failure, no skip). Kept
        // temporarily to avoid breaking the migration in one step; the body is
        // intentionally a loud check so old call sites that still reference it
        // cannot pass vacuously.
        GoldenPixel.assertRendererFunctional()
        return true
    }

    private func solidColor(red: CGFloat, green: CGFloat, blue: CGFloat) -> CIImage {
        let bytes = [
            UInt8((red * 255).rounded()),
            UInt8((green * 255).rounded()),
            UInt8((blue * 255).rounded()),
            UInt8.max
        ]
        return CIImage(
            bitmapData: Data(bytes),
            bytesPerRow: 4,
            size: pixelBounds.size,
            format: .RGBA8,
            colorSpace: colorSpace
        )
    }

    private func samplePixel(from image: CIImage) -> Pixel {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            GoldenPixel.context.render(
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

@Suite("Visual Effect Static Contract")
struct VisualEffectStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("custom compositor delegates effect pixels to the shared processor")
    func customCompositorUsesSharedVisualEffectProcessor() throws {
        let source = try source("App/MovieCutMac/Export/CustomVideoCompositor.swift")

        #expect(source.contains("VisualEffectPixelProcessor.apply(clipEffects, to: image)"))
        #expect(!source.contains("private func applyEffects"))
        #expect(!source.contains("private func applyStyleTransfer"))
    }

    @Test("export and playback route effect clips through the custom compositor")
    func previewAndExportRouteEffectClipsThroughCustomCompositor() throws {
        let exportSource = try source("App/MovieCutMac/Export/ExportEngine.swift")
        let playbackSource = try source("App/MovieCutMac/Playback/PlaybackEngine.swift")

        #expect(exportSource.contains("|| !clip.effects.isEmpty"))
        #expect(exportSource.contains("effects: clip.effects"))
        #expect(playbackSource.contains("|| !clipInstruction.effects.isEmpty"))
        #expect(playbackSource.contains("effects: clipInstruction.effects"))
    }

    @Test("inspector exposes procedural LUT presets")
    func inspectorExposesProceduralLUTPresets() throws {
        let effectSource = try source("Sources/MovieCutCore/Models/Effect.swift")
        let inspectorSource = try source("App/MovieCutMac/Inspector/InspectorEffectsSection.swift")
        let displayNameSource = try source("Sources/MovieCutCore/Models/DisplayNames.swift")

        #expect(effectSource.contains("case cinematicLUT"))
        #expect(effectSource.contains("case vintageLUT"))
        #expect(effectSource.contains("case noirLUT"))
        #expect(effectSource.contains("case vividLUT"))
        #expect(effectSource.contains("case coolLUT"))
        #expect(inspectorSource.contains("ForEach(EffectType.allCases"))
        #expect(inspectorSource.contains("case .cinematicLUT, .vintageLUT, .vividLUT, .coolLUT"))
        #expect(displayNameSource.contains("Cinematic LUT"))
        #expect(displayNameSource.contains("Vintage LUT"))
        #expect(displayNameSource.contains("Noir LUT"))
        #expect(displayNameSource.contains("Vivid LUT"))
        #expect(displayNameSource.contains("Cool LUT"))
    }
}
