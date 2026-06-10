import CoreGraphics
import CoreImage
import Foundation
import MovieCutCore
import Testing

@Suite("ChromaKey Pixel Processor")
struct ChromaKeyPixelProcessorTests {
    private let context = CIContext()
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let pixelBounds = CGRect(x: 0, y: 0, width: 1, height: 1)

    @Test("green screen pixels become transparent")
    func greenScreenPixelsBecomeTransparent() {
        guard coreImageRenderingAvailable() else { return }

        let image = solidColor(red: 0, green: 1, blue: 0)
        let processed = samplePixel(
            from: ChromaKeyPixelProcessor.apply(
                ChromaKeySettings(keyColor: "#00FF00", tolerance: 0.12, softness: 0.2, spillSuppression: 0.8),
                to: image
            )
        )

        #expect(processed.a < 16)
    }

    @Test("non-key foreground color stays opaque")
    func nonKeyForegroundColorStaysOpaque() {
        guard coreImageRenderingAvailable() else { return }

        let image = solidColor(red: 0.9, green: 0.1, blue: 0.1)
        let processed = samplePixel(
            from: ChromaKeyPixelProcessor.apply(.greenScreen(), to: image)
        )

        #expect(processed.a > 245)
        #expect(processed.r > 200)
    }

    @Test("softness produces partial alpha on near-key colors")
    func softnessProducesPartialAlphaOnNearKeyColors() {
        guard coreImageRenderingAvailable() else { return }

        let image = solidColor(red: 0.1, green: 0.85, blue: 0.1)
        let original = samplePixel(from: image)
        let processed = samplePixel(
            from: ChromaKeyPixelProcessor.apply(
                ChromaKeySettings(keyColor: "#00FF00", tolerance: 0.1, softness: 0.35, spillSuppression: 0.8),
                to: image
            )
        )

        #expect(processed.a > 16)
        #expect(processed.a < 245)
        #expect(processed.g < original.g)
    }

    @Test("invalid hex falls back to green screen key")
    func invalidHexFallsBackToGreenScreenKey() {
        #expect(ChromaKeyPixelProcessor.rgbComponents(from: "not-a-hex-color") == nil)
        guard coreImageRenderingAvailable() else { return }

        let image = solidColor(red: 0, green: 1, blue: 0)
        let processed = samplePixel(
            from: ChromaKeyPixelProcessor.apply(
                ChromaKeySettings(keyColor: "not-a-hex-color", tolerance: 0.12, softness: 0.2, spillSuppression: 0.8),
                to: image
            )
        )

        #expect(processed.a < 16)
    }

    @Test("output extent equals input extent")
    func outputExtentEqualsInputExtent() {
        let image = CIImage(color: CIColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1))
            .cropped(to: CGRect(x: 12, y: 34, width: 64, height: 48))
        let processed = ChromaKeyPixelProcessor.apply(.greenScreen(), to: image)

        #expect(processed.extent == image.extent)
    }

    private func coreImageRenderingAvailable() -> Bool {
        let sentinel = samplePixel(from: solidColor(red: 0.35, green: 0.35, blue: 0.35))
        if sentinel.r == 0 && sentinel.g == 0 && sentinel.b == 0 && sentinel.a == 0 {
            print("Skipping CIContext pixel assertion: renderer returned transparent black for a non-black fixture.")
            return false
        }
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

    private struct Pixel {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var a: UInt8
    }
}

@Suite("ChromaKey Static Contract")
struct ChromaKeyStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("custom compositor delegates chroma key pixels to the shared processor")
    func customCompositorUsesSharedChromaKeyProcessor() throws {
        let source = try source("App/MovieCutMac/Export/CustomVideoCompositor.swift")

        #expect(source.contains("ChromaKeyPixelProcessor.apply(chromaKey, to: image)"))
        #expect(source.contains("ChromaKeyPixelProcessor.apply("))
        #expect(!source.contains("private func applyChromaKey"))
        #expect(!source.contains("CIColorCube"))
    }

    @Test("chroma key compositor delegates to the shared processor")
    func chromaKeyCompositorDelegatesToSharedProcessor() throws {
        let source = try source("App/MovieCutMac/Export/ChromaKeyCompositor.swift")

        #expect(source.contains("ChromaKeyPixelProcessor.apply($0, to: image)"))
        #expect(source.contains("ChromaKeyPixelProcessor.apply($0, to: request.sourceImage)"))
        #expect(!source.contains("CIColorCube"))
        #expect(!source.contains("private func applyChromaKey"))
    }

    @Test("export and playback route chroma key clips through custom compositor")
    func exportAndPlaybackRouteChromaKeyClipsThroughCustomCompositor() throws {
        let exportSource = try source("App/MovieCutMac/Export/ExportEngine.swift")
        let playbackSource = try source("App/MovieCutMac/Playback/PlaybackEngine.swift")

        #expect(exportSource.contains("|| clip.chromaKey != nil"))
        #expect(exportSource.contains("chromaKey: clip.chromaKey"))
        #expect(exportSource.contains("videoComposition.customVideoCompositorClass = CustomVideoCompositor.self"))
        #expect(playbackSource.contains("|| clipInstruction.chromaKey != nil"))
        #expect(playbackSource.contains("chromaKey: clipInstruction.chromaKey"))
        #expect(playbackSource.contains("mutableVideoComposition.customVideoCompositorClass = CustomVideoCompositor.self"))
    }

    @Test("chroma key view exposes expected controls")
    func chromaKeyViewExposesExpectedControls() throws {
        let source = try source("App/MovieCutMac/Effects/ChromaKeyView.swift")

        #expect(source.contains("Enable Chroma Key"))
        #expect(source.contains("Key Color"))
        #expect(source.contains("Button(\"Green\")"))
        #expect(source.contains("Button(\"Blue\")"))
        #expect(source.contains("Tolerance"))
        #expect(source.contains("Softness"))
        #expect(source.contains("Spill Suppression"))
    }
}
