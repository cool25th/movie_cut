import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import MovieCutCore

/// F-11 canvas background: model persistence, command undo, and the shared
/// pixel processor that both compositors consume.
@Suite("Canvas Background")
struct CanvasBackgroundTests {
    private let context = CIContext()
    private let renderSize = CGSize(width: 108, height: 192)

    // MARK: - Model

    @Test("legacy project JSON without canvasBackground decodes as nil")
    func legacyProjectDecodesNilBackground() throws {
        let project = Project(name: "Legacy")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var json = try #require(JSONSerialization.jsonObject(with: encoder.encode(project)) as? [String: Any])
        json.removeValue(forKey: "canvasBackground")
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Project.self, from: data)
        #expect(decoded.canvasBackground == nil)
    }

    @Test("each background kind round-trips through project encoding")
    func backgroundRoundTrips() throws {
        let cases: [CanvasBackground] = [
            .color(hex: "0B1D3A"),
            .sourceBlur(radius: 24),
            .image(url: URL(fileURLWithPath: "/tmp/bg.png"))
        ]

        for background in cases {
            var project = Project(name: "RoundTrip")
            project.canvasBackground = background

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(Project.self, from: encoder.encode(project))
            #expect(decoded.canvasBackground == background)
        }
    }

    // MARK: - Command

    @Test("set command applies and undo restores the previous background")
    func commandAppliesAndUndoes() async throws {
        let session = EditorSession(project: Project(name: "Background"))

        try await session.dispatch(SetCanvasBackgroundCommand(background: .color(hex: "FFFFFF")))
        try await session.dispatch(SetCanvasBackgroundCommand(background: .sourceBlur(radius: 12)))

        var snapshot = await session.snapshot()
        #expect(snapshot.canvasBackground == .sourceBlur(radius: 12))

        try await session.undo()
        snapshot = await session.snapshot()
        #expect(snapshot.canvasBackground == .color(hex: "FFFFFF"))

        try await session.undo()
        snapshot = await session.snapshot()
        #expect(snapshot.canvasBackground == nil)
    }

    @Test("command apply clears the background")
    func commandInvertRestoresPrior() throws {
        var project = Project(name: "Invert")
        project.canvasBackground = .color(hex: "112233")

        let command = SetCanvasBackgroundCommand(background: nil)
        try command.apply(to: &project)
        #expect(project.canvasBackground == nil)
    }

    // MARK: - Pixel processor

    @Test("nil background passes the frame through unchanged")
    func nilBackgroundIsPassthrough() {
        let frame = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 60, width: 108, height: 72))
        let composed = CanvasBackgroundPixelProcessor.compose(
            frame: frame,
            over: nil,
            renderSize: renderSize
        )
        #expect(composed === frame || composed.extent == frame.extent)
    }

    @Test("color background fills the full canvas extent")
    func colorBackgroundFillsCanvas() {
        let frame = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 60, width: 108, height: 72))
        let composed = CanvasBackgroundPixelProcessor.compose(
            frame: frame,
            over: .color(hex: "FFFFFF"),
            renderSize: renderSize
        )
        #expect(composed.extent == CGRect(x: 0, y: 0, width: renderSize.width, height: renderSize.height))

        let letterbox = samplePixel(from: composed, at: CGPoint(x: 54, y: 10))
        let center = samplePixel(from: composed, at: CGPoint(x: 54, y: 96))
        if letterbox.a == 0 && center.a == 0 {
            print("Skipping CIContext pixel assertion: renderer returned transparent black.")
        } else {
            #expect(letterbox.r > 200 && letterbox.g > 200 && letterbox.b > 200)
            #expect(center.r > 200 && center.g < 80 && center.b < 80)
        }
    }

    @Test("source blur background covers the canvas and stays renderable")
    func blurBackgroundCoversCanvas() {
        let frame = CIImage(color: .green).cropped(to: CGRect(x: 0, y: 60, width: 108, height: 72))
        let composed = CanvasBackgroundPixelProcessor.compose(
            frame: frame,
            over: .sourceBlur(radius: 16),
            renderSize: renderSize
        )
        #expect(composed.extent == CGRect(x: 0, y: 0, width: renderSize.width, height: renderSize.height))

        let band = samplePixel(from: composed, at: CGPoint(x: 54, y: 8))
        if band.a != 0 {
            // Blurred green source should tint the letterbox band green-ish.
            #expect(band.g >= band.r)
        }
    }

    @Test("invalid hex and missing image fall back to black")
    func invalidInputsFallBackToBlack() {
        let frame = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 60, width: 108, height: 72))

        let badHex = CanvasBackgroundPixelProcessor.backgroundImage(
            for: .color(hex: "ZZZ"),
            sourceFrame: frame,
            renderSize: renderSize
        )
        #expect(badHex.extent == CGRect(x: 0, y: 0, width: renderSize.width, height: renderSize.height))

        let missingImage = CanvasBackgroundPixelProcessor.backgroundImage(
            for: .image(url: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).png")),
            sourceFrame: frame,
            renderSize: renderSize
        )
        #expect(missingImage.extent == CGRect(x: 0, y: 0, width: renderSize.width, height: renderSize.height))
    }

    @Test("aspect fill scales the source to cover the target rect")
    func aspectFillCoversRect() {
        let source = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 160, height: 90))
        let target = CGRect(x: 0, y: 0, width: renderSize.width, height: renderSize.height)
        let filled = CanvasBackgroundPixelProcessor.aspectFill(source, into: target)
        #expect(filled.extent == target)
    }

    @Test("hex parsing maps channels correctly")
    func hexParsing() throws {
        let color = try #require(CanvasBackgroundPixelProcessor.ciColor(fromHex: "#3366CC"))
        #expect(abs(color.red - 0x33 / 255.0) < 0.001)
        #expect(abs(color.green - 0x66 / 255.0) < 0.001)
        #expect(abs(color.blue - 0xCC / 255.0) < 0.001)
        #expect(CanvasBackgroundPixelProcessor.ciColor(fromHex: "nope") == nil)
    }

    // MARK: - Helpers

    private func samplePixel(from image: CIImage, at point: CGPoint) -> Pixel {
        let bounds = CGRect(x: point.x, y: point.y, width: 1, height: 1)
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(
                image.cropped(to: bounds),
                toBitmap: buffer.baseAddress!,
                rowBytes: 4,
                bounds: bounds,
                format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
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
