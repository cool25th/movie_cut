import Foundation
import Testing
@testable import MovieCutCore

/// F-15 beat detection: pure onset math against synthesized click tracks,
/// marker-kind persistence, and batch marker commands.
@Suite("Beat Detection")
struct BeatDetectionTests {
    /// Builds a mono click track: short bursts at a fixed BPM over silence.
    private func clickTrack(
        bpm: Double,
        beats: Int,
        sampleRate: Double = 22050,
        clickDuration: Double = 0.03
    ) -> [Float] {
        let interval = 60.0 / bpm
        let totalDuration = interval * Double(beats) + 1.0
        var samples = [Float](repeating: 0, count: Int(totalDuration * sampleRate))
        for beat in 0..<beats {
            let start = Int((Double(beat) * interval + 0.5) * sampleRate)
            let end = min(samples.count, start + Int(clickDuration * sampleRate))
            for index in start..<end {
                // 440 Hz burst with full amplitude.
                let t = Double(index - start) / sampleRate
                samples[index] = Float(sin(2 * .pi * 440 * t))
            }
        }
        return samples
    }

    @Test("fixed-BPM click track yields beat intervals within 50ms (AC①)")
    func fixedBPMIntervals() {
        let provider = BeatDetectionProvider()
        let beats = provider.detectBeats(
            monoSamples: clickTrack(bpm: 120, beats: 8),
            sampleRate: 22050
        )

        #expect(beats.count == 8)
        let intervals = zip(beats.dropFirst(), beats).map(-)
        for interval in intervals {
            #expect(abs(interval - 0.5) < 0.05, Comment(rawValue: "interval \(interval)"))
        }
    }

    @Test("slower tempo still resolves the right beat count")
    func slowerTempo() {
        let provider = BeatDetectionProvider()
        let beats = provider.detectBeats(
            monoSamples: clickTrack(bpm: 80, beats: 6),
            sampleRate: 22050
        )
        #expect(beats.count == 6)
    }

    @Test("silence and constant tone produce no beats")
    func noFalsePositives() {
        let provider = BeatDetectionProvider()
        let silence = [Float](repeating: 0, count: 22050 * 3)
        #expect(provider.detectBeats(monoSamples: silence, sampleRate: 22050).isEmpty)

        let tone = (0..<(22050 * 3)).map { Float(sin(2 * .pi * 220 * Double($0) / 22050)) }
        let toneBeats = provider.detectBeats(monoSamples: tone, sampleRate: 22050)
        #expect(toneBeats.count <= 1)
    }

    @Test("minimum beat interval suppresses double triggers")
    func minimumIntervalSuppression() {
        let provider = BeatDetectionProvider(
            configuration: .init(minimumBeatInterval: 0.4)
        )
        // 240 BPM clicks (0.25s apart) with a 0.4s floor → roughly every other click.
        let beats = provider.detectBeats(
            monoSamples: clickTrack(bpm: 240, beats: 8),
            sampleRate: 22050
        )
        let intervals = zip(beats.dropFirst(), beats).map(-)
        for interval in intervals {
            #expect(interval >= 0.4 - 0.001)
        }
    }

    @Test("estimated BPM matches the click track tempo")
    func bpmEstimate() {
        let provider = BeatDetectionProvider()
        let beats = provider.detectBeats(
            monoSamples: clickTrack(bpm: 120, beats: 8),
            sampleRate: 22050
        )
        let bpm = BeatDetectionProvider.estimatedBPM(from: beats)
        #expect(bpm != nil && abs(bpm! - 120) < 8)
    }

    // MARK: - Marker kind persistence

    @Test("legacy marker JSON decodes as standard kind")
    func legacyMarkerDecodesStandard() throws {
        let marker = Marker(time: 3, name: "Legacy")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(marker)) as? [String: Any])
        json.removeValue(forKey: "kind")
        let decoded = try JSONDecoder().decode(Marker.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.kind == .standard)
    }

    @Test("beat marker kind round-trips")
    func beatKindRoundTrips() throws {
        let marker = Marker(time: 1.5, name: "Beat 1", color: "FF9F0A", kind: .beat)
        let decoded = try JSONDecoder().decode(Marker.self, from: JSONEncoder().encode(marker))
        #expect(decoded.kind == .beat)
        #expect(decoded.time == 1.5)
    }

    // MARK: - Batch marker commands

    @Test("batch add is a single undo and clear-by-kind removes only beats")
    func batchAddAndClearByKind() async throws {
        var project = Project(name: "Beats")
        project.markers = [Marker(time: 0, name: "User marker")]
        project.timeline.markers = project.markers

        let session = EditorSession(project: project)
        let beatMarkers = (0..<5).map { index in
            Marker(time: Double(index) * 0.5, name: "Beat \(index + 1)", kind: .beat)
        }
        try await session.dispatch(AddMarkersCommand(markers: beatMarkers))

        var snapshot = await session.snapshot()
        #expect(snapshot.markers.count == 6)
        #expect(snapshot.timeline.markers.count == 6)

        try await session.dispatch(RemoveMarkersCommand(kind: .beat))
        snapshot = await session.snapshot()
        #expect(snapshot.markers.count == 1)
        #expect(snapshot.markers[0].name == "User marker")

        try await session.undo()
        snapshot = await session.snapshot()
        #expect(snapshot.markers.count == 6)

        try await session.undo()
        snapshot = await session.snapshot()
        #expect(snapshot.markers.count == 1)
    }

    @Test("remove command clears the matching markers")
    func removeInvertRestores() throws {
        var project = Project(name: "Invert")
        let beat = Marker(time: 2, name: "Beat 1", kind: .beat)
        project.markers = [beat]
        project.timeline.markers = [beat]

        let remove = RemoveMarkersCommand(kind: .beat)
        try remove.apply(to: &project)
        #expect(project.markers.isEmpty)
    }

    @Test("empty batch add and no-match removal are rejected")
    func invalidBatchesRejected() {
        var project = Project(name: "Empty")
        #expect(throws: (any Error).self) {
            _ = try AddMarkersCommand(markers: []).apply(to: &project)
        }
        #expect(throws: (any Error).self) {
            _ = try RemoveMarkersCommand(kind: .beat).apply(to: &project)
        }
    }
}

/// Wiring visibility for the beat marker UI (not a completion criterion by
/// itself — see spec DoD §1.3).
@Suite("Beat Detection Static Contract")
struct BeatDetectionStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("view model wires detection into batch marker commands")
    func viewModelWiresDetection() throws {
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
        #expect(viewModel.contains("func detectBeats"))
        #expect(viewModel.contains("BeatDetectionProvider"))
        #expect(viewModel.contains("AddMarkersCommand"))
        #expect(viewModel.contains("RemoveMarkersCommand(kind: .beat)"))
        #expect(viewModel.contains("estimatedBPM"))
    }

    @Test("timeline renders beat ticks and keeps beats in snap points")
    func timelineRendersBeatTicks() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        #expect(timeline.contains("marker.kind == .beat"))
        // Snap points are built from sortedMarkers times, which include beats.
        #expect(timeline.contains("sortedMarkers.map(\\.time)"))
    }

    @Test("quick tools expose detect and clear beats")
    func quickToolsExposeBeats() throws {
        let content = try source("App/MovieCutMac/ContentView.swift")
        #expect(content.contains("Detect Beats"))
        #expect(content.contains("Clear Beats"))
        #expect(content.contains("canDetectBeats"))
    }
}
