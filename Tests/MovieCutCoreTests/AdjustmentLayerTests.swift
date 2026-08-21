import Foundation
import Testing
@testable import MovieCutCore

/// G-03 adjustment layers — Core half: the clip flag's persistence contract
/// (schema v6 + pre-v6 fallback) and the chain collection semantics the
/// design note locks (order, coverage, content exclusion, video-only scope).
@Suite("Adjustment Layers (G-03 Core)")
struct AdjustmentLayerTests {
    private func clip(
        start: TimeInterval,
        duration: TimeInterval,
        adjustment: Bool = false
    ) -> Clip {
        var clip = Clip(
            assetId: UUID(),
            kind: adjustment ? .video : .video,
            sourceRange: TimeRange(start: 0, duration: duration),
            timelineRange: TimeRange(start: start, duration: duration)
        )
        clip.isAdjustmentLayer = adjustment
        return clip
    }

    private func project(tracks: [(kind: TrackKind, zIndex: Int, clips: [Clip])]) -> Project {
        var project = Project(name: "adjust")
        project.timeline.tracks = tracks.map { entry in
            var track = Track(kind: entry.kind, name: "T\(entry.zIndex)", zIndex: entry.zIndex)
            track.clips = entry.clips
            return track
        }
        return project
    }

    // MARK: - Persistence

    @Test("isAdjustmentLayer round-trips and defaults to false")
    func roundTripAndDefault() throws {
        let plain = Clip(assetId: UUID(), kind: .video, sourceRange: TimeRange(start: 0, duration: 1), timelineRange: TimeRange(start: 0, duration: 1))
        #expect(plain.isAdjustmentLayer == false)

        var adjusted = plain
        adjusted.isAdjustmentLayer = true
        let data = try JSONEncoder().encode(adjusted)
        let decoded = try JSONDecoder().decode(Clip.self, from: data)
        #expect(decoded.isAdjustmentLayer == true)

        // A pre-v6 clip JSON (no key) decodes to false.
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "AdjustmentLayerTests", code: 1)
        }
        json.removeValue(forKey: "isAdjustmentLayer")
        let legacy = try JSONDecoder().decode(Clip.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.isAdjustmentLayer == false)
    }

    @Test("schema v6 migration bumps v5 projects without payload changes")
    func migrationV5toV6() throws {
        var project = project(tracks: [(.video, 0, [clip(start: 0, duration: 2)])])
        project.schemaVersion = 5
        var migrated = project
        try ProjectMigrationRunner.migrate(&migrated)
        #expect(migrated.schemaVersion == currentSchemaVersion)
        #expect(migrated.timeline.tracks[0].clips[0].isAdjustmentLayer == false)
    }

    // MARK: - Chain semantics (design note locks)

    @Test("adjustments apply bottom-track-first and only inside their range")
    func orderAndCoverage() {
        let bottom = clip(start: 1, duration: 2, adjustment: true)
        let top = clip(start: 0, duration: 4, adjustment: true)
        let project = project(tracks: [
            (.video, 2, [top]),
            (.video, 1, [bottom]),
        ])

        // Inside both ranges: bottom (zIndex 1) applies BEFORE top (zIndex 2).
        let inside = AdjustmentLayerChain.activeAdjustments(at: 1.5, in: project.timeline.tracks)
        #expect(inside.map(\.id) == [bottom.id, top.id])

        // Outside the bottom adjustment's range: only the top one is active.
        let outside = AdjustmentLayerChain.activeAdjustments(at: 3.5, in: project.timeline.tracks)
        #expect(outside.map(\.id) == [top.id])

        // Past everything: nothing.
        #expect(AdjustmentLayerChain.activeAdjustments(at: 4.5, in: project.timeline.tracks).isEmpty)
    }

    @Test("adjustment clips are excluded from visible content; audio-kind flags are ignored (v1)")
    func contentExclusionAndScope() {
        let adjustment = clip(start: 0, duration: 2, adjustment: true)
        let visible = clip(start: 0, duration: 2)
        var audioAdjustment = clip(start: 0, duration: 2, adjustment: true)
        audioAdjustment.kind = .audio
        let project = project(tracks: [
            (.video, 0, [adjustment, visible]),
            (.audio, 1, [audioAdjustment]),
        ])
        let tracks = project.timeline.tracks

        #expect(AdjustmentLayerChain.isAdjustmentContent(adjustment))
        #expect(AdjustmentLayerChain.isAdjustmentContent(visible) == false)
        #expect(AdjustmentLayerChain.visibleClips(at: 1, in: tracks).map(\.id) == [visible.id])
        // v1: only video-kind tracks' adjustment flags are honored.
        #expect(AdjustmentLayerChain.activeAdjustments(at: 1, in: tracks).map(\.id) == [adjustment.id])
    }
}
