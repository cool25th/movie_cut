import CoreGraphics
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutMac

/// G-26 master-audio freshness behavior tests (P1 review follow-up).
///
/// The picker's serialized mutation worker and the loudness meter's
/// staleness guards were previously pinned only by source-string
/// StaticContract tests. These tests drive the REAL EditorViewModel paths —
/// the synchronous enqueue + single drain worker, real EditorSession
/// dispatches, and the real refresh-time invalidation — so the user-visible
/// contracts are locked as behavior:
///
/// 1. Rapid preset toggles coalesce and the user's LAST selection wins.
/// 2. A mix-affecting commit (preset switch, ducking change) invalidates any
///    existing measurement, so a stale LUFS reading can never present itself
///    as the new mix's loudness.
@MainActor
@Suite("Master audio freshness (G-26)")
struct MasterAudioFreshnessTests {
    private func makeViewModel() -> EditorViewModel {
        EditorViewModel(project: Project(
            name: "freshness",
            mediaLibrary: MediaLibrary(assets: [:]),
            timeline: Timeline(canvasSize: CGSize(width: 100, height: 100), tracks: [])
        ))
    }

    /// Yields the main actor until the serialized mutation worker finishes
    /// (bounded so a stuck worker fails the test instead of hanging it).
    private func awaitMutationDrain(_ vm: EditorViewModel) async {
        for _ in 0..<500 where vm.masterAudioProcessingMutationTask != nil {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        #expect(vm.masterAudioProcessingMutationTask == nil, "mutation worker must settle")
    }

    @Test("rapid preset toggles coalesce and the last selection wins")
    func rapidTogglesLastSelectionWins() async {
        let vm = makeViewModel()
        #expect(vm.currentProject.masterAudioProcessing == nil)

        // Three synchronous picker events before the worker can drain —
        // the UI fires these when a user flips the segmented control fast.
        vm.setMasterAudioProcessing(.sns)
        vm.setMasterAudioProcessing(nil)
        vm.setMasterAudioProcessing(.sns)
        await awaitMutationDrain(vm)

        #expect(vm.currentProject.masterAudioProcessing == .sns)
        #expect(vm.desiredMasterAudioProcessing == .sns)

        // And the opposite terminal state, toggling the other way.
        vm.setMasterAudioProcessing(nil)
        vm.setMasterAudioProcessing(.sns)
        vm.setMasterAudioProcessing(nil)
        await awaitMutationDrain(vm)

        #expect(vm.currentProject.masterAudioProcessing == nil,
                "the user's final OFF selection must be the committed state")
    }

    @Test("a committed preset switch discards the previous measurement")
    func presetSwitchInvalidatesStaleMeasurement() async {
        let vm = makeViewModel()

        // A measurement left from the bypassed mix (seeded the way a
        // finished measureMasterLoudness() would leave it). After the
        // user switches the preset on, that LUFS reading describes a mix
        // that no longer exists and must not survive the commit.
        vm.masterLoudness = AudioGraphLoudness.Measurement(
            integratedLufs: -30, truePeakDbTp: -20, samplePeakDbFs: -18
        )
        vm.setMasterAudioProcessing(.sns)
        await awaitMutationDrain(vm)

        #expect(vm.currentProject.masterAudioProcessing == .sns)
        #expect(vm.masterLoudness == nil,
                "switching the preset must invalidate the old mix's measurement")
    }

    @Test("a mix-affecting clip commit invalidates the measurement")
    func duckingCommitInvalidatesMeasurement() async throws {
        let vm = makeViewModel()
        vm.masterLoudness = AudioGraphLoudness.Measurement(
            integratedLufs: -18, truePeakDbTp: -3, samplePeakDbFs: -2
        )

        // Any measurement-relevant commit (volume/fade/ducking/EQ/mute/solo
        // all route through the same session-refresh invalidation) must
        // clear the reading; ducking is used here as the representative.
        await vm.apply(SetAudioDuckingCommand(
            duckingRangesByClip: [:],
            level: AudioDuckingPlanner.defaultDuckingLevel
        ))

        #expect(vm.masterLoudness == nil,
                "a committed mix change must invalidate the existing loudness measurement")
        #expect(vm.masterLoudnessError == nil)
    }

    @Test("measuring a project with no audio reports the error, and a later commit clears it")
    func noAudioErrorIsReportedThenClearedByCommits() async {
        let vm = makeViewModel()

        await vm.measureMasterLoudness()
        #expect(vm.masterLoudness == nil)
        #expect(vm.masterLoudnessError != nil,
                "the empty project must surface the no-audio error, not silence")

        // The error is measurement state too: after the mix changes it must
        // not linger (the meter re-reads against the new mix).
        await vm.apply(SetAudioDuckingCommand(
            duckingRangesByClip: [:],
            level: AudioDuckingPlanner.defaultDuckingLevel
        ))
        #expect(vm.masterLoudnessError == nil)
    }
}
