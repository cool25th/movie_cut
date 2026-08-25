import AVFoundation
import CoreGraphics
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutMac

/// BUG-08 (2026-08-26 review): an all-`.normal` multi-track frame must still
/// composite its lower source track. The old pixel-identity gate returned the
/// primary as-is unless some clip carried a non-normal blend mode, so an
/// overlay using plain opacity/mask/crop dropped the track beneath it and
/// showed the canvas background instead. These tests drive the REAL
/// CustomVideoCompositor — AVAssetImageGenerator instantiates it from
/// `customVideoCompositorClass` — over distinct-color fixtures with the same
/// instruction/effect shape the engines produce (clipEffects ordered
/// bottom-to-top, so the reversed walk makes the red track primary).
@Suite("Multi-track normal compositing (BUG-08)")
struct MultitrackNormalBlendPixelTests {
    private static let fixturesRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MovieCutMacTests
        .deletingLastPathComponent()  // App
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("Tests/Fixtures")

    private struct TrackSpec {
        let fixture: String
        let opacity: Double
    }

    /// Inserts one composition track per spec (in order) and attaches a
    /// single 0–2s instruction carrying one clip effect per track.
    private func buildComposition(_ specs: [TrackSpec]) async throws -> (composition: AVMutableComposition, videoComposition: AVMutableVideoComposition) {
        let composition = AVMutableComposition()
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600))

        var trackIDs: [CMPersistentTrackID] = []
        var effects: [CustomCompositionClipEffect] = []
        for spec in specs {
            let asset = AVURLAsset(url: Self.fixturesRoot.appendingPathComponent(spec.fixture))
            let source = try #require(
                try await asset.loadTracks(withMediaType: .video).first,
                "fixture \(spec.fixture) has no video track"
            )
            let track = try #require(
                composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            )
            try track.insertTimeRange(range, of: source, at: .zero)
            trackIDs.append(track.trackID)
            effects.append(try #require(CustomCompositionClipEffect(
                trackID: track.trackID,
                timeRange: range,
                opacity: spec.opacity,
                colorCorrection: nil,
                mask: nil,
                includeIdentitySource: true
            )))
        }

        let instruction = CustomCompositionInstruction(
            timeRange: range,
            trackIDs: trackIDs,
            clipEffects: effects
        )

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: 320, height: 240)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.customVideoCompositorClass = CustomVideoCompositor.self
        videoComposition.instructions = [instruction]
        return (composition, videoComposition)
    }

    /// Renders one frame through the real compositor and downsamples to mean RGB.
    private static func meanFrameRGB(
        of composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        at seconds: Double
    ) throws -> (r: Double, g: Double, b: Double) {
        let generator = AVAssetImageGenerator(asset: composition)
        generator.videoComposition = videoComposition
        generator.maximumSize = CGSize(width: 320, height: 240)
        let frame = try #require(
            try generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
        )
        let width = 32, height = 24
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = try #require(context.data?.bindMemory(to: UInt8.self, capacity: width * height * 4))
        var r = 0.0, g = 0.0, b = 0.0
        for i in 0..<(width * height) {
            r += Double(pixels[i * 4])
            g += Double(pixels[i * 4 + 1])
            b += Double(pixels[i * 4 + 2])
        }
        let count = Double(width * height)
        return (r / count, g / count, b / count)
    }

    @Test("half-opacity `.normal` overlay shows the blue track beneath (BUG-08)")
    func halfOpacityOverlayShowsBase() async throws {
        // Bottom-to-top: blue base, red top at half opacity.
        let built = try await buildComposition([
            TrackSpec(fixture: "solid_blue_320x240_2s_30fps.mp4", opacity: 1),
            TrackSpec(fixture: "solid_red_320x240_2s_30fps.mp4", opacity: 0.5),
        ])
        let mean = try Self.meanFrameRGB(
            of: built.composition, videoComposition: built.videoComposition, at: 0.5
        )
        // Half-opacity red over solid blue must show BOTH layers (~130 per
        // channel). With the dropped-layer defect the blue channel collapses
        // toward the canvas background (~20).
        #expect(mean.r > 90, "the half-opacity red top must contribute, got \(mean)")
        #expect(mean.b > 80, "BUG-08: the blue base must show through the `.normal` half-opacity top, got \(mean)")
        #expect(mean.g < 70, "neither fixture has meaningful green, got \(mean)")
    }

    @Test("a single active track keeps the identity passthrough")
    func singleTrackRendersBlue() async throws {
        // The revised gate must still return single-track frames untouched —
        // the original Requirement 4.3 byte-identity concern now lives in the
        // empty-activeEffects guard.
        let built = try await buildComposition([
            TrackSpec(fixture: "solid_blue_320x240_2s_30fps.mp4", opacity: 1),
        ])
        let mean = try Self.meanFrameRGB(
            of: built.composition, videoComposition: built.videoComposition, at: 0.5
        )
        #expect(mean.b > 180, "solid blue must render as blue, got \(mean)")
        #expect(mean.r < 60, "solid blue must not bleed red, got \(mean)")
    }
}
