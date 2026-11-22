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
    /// Snap targets materialized once per drag (CA-19) — replaced the
    /// 5-stage array chain that reallocated on every snappedTime call.
    @State private var cachedDragSnapPoints: [Double]? = nil

    private let secondsWidth: CGFloat = 38
    private let trackHeaderWidth: CGFloat = 76
    private let trackLaneHeight: CGFloat = 76
    private let trackRowVerticalPadding: CGFloat = 10
    private let beatBandHeight: CGFloat = 14
    /// CA-19: snap radius in points — a drag within this distance of a snap
    /// target (other clips' edges, playhead, zero) locks to it.
    private let snapRadius: CGFloat = 14

    private var timelineContentWidth: CGFloat {
        let clipEnd = viewModel.currentProject.timeline.duration
        let markerEnd = viewModel.currentProject.markers.lazy.map(\.time).max() ?? 0
        let visibleSeconds = max(clipEnd, markerEnd) + 4
        return max(360, CGFloat(visibleSeconds) * secondsWidth + 64)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            timelineHeader

            Divider()

            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 10) {
                    // Fixed left track-header column aligned 1:1 with the shared
                    // horizontal track lanes on the right.
                    VStack(alignment: .leading, spacing: 14) {
                        Color.clear
                            .frame(width: trackHeaderWidth, height: beatBandHeight)

                        ForEach(viewModel.currentProject.timeline.tracks) { track in
                            trackHeader(track)
                        }
                    }

                    // Single shared horizontal ScrollView so all tracks, beat ticks,
                    // snap alignment guides, and the playhead scroll in lockstep.
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 14) {
                            beatTickStrip

                            ZStack(alignment: .topLeading) {
                                VStack(alignment: .leading, spacing: 14) {
                                    ForEach(viewModel.currentProject.timeline.tracks) { track in
                                        trackLane(track)
                                    }
                                }

                                // CA-19: alignment guide at the exact linear snap x-coordinate.
                                if let guideTime = snapGuideTime, draggedClipId != nil {
                                    Rectangle()
                                        .fill(Color.accentColor.opacity(0.65))
                                        .frame(width: 1.5)
                                        .frame(maxHeight: .infinity)
                                        .offset(x: CGFloat(guideTime) * secondsWidth)
                                        .allowsHitTesting(false)
                                        .accessibilityHidden(true)
                                        .transition(.opacity)
                                }

                                IOSTimelinePlayheadLine(
                                    viewModel: viewModel,
                                    secondsWidth: secondsWidth
                                )
                            }
                            .animation(.easeInOut(duration: 0.1), value: snapGuideTime)
                        }
                        .frame(width: timelineContentWidth, alignment: .leading)
                        .padding(.trailing, 24)
                    }
                    .scrollIndicators(.visible)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
        }
    }

    /// CA-14: one 2pt orange tick per beat marker placed in a ZStack at its exact
    /// linear timeline coordinate inside the shared horizontal scroll strip.
    private var beatTickStrip: some View {
        let beats = viewModel.currentProject.markers.filter { $0.kind == .beat }
        return ZStack(alignment: .leading) {
            Color.clear
            ForEach(beats) { marker in
                Rectangle()
                    .fill(Color.orange.opacity(0.85))
                    .frame(width: 2, height: 12)
                    .offset(x: CGFloat(marker.time) * secondsWidth)
            }
        }
        .frame(width: timelineContentWidth, height: beatBandHeight, alignment: .leading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var timelineHeader: some View {
        HStack(spacing: 12) {
            IOSTimelinePlayheadLabel(viewModel: viewModel)

            Spacer()

            Text("\(viewModel.currentProject.timeline.tracks.count) tracks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(uiColor: .systemBackground))
    }

    private func trackHeader(_ track: Track) -> some View {
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
        .frame(width: trackHeaderWidth, height: trackLaneHeight, alignment: .leading)
        .padding(.vertical, trackRowVerticalPadding)
    }

    private func trackLane(_ track: Track) -> some View {
        let sortedClips = track.clips.sorted { $0.timelineRange.start < $1.timelineRange.start }
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .frame(width: timelineContentWidth, height: trackLaneHeight + trackRowVerticalPadding * 2)

            if sortedClips.isEmpty {
                emptyTrackPlaceholder
                    .padding(.leading, 8)
            } else {
                ForEach(sortedClips) { clip in
                    clipButton(clip)
                }
            }
        }
        .frame(width: timelineContentWidth, height: trackLaneHeight + trackRowVerticalPadding * 2, alignment: .leading)
    }

    private func clipButton(_ clip: Clip) -> some View {
        let isSelected = viewModel.selectedClipId == clip.id
        let activeDragOffset = draggedClipId == clip.id ? (dragTranslation == 0 ? dragOffset : dragTranslation) : 0
        let linearX = CGFloat(clip.timelineRange.start) * secondsWidth

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
            .padding(.horizontal, 10)
            .frame(width: width(for: clip), height: 64, alignment: .leading)
            .background(fillColor(for: clip.kind), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color(uiColor: .systemYellow) : Color.clear, lineWidth: 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: linearX + activeDragOffset)
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
                    // Materialize the drag's snap targets once — the dragged
                    // clip is the only thing moving, so this snapshot stays
                    // valid for the whole gesture.
                    cachedDragSnapPoints = viewModel.currentProject.timeline.tracks
                        .flatMap(\.clips)
                        .filter { $0.id != clip.id }
                        .flatMap { [$0.timelineRange.start, $0.timelineRange.end] }
                        + viewModel.currentProject.markers.map(\.time)
                        + [viewModel.playheadTime, 0.0]
                }
                dragOffset = value.translation.width
                // Live alignment guide: evaluate the snapped position while
                // dragging so the overlay (guarded on snapGuideTime) actually
                // shows mid-gesture, not only for the final commit.
                let liveStart = max(
                    0,
                    (dragInitialStartTime ?? clip.timelineRange.start)
                        + Double(value.translation.width / secondsWidth)
                )
                _ = snappedTime(liveStart, excluding: clip.id)
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
                cachedDragSnapPoints = nil
            }
    }

    /// CA-19: returns the nearest snap point within the threshold, or the
    /// raw time when no target is close enough. Snap targets are other
    /// clips' start/end edges, the playhead, and zero — the same set the
    /// Mac timeline uses. Also records the active snap target for the
    /// alignment guide.
    private func snappedTime(_ rawTime: Double, excluding clipId: UUID) -> Double {
        // CA-14: markers (beat markers included) are snap targets too — the
        // same guide set the Mac timeline snaps to, so beats generated on
        // either platform guide drags identically. Uses the gesture's cached
        // snapshot when available; falls back to a fresh build for callers
        // outside a drag.
        let snapPoints = cachedDragSnapPoints ?? viewModel.currentProject.timeline.tracks
            .flatMap(\.clips)
            .filter { $0.id != clipId }
            .flatMap { [$0.timelineRange.start, $0.timelineRange.end] }
            + viewModel.currentProject.markers.map(\.time)
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

    private func width(for clip: Clip) -> CGFloat {
        max(44, min(2400, clip.timelineRange.duration * secondsWidth))
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
}

/// Lightweight child view isolating `viewModel.playheadTime` observation for the
/// timeline header readout so playback ticks do not invalidate `IOSTimelineView.body`.
private struct IOSTimelinePlayheadLabel: View {
    let viewModel: IOSEditorViewModel

    var body: some View {
        Label(Self.timeString(viewModel.playheadTime), systemImage: "timeline.selection")
            .font(.caption.monospacedDigit())
    }

    private static func timeString(_ time: TimeInterval) -> String {
        let clampedTime = max(0, time.isFinite ? time : 0)
        let totalSeconds = Int(clampedTime.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// Shared vertical playhead indicator aligned across all iOS timeline tracks.
private struct IOSTimelinePlayheadLine: View {
    let viewModel: IOSEditorViewModel
    let secondsWidth: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.cyan)
            .frame(width: 2)
            .frame(maxHeight: .infinity)
            .offset(x: CGFloat(viewModel.playheadTime) * secondsWidth)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
#endif
