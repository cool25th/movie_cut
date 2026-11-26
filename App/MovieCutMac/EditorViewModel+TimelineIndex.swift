import MovieCutCore
import SwiftUI

/// CA-20 stage 2-B (W4): the timeline index — FCP's Timeline Index. One
/// searchable list over the project's clips AND markers (role names
/// searchable too), each row jumping the playhead to (and, for clips,
/// selecting) its target. The entry build and filter are pure functions of
/// the project snapshot, so search correctness is unit-testable and the
/// reveal path reuses the transport's own seek.
extension EditorViewModel {
    struct TimelineIndexEntry: Identifiable, Equatable {
        enum Kind: Equatable {
            case clip(trackName: String, role: String?)
            case marker
        }

        var id: UUID
        var kind: Kind
        /// The searchable/display title: asset filename for media clips,
        /// text excerpt for text clips, marker name for markers.
        var title: String
        /// Timeline position the row reveals.
        var time: TimeInterval
        /// The clip to select on reveal (markers only move the playhead).
        var clipId: UUID?
    }

    /// All index entries (clips + non-beat markers), timeline order.
    /// Beat markers are analysis artifacts, not index rows — they would
    /// drown the list on any beat-detected project.
    func timelineIndexEntries(filter: String = "") -> [TimelineIndexEntry] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rolesById = Dictionary(uniqueKeysWithValues: currentProject.roles.map { ($0.id, $0.name) })

        var entries: [TimelineIndexEntry] = []
        for track in currentProject.timeline.tracks {
            for clip in track.clips.sorted(by: { $0.timelineRange.start < $1.timelineRange.start }) {
                let roleName = clip.roleId.flatMap { rolesById[$0] }
                let entry = TimelineIndexEntry(
                    id: clip.id,
                    kind: .clip(trackName: track.name, role: roleName),
                    title: Self.indexTitle(for: clip, in: currentProject),
                    time: clip.timelineRange.start,
                    clipId: clip.id
                )
                if query.isEmpty || Self.entry(entry, matches: query) {
                    entries.append(entry)
                }
            }
        }
        for marker in currentProject.markers where marker.kind != .beat {
            let entry = TimelineIndexEntry(
                id: marker.id,
                kind: .marker,
                title: marker.name,
                time: marker.time,
                clipId: nil
            )
            if query.isEmpty || Self.entry(entry, matches: query) {
                entries.append(entry)
            }
        }
        return entries.sorted { lhs, rhs in
            lhs.time != rhs.time ? lhs.time < rhs.time : lhs.title < rhs.title
        }
    }

    /// Reveals an entry: clips select + jump, markers jump via the marker
    /// path (which also reports the quick-tool status line).
    func revealTimelineIndexEntry(_ entry: TimelineIndexEntry) {
        if let clipId = entry.clipId {
            selectedClipIds = [clipId]
            scrubPlayhead(to: entry.time)
        } else if let marker = currentProject.markers.first(where: { $0.id == entry.id }) {
            goToMarker(marker)
        }
    }

    /// Case-insensitive match over title, track name, and role name — the
    /// three things a W4 editor remembers about a clip.
    private static func entry(_ entry: TimelineIndexEntry, matches query: String) -> Bool {
        if entry.title.lowercased().contains(query) { return true }
        if case let .clip(trackName, role) = entry.kind {
            if trackName.lowercased().contains(query) { return true }
            if let role, role.lowercased().contains(query) { return true }
        }
        return false
    }

    private static func indexTitle(for clip: Clip, in project: Project) -> String {
        if let textContent = clip.textContent {
            let flat = textContent.text.replacingOccurrences(of: "\n", with: " ")
            return flat.isEmpty ? NSLocalizedString("Text Clip", comment: "") : flat
        }
        if let assetId = clip.assetId,
           let asset = project.mediaLibrary.assets[assetId] {
            let name = (asset.originalURL.lastPathComponent as NSString).deletingPathExtension
            return name.isEmpty ? asset.originalURL.lastPathComponent : name
        }
        return NSLocalizedString("Clip", comment: "")
    }
}

extension EditorViewModel {

    // MARK: - N1-A transcript search

    /// Transcript phrase matches for the index panel's query — subtitle
    /// cards searched as ONE concatenated corpus (N1-A), so a spoken phrase
    /// split across two cards still hits, word-time precise when karaoke
    /// timings exist. The corpus is cached per timeline state (the build
    /// dominates; queries must stay keystroke-cheap).
    func transcriptMatches(for filter: String) -> [TranscriptSearchIndex.Match] {
        if transcriptCorpusCache?.timeline != currentProject.timeline {
            let items = currentProject.timeline.tracks.flatMap { track in
                track.clips.compactMap { clip -> TranscriptSearchIndex.Item? in
                    guard let content = clip.textContent, content.contentKind != .sticker else {
                        return nil
                    }
                    return TranscriptSearchIndex.Item(
                        clipId: clip.id,
                        text: content.text,
                        timelineStart: clip.timelineRange.start,
                        words: content.wordTimings
                    )
                }
            }
            transcriptCorpusCache = (currentProject.timeline, TranscriptSearchIndex.Corpus(items: items))
        }
        return transcriptCorpusCache!.corpus.matches(for: filter)
    }

    /// Reveals a transcript hit: selects the subtitle card and jumps the
    /// playhead to the matched word's second.
    func revealTranscriptMatch(_ match: TranscriptSearchIndex.Match) {
        if currentProject.timeline.tracks.contains(where: { track in
            track.clips.contains { $0.id == match.clipId }
        }) {
            selectedClipIds = [match.clipId]
        }
        scrubPlayhead(to: match.time)
    }
}

extension EditorViewModel {

    /// N1: two matches closer than this (seconds) are "the same moment" —
    /// range delete/keep between them is refused instead of doing nothing.
    private static let minimumTranscriptRangeSeconds: TimeInterval = 0.01

    // MARK: - N1-B transcript range delete

    /// Deletes the sentence span of one transcript hit (N1-B "이 부분
    /// 삭제"). In the auto-subtitle workflow the subtitle card's timeline
    /// range IS the spoken sentence span, so removing it cuts the speech
    /// from every track in one atomic undo (`AutoCutCommand` splits at the
    /// boundaries and removes what falls inside).
    func deleteTranscriptSentence(_ match: TranscriptSearchIndex.Match) async {
        guard let card = currentProject.timeline.tracks.flatMap(\.clips)
            .first(where: { $0.id == match.clipId })
        else {
            lastErrorMessage = NSLocalizedString(
                "The subtitle card for this match is no longer on the timeline.",
                comment: "N1-B missing card error"
            )
            return
        }
        lastErrorMessage = nil
        await apply(AutoCutCommand(removableRanges: [card.timelineRange]))
        lastStatusMessage = NSLocalizedString(
            "Deleted the matched sentence span.",
            comment: "N1-B status"
        )
    }

    /// Deletes everything between two matched words — [start, end) in
    /// timeline seconds, keeping the end phrase itself (N1-B "여기부터
    /// 여기까지 삭제"). One atomic undo.
    func deleteTranscriptRange(
        from start: TranscriptSearchIndex.Match,
        to end: TranscriptSearchIndex.Match
    ) async {
        let lower = min(start.time, end.time)
        let upper = max(start.time, end.time)
        guard upper - lower > Self.minimumTranscriptRangeSeconds else {
            lastErrorMessage = NSLocalizedString(
                "The two matches are at the same moment; nothing to delete between them.",
                comment: "N1-B empty range error"
            )
            return
        }
        lastErrorMessage = nil
        await apply(AutoCutCommand(removableRanges: [
            TimeRange(start: lower, duration: upper - lower),
        ]))
        lastStatusMessage = NSLocalizedString(
            "Deleted the transcript range between the two matches.",
            comment: "N1-B range status"
        )
    }
}

extension EditorViewModel {

    // MARK: - N1 on-demand transcription + keep-only

    /// N1: the speech clip an on-demand "Transcribe & Search" pass should
    /// use — the selected audio/video clip when there is one, else the
    /// first speech clip on the timeline.
    func transcriptSearchTranscriptionTarget() -> Clip? {
        if let selectedClip, selectedClip.kind == .audio || selectedClip.kind == .video {
            return selectedClip
        }
        return currentProject.timeline.tracks
            .flatMap(\.clips)
            .first { $0.kind == .audio || $0.kind == .video }
    }

    /// N1: offer the on-demand pass only when a phrase search has nothing
    /// to search — speech clips exist but no text clips do.
    var canOfferTranscriptSearchTranscription: Bool {
        let clips = currentProject.timeline.tracks.flatMap(\.clips)
        let hasSpeech = clips.contains { $0.kind == .audio || $0.kind == .video }
        let hasText = clips.contains { $0.textContent != nil }
        return hasSpeech && !hasText
    }

    /// N1: "Transcribe & Search" — no subtitle matches because the project
    /// has no subtitles yet; transcribe the speech content once through the
    /// existing auto-subtitle flow so the phrase search has material.
    func transcribeForTranscriptSearch() async {
        guard let target = transcriptSearchTranscriptionTarget() else {
            lastErrorMessage = NSLocalizedString(
                "No audio or video clips to transcribe.", comment: "N1 on-demand error"
            )
            return
        }
        lastErrorMessage = nil
        // prepareSubtitles aligns its output to the selection, so select
        // the target speech clip for the pass.
        selectedClipId = target.id
        await generateSubtitles()
    }

    /// N1 keep-only: keeps [start, end) between two matched words and
    /// removes everything around it — one atomic `AutoCutCommand`, so a
    /// single undo restores the full timeline.
    func keepTranscriptRangeOnly(
        from start: TranscriptSearchIndex.Match,
        to end: TranscriptSearchIndex.Match
    ) async {
        let lower = min(start.time, end.time)
        let upper = max(start.time, end.time)
        guard upper - lower > Self.minimumTranscriptRangeSeconds else {
            lastErrorMessage = NSLocalizedString(
                "The two matches are at the same moment; nothing to keep between them.",
                comment: "N1 keep-only empty range error"
            )
            return
        }
        let total = currentProject.timeline.duration
        var removable: [TimeRange] = []
        if lower > Self.minimumTranscriptRangeSeconds {
            removable.append(TimeRange(start: 0, duration: lower))
        }
        if upper < total - Self.minimumTranscriptRangeSeconds {
            removable.append(TimeRange(start: upper, duration: total - upper))
        }
        guard !removable.isEmpty else {
            lastErrorMessage = NSLocalizedString(
                "This range already covers the whole timeline.",
                comment: "N1 keep-only whole-timeline error"
            )
            return
        }
        lastErrorMessage = nil
        await apply(AutoCutCommand(removableRanges: removable))
        lastStatusMessage = NSLocalizedString(
            "Kept only the transcript range between the two matches.",
            comment: "N1 keep-only status"
        )
    }

    /// N1 keep-only: keeps one matched sentence's span (the subtitle card's
    /// range) and removes everything around it.
    func keepTranscriptSentenceOnly(_ match: TranscriptSearchIndex.Match) async {
        guard let card = currentProject.timeline.tracks.flatMap(\.clips)
            .first(where: { $0.id == match.clipId })
        else {
            lastErrorMessage = NSLocalizedString(
                "The subtitle card for this match is no longer on the timeline.",
                comment: "N1 keep-only missing card error"
            )
            return
        }
        await keepTranscriptRangeOnly(
            from: TranscriptSearchIndex.Match(
                clipId: card.id, time: card.timelineRange.start, excerpt: ""
            ),
            to: TranscriptSearchIndex.Match(
                clipId: card.id, time: card.timelineRange.end, excerpt: ""
            )
        )
    }
}
