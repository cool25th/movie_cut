import AVFoundation
import CoreGraphics
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutiOS

/// BUG-IOS-09: clip transitions must reach the RENDER output. The engine
/// previously never built `transitionEffects`, so every transition rendered
/// as a hard cut. Consecutive clips on a transition-carrying track now
/// alternate across two composition tracks with overlap back-timing (Mac
/// ExportEngine parity), and the compositor's two-source transition branch
/// blends them through the shared TransitionPixelProcessor.
@MainActor
@Suite("iOS transition pipeline (BUG-IOS-09)")
struct IOSTransitionPipelineTests {
    private static func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MovieCutiOSTests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Tests/Fixtures")
            .appendingPathComponent(name)
    }

    /// Red 0–2s with a 0.6s crossDissolve at its boundary, blue 2–4s.
    private func transitionProject() -> Project {
        let redId = UUID(), blueId = UUID()
        let red = MediaAsset(originalURL: Self.fixtureURL("solid_red_320x240_2s_30fps.mp4"), kind: .video, duration: 2)
        let blue = MediaAsset(originalURL: Self.fixtureURL("solid_blue_320x240_2s_30fps.mp4"), kind: .video, duration: 2)

        var redClip = Clip(
            assetId: redId,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        redClip.transition = Transition(type: .crossDissolve, duration: 0.6)
        let blueClip = Clip(
            assetId: blueId,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 2, duration: 2)
        )

        var project = Project(
            name: "transition",
            mediaLibrary: MediaLibrary(assets: [redId: red, blueId: blue]),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V1", zIndex: 0, clips: [redClip, blueClip])
            ])
        )
        project.canvas = CanvasPreset(aspectRatio: .custom, customWidth: 320, customHeight: 240)
        return project
    }

    private static func meanFrameRGB(
        of project: Project,
        at seconds: Double
    ) async throws -> (r: Double, g: Double, b: Double) {
        let plan = try await IOSExportEngine().makeRenderPlan(for: project)
        let videoComposition = try #require(plan.videoComposition)
        let generator = AVAssetImageGenerator(asset: plan.composition)
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

    @Test("transition plan uses two slot tracks, an overlapped duration, and one transition effect")
    func transitionPlanStructure() async throws {
        let plan = try await IOSExportEngine().makeRenderPlan(for: transitionProject())

        let videoTracks = plan.composition.tracks.filter { $0.mediaType == .video }
        #expect(videoTracks.count == 2,
                "a transition-carrying track must alternate clips across two composition tracks, got \(videoTracks.count)")

        // The 0.6s overlap shortens 4.0s of model timeline to 3.4s.
        #expect(abs(plan.composition.duration.seconds - 3.4) < 0.05,
                "composition must carry the overlapped duration, got \(plan.composition.duration.seconds)")

        let videoComposition = try #require(plan.videoComposition)
        // Every segment instruction carries the same transition list (the
        // compositor time-filters per frame, Mac parity) — count DISTINCT
        // transitions, not per-instruction copies.
        let uniqueTransitions = Set(
            videoComposition.instructions.compactMap { instruction -> String? in
                guard let custom = instruction as? CustomCompositionInstruction,
                      let transition = custom.transitionEffects.first else {
                    return nil
                }
                return "\(transition.outgoingTrackID)-\(transition.timeRange.start.seconds)-\(transition.type)"
            }
        )
        #expect(uniqueTransitions.count == 1, "exactly one crossDissolve transition expected, got \(uniqueTransitions)")
    }

    @Test("transition-free tracks keep the single-track layout")
    func transitionFreeTrackStaysSingle() async throws {
        // Same two clips, no transition — the byte-identity-preserving
        // single-track layout must be untouched.
        var project = transitionProject()
        project.timeline.tracks[0].clips[0].transition = nil

        let plan = try await IOSExportEngine().makeRenderPlan(for: project)
        let videoTracks = plan.composition.tracks.filter { $0.mediaType == .video }
        #expect(videoTracks.count == 1, "no transition → one composition track, got \(videoTracks.count)")
        #expect(abs(plan.composition.duration.seconds - 4.0) < 0.05,
                "no transition → full timeline duration, got \(plan.composition.duration.seconds)")
    }

    @Test("crossDissolve renders both sources through the blend window (BUG-IOS-09)")
    func crossDissolveBlendsInPlanFrame() async throws {
        let project = transitionProject()
        // Window is the outgoing clip's tail: [1.4, 2.0].
        let before = try await Self.meanFrameRGB(of: project, at: 0.5)
        #expect(before.r > 180 && before.b < 70, "before the window the frame must be pure red, got \(before)")

        let mid = try await Self.meanFrameRGB(of: project, at: 1.7)
        // Progress 0.5 cross-dissolves red and blue toward the middle (~125
        // per channel). The dropped-transition defect rendered a hard cut:
        // pure red before 2.0, pure blue after — both fail these bands.
        #expect(mid.r > 60 && mid.r < 200, "mid-transition must blend red down, got \(mid)")
        #expect(mid.b > 60 && mid.b < 200, "mid-transition must blend blue up, got \(mid)")

        let after = try await Self.meanFrameRGB(of: project, at: 2.5)
        #expect(after.b > 180 && after.r < 70, "after the window the frame must be pure blue, got \(after)")
    }

    /// 후속 관찰 상환 (2026-08-26): rotation × transition combination. The
    /// compositor's two-source branch orients each leg through the effect's
    /// sourcePreferredTransform — a rotated outgoing source must enter the
    /// blend UPRIGHT, not sideways.
    @Test("rotated outgoing source transitions upright (후속 관찰 b)")
    func rotatedOutgoingTransitionsUpright() async throws {
        let rotatedId = UUID(), blueId = UUID()
        let rotated = MediaAsset(originalURL: Self.fixtureURL("ca04_rotated_asym_320x240_2s_90deg.mp4"), kind: .video, duration: 2)
        let blue = MediaAsset(originalURL: Self.fixtureURL("solid_blue_320x240_2s_30fps.mp4"), kind: .video, duration: 2)

        var rotatedClip = Clip(
            assetId: rotatedId,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        rotatedClip.transition = Transition(type: .crossDissolve, duration: 0.6)
        let blueClip = Clip(
            assetId: blueId,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 2, duration: 2)
        )

        var project = Project(
            name: "rotated-transition",
            mediaLibrary: MediaLibrary(assets: [rotatedId: rotated, blueId: blue]),
            timeline: Timeline(canvasSize: CGSize(width: 240, height: 320), tracks: [
                Track(kind: .video, name: "V1", zIndex: 0, clips: [rotatedClip, blueClip])
            ])
        )
        project.canvas = CanvasPreset(aspectRatio: .custom, customWidth: 240, customHeight: 320)

        // BEFORE the transition window: the rotated clip must already render
        // upright through the normal path (BUG-IOS-08 covers the single-track
        // case; this pins it in the transition-carrying track shape).
        let before = try await Self.meanFrameRGB(of: project, at: 0.5)
        #expect(before.r > 90 && before.b > 90,
                "upright asymmetric content shows both halves, got \(before)")

        // Band measurement before the window: red on top / blue on bottom.
        let plan = try await IOSExportEngine().makeRenderPlan(for: project)
        let videoComposition = try #require(plan.videoComposition)
        let generator = AVAssetImageGenerator(asset: plan.composition)
        generator.videoComposition = videoComposition
        generator.maximumSize = CGSize(width: 240, height: 320)
        let frame = try #require(
            try generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil)
        )

        let width = 24, height = 32
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = try #require(context.data?.bindMemory(to: UInt8.self, capacity: width * height * 4))

        func bandMean(_ rows: Range<Int>) -> (r: Double, b: Double) {
            var r = 0.0, b = 0.0
            for row in rows {
                for column in 0..<width {
                    let offset = (row * width + column) * 4
                    r += Double(pixels[offset])
                    b += Double(pixels[offset + 2])
                }
            }
            let count = Double(rows.count * width)
            return (r / count, b / count)
        }

        let top = bandMean(4..<13)
        let bottom = bandMean(19..<28)
        #expect(top.r - top.b > 40, "rotated outgoing must be upright pre-transition (red top), got \(top)")
        #expect(bottom.b - bottom.r > 20, "rotated outgoing must be upright pre-transition (blue bottom), got \(bottom)")

        // AFTER the window: pure blue incoming (letterboxed into the portrait
        // canvas — 320x240 source fits 240x180 of 320 → mean b ≈ 130-140).
        let after = try await Self.meanFrameRGB(of: project, at: 2.5)
        #expect(after.b > 100 && after.r < 50, "after the window the incoming blue must dominate, got \(after)")
    }
}
