#if os(iOS)
import MovieCutCore
import SwiftUI

struct IOSTimelineView: View {
    @Bindable var viewModel: IOSEditorViewModel
    var onInspectorRequested: () -> Void

    private let secondsWidth: CGFloat = 38
    private let trackHeaderWidth: CGFloat = 76

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            timelineHeader

            Divider()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(viewModel.currentProject.timeline.tracks) { track in
                        trackRow(track)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
        }
    }

    private var timelineHeader: some View {
        HStack(spacing: 12) {
            Label(timeString(viewModel.playheadTime), systemImage: "timeline.selection")
                .font(.caption.monospacedDigit())

            Spacer()

            Text("\(viewModel.currentProject.timeline.tracks.count) tracks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(uiColor: .systemBackground))
    }

    private func trackRow(_ track: Track) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: trackIcon(for: track.kind))
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))

                Text(track.name)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: trackHeaderWidth, alignment: .leading)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(clipSegments(for: track)) { segment in
                        Color.clear
                            .frame(width: width(forGap: segment.leadingGap))

                        clipButton(segment.clip)
                    }

                    if track.clips.isEmpty {
                        emptyTrackPlaceholder
                    }
                }
                .frame(minHeight: 76, alignment: .leading)
                .padding(.trailing, 24)
            }
            .scrollIndicators(.visible)
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func clipButton(_ clip: Clip) -> some View {
        let isSelected = viewModel.selectedClipId == clip.id

        return Button {
            select(clip)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: iconName(for: clip.kind))
                        .font(.callout)
                    Text(clip.kind.rawValue.capitalized)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }

                Text(durationText(clip.timelineRange.duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.86))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(width: width(for: clip), height: 64, alignment: .leading)
            .background(fillColor(for: clip.kind), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color(uiColor: .systemYellow) : Color.clear, lineWidth: 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Inspect", systemImage: "slider.horizontal.3") {
                select(clip)
                onInspectorRequested()
            }

            Button("Delete", systemImage: "trash", role: .destructive) {
                select(clip)
                Task { await viewModel.deleteClip() }
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                select(clip)
                onInspectorRequested()
            }
        )
        .accessibilityLabel("\(clip.kind.rawValue.capitalized) clip, \(durationText(clip.timelineRange.duration))")
    }

    private var emptyTrackPlaceholder: some View {
        Text("Empty")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 116, height: 64)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
    }

    private func select(_ clip: Clip) {
        viewModel.selectedClipId = clip.id
        viewModel.playheadTime = clip.timelineRange.start
    }

    private func clipSegments(for track: Track) -> [TimelineClipSegment] {
        let clips = track.clips.sorted { $0.timelineRange.start < $1.timelineRange.start }
        var cursor: TimeInterval = 0

        return clips.map { clip in
            let gap = max(0, clip.timelineRange.start - cursor)
            cursor = max(cursor, clip.timelineRange.end)
            return TimelineClipSegment(clip: clip, leadingGap: gap)
        }
    }

    private func width(for clip: Clip) -> CGFloat {
        max(112, min(360, clip.timelineRange.duration * secondsWidth))
    }

    private func width(forGap gap: TimeInterval) -> CGFloat {
        min(1_200, max(0, gap * secondsWidth))
    }

    private func fillColor(for kind: ClipKind) -> Color {
        switch kind {
        case .video: Color(uiColor: .systemIndigo)
        case .audio: Color(uiColor: .systemTeal)
        case .image: Color(uiColor: .systemOrange)
        case .text: Color(uiColor: .systemGray)
        }
    }

    private func iconName(for kind: ClipKind) -> String {
        switch kind {
        case .video: "video.fill"
        case .audio: "waveform"
        case .image: "photo.fill"
        case .text: "textformat"
        }
    }

    private func trackIcon(for kind: TrackKind) -> String {
        switch kind {
        case .video: "film.stack"
        case .audio: "waveform"
        case .text: "textformat.size"
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        String(format: "%.1fs", duration)
    }

    private func timeString(_ time: TimeInterval) -> String {
        let clampedTime = max(0, time.isFinite ? time : 0)
        let totalSeconds = Int(clampedTime.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct TimelineClipSegment: Identifiable {
    var clip: Clip
    var leadingGap: TimeInterval

    var id: UUID {
        clip.id
    }
}
#endif
