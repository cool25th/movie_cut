import AppKit
import SwiftUI
import MovieCutCore
import UniformTypeIdentifiers

struct TimelineView: View {
    var viewModel: EditorViewModel

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var draggedClipId: UUID? = nil
    @State private var dragInitialTimelineRange: TimeRange?
    @State private var dragInitialSourceRange: TimeRange?

    private let trackHeight: CGFloat = 50
    private let rulerHeight: CGFloat = 24
    private let trimHandleWidth: CGFloat = 8
    private let minimumClipDuration: TimeInterval = 0.1

    private var pixelsPerSecond: Double {
        viewModel.timelineZoom
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(NSLocalizedString("Timeline", comment: ""))
                    .font(.headline)
                Spacer()
                Button(action: { viewModel.timelineZoom = max(20, viewModel.timelineZoom - 20) }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(NSLocalizedString("Zoom Out", comment: ""))
                .accessibilityHint(NSLocalizedString("Zooms the timeline out.", comment: ""))
                Button(action: { viewModel.timelineZoom = min(300, viewModel.timelineZoom + 20) }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(NSLocalizedString("Zoom In", comment: ""))
                .accessibilityHint(NSLocalizedString("Zooms the timeline in.", comment: ""))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 0) {
                    timeRuler

                    ForEach(viewModel.currentProject.timeline.tracks) { track in
                        trackLane(track)
                    }
                }
            }
        }
        .frame(minHeight: 180)
        .background(Color(nsColor: .textBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NSLocalizedString("Timeline", comment: ""))
    }

    private var timeRuler: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .frame(width: 80, height: rulerHeight)
                .overlay(alignment: .leading) {
                    Text(NSLocalizedString("Time", comment: ""))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }

            Canvas { context, size in
                var x: CGFloat = 0
                var time: TimeInterval = 0
                let interval: TimeInterval = pixelsPerSecond >= 100 ? 1 : (pixelsPerSecond >= 50 ? 5 : 10)

                while x < size.width {
                    let isMajor = Int(time) % 10 == 0
                    let tickH: CGFloat = isMajor ? rulerHeight : rulerHeight / 2

                    context.stroke(
                        Path { p in
                            p.move(to: CGPoint(x: x, y: rulerHeight))
                            p.addLine(to: CGPoint(x: x, y: rulerHeight - tickH))
                        },
                        with: .color(.secondary),
                        lineWidth: isMajor ? 1 : 0.5
                    )

                    if isMajor {
                        let text = Text("\(Int(time))s")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        context.draw(text, at: CGPoint(x: x + 4, y: 8))
                    }

                    time += interval
                    x = CGFloat(time) * CGFloat(pixelsPerSecond)
                }
            }
            .frame(height: rulerHeight)
        }
    }

    private func trackLane(_ track: Track) -> some View {
        HStack(spacing: 0) {
            // Track header
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.caption)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: track.isMuted ? "speaker.slash" : "speaker.wave.2")
                        .font(.caption2)
                    Image(systemName: track.isLocked ? "lock" : "lock.open")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .frame(width: 80, alignment: .leading)
            .padding(.horizontal, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            // Clips area
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(nsColor: .textBackgroundColor))

                ForEach(track.clips) { clip in
                    clipView(clip, trackKind: track.kind)
                }

                // Playhead
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2)
                    .offset(x: CGFloat(viewModel.playheadTime) * CGFloat(pixelsPerSecond))
                    .accessibilityElement()
                    .accessibilityLabel(NSLocalizedString("Playhead", comment: ""))
                    .accessibilityValue(timelineSecondsString(viewModel.playheadTime))

                ForEach(viewModel.currentProject.markers) { marker in
                    Rectangle()
                        .fill(Color.yellow.opacity(0.7))
                        .frame(width: 2, height: trackHeight)
                        .offset(x: CGFloat(marker.time) * CGFloat(pixelsPerSecond))
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                for provider in providers {
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                        guard let data = data as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil)
                        else { return }

                        Task { @MainActor in
                            await viewModel.importMedia([url])
                        }
                    }
                }
                return true
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(track.name)
            .accessibilityHint(NSLocalizedString("Drop media files here to add them to this track.", comment: ""))
        }
        .frame(height: trackHeight)
        .overlay(alignment: .bottom) { Divider() }
    }

    @MainActor
    private func clipView(_ clip: Clip, trackKind: TrackKind) -> some View {
        let x = CGFloat(clip.timelineRange.start) * CGFloat(pixelsPerSecond)
        let width = CGFloat(clip.timelineRange.duration) * CGFloat(pixelsPerSecond)
        let isSelected = viewModel.selectedClipIds.contains(clip.id)
        let isActiveDrag = isDragging && draggedClipId == clip.id

        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(colorForClip(trackKind: trackKind, selected: isSelected))
                .overlay {
                    if trackKind != .text {
                        Canvas { context, size in
                            let samples = viewModel.waveform(for: clip)
                            guard !samples.isEmpty else { return }

                            let barWidth = max(1, size.width / CGFloat(samples.count))
                            let midY = size.height / 2

                            for (index, sample) in samples.enumerated() {
                                let barHeight = CGFloat(sample) * size.height * 0.8
                                let rect = CGRect(
                                    x: CGFloat(index) * barWidth,
                                    y: midY - barHeight / 2,
                                    width: max(1, barWidth - 0.5),
                                    height: barHeight
                                )
                                context.fill(Path(rect), with: .color(.white.opacity(0.4)))
                            }
                        }
                        .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .leading) {
                    Text(clipLabel(clip))
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
                .contentShape(Rectangle())
                .gesture(moveGesture(for: clip))
                .accessibilityElement()
                .accessibilityLabel(String(format: NSLocalizedString("Clip %@", comment: ""), clipLabel(clip)))
                .accessibilityValue(
                    String(
                        format: NSLocalizedString("Starts at %@, duration %@", comment: ""),
                        timelineSecondsString(clip.timelineRange.start),
                        timelineSecondsString(clip.timelineRange.duration)
                    )
                )
                .accessibilityHint(NSLocalizedString("Selects the clip. Drag to move it on the timeline.", comment: ""))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    selectClip(clip.id, extendingSelection: false)
                }

            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: trimHandleWidth)
                    .contentShape(Rectangle())
                    .gesture(leftTrimGesture(for: clip))
                    .accessibilityElement()
                    .accessibilityLabel(String(format: NSLocalizedString("Left trim handle for %@", comment: ""), clipLabel(clip)))
                    .accessibilityHint(NSLocalizedString("Drag to trim the clip start.", comment: ""))

                Spacer(minLength: 0)

                Rectangle()
                    .fill(Color.clear)
                    .frame(width: trimHandleWidth)
                    .contentShape(Rectangle())
                    .gesture(rightTrimGesture(for: clip))
                    .accessibilityElement()
                    .accessibilityLabel(String(format: NSLocalizedString("Right trim handle for %@", comment: ""), clipLabel(clip)))
                    .accessibilityHint(NSLocalizedString("Drag to trim the clip end.", comment: ""))
            }
        }
            .frame(width: max(2, width), height: trackHeight - 8)
            .offset(x: x, y: 4)
            .zIndex(isActiveDrag || isSelected ? 1 : 0)
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .onTapGesture {
                selectClip(clip.id, extendingSelection: isCommandModifierPressed)
            }
            .contextMenu {
                Button(NSLocalizedString("Split", comment: "")) {
                    selectClip(clip.id, extendingSelection: false)
                    Task { await viewModel.splitClip() }
                }
                Button(NSLocalizedString("Delete", comment: "")) {
                    let clipIds = contextMenuClipIds(anchor: clip.id)
                    Task { await viewModel.deleteClips(clipIds) }
                }
                Button(NSLocalizedString("Duplicate", comment: "")) {
                    let clipIds = contextMenuClipIds(anchor: clip.id)
                    Task { await viewModel.duplicateClips(clipIds) }
                }
                Divider()
                Button(NSLocalizedString("Ripple Delete", comment: "")) {
                    selectClip(clip.id, extendingSelection: false)
                    Task { await viewModel.rippleDeleteClip(clipId: clip.id) }
                }
            }
    }

    private var isCommandModifierPressed: Bool {
        NSApp.currentEvent?.modifierFlags.contains(.command) == true
    }

    @MainActor
    private func selectClip(_ clipId: UUID, extendingSelection: Bool) {
        if extendingSelection {
            if viewModel.selectedClipIds.contains(clipId) {
                viewModel.selectedClipIds.remove(clipId)
            } else {
                viewModel.selectedClipIds.insert(clipId)
            }
        } else {
            viewModel.selectedClipIds = [clipId]
        }
    }

    @MainActor
    private func contextMenuClipIds(anchor clipId: UUID) -> Set<UUID> {
        if viewModel.selectedClipIds.contains(clipId) {
            return viewModel.selectedClipIds
        }

        viewModel.selectedClipIds = [clipId]
        return [clipId]
    }

    private func moveGesture(for clip: Clip) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                beginClipDrag(clip)
                dragOffset = value.translation.width

                guard let initialRange = dragInitialTimelineRange else { return }
                let rawStart = max(0, initialRange.start + Double(value.translation.width) / pixelsPerSecond)
                let newStart = max(0, snappedTime(rawStart, allClips: allClips(excluding: clip.id)))

                updateClip(
                    clip.id,
                    timelineRange: TimeRange(start: newStart, duration: initialRange.duration)
                )
            }
            .onEnded { _ in
                commitMove(for: clip.id)
                endClipDrag()
            }
    }

    private func leftTrimGesture(for clip: Clip) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                beginClipDrag(clip)
                dragOffset = value.translation.width

                guard let initialTimelineRange = dragInitialTimelineRange,
                      let initialSourceRange = dragInitialSourceRange
                else { return }

                let minimumStart = max(0, initialTimelineRange.start - initialSourceRange.start)
                let maximumStart = max(minimumStart, initialTimelineRange.end - minimumClipDuration)
                let rawStart = initialTimelineRange.start + Double(value.translation.width) / pixelsPerSecond
                let snappedStart = snappedTime(rawStart, allClips: allClips(excluding: clip.id))
                let newStart = min(maximumStart, max(minimumStart, snappedStart))
                let newDuration = max(minimumClipDuration, initialTimelineRange.end - newStart)
                let sourceDelta = newStart - initialTimelineRange.start
                let newSourceRange = TimeRange(
                    start: max(0, initialSourceRange.start + sourceDelta),
                    duration: newDuration
                )

                updateClip(
                    clip.id,
                    sourceRange: newSourceRange,
                    timelineRange: TimeRange(start: newStart, duration: newDuration)
                )
            }
            .onEnded { _ in
                commitTrim(for: clip.id)
                endClipDrag()
            }
    }

    private func rightTrimGesture(for clip: Clip) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                beginClipDrag(clip)
                dragOffset = value.translation.width

                guard let initialTimelineRange = dragInitialTimelineRange,
                      let initialSourceRange = dragInitialSourceRange
                else { return }

                let rawEnd = initialTimelineRange.end + Double(value.translation.width) / pixelsPerSecond
                let snappedEnd = snappedTime(rawEnd, allClips: allClips(excluding: clip.id))
                let newEnd = max(initialTimelineRange.start + minimumClipDuration, snappedEnd)
                let newDuration = newEnd - initialTimelineRange.start
                let newSourceRange = TimeRange(start: initialSourceRange.start, duration: newDuration)

                updateClip(
                    clip.id,
                    sourceRange: newSourceRange,
                    timelineRange: TimeRange(start: initialTimelineRange.start, duration: newDuration)
                )
            }
            .onEnded { _ in
                commitTrim(for: clip.id)
                endClipDrag()
            }
    }

    private func beginClipDrag(_ clip: Clip) {
        if draggedClipId != clip.id {
            dragInitialTimelineRange = clip.timelineRange
            dragInitialSourceRange = clip.sourceRange
        }
        isDragging = true
        draggedClipId = clip.id
        viewModel.selectedClipId = clip.id
    }

    private func endClipDrag() {
        dragOffset = 0
        isDragging = false
        draggedClipId = nil
        dragInitialTimelineRange = nil
        dragInitialSourceRange = nil
    }

    private func commitMove(for clipId: UUID) {
        guard let clip = clip(for: clipId) else { return }
        let trackId = trackId(containing: clipId)

        Task {
            await viewModel.moveClip(
                clipId: clipId,
                sourceTrackId: trackId,
                targetTrackId: trackId,
                timelineRange: clip.timelineRange
            )
        }
    }

    private func commitTrim(for clipId: UUID) {
        guard let clip = clip(for: clipId) else { return }
        let trackId = trackId(containing: clipId)

        Task {
            await viewModel.trimClip(
                clipId: clipId,
                trackId: trackId,
                sourceRange: clip.sourceRange,
                timelineRange: clip.timelineRange
            )
        }
    }

    private func updateClip(_ clipId: UUID, sourceRange: TimeRange? = nil, timelineRange: TimeRange) {
        for trackIndex in viewModel.currentProject.timeline.tracks.indices {
            guard let clipIndex = viewModel.currentProject.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipId }) else {
                continue
            }

            if let sourceRange {
                viewModel.currentProject.timeline.tracks[trackIndex].clips[clipIndex].sourceRange = sourceRange
            }
            viewModel.currentProject.timeline.tracks[trackIndex].clips[clipIndex].timelineRange = timelineRange
            return
        }
    }

    private func clip(for clipId: UUID) -> Clip? {
        viewModel.currentProject.timeline.tracks
            .flatMap(\.clips)
            .first { $0.id == clipId }
    }

    private func trackId(containing clipId: UUID) -> UUID? {
        viewModel.currentProject.timeline.tracks.first { track in
            track.clips.contains { $0.id == clipId }
        }?.id
    }

    private func allClips(excluding clipId: UUID) -> [Clip] {
        viewModel.currentProject.timeline.tracks
            .flatMap(\.clips)
            .filter { $0.id != clipId }
    }

    private func snappedTime(_ rawTime: Double, allClips: [Clip], threshold: Double = 5.0) -> Double {
        let snapPoints = allClips.flatMap { [$0.timelineRange.start, $0.timelineRange.start + $0.timelineRange.duration] }
            + [viewModel.playheadTime, 0.0]
        let thresholdTime = threshold / pixelsPerSecond
        for point in snapPoints {
            if abs(rawTime - point) < thresholdTime {
                return point
            }
        }
        return rawTime
    }

    private func colorForClip(trackKind: TrackKind, selected: Bool) -> Color {
        switch trackKind {
        case .video: return selected ? .blue : .blue.opacity(0.6)
        case .audio: return selected ? .green : .green.opacity(0.6)
        case .text: return selected ? .orange : .orange.opacity(0.6)
        }
    }

    private func clipLabel(_ clip: Clip) -> String {
        if let textContent = clip.textContent {
            return String(textContent.text.prefix(20))
        }
        return String(describing: clip.kind)
    }

    private func timelineSecondsString(_ time: TimeInterval) -> String {
        String(format: NSLocalizedString("%.2fs", comment: ""), time)
    }
}
