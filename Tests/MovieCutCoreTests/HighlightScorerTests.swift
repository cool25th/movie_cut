import Foundation
import Testing
@testable import MovieCutCore

/// F-20 auto highlights: scoring math that combines silence, scene, and beat
/// provider outputs into ranked non-overlapping candidates.
@Suite("Highlight Scorer")
struct HighlightScorerTests {
    @Test("returns the requested number of non-overlapping candidates (AC)")
    func returnsNonOverlappingCandidates() {
        // 30-minute timeline with three lively islands separated by silence.
        let duration: TimeInterval = 1800
        var silence: [TimeRange] = [TimeRange(start: 0, duration: duration)]

        // Carve out speech (remove silence) in three windows.
        func speak(_ start: TimeInterval, _ length: TimeInterval) {
            silence = subtract(TimeRange(start: start, duration: length), from: silence)
        }
        speak(100, 40)
        speak(800, 40)
        speak(1500, 40)

        let scenes = [110.0, 120, 130, 810, 820, 830, 1510, 1520, 1530]
        let beats = Array(stride(from: 100.0, to: 140, by: 0.5))
            + Array(stride(from: 800.0, to: 840, by: 0.5))
            + Array(stride(from: 1500.0, to: 1540, by: 0.5))

        let candidates = HighlightScorer.scoreHighlights(
            duration: duration,
            silenceRanges: silence,
            sceneChangeTimes: scenes,
            energyMarkers: beats,
            configuration: .init(minWindow: 15, maxWindow: 30, windowStride: 5, candidateCount: 3)
        )

        #expect(candidates.count == 3)
        // Non-overlapping.
        for i in candidates.indices.dropLast() {
            #expect(candidates[i].range.end <= candidates[i + 1].range.start + 0.001)
        }
        // Each candidate length within the configured window bounds.
        for candidate in candidates {
            #expect(candidate.range.duration >= 15 - 0.001)
            #expect(candidate.range.duration <= 30 + 0.001)
        }
        // Candidates should land near the lively islands, not the dead air.
        #expect(candidates.contains { $0.range.start >= 95 && $0.range.start <= 145 })
        #expect(candidates.contains { $0.range.start >= 795 && $0.range.start <= 845 })
    }

    @Test("speech-dense windows outscore silent windows")
    func speechBeatsSilence() {
        let duration: TimeInterval = 120
        // Silence covers the first half only.
        let silence = [TimeRange(start: 0, duration: 60)]

        let candidates = HighlightScorer.scoreHighlights(
            duration: duration,
            silenceRanges: silence,
            sceneChangeTimes: [],
            energyMarkers: [],
            configuration: .init(minWindow: 20, maxWindow: 20, windowStride: 10, candidateCount: 1)
        )

        let best = try! #require(candidates.first)
        // The best window should sit in the speech half (second half).
        #expect(best.range.start >= 55)
        #expect(best.speechDensity > 0.9)
    }

    @Test("scene activity and energy raise the score")
    func sceneAndEnergyContribute() {
        let duration: TimeInterval = 60
        let plain = HighlightScorer.scoreHighlights(
            duration: duration,
            silenceRanges: [],
            sceneChangeTimes: [],
            energyMarkers: [],
            configuration: .init(minWindow: 20, maxWindow: 20, windowStride: 20, candidateCount: 1)
        ).first!

        let lively = HighlightScorer.scoreHighlights(
            duration: duration,
            silenceRanges: [],
            sceneChangeTimes: [5, 10, 15],
            energyMarkers: Array(stride(from: 0.0, to: 20, by: 0.5)),
            configuration: .init(minWindow: 20, maxWindow: 20, windowStride: 20, candidateCount: 1)
        ).first!

        #expect(lively.score > plain.score)
        #expect(lively.sceneActivity > 0)
        #expect(lively.energy > 0)
    }

    @Test("zero or sub-window duration yields no candidates")
    func tooShort() {
        #expect(HighlightScorer.scoreHighlights(
            duration: 0,
            silenceRanges: [],
            sceneChangeTimes: [],
            energyMarkers: []
        ).isEmpty)

        // Duration shorter than 1s window floor.
        #expect(HighlightScorer.scoreHighlights(
            duration: 0.5,
            silenceRanges: [],
            sceneChangeTimes: [],
            energyMarkers: []
        ).isEmpty)
    }

    @Test("candidate window lengths clamp to the available duration")
    func windowLengthsClamp() {
        let lengths = HighlightScorer.candidateWindowLengths(
            duration: 25,
            configuration: .init(minWindow: 15, maxWindow: 60)
        )
        #expect(lengths.allSatisfy { $0 <= 25 })
        #expect(lengths.contains { $0 <= 15 })
    }

    @Test("scores are normalized to 0...1")
    func scoresNormalized() {
        let candidates = HighlightScorer.scoreHighlights(
            duration: 200,
            silenceRanges: [],
            sceneChangeTimes: Array(stride(from: 0.0, to: 200, by: 1)),
            energyMarkers: Array(stride(from: 0.0, to: 200, by: 0.1)),
            configuration: .init(candidateCount: 3)
        )
        for candidate in candidates {
            #expect(candidate.score >= 0 && candidate.score <= 1.0001)
        }
    }

    // MARK: - Helpers

    private func subtract(_ remove: TimeRange, from ranges: [TimeRange]) -> [TimeRange] {
        var result: [TimeRange] = []
        for range in ranges {
            let overlapStart = max(range.start, remove.start)
            let overlapEnd = min(range.end, remove.end)
            if overlapEnd <= overlapStart {
                result.append(range)
                continue
            }
            if overlapStart > range.start {
                result.append(TimeRange(start: range.start, duration: overlapStart - range.start))
            }
            if overlapEnd < range.end {
                result.append(TimeRange(start: overlapEnd, duration: range.end - overlapEnd))
            }
        }
        return result
    }
}

/// Wiring visibility for the highlights UI (not a completion criterion by
/// itself — see spec DoD §1.3).
@Suite("Highlights Static Contract")
struct HighlightsStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("view model scores and creates a sequence from a highlight")
    func viewModelOrchestrates() throws {
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
        #expect(viewModel.contains("func detectHighlights"))
        #expect(viewModel.contains("HighlightScorer.scoreHighlights"))
        #expect(viewModel.contains("func createSequenceFromHighlight"))
        // Auto Highlights routes through the command path so undo survives: it
        // dispatches ReplaceProjectCommand instead of replacing the session,
        // which previously destroyed the undo stack.
        #expect(viewModel.contains("ReplaceProjectCommand"))
        #expect(!viewModel.contains("session = EditorSession(project: newProject)"))
    }

    @Test("inspector exposes the highlights section")
    func inspectorExposesSection() throws {
        let inspector = try source("App/MovieCutMac/InspectorPanel.swift")
        #expect(inspector.contains("HighlightsSection"))
        #expect(inspector.contains("Find Highlights"))
        #expect(inspector.contains("createSequenceFromHighlight"))
    }
}
