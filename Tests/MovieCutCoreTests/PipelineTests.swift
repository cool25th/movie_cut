import CoreVideo
import Foundation
import Testing
@testable import MovieCutCore

#if canImport(AVFoundation)
import AVFoundation
#endif

@MainActor
@Suite("Pipeline coverage")
struct PipelineTests {
    @Test("Export resolution enum raw values are stable")
    func testExportResolutionEnumValues() {
        #expect(ExportResolution.p720.rawValue == "p720")
        #expect(ExportResolution.p1080.rawValue == "p1080")
        #expect(ExportResolution.p4K.rawValue == "p4K")
    }

    @Test("Export codec enum has expected cases")
    func testExportCodecEnumHasExpectedCases() {
        let codecRawValues: Set<String> = [
            ExportCodec.h264.rawValue,
            ExportCodec.hevc.rawValue
        ]

        #expect(codecRawValues == ["h264", "hevc"])
    }

    @Test("Noise reduction service initializes")
    func testNoiseReductionServiceInitializes() {
        #if canImport(AVFoundation)
        let service = NoiseReductionService()

        #expect(type(of: service) == NoiseReductionService.self)
        #else
        #expect(true)
        #endif
    }

    @Test("Background removal provider returns an image")
    func testBackgroundRemovalProviderReturnsImage() throws {
        let provider = BackgroundRemovalProvider()
        let sourceBuffer = try makePipelineTestPixelBuffer(width: 128, height: 128)
        let outputBuffer = try #require(provider.removeBackground(from: sourceBuffer))

        #expect(CVPixelBufferGetWidth(outputBuffer) == 128)
        #expect(CVPixelBufferGetHeight(outputBuffer) == 128)
        #expect(CVPixelBufferGetPixelFormatType(outputBuffer) == kCVPixelFormatType_32BGRA)
    }

    @Test("Audio fade command inverts correctly")
    func testAudioFadeCommandInvertsCorrectly() throws {
        let clipId = UUID()
        let originalFadeIn = 0.2
        let originalFadeOut = 0.4
        let clip = Clip(
            id: clipId,
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 5),
            timelineRange: TimeRange(start: 0, duration: 5),
            fadeInDuration: originalFadeIn,
            fadeOutDuration: originalFadeOut
        )
        var project = Project(
            name: "Pipeline Test",
            timeline: Timeline(tracks: [
                Track(kind: .audio, name: "Audio 1", clips: [clip])
            ])
        )
        let command = AudioFadeCommand(
            clipId: clipId,
            fadeInDuration: 1.0,
            fadeOutDuration: 1.5
        )

        let result = try command.apply(to: &project)
        let inverse = try #require(try command.invert(from: result) as? AudioFadeCommand)

        #expect(inverse.clipId == clipId)
        #expect(inverse.fadeInDuration == originalFadeIn)
        #expect(inverse.fadeOutDuration == originalFadeOut)
    }
}

private func makePipelineTestPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
    let attributes: [String: Any] = [
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:]
    ]
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        attributes as CFDictionary,
        &pixelBuffer
    )

    guard status == kCVReturnSuccess, let pixelBuffer else {
        throw PipelineTestError.pixelBufferCreationFailed(status)
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        throw PipelineTestError.baseAddressUnavailable
    }

    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let centerX = width / 2
    let headCenterY = height / 3
    let headRadius = max(width, height) / 8

    for y in 0..<height {
        let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)

        for x in 0..<width {
            let dx = x - centerX
            let dy = y - headCenterY
            let isHead = dx * dx + dy * dy <= headRadius * headRadius
            let isBody = abs(dx) <= width / 7 && y > headCenterY && y < height * 5 / 6
            let offset = x * 4

            if isHead || isBody {
                row[offset] = 70
                row[offset + 1] = 70
                row[offset + 2] = 70
                row[offset + 3] = 255
            } else {
                row[offset] = 210
                row[offset + 1] = 225
                row[offset + 2] = 235
                row[offset + 3] = 255
            }
        }
    }

    return pixelBuffer
}

private enum PipelineTestError: Error {
    case pixelBufferCreationFailed(CVReturn)
    case baseAddressUnavailable
}
