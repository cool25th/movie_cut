import Foundation
import Testing
@testable import MovieCutCore

/// BUG-ACC-04: start+duration ties in magnetic compaction must not fall
/// through to random UUID ordering — an adjustment layer borrowing a real
/// clip's span could compact FIRST (coin-flip per run, measured ~50%), shove
/// the renderable content to the back half of the track, and kill the export
/// on an empty-source composition request. An adjustment layer is an overlay:
/// it never displaces renderable content in a tie.
@Suite("Magnetic compaction adjustment tie (BUG-ACC-04)")
struct MagneticCompactionAdjustmentTieTests {
    private func clip(
        id: UUID = UUID(),
        adjustment: Bool = false
    ) -> Clip {
        var c = Clip(
            assetId: UUID(),
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 300),
            timelineRange: TimeRange(start: 0, duration: 300)
        )
        c.id = id
        c.isAdjustmentLayer = adjustment
        return c
    }

    @Test("comparator: content beats adjustment on a start+duration tie, independent of UUID order")
    func comparatorTie() {
        // Fixed UUIDs chosen so the ADJUSTMENT holds the smaller uuidString
        // in this pair — the assertion must hold regardless (previously the
        // uuid comparison decided, i.e. a coin flip on random UUIDs).
        let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let highID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let content = clip(id: highID)
        let adjustment = clip(id: lowID, adjustment: true)
        #expect(Track.clipTimelineOrder(content, adjustment) == true)
        #expect(Track.clipTimelineOrder(adjustment, content) == false)
    }

    @Test("compaction: identical spans keep content first, adjustment behind — deterministic")
    func compactionTie() throws {
        var track = Track(kind: .video, name: "v", zIndex: 0)
        let content = clip()
        let adjustment = clip(adjustment: true)
        // Worst-case incoming order: the adjustment listed first.
        track.clips = [adjustment, content]
        try track.compactClipsMagnetically()
        #expect(track.clips[0].isAdjustmentLayer == false)
        #expect(track.clips[0].timelineRange == TimeRange(start: 0, duration: 300))
        #expect(track.clips[1].isAdjustmentLayer == true)
        #expect(track.clips[1].timelineRange == TimeRange(start: 300, duration: 300))
    }
}
