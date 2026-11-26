import MovieCutCore
import SwiftUI

/// CA-20 stage 2-B (W4): the Timeline Index — FCP's Timeline Index panel.
/// One searchable list over clips and markers (role and track names
/// searchable); a row reveals its target (clips select + jump, markers
/// jump). VoiceOver reads kind, title, and timecode per row — the
/// keyboard/VoiceOver walkthrough is the DoD's manual (U) axis.
struct TimelineIndexPanel: View {
    @Bindable var viewModel: EditorViewModel
    @State private var filter = ""
    /// N1-B: the pending "delete range start" mark (transient UI state).
    @State private var rangeMark: TranscriptSearchIndex.Match?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: MovieCutSpacing.xSmall) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MovieCutTheme.mutedText)
                TextField(NSLocalizedString("Search clips and markers", comment: ""), text: $filter)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("timelineIndex.search")
                if !filter.isEmpty {
                    Button {
                        filter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MovieCutTheme.mutedText)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(NSLocalizedString("Clear search", comment: ""))
                }
                Spacer()
                Text(String(
                    format: NSLocalizedString("%d results", comment: ""),
                    viewModel.timelineIndexEntries(filter: filter).count
                        + viewModel.transcriptMatches(for: filter).count
                ))
                    .font(MovieCutTypography.micro)
                    .foregroundStyle(MovieCutTheme.mutedText)
            }
            .padding(.horizontal, MovieCutSpacing.small)
            .padding(.vertical, MovieCutSpacing.xSmall)
            .background(MovieCutTheme.panelBackgroundRaised)

            Divider()
                .overlay(MovieCutTheme.divider)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // N1-A: transcript phrase hits sit above the clip list —
                    // a search that matched spoken content jumps to the word.
                    let transcriptMatches = viewModel.transcriptMatches(for: filter)
                    if !transcriptMatches.isEmpty {
                        HStack(spacing: MovieCutSpacing.xSmall) {
                            Text(NSLocalizedString("Transcript", comment: "N1-A transcript search section"))
                                .font(MovieCutTypography.micro)
                                .foregroundStyle(MovieCutTheme.mutedText)
                            if let mark = rangeMark {
                                Spacer()
                                Text(String(
                                    format: NSLocalizedString(
                                        "Range start marked at %d s", comment: "N1-B range mark status"
                                    ),
                                    Int(mark.time.rounded(.down))
                                ))
                                    .font(MovieCutTypography.micro)
                                    .foregroundStyle(MovieCutTheme.accent)
                                Button {
                                    rangeMark = nil
                                } label: {
                                    Text(NSLocalizedString("Clear", comment: "N1-B clear range mark"))
                                        .font(MovieCutTypography.micro)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(NSLocalizedString(
                                    "Clear range mark", comment: "N1-B clear a11y"
                                ))
                            }
                        }
                        .padding(.horizontal, MovieCutSpacing.small)
                        .padding(.vertical, MovieCutSpacing.xSmall)
                        ForEach(transcriptMatches) { match in
                            transcriptRow(match)
                            Divider()
                                .overlay(MovieCutTheme.divider.opacity(0.5))
                        }
                    } else if !filter.trimmingCharacters(in: .whitespaces).isEmpty,
                              viewModel.canOfferTranscriptSearchTranscription {
                        // N1: nothing to search yet — the project has speech
                        // clips but no subtitles. Offer the on-demand pass
                        // so the phrase search gets its material.
                        Button {
                            Task { await viewModel.transcribeForTranscriptSearch() }
                        } label: {
                            Label(
                                NSLocalizedString(
                                    "No transcript matches — Transcribe & Search",
                                    comment: "N1 on-demand transcription row"
                                ),
                                systemImage: "waveform.badge.magnifyingglass"
                            )
                            .font(MovieCutTypography.cardBody)
                            .foregroundStyle(MovieCutTheme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, MovieCutSpacing.small)
                        .padding(.vertical, MovieCutSpacing.xSmall)
                        .accessibilityHint(NSLocalizedString(
                            "Transcribes the project's speech so the search can match it",
                            comment: "N1 on-demand a11y hint"
                        ))
                        Divider()
                            .overlay(MovieCutTheme.divider.opacity(0.5))
                    }
                    ForEach(viewModel.timelineIndexEntries(filter: filter)) { entry in
                        row(entry)
                        Divider()
                            .overlay(MovieCutTheme.divider.opacity(0.5))
                    }
                }
            }
            .movieCutScrollBackground(MovieCutTheme.panelBackground)
        }
        .frame(maxHeight: 220)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NSLocalizedString("Timeline Index", comment: ""))
    }

    /// N1-A: a transcript phrase hit — excerpt plus the matched word's
    /// timecode; revealing selects the subtitle card and seeks to the word.
    private func transcriptRow(_ match: TranscriptSearchIndex.Match) -> some View {
        Button {
            viewModel.revealTranscriptMatch(match)
        } label: {
            HStack(spacing: MovieCutSpacing.small) {
                Image(systemName: "text.quote")
                    .foregroundStyle(MovieCutTheme.accent)
                    .frame(width: 16)
                Text(match.excerpt)
                    .font(MovieCutTypography.cardBody)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Spacer()
                Text(TimecodeParser.rulerLabel(forSeconds: Int(match.time.rounded(.down))))
                    .font(MovieCutTypography.micro.monospacedDigit())
                    .foregroundStyle(MovieCutTheme.mutedText)
            }
            .padding(.horizontal, MovieCutSpacing.small)
            .padding(.vertical, MovieCutSpacing.xSmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString(
            "Transcript match", comment: "N1-A transcript row a11y"
        ) + ": " + match.excerpt)
        .accessibilityHint(NSLocalizedString(
            "Moves the playhead to the matched word",
            comment: "N1-A transcript row a11y hint"
        ))
        .accessibilityIdentifier("timelineIndex.transcript.\(match.id)")
        // N1-B: the delete actions — atomic per AutoCutCommand (one undo).
        .contextMenu {
            Button {
                Task { await viewModel.deleteTranscriptSentence(match) }
            } label: {
                Label(
                    NSLocalizedString("Delete Sentence", comment: "N1-B action"),
                    systemImage: "scissors"
                )
            }
            Button {
                Task { await viewModel.keepTranscriptSentenceOnly(match) }
            } label: {
                Label(
                    NSLocalizedString("Keep Only This Sentence", comment: "N1 keep-only action"),
                    systemImage: "arrow.right.to.line.compact"
                )
            }
            Divider()
            if let mark = rangeMark {
                Button {
                    Task {
                        await viewModel.deleteTranscriptRange(from: mark, to: match)
                        rangeMark = nil
                    }
                } label: {
                    Label(
                        String(
                            format: NSLocalizedString(
                                "Delete Range to Here (from %d s)", comment: "N1-B range action"
                            ),
                            Int(mark.time.rounded(.down))
                        ),
                        systemImage: "arrow.left.to.line.compact"
                    )
                }
                .disabled(abs(mark.time - match.time) <= 0.01)
                Button {
                    Task {
                        await viewModel.keepTranscriptRangeOnly(from: mark, to: match)
                        rangeMark = nil
                    }
                } label: {
                    Label(
                        String(
                            format: NSLocalizedString(
                                "Keep Only from Mark to Here (from %d s)", comment: "N1 keep-only range action"
                            ),
                            Int(mark.time.rounded(.down))
                        ),
                        systemImage: "rectangle.compress.vertical"
                    )
                }
                .disabled(abs(mark.time - match.time) <= 0.01)
                Button {
                    rangeMark = nil
                } label: {
                    Label(
                        NSLocalizedString("Clear Range Mark", comment: "N1-B action"),
                        systemImage: "xmark.circle"
                    )
                }
            } else {
                Button {
                    rangeMark = match
                } label: {
                    Label(
                        NSLocalizedString("Mark Delete-Range Start", comment: "N1-B action"),
                        systemImage: "flag"
                    )
                }
            }
        }
    }

    private func row(_ entry: EditorViewModel.TimelineIndexEntry) -> some View {
        Button {
            viewModel.revealTimelineIndexEntry(entry)
        } label: {
            HStack(spacing: MovieCutSpacing.small) {
                Image(systemName: iconName(entry.kind))
                    .foregroundStyle(iconColor(entry.kind))
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(MovieCutTypography.cardBody)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(subtitle(entry.kind))
                        .font(MovieCutTypography.micro)
                        .foregroundStyle(MovieCutTheme.mutedText)
                        .lineLimit(1)
                }
                Spacer()
                Text(TimecodeParser.rulerLabel(forSeconds: Int(entry.time.rounded(.down))))
                    .font(MovieCutTypography.micro.monospacedDigit())
                    .foregroundStyle(MovieCutTheme.mutedText)
            }
            .padding(.horizontal, MovieCutSpacing.small)
            .padding(.vertical, MovieCutSpacing.xSmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilitySummary(entry))
        .accessibilityHint(NSLocalizedString("Moves the playhead to this item", comment: ""))
        .accessibilityIdentifier("timelineIndex.row.\(entry.id.uuidString)")
    }

    private func iconName(_ kind: EditorViewModel.TimelineIndexEntry.Kind) -> String {
        switch kind {
        case .clip: "doc.fill"
        case .marker: "bookmark.fill"
        }
    }

    private func iconColor(_ kind: EditorViewModel.TimelineIndexEntry.Kind) -> Color {
        switch kind {
        case .clip: MovieCutTheme.accent
        case .marker: .orange
        }
    }

    private func subtitle(_ kind: EditorViewModel.TimelineIndexEntry.Kind) -> String {
        switch kind {
        case let .clip(trackName, role):
            if let role {
                return "\(trackName) · \(role)"
            }
            return trackName
        case .marker:
            return NSLocalizedString("Marker", comment: "")
        }
    }

    private func accessibilitySummary(_ entry: EditorViewModel.TimelineIndexEntry) -> String {
        let kindLabel: String
        switch entry.kind {
        case .clip: kindLabel = NSLocalizedString("Clip", comment: "")
        case .marker: kindLabel = NSLocalizedString("Marker", comment: "")
        }
        return "\(kindLabel), \(entry.title), \(TimecodeParser.rulerLabel(forSeconds: Int(entry.time.rounded(.down))))"
    }
}
