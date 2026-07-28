import Foundation
import Testing

/// Static contract for the waveform decode-trigger identity.
///
/// This is a proxy test, with an honest limitation: it cannot verify SwiftUI
/// actually re-runs the `.task` on an asset swap (that requires the view
/// lifecycle, which Core tests cannot reach). What it CAN pin is the value-level
/// contract the fix rests on: the decode-trigger identity must be keyed on the
/// asset, not just the clip id.
///
/// Why this matters: 4f1a65c moved the decode trigger to `.task(id: clipId)`.
/// When noise reduction swaps a clip's asset (clip id unchanged), `.task` never
/// re-ran and the waveform was stuck on the fallback forever. The fix keys the
/// task on WaveformRequestKey(clip:) — clip + asset. This test fails if the
/// view regresses to `.task(id: clipId)` (clip-only identity).
@Suite("Waveform task identity StaticContract")
struct WaveformTaskIdentityStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("waveformCanvas .task id includes the asset (WaveformRequestKey)")
    func taskIdIncludesAsset() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")

        // The decode-triggering .task must key on the asset-bearing identity.
        // A clip-only id (.task(id: clipId)) is the regression: it does not
        // re-run on an asset swap.
        #expect(timeline.contains(".task(id: requestKey)"), "waveform decode .task must key on WaveformRequestKey (clip + asset), not clip id alone")
        #expect(!timeline.contains(".task(id: clipId)"), "waveform decode .task must not key on clip id alone (regression from 4f1a65c)")
    }

    @Test("noise reduction invalidation re-requests the decode for the new asset")
    func noiseReductionReRequestsDecode() throws {
        let vm = try source("App/MovieCutMac/EditorViewModel.swift")

        // The asset-swap site must re-request the decode itself, not just clear
        // the cache and hope the view notices.
        #expect(vm.contains("invalidateWaveform(for:"), "noise reduction must call invalidateWaveform to re-request the decode for the new asset")
    }
}
