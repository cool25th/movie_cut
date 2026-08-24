import AVFoundation
import CoreGraphics
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutiOS

/// iOS output golden tests — the external review's remaining demand: green
/// unit tests prove wiring, not OUTPUT. These drive the REAL
/// `IOSExportEngine.exportProject` on the standard fixture and pin the
/// output contract:
///
/// 1. Constant-rate speed changes the output length by the rate
///    (2x → half, 0.5x → double) — the historic double-shrink bug class.
/// 2. A freeze frame holds its source across the full timeline span.
/// 3. The exported movie's pixels actually decode to the fixture's content
///    (solid red) — an encode that produces green frames would pass a
///    duration-only check.
@MainActor
@Suite("iOS export output behavior (golden)")
struct IOSExportEngineBehaviorTests {
    private static let fixtureURL: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MovieCutiOSTests
        .deletingLastPathComponent()  // App
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("Tests/Fixtures/solid_red_320x240_2s_30fps.mp4")

    private func makeProject(rate: Double, timelineDuration: Double, sourceDuration: Double) -> Project {
        let assetId = UUID()
        let asset = MediaAsset(originalURL: Self.fixtureURL, kind: .video, duration: 2)
        var clip = Clip(
            assetId: assetId,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: sourceDuration),
            timelineRange: TimeRange(start: 0, duration: timelineDuration)
        )
        clip.playbackRate = rate
        return Project(
            name: "golden-\(rate)x",
            mediaLibrary: MediaLibrary(assets: [assetId: asset]),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V1", zIndex: 0, clips: [clip])
            ])
        )
    }

    private func exportedDuration(of url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return duration.seconds
    }

    /// Mean RGB of a decoded frame, sampled at `time`.
    private func meanFrameRGB(of url: URL, at time: Double) throws -> (r: Double, g: Double, b: Double) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        let cgImage = try generator.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 600), actualTime: nil)
        let width = 32, height = 24
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "golden", code: 1)
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { throw NSError(domain: "golden", code: 2) }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var r = 0.0, g = 0.0, b = 0.0
        for i in 0..<(width * height) {
            r += Double(pixels[i * 4])
            g += Double(pixels[i * 4 + 1])
            b += Double(pixels[i * 4 + 2])
        }
        let count = Double(width * height)
        return (r / count, g / count, b / count)
    }

    @Test("2x speed halves the output duration (fixture 2s → ~1s)")
    func doubleSpeedHalvesDuration() async throws {
        let engine = IOSExportEngine()
        let url = try await engine.exportProject(makeProject(rate: 2.0, timelineDuration: 1.0, sourceDuration: 2.0))
        let duration = try await exportedDuration(of: url)
        // ±0.15s tolerance (~4 frames at 30fps) for encoder padding.
        #expect(abs(duration - 1.0) < 0.15,
                "2x of a 2s source must export ~1s, got \(duration)s")
    }

    @Test("0.5x speed doubles the output duration (fixture 2s → ~4s)")
    func halfSpeedDoublesDuration() async throws {
        let engine = IOSExportEngine()
        let url = try await engine.exportProject(makeProject(rate: 0.5, timelineDuration: 4.0, sourceDuration: 2.0))
        let duration = try await exportedDuration(of: url)
        #expect(abs(duration - 4.0) < 0.2,
                "0.5x of a 2s source must export ~4s, got \(duration)s")
    }

    @Test("freeze frame holds its source across the timeline span (~1s)")
    func freezeFrameHoldsSpan() async throws {
        // A 0.04s source window over a 1s timeline span = freeze.
        let engine = IOSExportEngine()
        let url = try await engine.exportProject(makeProject(rate: 1.0, timelineDuration: 1.0, sourceDuration: 0.04))
        let duration = try await exportedDuration(of: url)
        #expect(abs(duration - 1.0) < 0.15,
                "a frozen frame must fill the 1s timeline, got \(duration)s")
    }

    @Test("the exported movie decodes to the fixture's solid-red content")
    func exportedPixelsMatchFixtureContent() async throws {
        let engine = IOSExportEngine()
        let url = try await engine.exportProject(makeProject(rate: 1.0, timelineDuration: 1.0, sourceDuration: 1.0))
        let mean = try meanFrameRGB(of: url, at: 0.5)
        #expect(mean.r > 150, "solid-red fixture must export red-dominant pixels, got \(mean)")
        #expect(mean.g < 80 && mean.b < 80, "green/blue must stay low, got \(mean)")
    }
}
