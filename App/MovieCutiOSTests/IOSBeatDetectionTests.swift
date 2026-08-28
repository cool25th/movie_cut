import AVFoundation
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutiOS

/// CA-14: beat detection on iOS (Mac `detectBeats` parity) — the real
/// command-path behavior: import a click track, select it, detect beats
/// through `BeatDetectionProvider.analyze(asset:)` + `AddMarkersCommand`,
/// then clear them in one undoable step.
@MainActor
@Suite("iOS beat detection (CA-14)")
struct IOSBeatDetectionTests {
    /// Writes a deterministic click track (440 Hz bursts at a fixed BPM over
    /// silence) as a real WAV so the provider's AVAssetReader decode path runs
    /// exactly as it does for user-imported music.
    private func clickTrackWAV(bpm: Double = 120, beats: Int = 8) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ca14-click-\(UUID().uuidString).wav")

        let sampleRate = 22_050.0
        let interval = 60.0 / bpm
        let totalDuration = interval * Double(beats) + 1.0
        let totalSamples = AVAudioFrameCount(totalDuration * sampleRate)

        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate, channels: 1
        )!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalSamples)!
        buffer.frameLength = totalSamples
        let channel = buffer.floatChannelData![0]

        let clickDuration = 0.03
        for beat in 0..<beats {
            let start = Int((Double(beat) * interval + 0.5) * sampleRate)
            let end = min(Int(totalSamples), start + Int(clickDuration * sampleRate))
            for index in start..<end {
                let t = Double(index - start) / sampleRate
                channel[index] = Float(sin(2 * .pi * 440 * t))
            }
        }
        try file.write(from: buffer)
        return url
    }

    @Test("detect beats on an imported click track adds beat markers, clear removes them")
    func detectAndClear() async throws {
        let wav = try clickTrackWAV()
        defer { try? FileManager.default.removeItem(at: wav) }

        let vm = IOSEditorViewModel(
            autosaveDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("ca14-autosave-\(UUID().uuidString)", isDirectory: true)
        )

        // Selection gating: a fresh VM with no timeline has no selection, so
        // detection is unavailable (addClipToTimeline auto-selects afterwards).
        #expect(!vm.canDetectBeats)

        let asset = MediaImporter.probe(url: wav)
        await vm.importMedia(from: wav, kind: .audio)
        await vm.addClipToTimeline(asset: asset)
        let clip = try #require(
            vm.currentProject.timeline.tracks.flatMap(\.clips).first { $0.assetId == asset.id }
        )
        vm.selectedClipId = clip.id
        #expect(vm.canDetectBeats)

        await vm.detectBeats()

        let beatMarkers = vm.currentProject.markers.filter { $0.kind == .beat }
        #expect(beatMarkers.count >= 6, "expected the 8-click track to yield beats, got \(beatMarkers.count)")
        #expect(vm.hasBeatMarkers)
        #expect(vm.lastErrorMessage == nil)

        // Timeline mapping: every marker must sit inside the clip's span.
        for marker in beatMarkers {
            #expect(marker.time >= clip.timelineRange.start - 0.001)
            #expect(marker.time <= clip.timelineRange.end + 0.001)
        }

        await vm.clearBeatMarkers()
        #expect(!vm.hasBeatMarkers)
        #expect(vm.currentProject.markers.filter { $0.kind == .beat }.isEmpty)
    }

    @Test("detect beats without a selection reports an explicit error, not silence")
    func noSelectionReportsError() async throws {
        let vm = IOSEditorViewModel(
            autosaveDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("ca14-autosave-\(UUID().uuidString)", isDirectory: true)
        )
        await vm.detectBeats()
        #expect(vm.lastErrorMessage != nil)
        #expect(vm.currentProject.markers.isEmpty)
    }
}
