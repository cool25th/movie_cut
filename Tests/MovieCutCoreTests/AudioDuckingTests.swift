import Foundation
import Testing
@testable import MovieCutCore

/// F-14 range-based audio ducking: planner math, clip metadata persistence,
/// and the single-undo command that writes ducking onto target clips.
@Suite("Audio Ducking")
struct AudioDuckingTests {
    // MARK: - Planner

    @Test("voice intervals are the complement of silence within the speech range")
    func voiceIntervalsComplementSilence() {
        let speech = TimeRange(start: 10, duration: 10)
        let silences = [
            TimeRange(start: 12, duration: 2),   // inside
            TimeRange(start: 17, duration: 1),   // inside
            TimeRange(start: 5, duration: 4)     // mostly before; clamped to 10...
        ]

        let voice = AudioDuckingPlanner.voiceIntervals(
            speechTimelineRange: speech,
            silenceRangesInTimeline: silences
        )

        // Expected: silence inside speech = [9..10→clamped none? 5+4=9 ends at 9 → outside],
        // so voiced: 10-12, 14-17, 18-20.
        #expect(voice.count == 3)
        #expect(abs(voice[0].start - 10) < 0.001 && abs(voice[0].end - 12) < 0.001)
        #expect(abs(voice[1].start - 14) < 0.001 && abs(voice[1].end - 17) < 0.001)
        #expect(abs(voice[2].start - 18) < 0.001 && abs(voice[2].end - 20) < 0.001)
    }

    @Test("fully silent speech yields no voice intervals")
    func fullySilentSpeech() {
        let speech = TimeRange(start: 0, duration: 5)
        let voice = AudioDuckingPlanner.voiceIntervals(
            speechTimelineRange: speech,
            silenceRangesInTimeline: [TimeRange(start: 0, duration: 5)]
        )
        #expect(voice.isEmpty)
    }

    @Test("short voice blips below the minimum duration are dropped")
    func shortVoiceDropped() {
        let speech = TimeRange(start: 0, duration: 2)
        let voice = AudioDuckingPlanner.voiceIntervals(
            speechTimelineRange: speech,
            silenceRangesInTimeline: [
                TimeRange(start: 0.1, duration: 0.85),
                TimeRange(start: 1.0, duration: 1.0)
            ],
            minimumDuration: 0.2
        )
        // Gaps: 0-0.1 (too short), 0.95-1.0 (too short) → nothing.
        #expect(voice.isEmpty)
    }

    @Test("ducking ranges are padded, merged, clipped, and clip-local")
    func duckingRangesArePaddedAndLocal() {
        let target = TimeRange(start: 5, duration: 10)   // BGM 5..15
        let voice = [
            TimeRange(start: 6, duration: 1),            // pads to 5.85..7.15
            TimeRange(start: 7.2, duration: 1),          // pads to 7.05..8.35 → merges with prior
            TimeRange(start: 14.5, duration: 2)          // pads to 14.35..16.65 → clipped at 15
        ]

        let ranges = AudioDuckingPlanner.duckingRanges(
            forTarget: target,
            voiceIntervals: voice,
            padding: 0.15
        )

        #expect(ranges.count == 2)
        #expect(abs(ranges[0].start - 0.85) < 0.001)     // 5.85 - 5
        #expect(abs(ranges[0].end - 3.35) < 0.001)       // 8.35 - 5
        #expect(abs(ranges[1].start - 9.35) < 0.001)     // 14.35 - 5
        #expect(abs(ranges[1].end - 10.0) < 0.001)       // clipped to target end
    }

    @Test("non-overlapping target produces no ducking ranges")
    func nonOverlappingTarget() {
        let ranges = AudioDuckingPlanner.duckingRanges(
            forTarget: TimeRange(start: 100, duration: 5),
            voiceIntervals: [TimeRange(start: 0, duration: 10)]
        )
        #expect(ranges.isEmpty)
    }

    @Test("merge combines touching and overlapping ranges")
    func mergeOverlapping() {
        let merged = AudioDuckingPlanner.mergeOverlapping([
            TimeRange(start: 3, duration: 2),
            TimeRange(start: 0, duration: 1),
            TimeRange(start: 1, duration: 1),
            TimeRange(start: 4.5, duration: 1)
        ])
        #expect(merged.count == 2)
        #expect(abs(merged[0].start - 0) < 0.001 && abs(merged[0].end - 2) < 0.001)
        #expect(abs(merged[1].start - 3) < 0.001 && abs(merged[1].end - 5.5) < 0.001)
    }

    // MARK: - Model persistence

    @Test("legacy clip JSON decodes with empty ducking metadata")
    func legacyClipDecodesEmptyDucking() throws {
        let clip = Clip(
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 5),
            timelineRange: TimeRange(start: 0, duration: 5)
        )
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(clip)) as! [String: Any]
        json.removeValue(forKey: "duckingRanges")
        json.removeValue(forKey: "duckingLevel")
        let decoded = try JSONDecoder().decode(Clip.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(decoded.duckingRanges.isEmpty)
        #expect(decoded.duckingLevel == nil)
    }

    @Test("ducking metadata round-trips through clip encoding")
    func duckingRoundTrips() throws {
        var clip = Clip(
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 8),
            timelineRange: TimeRange(start: 2, duration: 8)
        )
        clip.duckingRanges = [TimeRange(start: 1, duration: 2), TimeRange(start: 5, duration: 1.5)]
        clip.duckingLevel = 0.25

        let decoded = try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(clip))
        #expect(decoded.duckingRanges == clip.duckingRanges)
        #expect(decoded.duckingLevel == 0.25)
    }

    // MARK: - Command

    @Test("set ducking command writes ranges and undo restores them")
    func commandWritesAndUndoes() async throws {
        var project = Project(name: "Ducking")
        let bgm = Clip(
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 20),
            timelineRange: TimeRange(start: 0, duration: 20)
        )
        var track = Track(kind: .audio, name: "Audio 1")
        track.clips = [bgm]
        project.timeline.tracks = [track]

        let session = EditorSession(project: project)
        try await session.dispatch(SetAudioDuckingCommand(
            duckingRangesByClip: [bgm.id: [TimeRange(start: 3, duration: 4)]],
            level: 0.25
        ))

        var snapshot = await session.snapshot()
        var stored = snapshot.timeline.tracks[0].clips[0]
        #expect(stored.duckingRanges == [TimeRange(start: 3, duration: 4)])
        #expect(stored.duckingLevel == 0.25)

        try await session.undo()
        snapshot = await session.snapshot()
        stored = snapshot.timeline.tracks[0].clips[0]
        #expect(stored.duckingRanges.isEmpty)
        #expect(stored.duckingLevel == nil)
    }

    @Test("nil level clears existing ducking")
    func clearAndInvert() throws {
        var project = Project(name: "Clear")
        var bgm = Clip(
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 10),
            timelineRange: TimeRange(start: 0, duration: 10)
        )
        bgm.duckingRanges = [TimeRange(start: 1, duration: 2)]
        bgm.duckingLevel = 0.3
        var track = Track(kind: .audio, name: "Audio 1")
        track.clips = [bgm]
        project.timeline.tracks = [track]

        let clear = SetAudioDuckingCommand(duckingRangesByClip: [bgm.id: []], level: nil)
        try clear.apply(to: &project)
        #expect(project.timeline.tracks[0].clips[0].duckingRanges.isEmpty)
        #expect(project.timeline.tracks[0].clips[0].duckingLevel == nil)
    }

    @Test("out-of-range level is rejected")
    func invalidLevelRejected() {
        var project = Project(name: "Invalid")
        #expect(throws: (any Error).self) {
            _ = try SetAudioDuckingCommand(duckingRangesByClip: [:], level: 1.5)
                .apply(to: &project)
        }
    }
}

/// Wiring visibility for the engine ramp paths (not a completion criterion by
/// itself — see spec DoD §1.3).
@Suite("Audio Ducking Static Contract")
struct AudioDuckingStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("both mac engines apply identical ducking ramps")
    func enginesApplyDuckingRamps() throws {
        for path in [
            "App/MovieCutMac/Export/ExportEngine.swift",
            "App/MovieCutMac/Playback/PlaybackEngine.swift"
        ] {
            let engine = try source(path)
            #expect(engine.contains("func applyDuckingRamps"), Comment(rawValue: path))
            #expect(engine.contains("AudioDuckingPlanner.attackDuration"), Comment(rawValue: path))
            #expect(engine.contains("AudioDuckingPlanner.mergeOverlapping(clip.duckingRanges)"), Comment(rawValue: path))
            #expect(engine.contains("applyDuckingRamps(\n                for: clip,"), Comment(rawValue: path))
        }
    }

    @Test("view model orchestrates silence analysis into ducking command")
    func viewModelOrchestratesDucking() throws {
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
        #expect(viewModel.contains("func autoDuckOtherAudio"))
        #expect(viewModel.contains("AudioDuckingPlanner.voiceIntervals"))
        #expect(viewModel.contains("AudioDuckingPlanner.duckingRanges"))
        #expect(viewModel.contains("SetAudioDuckingCommand"))
        #expect(viewModel.contains("func clearDuckingOnSelectedClip"))
    }

    @Test("inspector exposes duck and clear controls")
    func inspectorExposesDucking() throws {
        let inspector = try source("App/MovieCutMac/Inspector/InspectorBasicSection.swift")
        #expect(inspector.contains("Duck Other Audio"))
        #expect(inspector.contains("Clear Ducking"))
        #expect(inspector.contains("autoDuckOtherAudio"))
    }
}
