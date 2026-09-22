import Foundation

/// N1-A: phrase search over timeline subtitle cards — the "find where this
/// is said" half of transcript-based editing.
///
/// The corpus is the CONCATENATION of all text clips in timeline order, so
/// a spoken phrase split across two subtitle cards still matches. When a
/// card carries word timings (the auto-subtitle karaoke contract), a match
/// resolves to the timeline second of its FIRST WORD, not the card start —
/// long cards jump to the word, not the beginning.
public enum TranscriptSearchIndex {

    /// One searchable subtitle card.
    public struct Item: Sendable, Equatable {
        /// The text clip's identity.
        public let clipId: UUID
        /// The card's full text.
        public let text: String
        /// The card's timeline start second.
        public let timelineStart: TimeInterval
        /// Word timings in CLIP-LOCAL seconds (the storage contract of
        /// `TextClipContent.wordTimings` — `SubtitleGenerator` stores words
        /// shifted by the card start). Nil on cards without word timings.
        public let words: [WordTiming]?

        public init(clipId: UUID, text: String, timelineStart: TimeInterval, words: [WordTiming]? = nil) {
            self.clipId = clipId
            self.text = text
            self.timelineStart = timelineStart
            self.words = words
        }
    }

    /// One phrase hit.
    public struct Match: Equatable, Sendable, Identifiable {
        /// The card containing the first matched word.
        public let clipId: UUID
        /// Timeline second of the first matched word (card start when the
        /// card has no word timings, or the word map failed).
        public let time: TimeInterval
        /// Context window around the match (corpus-normalized text).
        public let excerpt: String
        /// Stable identity for list UIs.
        public var id: String { "\(clipId.uuidString)-\(String(format: "%.3f", time))" }

        public init(clipId: UUID, time: TimeInterval, excerpt: String) {
            self.clipId = clipId
            self.time = time
            self.excerpt = excerpt
        }
    }

    /// Matches are capped so a degenerate query (a single common letter)
    /// cannot flood the index panel.
    public static let matchLimit = 50

    /// A build-once, search-many index over the subtitle cards. Building the
    /// corpus is the expensive part (normalize + span math over every card),
    /// so interactive search surfaces (a search field firing per keystroke)
    /// build once per timeline change and query the same corpus — the
    /// N1 measurement found per-query rebuilds cost ~180 ms p95 on a
    /// 30-minute timeline.
    public struct Corpus: Sendable {
        private let characters: [Character]
        private let cardSpans: [(start: Int, end: Int, item: Item)]
        private let wordSpans: [(start: Int, end: Int, card: Int, word: WordTiming)]

        /// Builds the normalized corpus and span maps from timeline-ordered
        /// items (order is normalized here — callers may pass any order).
        public init(items: [Item]) {
            var corpus = " "
            var cardSpans: [(start: Int, end: Int, item: Item)] = []
            for item in items.sorted(by: { $0.timelineStart < $1.timelineStart }) {
                let itemText = TranscriptSearchIndex.normalize(item.text)
                guard !itemText.isEmpty else { continue }
                // The corpus always ends with a separator space, so the item's
                // text starts AT the current count (index == count, not
                // count - 1 — the pad space owns the last index).
                let start = corpus.count
                corpus += itemText
                cardSpans.append((start: start, end: corpus.count, item: item))
                corpus += " "
            }
            var wordSpans: [(start: Int, end: Int, card: Int, word: WordTiming)] = []
            for (cardIndex, span) in cardSpans.enumerated() {
                guard let words = span.item.words, !words.isEmpty else { continue }
                let tokens = corpus[corpus.index(corpus.startIndex, offsetBy: span.start)..<corpus.index(corpus.startIndex, offsetBy: span.end)]
                    .components(separatedBy: " ")
                guard tokens.count == words.count else { continue }
                var offset = span.start
                for (tokenIndex, token) in tokens.enumerated() {
                    wordSpans.append((offset, offset + token.count, cardIndex, words[tokenIndex]))
                    offset += token.count + 1
                }
            }
            self.characters = Array(corpus)
            self.cardSpans = cardSpans
            self.wordSpans = wordSpans
        }

        /// Case-insensitive, whitespace-collapsed phrase search. An empty
        /// (or whitespace-only) query matches nothing by contract.
        public func matches(for rawQuery: String) -> [TranscriptSearchIndex.Match] {
            let query = TranscriptSearchIndex.normalize(rawQuery)
            guard !query.isEmpty else { return [] }

            var results: [TranscriptSearchIndex.Match] = []
            let padded = Array(" " + query + " ")
            var searchFrom = 0
            while results.count < TranscriptSearchIndex.matchLimit {
                let found = TranscriptSearchIndex.firstRange(of: padded, in: characters, from: searchFrom)
                guard let found else { break }
                let phraseStart = found.lowerBound + 1
                let phraseEnd = found.upperBound - 1
                let resolved = TranscriptSearchIndex.resolve(
                    phraseStart, cardSpans: cardSpans, wordSpans: wordSpans
                )
                results.append(TranscriptSearchIndex.Match(
                    clipId: resolved.item.clipId,
                    time: resolved.time,
                    excerpt: TranscriptSearchIndex.excerpt(
                        around: phraseStart..<phraseEnd, in: characters
                    )
                ))
                searchFrom = found.upperBound
            }
            return results
        }
    }

    /// One-shot convenience over `Corpus` (build + single search).
    public static func matches(for rawQuery: String, in items: [Item]) -> [Match] {
        Corpus(items: items).matches(for: rawQuery)
    }

    // MARK: - Internals

    private static func normalize(_ text: String) -> String {
        let lowered = text.replacingOccurrences(of: "\n", with: " ").lowercased()
        return lowered.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Literal substring search over a character array (the corpus is
    /// already normalized, so no locale or diacritic rules apply).
    private static func firstRange(
        of needle: [Character],
        in haystack: [Character],
        from: Int
    ) -> Range<Int>? {
        guard !needle.isEmpty, haystack.count >= needle.count, from <= haystack.count - needle.count else {
            return nil
        }
        var position = from
        while position <= haystack.count - needle.count {
            if haystack[position] == needle[0] {
                var matched = true
                for offset in 1..<needle.count where haystack[position + offset] != needle[offset] {
                    matched = false
                    break
                }
                if matched { return position..<(position + needle.count) }
            }
            position += 1
        }
        return nil
    }

    /// Resolves a corpus offset to (card, timeline second): the word whose
    /// span contains it when word timings cover the card, otherwise the
    /// owning card's start.
    private static func resolve(
        _ offset: Int,
        cardSpans: [(start: Int, end: Int, item: Item)],
        wordSpans: [(start: Int, end: Int, card: Int, word: WordTiming)]
    ) -> (item: Item, time: TimeInterval) {
        for span in wordSpans where offset >= span.start && offset < span.end {
            let item = cardSpans[span.card].item
            return (item, item.timelineStart + max(0, span.word.startTime))
        }
        for span in cardSpans where offset >= span.start && offset < span.end {
            return (span.item, span.item.timelineStart)
        }
        // Separator positions resolve to the nearest preceding card.
        let previous = cardSpans.last { $0.start <= offset }
        let item = previous?.item ?? Item(clipId: UUID(), text: "", timelineStart: 0)
        return (item, item.timelineStart)
    }

    /// A short context window around the match for display.
    private static func excerpt(around range: Range<Int>, in characters: [Character]) -> String {
        let window = 24
        let start = max(range.lowerBound - window, 1)  // skip the corpus pad
        let end = min(range.upperBound + window, characters.count - 1)
        let prefix = start > 1 ? "…" : ""
        let suffix = end < characters.count - 1 ? "…" : ""
        return prefix + String(characters[start..<end]) + suffix
    }
}
