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
                Text(String(format: NSLocalizedString("%d results", comment: ""),
                            viewModel.timelineIndexEntries(filter: filter).count))
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
