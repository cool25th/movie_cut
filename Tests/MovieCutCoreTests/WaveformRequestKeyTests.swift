import Foundation
import MovieCutCore
import Testing

/// Regression test for the waveform invalidation break introduced by 4f1a65c.
///
/// When a clip's asset is swapped (noise reduction, denoise), `SetClipSourceAssetCommand`
/// keeps the clip id but changes the asset. The waveform decode trigger is a SwiftUI
/// `.task(id:)`, which only re-runs when its id changes. If the id were just `clipId`,
/// the asset swap would never re-trigger a decode and the waveform would be stuck on the
/// fallback forever.
///
/// This test fixes the value-level condition for re-requesting: the decode-request
/// identity must include the asset. It is a proxy — it does not verify the view actually
/// re-runs — but it pins the contract the view's `.task(id:)` must depend on.
@Suite("WaveformRequestKey")
struct WaveformRequestKeyTests {
    private let clipId = UUID(uuidString: "aa000000-0000-4000-8000-000000000001")!
    private let assetA = UUID(uuidString: "bb000000-0000-4000-8000-000000000001")!
    private let assetB = UUID(uuidString: "bb000000-0000-4000-8000-000000000002")!

    @Test("Same clip id, different asset → different request key")
    func assetSwapProducesDifferentKey() {
        // The exact regression: noise reduction swaps the asset, clipId is unchanged.
        let before = WaveformRequestKey(clipId: clipId, assetId: assetA)
        let after = WaveformRequestKey(clipId: clipId, assetId: assetB)
        #expect(before != after, "an asset swap must change the waveform request key, else the .task(id:) never re-runs")
    }

    @Test("Same clip id and asset → same key")
    func stableBindingProducesSameKey() {
        let a = WaveformRequestKey(clipId: clipId, assetId: assetA)
        let b = WaveformRequestKey(clipId: clipId, assetId: assetA)
        #expect(a == b)
    }

    @Test("Different clip id, same asset → different key")
    func differentClipsAreDifferent() {
        let other = UUID(uuidString: "aa000000-0000-4000-8000-000000000002")!
        let a = WaveformRequestKey(clipId: clipId, assetId: assetA)
        let b = WaveformRequestKey(clipId: other, assetId: assetA)
        #expect(a != b)
    }

    @Test("Clip convenience initializer mirrors explicit construction")
    func clipInitMatchesExplicit() {
        let clip = Clip(
            id: clipId,
            assetId: assetA,
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 1),
            timelineRange: TimeRange(start: 0, duration: 1)
        )
        #expect(WaveformRequestKey(clip: clip) == WaveformRequestKey(clipId: clipId, assetId: assetA))
    }

    @Test("Asset-less clip is distinguished only by clip id")
    func assetlessClipKey() {
        let a = WaveformRequestKey(clipId: clipId, assetId: nil)
        let b = WaveformRequestKey(clipId: clipId, assetId: nil)
        #expect(a == b)
    }

    @Test("WaveformRequestKey is usable as a SwiftUI .task(id:) identity")
    func hashableForTaskIdentity() {
        let key = WaveformRequestKey(clipId: clipId, assetId: assetA)
        let set: Set<WaveformRequestKey> = [key]
        #expect(set.contains(WaveformRequestKey(clipId: clipId, assetId: assetA)))
        #expect(!set.contains(WaveformRequestKey(clipId: clipId, assetId: assetB)))
    }
}
