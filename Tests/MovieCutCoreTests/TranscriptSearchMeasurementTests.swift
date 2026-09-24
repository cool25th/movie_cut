import Foundation
import Testing
@testable import MovieCutCore

/// N1 measurement — the machine axes of transcript-based editing,
/// pre-registered before measurement (2026-09-22):
///
///   T1 search latency  — a 30-minute timeline (900 two-second subtitle
///                        cards, word-timed) must answer a phrase query with
///                        p95 ≤ 50 ms over 200 queries against a BUILT
///                        corpus (the CA-20 timeline-index budget for
///                        30-minute projects). First run FAILED at
///                        180.6 ms p95: the one-shot API rebuilt the corpus
///                        per query. The fix — build-once `Corpus` + a
///                        timeline-keyed VM cache — is measured here.
///   T1b corpus build    — one corpus build over the same 30-minute
///                         timeline ≤ 250 ms (pre-registered at fix time,
///                         before the fixed measurement ran; this is the
///                         per-timeline-mutation cost, not per keystroke).
///   T2 jump accuracy   — for 100 sampled words, the match's timeline second
///                        must equal the word's true timeline second within
///                        ±10 ms. Threshold ≥ 95% (expected 100% — the
///                        threshold guards regressions in the span math).
///   T3 undo round-trip — held by the N1-B Mac behavior tests (one undo
///                       restores the exact timeline; cited, not remeasured).
///
/// The DoD's "rough-cut time −30% vs manual timeline editing" is a HUMAN
/// time metric: it needs real editors and is explicitly deferred to the
/// beta workflow measurement (docs/N1_MEASUREMENT_20260922.md records this
/// transfer). Only machine axes are claimed here — no modeled proxy is
/// reported as a measurement.
@Suite("Transcript search measurement (N1)")
struct TranscriptSearchMeasurementTests {

    /// 900 word-timed cards over 30 minutes (2 s each), deterministic.
    private func thirtyMinuteItems() -> [TranscriptSearchIndex.Item] {
        (0..<900).map { index in
            let cardStart = Double(index) * 2.0
            let words: [WordTiming] = (0..<6).map { wordIndex in
                WordTiming(
                    text: Self.wordText(card: index, word: wordIndex),
                    startTime: Double(wordIndex) * 0.25,
                    endTime: Double(wordIndex) * 0.25 + 0.2,
                    confidence: 1
                )
            }
            return TranscriptSearchIndex.Item(
                clipId: UUID(),
                text: (0..<6).map { Self.wordText(card: index, word: $0) }.joined(separator: " "),
                timelineStart: cardStart,
                words: words
            )
        }
    }

    /// Deterministic pseudo-words so sampled queries are reproducible.
    private static func wordText(card: Int, word: Int) -> String {
        "w\(card)x\(word)"
    }

    @Test("T1b: one corpus build over the 30-minute timeline ≤ 250 ms")
    func corpusBuildLatency() throws {
        let items = thirtyMinuteItems()
        let clock = ContinuousClock()

        // Min-of-3, adopted 2026-09-24 with evidence: the single-shot wall
        // clock passed standalone (195 ms) but failed twice inside the full
        // 1,515-test parallel run (349 ms) — co-scheduled suites inflate
        // wall time ~1.8x while the budget's headroom is only 1.28x. The
        // threshold's meaning is "the machine is capable of building the
        // 30-minute corpus within 250 ms"; min-of-N measures capability and
        // still catches real regressions (which raise every iteration).
        func ms(_ e: ContinuousClock.Duration) -> Double {
            (Double(e.components.seconds) + Double(e.components.attoseconds) / 1e18) * 1000
        }
        // Two warmup builds first: removes one-shot allocation/JIT cost from
        // the samples so min-of-3 measures steady-state capability (2026-09-24).
        _ = TranscriptSearchIndex.Corpus(items: items)
        _ = TranscriptSearchIndex.Corpus(items: items)
        let samples = (0..<3).map { _ in
            ms(clock.measure { _ = TranscriptSearchIndex.Corpus(items: items) })
        }
        let best = samples.min() ?? .infinity
        #expect(best <= 250.0, "corpus build best-of-3 \(samples) ms — min \(best) ms exceeded the 250 ms budget")
    }

    @Test("T1: phrase search p95 ≤ 50 ms on a built 30-minute corpus (200 queries)")
    func searchLatencyP95() throws {
        let corpus = TranscriptSearchIndex.Corpus(items: thirtyMinuteItems())
        let clock = ContinuousClock()

        // 200 reproducible queries: half hit existing phrases spread over
        // the timeline, half miss entirely (both paths cost corpus time).
        var samples: [Double] = []
        for queryIndex in 0..<200 {
            let query: String
            if queryIndex % 2 == 0 {
                let card = (queryIndex / 2) * 9 % 900
                query = "w\(card)x2 w\(card)x3"
            } else {
                query = "miss\(queryIndex) nothing"
            }
            let elapsed = clock.measure {
                _ = corpus.matches(for: query)
            }
            samples.append(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
        }

        let sorted = samples.sorted()
        let p95Index = min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.down)))
        let p95 = sorted[p95Index] * 1000  // ms
        #expect(p95 <= 50.0, "search p95 \(p95) ms exceeded the 50 ms budget")
    }

    @Test("T2: jump accuracy ≥ 95% of sampled words resolve within ±10 ms")
    func jumpAccuracy() throws {
        let corpus = TranscriptSearchIndex.Corpus(items: thirtyMinuteItems())

        var withinTolerance = 0
        let sampleCount = 100
        for sample in 0..<sampleCount {
            let card = sample * 9 % 900
            let word = sample % 6
            let expectedTime = Double(card) * 2.0 + Double(word) * 0.25

            let matches = corpus.matches(for: Self.wordText(card: card, word: word))
            guard let first = matches.first else {
                continue  // counted as inaccurate below
            }
            if abs(first.time - expectedTime) <= 0.010 {
                withinTolerance += 1
            }
        }
        let accuracy = Double(withinTolerance) / Double(sampleCount)
        #expect(accuracy >= 0.95, "jump accuracy \(accuracy) below the 95% threshold")
        // Stronger deterministic expectation: with word-timed cards the
        // resolution is exact — failures here mean span-math regressions.
        #expect(accuracy == 1.0, "word-timed cards should resolve exactly; got \(accuracy)")
    }
}
