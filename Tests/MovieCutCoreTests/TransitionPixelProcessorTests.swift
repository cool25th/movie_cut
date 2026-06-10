import CoreGraphics
import CoreImage
import Foundation
import MovieCutCore
import Testing

@Suite("Transition Pixel Processor")
struct TransitionPixelProcessorTests {
    private let context = CIContext()
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let imageBounds = CGRect(x: 0, y: 0, width: 16, height: 16)

    @Test("cross dissolve mixes red outgoing and blue incoming")
    func crossDissolveMixesExpectedPixels() {
        guard coreImageRenderingAvailable() else { return }

        let outgoing = solidColorImage(red: 1, green: 0, blue: 0)
        let incoming = solidColorImage(red: 0, green: 0, blue: 1)
        let samplePoint = CGPoint(x: 8, y: 8)

        let start = samplePixel(
            from: TransitionPixelProcessor.apply(
                type: .crossDissolve,
                from: outgoing,
                to: incoming,
                progress: 0
            ),
            at: samplePoint
        )
        let middle = samplePixel(
            from: TransitionPixelProcessor.apply(
                type: .crossDissolve,
                from: outgoing,
                to: incoming,
                progress: 0.5
            ),
            at: samplePoint
        )
        let end = samplePixel(
            from: TransitionPixelProcessor.apply(
                type: .crossDissolve,
                from: outgoing,
                to: incoming,
                progress: 1
            ),
            at: samplePoint
        )

        assertPixel(start, red: 255, green: 0, blue: 0)
        #expect(Int(middle.r) > 140 && Int(middle.r) < 205)
        #expect(middle.g < 4)
        #expect(Int(middle.b) > 140 && Int(middle.b) < 205)
        #expect(abs(Int(middle.r) - Int(middle.b)) <= 4)
        #expect(middle.a > 250)
        assertPixel(end, red: 0, green: 0, blue: 255)
    }

    @Test("wipe right reveals incoming on the left and preserves outgoing on the right")
    func wipeRightRevealDirection() {
        guard coreImageRenderingAvailable() else { return }

        let processed = TransitionPixelProcessor.apply(
            type: .wipeRight,
            from: solidColorImage(red: 1, green: 0, blue: 0),
            to: solidColorImage(red: 0, green: 0, blue: 1),
            progress: 0.5
        )

        assertPixel(samplePixel(from: processed, at: CGPoint(x: 2, y: 8)), red: 0, green: 0, blue: 255)
        assertPixel(samplePixel(from: processed, at: CGPoint(x: 14, y: 8)), red: 255, green: 0, blue: 0)
    }

    @Test("wipe left up and down use distinct reveal directions")
    func wipeDirectionalVariantsDiffer() {
        guard coreImageRenderingAvailable() else { return }

        let outgoing = solidColorImage(red: 1, green: 0, blue: 0)
        let incoming = solidColorImage(red: 0, green: 0, blue: 1)
        let wipeLeft = TransitionPixelProcessor.apply(type: .wipeLeft, from: outgoing, to: incoming, progress: 0.5)
        let wipeUp = TransitionPixelProcessor.apply(type: .wipeUp, from: outgoing, to: incoming, progress: 0.5)
        let wipeDown = TransitionPixelProcessor.apply(type: .wipeDown, from: outgoing, to: incoming, progress: 0.5)

        assertPixel(samplePixel(from: wipeLeft, at: CGPoint(x: 2, y: 8)), red: 255, green: 0, blue: 0)
        assertPixel(samplePixel(from: wipeLeft, at: CGPoint(x: 14, y: 8)), red: 0, green: 0, blue: 255)
        assertPixel(samplePixel(from: wipeUp, at: CGPoint(x: 8, y: 2)), red: 0, green: 0, blue: 255)
        assertPixel(samplePixel(from: wipeUp, at: CGPoint(x: 8, y: 14)), red: 255, green: 0, blue: 0)
        assertPixel(samplePixel(from: wipeDown, at: CGPoint(x: 8, y: 2)), red: 255, green: 0, blue: 0)
        assertPixel(samplePixel(from: wipeDown, at: CGPoint(x: 8, y: 14)), red: 0, green: 0, blue: 255)
    }

    @Test("slide left changes sampled pixels compared with cross dissolve")
    func slideLeftDiffersFromCrossDissolve() {
        guard coreImageRenderingAvailable() else { return }

        let outgoing = solidColorImage(red: 1, green: 0, blue: 0)
        let incoming = solidColorImage(red: 0, green: 0, blue: 1)
        let point = CGPoint(x: 2, y: 8)
        let slide = TransitionPixelProcessor.apply(type: .slideLeft, from: outgoing, to: incoming, progress: 0.5)
        let dissolve = TransitionPixelProcessor.apply(type: .crossDissolve, from: outgoing, to: incoming, progress: 0.5)

        #expect(pixelDistance(samplePixel(from: slide, at: point), samplePixel(from: dissolve, at: point)) > 80)
    }

    @Test("zoom in preserves extent and changes the center sample as progress advances")
    func zoomInPreservesExtentAndChangesCenter() {
        guard coreImageRenderingAvailable() else { return }

        let outgoing = solidColorImage(red: 1, green: 0, blue: 0)
        let incoming = solidColorImage(red: 0, green: 0, blue: 1)
        let early = TransitionPixelProcessor.apply(type: .zoomIn, from: outgoing, to: incoming, progress: 0.25)
        let late = TransitionPixelProcessor.apply(type: .zoomIn, from: outgoing, to: incoming, progress: 0.75)

        #expect(early.extent == outgoing.extent)
        #expect(late.extent == outgoing.extent)
        #expect(pixelDistance(
            samplePixel(from: early, at: CGPoint(x: 8, y: 8)),
            samplePixel(from: late, at: CGPoint(x: 8, y: 8))
        ) > 80)
    }

    @Test("glitch is deterministic and differs from plain cross dissolve")
    func glitchIsDeterministicAndDistinct() {
        guard coreImageRenderingAvailable() else { return }

        let outgoing = solidColorImage(red: 1, green: 0, blue: 0)
        let incoming = solidColorImage(red: 0, green: 0, blue: 1)
        let first = TransitionPixelProcessor.apply(type: .glitch, from: outgoing, to: incoming, progress: 0.5)
        let second = TransitionPixelProcessor.apply(type: .glitch, from: outgoing, to: incoming, progress: 0.5)
        let dissolve = TransitionPixelProcessor.apply(type: .crossDissolve, from: outgoing, to: incoming, progress: 0.5)

        let firstPixels = pixels(from: first)
        let secondPixels = pixels(from: second)
        let dissolvePixels = pixels(from: dissolve)

        #expect(firstPixels == secondPixels)
        #expect(firstPixels != dissolvePixels)
    }

    private func coreImageRenderingAvailable() -> Bool {
        let sentinel = samplePixel(
            from: solidColorImage(red: 0.35, green: 0.35, blue: 0.35),
            at: CGPoint(x: 0, y: 0)
        )
        if sentinel.r == 0 && sentinel.g == 0 && sentinel.b == 0 && sentinel.a == 0 {
            print("Skipping CIContext pixel assertion: renderer returned transparent black for a non-black fixture.")
            return false
        }
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
            context.render(
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

    private func pixels(from image: CIImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Int(imageBounds.width * imageBounds.height) * 4)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(
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

    private func assertPixel(
        _ pixel: Pixel,
        red: Int,
        green: Int,
        blue: Int,
        alpha: Int = 255,
        tolerance: Int = 2
    ) {
        #expect(abs(Int(pixel.r) - red) <= tolerance)
        #expect(abs(Int(pixel.g) - green) <= tolerance)
        #expect(abs(Int(pixel.b) - blue) <= tolerance)
        #expect(abs(Int(pixel.a) - alpha) <= tolerance)
    }

    private func pixelDistance(_ lhs: Pixel, _ rhs: Pixel) -> Int {
        abs(Int(lhs.r) - Int(rhs.r))
            + abs(Int(lhs.g) - Int(rhs.g))
            + abs(Int(lhs.b) - Int(rhs.b))
            + abs(Int(lhs.a) - Int(rhs.a))
    }

    private struct Pixel: Equatable {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var a: UInt8
    }
}

@Suite("Transition Static Contract")
struct TransitionStaticContractTests {
    private let expandedCases: [(TransitionType, String)] = [
        (.none, "none"),
        (.crossDissolve, "crossDissolve"),
        (.fadeThroughBlack, "fadeThroughBlack"),
        (.wipeRight, "wipeRight"),
        (.wipeLeft, "wipeLeft"),
        (.wipeUp, "wipeUp"),
        (.wipeDown, "wipeDown"),
        (.slideLeft, "slideLeft"),
        (.slideRight, "slideRight"),
        (.zoomIn, "zoomIn"),
        (.zoomOut, "zoomOut"),
        (.glitch, "glitch")
    ]

    private let advancedCases = [
        "wipeLeft",
        "wipeUp",
        "wipeDown",
        "slideLeft",
        "slideRight",
        "zoomIn",
        "zoomOut",
        "glitch"
    ]

    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("transition type all cases and raw values are stable")
    func transitionTypeRawValuesAreStable() {
        #expect(TransitionType.allCases == expandedCases.map(\.0))
        for (type, rawValue) in expandedCases {
            #expect(type.rawValue == rawValue)
        }
        #expect(TransitionType.wipeLeft.category == .wipe)
        #expect(TransitionType.slideLeft.category == .slide)
        #expect(TransitionType.zoomIn.category == .zoom)
        #expect(TransitionType.glitch.category == .stylized)
        #expect(TransitionType.wipeLeft.isDirectional)
        #expect(TransitionType.slideRight.isDirectional)
        #expect(TransitionType.glitch.requiresTwoSourcePixelProcessing)
    }

    @Test("Mac inspector exposes expanded transition labels and keeps picker duration controls")
    func macInspectorExposesExpandedTransitionLabels() throws {
        let sharedSource = try source("App/MovieCutMac/Inspector/InspectorShared.swift")
        let effectsSource = try source("App/MovieCutMac/Inspector/InspectorEffectsSection.swift")
        let labels = [
            "None",
            "Cross Dissolve",
            "Fade Through Black",
            "Wipe Right",
            "Wipe Left",
            "Wipe Up",
            "Wipe Down",
            "Slide Left",
            "Slide Right",
            "Zoom In",
            "Zoom Out",
            "Glitch"
        ]

        for label in labels {
            #expect(sharedSource.contains(label))
        }
        #expect(effectsSource.contains("ForEach(TransitionType.allCases"))
        #expect(effectsSource.contains("updateTransitionDuration"))
        #expect(effectsSource.contains("Slider(value: Binding("))
    }

    @Test("Mac export and playback handle advanced transition cases explicitly")
    func macExportAndPlaybackHandleAdvancedTransitionCases() throws {
        let exportSource = try source("App/MovieCutMac/Export/ExportEngine.swift")
        let playbackSource = try source("App/MovieCutMac/Playback/PlaybackEngine.swift")

        for rawValue in advancedCases {
            let caseName = ".\(rawValue)"
            #expect(exportSource.contains(caseName))
            #expect(playbackSource.contains(caseName))
        }

        #expect(exportSource.contains("advancedTransitionPixelProcessorHook"))
        #expect(playbackSource.contains("advancedTransitionPixelProcessorHook"))
        #expect(exportSource.contains("TransitionPixelProcessor.apply(type:from:to:progress:)"))
        #expect(playbackSource.contains("TransitionPixelProcessor.apply(type:from:to:progress:)"))
    }
}
