import Foundation

/// A scored long-form-to-short-form highlight candidate (F-20).
public struct HighlightCandidate: Sendable, Equatable, Identifiable {
    public var id: UUID
    /// The candidate window in timeline seconds.
    public var range: TimeRange
    /// Combined score 0...1.
    public var score: Double
    /// Fraction of the window that contains speech (non-silence).
    public var speechDensity: Double
    /// Normalized visual activity from scene changes.
    public var sceneActivity: Double
    /// Normalized audio energy proxy (e.g. beat density).
    public var energy: Double

    public init(
        id: UUID = UUID(),
        range: TimeRange,
        score: Double,
        speechDensity: Double,
        sceneActivity: Double,
        energy: Double
    ) {
        self.id = id
        self.range = range
        self.score = score
        self.speechDensity = speechDensity
        self.sceneActivity = sceneActivity
        self.energy = energy
    }
}

/// Combines existing analysis-provider outputs (silence, scene changes, and a
/// beat/energy proxy) into ranked highlight candidates. Pure math — no new ML
/// dependency (F-20).
public enum HighlightScorer {
    public struct Configuration: Sendable, Equatable {
        public var minWindow: TimeInterval
        public var maxWindow: TimeInterval
        public var windowStride: TimeInterval
        public var candidateCount: Int
        public var speechWeight: Double
        public var sceneWeight: Double
        public var energyWeight: Double
        /// Scene changes per second that maps to full visual-activity score.
        public var referenceScenesPerSecond: Double
        /// Energy markers per second that maps to full energy score.
        public var referenceEnergyPerSecond: Double

        public init(
            minWindow: TimeInterval = 15,
            maxWindow: TimeInterval = 60,
            windowStride: TimeInterval = 5,
            candidateCount: Int = 3,
            speechWeight: Double = 0.5,
            sceneWeight: Double = 0.25,
            energyWeight: Double = 0.25,
            referenceScenesPerSecond: Double = 0.1,
            referenceEnergyPerSecond: Double = 2.0
        ) {
            self.minWindow = minWindow
            self.maxWindow = maxWindow
            self.windowStride = max(1, windowStride)
            self.candidateCount = max(1, candidateCount)
            self.speechWeight = speechWeight
            self.sceneWeight = sceneWeight
            self.energyWeight = energyWeight
            self.referenceScenesPerSecond = max(.leastNonzeroMagnitude, referenceScenesPerSecond)
            self.referenceEnergyPerSecond = max(.leastNonzeroMagnitude, referenceEnergyPerSecond)
        }
    }

    /// Scores candidate windows and returns the top non-overlapping highlights,
    /// sorted by start time.
    public static func scoreHighlights(
        duration: TimeInterval,
        silenceRanges: [TimeRange],
        sceneChangeTimes: [TimeInterval],
        energyMarkers: [TimeInterval],
        configuration: Configuration = Configuration()
    ) -> [HighlightCandidate] {
        guard duration > 0 else { return [] }

        let windowLengths = candidateWindowLengths(duration: duration, configuration: configuration)
        guard !windowLengths.isEmpty else { return [] }

        let sortedScenes = sceneChangeTimes.filter { $0.isFinite }.sorted()
        let sortedEnergy = energyMarkers.filter { $0.isFinite }.sorted()
        let mergedSilence = mergeRanges(silenceRanges)

        var scored: [HighlightCandidate] = []
        for length in windowLengths {
            var start: TimeInterval = 0
            while start + length <= duration + 0.0001 {
                let window = TimeRange(start: start, duration: length)
                scored.append(makeCandidate(
                    window: window,
                    silence: mergedSilence,
                    scenes: sortedScenes,
                    energy: sortedEnergy,
                    configuration: configuration
                ))
                start += configuration.windowStride
            }
        }

        return pickTopNonOverlapping(scored, count: configuration.candidateCount)
            .sorted { $0.range.start < $1.range.start }
    }

    // MARK: - Internals

    static func candidateWindowLengths(
        duration: TimeInterval,
        configuration: Configuration
    ) -> [TimeInterval] {
        let maxUsable = min(configuration.maxWindow, duration)
        guard maxUsable >= 1 else { return [] }
        let minUsable = min(configuration.minWindow, maxUsable)
        if minUsable == maxUsable {
            return [maxUsable]
        }
        let mid = (minUsable + maxUsable) / 2
        return Array(Set([minUsable, mid, maxUsable])).sorted()
    }

    private static func makeCandidate(
        window: TimeRange,
        silence: [TimeRange],
        scenes: [TimeInterval],
        energy: [TimeInterval],
        configuration: Configuration
    ) -> HighlightCandidate {
        let length = window.duration
        let silentOverlap = silence.reduce(0.0) { $0 + overlapDuration(window, $1) }
        let speechDensity = max(0, min(1, 1 - silentOverlap / length))

        let sceneCount = Double(scenes.filter { $0 >= window.start && $0 < window.end }.count)
        let sceneActivity = min(1, (sceneCount / length) / configuration.referenceScenesPerSecond)

        let energyCount = Double(energy.filter { $0 >= window.start && $0 < window.end }.count)
        let energyScore = min(1, (energyCount / length) / configuration.referenceEnergyPerSecond)

        let totalWeight = configuration.speechWeight + configuration.sceneWeight + configuration.energyWeight
        let score = totalWeight <= 0 ? 0 : (
            configuration.speechWeight * speechDensity
            + configuration.sceneWeight * sceneActivity
            + configuration.energyWeight * energyScore
        ) / totalWeight

        return HighlightCandidate(
            range: window,
            score: score,
            speechDensity: speechDensity,
            sceneActivity: sceneActivity,
            energy: energyScore
        )
    }

    private static func pickTopNonOverlapping(
        _ candidates: [HighlightCandidate],
        count: Int
    ) -> [HighlightCandidate] {
        let ranked = candidates.sorted {
            $0.score == $1.score ? $0.range.start < $1.range.start : $0.score > $1.score
        }

        var picked: [HighlightCandidate] = []
        for candidate in ranked {
            guard picked.count < count else { break }
            let overlaps = picked.contains { overlapDuration($0.range, candidate.range) > 0 }
            if !overlaps {
                picked.append(candidate)
            }
        }
        return picked
    }

    private static func overlapDuration(_ a: TimeRange, _ b: TimeRange) -> TimeInterval {
        max(0, min(a.end, b.end) - max(a.start, b.start))
    }

    private static func mergeRanges(_ ranges: [TimeRange]) -> [TimeRange] {
        let sorted = ranges.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }
        var merged: [TimeRange] = [sorted[0]]
        for range in sorted.dropFirst() {
            let last = merged[merged.count - 1]
            if range.start <= last.end {
                let end = max(last.end, range.end)
                merged[merged.count - 1] = TimeRange(start: last.start, duration: end - last.start)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
