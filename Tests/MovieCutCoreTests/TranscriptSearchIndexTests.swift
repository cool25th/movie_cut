import Foundation
import Testing
@testable import MovieCutCore

/// N1-A: transcript phrase search — the corpus contract (cross-card
/// phrases), word-level time resolution, normalization, and the match cap.
@Suite("Transcript search index (N1-A)")
struct TranscriptSearchIndexTests {

    private func word(_ text: String, _ start: Double, _ end: Double) -> WordTiming {
        WordTiming(text: text, startTime: start, endTime: end, confidence: 1)
    }

    @Test("A phrase spanning two subtitle cards matches with the first card's word time")
    func crossCardPhraseMatch() {
        let cardOne = UUID()
        let cardTwo = UUID()
        // Card 1 ends mid-sentence; the phrase continues into card 2 — the
        // concatenated corpus must still find it.
        let items = [
            TranscriptSearchIndex.Item(
                clipId: cardOne, text: "and that is exactly why we",
                timelineStart: 10,
                words: [
                    word("and", 0.0, 0.2), word("that", 0.2, 0.4), word("is", 0.4, 0.5),
                    word("exactly", 0.5, 0.9), word("why", 0.9, 1.1), word("we", 1.1, 1.3),
                ]
            ),
            TranscriptSearchIndex.Item(
                clipId: cardTwo, text: "shipped it early",
                timelineStart: 14,
                words: [
                    word("shipped", 0.0, 0.4), word("it", 0.4, 0.6), word("early", 0.6, 1.0),
                ]
            ),
        ]

        let matches = TranscriptSearchIndex.matches(for: "exactly why we shipped", in: items)
        #expect(matches.count == 1)
        // "exactly" is word index 3 of card 1: 10 + 0.5 = 10.5.
        #expect(matches[0].time == 10.5, "expected the FIRST WORD's timeline second, got \(matches[0].time)")
        #expect(matches[0].clipId == cardOne)
        #expect(matches[0].excerpt.contains("exactly why we shipped"))
    }

    @Test("Matching is case-insensitive and collapses whitespace and newlines")
    func normalization() {
        let items = [
            TranscriptSearchIndex.Item(
                clipId: UUID(),
                text: "The   QUICK\nbrown fox",
                timelineStart: 3,
                words: [
                    word("The", 0.0, 0.2), word("QUICK", 0.2, 0.6),
                    word("brown", 0.6, 0.9), word("fox", 0.9, 1.2),
                ]
            ),
        ]
        let matches = TranscriptSearchIndex.matches(for: "quick   brown", in: items)
        #expect(matches.count == 1)
        #expect(abs(matches[0].time - 3.2) < 0.0001)
    }

    @Test("Cards without word timings resolve to the card start")
    func noWordTimingsFallback() {
        let items = [
            TranscriptSearchIndex.Item(clipId: UUID(), text: "no timings here", timelineStart: 7.5),
        ]
        let matches = TranscriptSearchIndex.matches(for: "timings here", in: items)
        #expect(matches.count == 1)
        #expect(matches[0].time == 7.5)
    }

    @Test("A word-boundary mismatch never hits: 'the' does not match 'there'")
    func wordBoundariesHold() {
        let items = [
            TranscriptSearchIndex.Item(clipId: UUID(), text: "there is nothing else", timelineStart: 0),
        ]
        #expect(TranscriptSearchIndex.matches(for: "the", in: items).isEmpty)
        #expect(TranscriptSearchIndex.matches(for: "there is", in: items).count == 1)
    }

    @Test("Empty and whitespace-only queries match nothing by contract")
    func emptyQueries() {
        let items = [
            TranscriptSearchIndex.Item(clipId: UUID(), text: "anything", timelineStart: 0),
        ]
        #expect(TranscriptSearchIndex.matches(for: "", in: items).isEmpty)
        #expect(TranscriptSearchIndex.matches(for: "   ", in: items).isEmpty)
    }

    @Test("Repeated hits are capped and reported in corpus (timeline) order")
    func capAndOrder() {
        var items: [TranscriptSearchIndex.Item] = []
        for index in 0..<80 {
            items.append(TranscriptSearchIndex.Item(
                clipId: UUID(),
                text: "again and again",
                timelineStart: Double(index)
            ))
        }
        let matches = TranscriptSearchIndex.matches(for: "again", in: items)
        #expect(matches.count == TranscriptSearchIndex.matchLimit)
        #expect(matches.map(\.time) == matches.map(\.time).sorted())
    }
}
