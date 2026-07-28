import CoreGraphics
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutMac

/// Behavior regression test for the waveform invalidation break (4f1a65c).
///
/// When a clip's source asset is swapped (e.g. noise reduction), the waveform
/// cache is invalidated. The decode must be re-requested for the new asset, or
/// the waveform stays on the fallback forever. This test pins that contract at
/// the ViewModel level — the same contract the view's `.task(id:)` relies on.
///
/// Scope: the invalidation/re-request contract only. It does not run the real
/// AVAssetReader decode (that is exercised by Core's WaveformGeneratorTests);
/// it asserts that an invalidated clip's asset is re-queued for decoding.
@MainActor
@Suite("Waveform invalidation")
struct WaveformInvalidationTests {
    /// Noise reduction swaps the clip's asset (clip id unchanged). After the
    /// swap, invalidating the waveform must re-request a decode for the new
    /// asset — otherwise the view's `.task(id: clipId)` never re-runs and the
    /// waveform is stuck.
    @Test("Invalidating a waveform after an asset swap re-requests the decode")
    func invalidationReRequestsDecodeForNewAsset() async throws {
        let assetA = UUID()
        let assetB = UUID()
        let clipId = UUID()
        let clipA = Clip(
            id: clipId,
            assetId: assetA,
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 1),
            timelineRange: TimeRange(start: 0, duration: 1)
        )
        let clipB = Clip(
            id: clipId,
            assetId: assetB,
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 1),
            timelineRange: TimeRange(start: 0, duration: 1)
        )

        let vm = EditorViewModel(project: Project(
            name: "test",
            mediaLibrary: MediaLibrary(assets: [
                assetA: MediaAsset(originalURL: URL(fileURLWithPath: "/tmp/a.wav"), kind: .audio, duration: 1),
                assetB: MediaAsset(originalURL: URL(fileURLWithPath: "/tmp/b.wav"), kind: .audio, duration: 1)
            ]),
            timeline: Timeline(canvasSize: CGSize(width: 100, height: 100), tracks: [
                Track(kind: .audio, name: "Audio 1", zIndex: 0, clips: [clipA])
            ])
        ))

        // Establish a request for the original asset, then clear the in-flight
        // marker so the re-request is observable (the decode never completes in
        // this test because the fixture URLs don't exist).
        vm.requestWaveformDecode(for: clipA)
        #expect(vm.isWaveformDecodeRequested(forClip: clipId))
        vm.cancelWaveformDecode(forClip: clipId)

        // Simulate the asset swap + invalidation (what applyNoiseReduction does).
        vm.invalidateWaveform(for: clipB)

        // The new asset must be re-queued for decoding.
        #expect(
            vm.isWaveformDecodeRequested(forClip: clipId),
            "invalidating a clip's waveform after an asset swap must re-request a decode for the new asset"
        )
    }
}
