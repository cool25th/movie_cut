import Foundation
import Testing
@testable import MovieCutCore

/// The platform-neutral ducking plan both view models consume (A1 dedup)
/// and the shared `Clip.timelineMapping` it relies on (A2).
@Suite("Speech ducking service (Core)")
struct SpeechDuckingServiceTests {

    private static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MovieCutCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root

    /// A 1 kHz constant tone has no silence, so the whole clip is voiced
    /// and the overlapping BGM must duck across the full overlap.
    @Test("A constant-tone speech clip ducks the overlapping BGM")
    func duckedPlan() async throws {
        let voiceURL = Self.repoRoot.appendingPathComponent("Tests/Fixtures/duck_voice_1000hz_1s_mono.wav")
        let bgmURL = Self.repoRoot.appendingPathComponent("Tests/Fixtures/duck_bgm_220hz_4s_mono.wav")
        let voiceAsset = MediaAsset(originalURL: voiceURL, kind: .audio, duration: 1)
        let bgmAsset = MediaAsset(originalURL: bgmURL, kind: .audio, duration: 4)

        let voice = Clip(assetId: voiceAsset.id, kind: .audio,
                         sourceRange: TimeRange(start: 0, duration: 1),
                         timelineRange: TimeRange(start: 0, duration: 1))
        let bgm = Clip(assetId: bgmAsset.id, kind: .audio,
                       sourceRange: TimeRange(start: 0, duration: 4),
                       timelineRange: TimeRange(start: 0, duration: 4))
        let project = Project(
            name: "duck",
            mediaLibrary: MediaLibrary(assets: [voiceAsset.id: voiceAsset, bgmAsset.id: bgmAsset]),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .audio, name: "A", zIndex: 0, clips: [voice, bgm]),
            ])
        )

        let outcome = try await SpeechDuckingService.plan(project: project, speechClip: voice, asset: voiceAsset)

        guard case .ducked(let rangesByClip, let voiceCount) = outcome else {
            Issue.record("expected .ducked, got \(outcome)")
            return
        }
        #expect(rangesByClip[bgm.id]?.isEmpty == false, "the overlapping BGM must receive ducking ranges")
        #expect(voiceCount >= 1)
        // The speech clip never ducks under itself.
        #expect(rangesByClip[voice.id] == nil)
    }

    @Test("No overlapping audio-track clip yields .noOverlappingAudio")
    func noOverlap() async throws {
        let voiceURL = Self.repoRoot.appendingPathComponent("Tests/Fixtures/duck_voice_1000hz_1s_mono.wav")
        let asset = MediaAsset(originalURL: voiceURL, kind: .audio, duration: 1)
        let voice = Clip(assetId: asset.id, kind: .audio,
                         sourceRange: TimeRange(start: 0, duration: 1),
                         timelineRange: TimeRange(start: 5, duration: 1))
        let project = Project(
            name: "duck-empty",
            mediaLibrary: MediaLibrary(assets: [asset.id: asset]),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .audio, name: "A", zIndex: 0, clips: [voice]),
            ])
        )
        let outcome = try await SpeechDuckingService.plan(project: project, speechClip: voice, asset: asset)
        #expect(outcome == .noOverlappingAudio)
    }

    @Test("Clip.timelineMapping maps source seconds through rate and clamps")
    func timelineMappingMath() throws {
        // 2× rate: 4 s of source occupy [0,2) on the timeline.
        let clip = Clip(
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 4),
            timelineRange: TimeRange(start: 0, duration: 2),
            playbackRate: 2
        )
        let mapped = try #require(clip.timelineMapping(for: TimeRange(start: 1, duration: 1)))
        #expect(abs(mapped.timelineRange.start - 0.5) < 0.001)
        #expect(abs(mapped.timelineRange.duration - 0.5) < 0.001)

        // A range entirely outside the clip's source span maps to nothing.
        #expect(clip.timelineMapping(for: TimeRange(start: 10, duration: 1)) == nil)
    }
}
