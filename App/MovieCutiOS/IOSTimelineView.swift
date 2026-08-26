#if os(iOS)
import MovieCutCore
import SwiftUI

struct IOSTimelineView: View {
    @Bindable var viewModel: IOSEditorViewModel
    var onInspectorRequested: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var draggedClipId: UUID?
    @State private var dragInitialStartTime: TimeInterval?
    @GestureState private var dragTranslation: CGFloat = 0
    // CA-19: the active snap target during a drag — drives the alignment
    // guide line (Mac TimelineView parity).
    @State private var snapGuideTime: TimeInterval? = nil

    private let secondsWidth: CGFloat = 38
    private let trackHeaderWidth: CGFloat = 76
    /// CA-19: snap radius in points — a drag within this distance of a snap
    /// target (other clips' edges, playhead, zero) locks to it.
    private let snapRadius: CGFloat = 14

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
                .overlay(alignment: .leading) {
                    // CA-19: the alignment guide — a vertical line at the
                    // active snap target, spanning all track lanes. The
                    // user SEES what the clip aligned to, not just feels the
                    // snap (Mac parity).
                    if let guideTime = snapGuideTime, draggedClipId != nil {
                        let x = CGFloat(guideTime) * secondsWidth
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.6))
                            .frame(width: 1.5)
                            .frame(maxHeight: .infinity)
                            .offset(x: x + 14)  // + horizontal padding
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.1), value: snapGuideTime)
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
        let activeDragOffset = draggedClipId == clip.id ? (dragTranslation == 0 ? dragOffset : dragTranslation) : 0

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
        .offset(x: activeDragOffset)
        .zIndex(draggedClipId == clip.id ? 1 : 0)
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
        .gesture(dragGesture(for: clip))
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

    private func dragGesture(for clip: Clip) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation.width
            }
            .onChanged { value in
                if draggedClipId != clip.id {
                    draggedClipId = clip.id
                    dragInitialStartTime = clip.timelineRange.start
                    select(clip)
                }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let initialStart = dragInitialStartTime ?? clip.timelineRange.start
                let rawStart = max(0, initialStart + Double(value.translation.width / secondsWidth))
                // CA-19: snap the final position to nearby targets (other
                // clips' edges, playhead, zero) — the same guide set the Mac
                // timeline snaps to.
                let newStart = snappedTime(rawStart, excluding: clip.id)

                Task {
                    await viewModel.moveClip(clipId: clip.id, newStart: newStart)
                }

                dragOffset = 0
                draggedClipId = nil
                dragInitialStartTime = nil
                snapGuideTime = nil
            }
    }

    /// CA-19: returns the nearest snap point within the threshold, or the
    /// raw time when no target is close enough. Snap targets are other
    /// clips' start/end edges, the playhead, and zero — the same set the
    /// Mac timeline uses. Also records the active snap target for the
    /// alignment guide.
    private func snappedTime(_ rawTime: Double, excluding clipId: UUID) -> Double {
        let snapPoints = viewModel.currentProject.timeline.tracks
            .flatMap(\.clips)
            .filter { $0.id != clipId }
            .flatMap { [$0.timelineRange.start, $0.timelineRange.end] }
            + [viewModel.playheadTime, 0.0]

        let threshold = Double(snapRadius / secondsWidth)
        var nearest: (point: Double, distance: Double)?
        for point in snapPoints {
            let distance = abs(rawTime - point)
            if distance < threshold && (nearest == nil || distance < nearest!.distance) {
                nearest = (point, distance)
            }
        }

        if let nearest {
            snapGuideTime = nearest.point
            return nearest.point
        }
        snapGuideTime = nil
        return rawTime
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
