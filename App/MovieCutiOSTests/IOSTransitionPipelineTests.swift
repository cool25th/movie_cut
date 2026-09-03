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

    /// CODEX-09: three 1s clips with 2s crossDissolves. Each request
    /// exceeds BOTH neighbors, so the transition effect window clamps to
    /// 1s — but the placement back-timing pulled starts by the RAW 2s
    /// request, putting clip 3 before its slot cursor where insertClip's
    /// `timelineStart >= cursor` guard silently dropped it from the export.
    private func oversizedTransitionProject() -> Project {
        let redId = UUID(), blueId = UUID()
        let red = MediaAsset(originalURL: Self.fixtureURL("solid_red_320x240_2s_30fps.mp4"), kind: .video, duration: 2)
        let blue = MediaAsset(originalURL: Self.fixtureURL("solid_blue_320x240_2s_30fps.mp4"), kind: .video, duration: 2)

        func clip(_ assetId: UUID, timelineStart: Double, transitionDuration: Double?) -> Clip {
            var clip = Clip(
                assetId: assetId,
                kind: .video,
                sourceRange: TimeRange(start: 0, duration: 1),
                timelineRange: TimeRange(start: timelineStart, duration: 1)
            )
            if let transitionDuration {
                clip.transition = Transition(type: .crossDissolve, duration: transitionDuration)
            }
            return clip
        }

        var project = Project(
            name: "oversized-transition",
            mediaLibrary: MediaLibrary(assets: [redId: red, blueId: blue]),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V1", zIndex: 0, clips: [
                    clip(redId, timelineStart: 0, transitionDuration: 2.0),
                    clip(blueId, timelineStart: 1, transitionDuration: 2.0),
                    clip(redId, timelineStart: 2, transitionDuration: nil),
                ])
            ])
        )
        project.canvas = CanvasPreset(aspectRatio: .custom, customWidth: 320, customHeight: 240)
        return project
    }

    @Test("oversized transitions keep all three clips placed (CODEX-09)")
    func oversizedTransitionsKeepAllClips() async throws {
        let project = oversizedTransitionProject()
        let plan = try await IOSExportEngine().makeRenderPlan(for: project)

        let videoTracks = plan.composition.tracks.filter { $0.mediaType == .video }
        #expect(videoTracks.count == 2,
                "transition-carrying track alternates two slots, got \(videoTracks.count)")

        let mediaSegments = videoTracks.flatMap { track in
            track.segments.filter { $0.sourceURL != nil }
        }
        #expect(mediaSegments.count == 3,
                "all three clips must place media — a silent drop loses the tail clip, got \(mediaSegments.count)")

        // Each 2s request clamps to the 1s neighbors: 3.0s of model timeline
        // loses 1.0s + 1.0s of overlap → 2.0s composition.
        #expect(abs(plan.composition.duration.seconds - 2.0) < 0.05,
                "composition carries the clamped overlaps, got \(plan.composition.duration.seconds)")

        // Late-window frame comes from the THIRD clip: with the drop, the
        // composition ended at 1.0s and this seek produced no frame at all.
        let late = try await Self.meanFrameRGB(of: project, at: 1.9)
        #expect(late.r > 150 && late.b < 110,
                "the second blend window must mix toward the third (red) clip, got \(late)")
    }

    /// CODEX-08: a mixed-rotation track made the SECOND clip inherit the
    /// track-level preferredTransform that insertClip set from whichever
    /// source hit the slot first — a landscape-then-portrait track rendered
    /// the portrait clip sideways, and portrait-then-landscape rotated the
    /// landscape clip. Each clip's effect must carry its OWN source
    /// orientation.
    private func mixedRotationProject(rotatedFirst: Bool) -> Project {
        let redId = UUID(), rotatedId = UUID()
        let red = MediaAsset(originalURL: Self.fixtureURL("solid_red_320x240_2s_30fps.mp4"), kind: .video, duration: 2)
        let rotated = MediaAsset(originalURL: Self.fixtureURL("ca04_rotated_asym_320x240_2s_90deg.mp4"), kind: .video, duration: 2)

        func clip(_ assetId: UUID, timelineStart: Double) -> Clip {
            Clip(
                assetId: assetId,
                kind: .video,
                sourceRange: TimeRange(start: 0, duration: 2),
                timelineRange: TimeRange(start: timelineStart, duration: 2)
            )
        }
        let first = rotatedFirst
            ? clip(rotatedId, timelineStart: 0)
            : clip(redId, timelineStart: 0)
        let second = rotatedFirst
            ? clip(redId, timelineStart: 2)
            : clip(rotatedId, timelineStart: 2)

        var project = Project(
            name: "mixed-rotation",
            mediaLibrary: MediaLibrary(assets: [redId: red, rotatedId: rotated]),
            timeline: Timeline(canvasSize: CGSize(width: 240, height: 320), tracks: [
                Track(kind: .video, name: "V1", zIndex: 0, clips: [first, second])
            ])
        )
        project.canvas = CanvasPreset(aspectRatio: .custom, customWidth: 240, customHeight: 320)
        return project
    }

    @Test("landscape-then-portrait track renders the portrait clip upright (CODEX-08)")
    func landscapeThenPortraitOrientsPortraitUpright() async throws {
        // In this order the defect stays hidden today: the track pt keeps
        // reading identity until the ROTATED clip inserts (the setter only
        // fires while the track is still identity), so the portrait clip
        // lands upright by accident. This pins that outcome so the per-clip
        // fix cannot regress it.
        let project = mixedRotationProject(rotatedFirst: false)
        let plan = try await IOSExportEngine().makeRenderPlan(for: project)
        let videoComposition = try #require(plan.videoComposition)
        let generator = AVAssetImageGenerator(asset: plan.composition)
        generator.videoComposition = videoComposition
        generator.maximumSize = CGSize(width: 240, height: 320)
        // t=3.0 sits inside the SECOND (rotated-asym, 90°) clip: upright it
        // shows red on top / blue on bottom; a sideways render leaves the
        // storage frame's left/right split, mixing both colors in every
        // horizontal band.
        let frame = try #require(
            try generator.copyCGImage(at: CMTime(seconds: 3.0, preferredTimescale: 600), actualTime: nil)
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
        #expect(top.r - top.b > 40, "portrait clip must render upright (red top), got \(top)")
        #expect(bottom.b - bottom.r > 20, "portrait clip must render upright (blue bottom), got \(bottom)")
    }

    @Test("portrait-then-landscape clip effects carry per-clip orientations (CODEX-08)")
    func portraitThenLandscapeEffectsCarryOwnOrientation() async throws {
        let project = mixedRotationProject(rotatedFirst: true)
        let plan = try await IOSExportEngine().makeRenderPlan(for: project)
        let videoComposition = try #require(plan.videoComposition)

        func orientationsAt(_ seconds: Double) -> [CGAffineTransform] {
            let t = CMTime(seconds: seconds, preferredTimescale: 600)
            return videoComposition.instructions.compactMap { instruction -> [CGAffineTransform]? in
                guard let custom = instruction as? CustomCompositionInstruction,
                      CMTimeRangeContainsTime(custom.timeRange, time: t) else {
                    return nil
                }
                return custom.clipEffects
                    .filter { CMTimeRangeContainsTime($0.timeRange, time: t) }
                    .map(\.sourcePreferredTransform)
            }.flatMap { $0 }
        }
        func isQuarterTurn(_ t: CGAffineTransform) -> Bool {
            abs(t.a) < 1e-6 && abs(t.d) < 1e-6
                && abs(abs(t.b) - 1) < 1e-6 && abs(abs(t.c) - 1) < 1e-6
        }
        func isIdentity(_ t: CGAffineTransform) -> Bool {
            t == .identity
        }

        // The first (rotated) clip's effect keeps the 90° storage transform
        // (rotation quadrant: a=d=0, |b|=|c|=1).
        let firstOrientations = orientationsAt(1.0)
        #expect(!firstOrientations.isEmpty && firstOrientations.allSatisfy(isQuarterTurn),
                "rotated clip effect must carry the 90° source transform, got \(firstOrientations)")

        // The SECOND (landscape) clip must NOT inherit it — identity only.
        // Track-level inheritance gave it the 90° transform and rotated the
        // landscape clip sideways.
        let secondOrientations = orientationsAt(3.0)
        #expect(!secondOrientations.isEmpty && secondOrientations.allSatisfy(isIdentity),
                "landscape clip effect must carry identity, got \(secondOrientations)")
    }
}
