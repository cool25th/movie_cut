import AVFoundation
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutiOS

/// CA-31(a): iOS audio preset action surface (Mac inspector parity). The
/// render paths already consume clip EQ (`eqDerivations`) and ducking
/// metadata (placed-span ducking) — these tests lock the missing piece:
/// the user-facing actions persist through the same command path the Mac
/// inspector uses, one undo step each.
@MainActor
@Suite("iOS audio presets (CA-31)")
struct IOSAudioPresetTests {

    private static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MovieCutiOSTests
        .deletingLastPathComponent()  // App
        .deletingLastPathComponent()  // repo root

    private func fixture(_ name: String) -> URL {
        Self.repoRoot.appendingPathComponent("Tests/Fixtures/\(name)")
    }

    private func tempAutosaveDir(_ label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ca31-\(label)-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("Voice Enhance preset persists on the clip and one undo restores flat")
    func eqPresetAppliesAndUndoes() async throws {
        let wav = fixture("duck_voice_1000hz_1s_mono.wav")
        #expect(FileManager.default.fileExists(atPath: wav.path), "missing duck voice fixture")

        let vm = IOSEditorViewModel(autosaveDirectory: tempAutosaveDir("eq"))
        let asset = MediaImporter.probe(url: wav)
        await vm.importMedia(from: wav, kind: .audio)
        await vm.addClipToTimeline(asset: asset)
        let clip = try #require(
            vm.currentProject.timeline.tracks.flatMap(\.clips).first { $0.assetId == asset.id }
        )
        vm.selectedClipId = clip.id

        await vm.applyAudioEQPreset(.voiceEnhance)
        let after = try #require(
            vm.currentProject.timeline.tracks.flatMap(\.clips).first { $0.id == clip.id }
        )
        #expect(after.equalizer == ClipEqualizerSettings.settings(for: .voiceEnhance))
        #expect(vm.lastErrorMessage == nil)

        // One undo restores the pre-preset state (no equalizer settings).
        await vm.undo()
        let undone = try #require(
            vm.currentProject.timeline.tracks.flatMap(\.clips).first { $0.id == clip.id }
        )
        #expect(undone.equalizer == nil)

        // Flat explicitly clears (nil) without an error.
        await vm.applyAudioEQPreset(.voiceEnhance)
        await vm.applyAudioEQPreset(.flat)
        let cleared = try #require(
            vm.currentProject.timeline.tracks.flatMap(\.clips).first { $0.id == clip.id }
        )
        #expect(cleared.equalizer == nil)
        #expect(vm.lastErrorMessage == nil)
    }

    @Test("Duck Background ducks an overlapping music clip under the selected speech clip")
    func duckBackgroundUnderSpeech() async throws {
        let voiceURL = fixture("duck_voice_1000hz_1s_mono.wav")
        let bgmURL = fixture("duck_bgm_220hz_4s_mono.wav")
        #expect(FileManager.default.fileExists(atPath: voiceURL.path), "missing voice fixture")
        #expect(FileManager.default.fileExists(atPath: bgmURL.path), "missing bgm fixture")

        let vm = IOSEditorViewModel(autosaveDirectory: tempAutosaveDir("duck"))
        let voice = MediaImporter.probe(url: voiceURL)
        let bgm = MediaImporter.probe(url: bgmURL)
        await vm.importMedia(from: voiceURL, kind: .audio)
        await vm.importMedia(from: bgmURL, kind: .audio)
        await vm.addClipToTimeline(asset: bgm)
        await vm.addClipToTimeline(asset: voice)

        func clipInProject(_ id: UUID) throws -> Clip {
            try #require(
                vm.currentProject.timeline.tracks.flatMap(\.clips).first { $0.id == id }
            )
        }
        let voiceClip = try #require(
            vm.currentProject.timeline.tracks.flatMap(\.clips).first { $0.assetId == voice.id }
        )
        let bgmClip = try #require(
            vm.currentProject.timeline.tracks.flatMap(\.clips).first { $0.assetId == bgm.id }
        )
        // addClipToTimeline places clips sequentially (bgm [0,4], voice
        // [4,5]); ducking is an overlap effect, so move the speech clip to
        // the start like the Mac overlay workflow does.
        await vm.moveClip(clipId: voiceClip.id, newStart: 0)
        let movedVoice = try #require(
            vm.currentProject.timeline.tracks.flatMap(\.clips).first { $0.id == voiceClip.id }
        )
        #expect(movedVoice.timelineRange.overlaps(
            vm.currentProject.timeline.tracks.flatMap(\.clips).first { $0.id == bgmClip.id }!.timelineRange
        ))
        vm.selectedClipId = voiceClip.id
        #expect(vm.canDuckBackground)

        await vm.duckBackgroundUnderSelectedClip()

        let ducked = try clipInProject(bgmClip.id)
        #expect(vm.lastErrorMessage == nil, "ducking failed: \(vm.lastErrorMessage ?? "?")")
        #expect(!ducked.duckingRanges.isEmpty,
                "expected ducking ranges on the overlapping music clip")
        #expect(ducked.duckingLevel == AudioDuckingPlanner.defaultDuckingLevel)
        // The speech clip itself is never ducked under itself.
        let speech = try clipInProject(voiceClip.id)
        #expect(speech.duckingRanges.isEmpty)

        // One undo clears the ducking metadata.
        await vm.undo()
        let restored = try clipInProject(bgmClip.id)
        #expect(restored.duckingRanges.isEmpty)
        #expect(restored.duckingLevel == nil)
    }

    @Test("Duck Background without a selection reports an explicit error, not silence")
    func duckWithoutSelectionReportsError() async throws {
        let vm = IOSEditorViewModel(autosaveDirectory: tempAutosaveDir("nosel"))
        #expect(!vm.canDuckBackground)
        await vm.duckBackgroundUnderSelectedClip()
        #expect(vm.lastErrorMessage != nil)
        #expect(vm.currentProject.timeline.tracks.flatMap(\.clips).isEmpty)
    }
}
