import AppKit
import SwiftUI
import MovieCutCore
import UniformTypeIdentifiers

extension UTType {
    static let movieCutMediaAssetID = UTType(exportedAs: "com.moviecut.media-asset-id")
}

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
    private let markerLabelWidth: CGFloat = 132

    private var pixelsPerSecond: Double {
        viewModel.timelineZoom
    }

    private var sortedMarkers: [Marker] {
        viewModel.currentProject.markers.sorted { $0.time < $1.time }
    }

    private var timelineContentWidth: CGFloat {
        let markerEnd = sortedMarkers.map(\.time).max() ?? 0
        let visibleSeconds = max(viewModel.visibleTimelineDuration, markerEnd + 2)
        return max(900, CGFloat(visibleSeconds) * CGFloat(pixelsPerSecond) + markerLabelWidth)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(NSLocalizedString("Timeline", comment: ""))
                    .font(.headline)
                if !sortedMarkers.isEmpty {
                    Text("\(sortedMarkers.count) markers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if viewModel.hasSelectedClips {
                    Divider()
                        .frame(height: 16)
                    selectedClipToolbar
                }
                Spacer()
                Button(action: { viewModel.goToPreviousMarker() }) {
                    Image(systemName: "backward.end.fill")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.previousMarker == nil)
                .help("Previous Marker")
                Button(action: { viewModel.goToNextMarker() }) {
                    Image(systemName: "forward.end.fill")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.nextMarker == nil)
                .help("Next Marker")
                Button(action: { viewModel.zoomTimelineOut() }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(NSLocalizedString("타임라인 축소", comment: ""))
                .accessibilityHint(NSLocalizedString("Zooms the timeline out.", comment: ""))
                Button(action: { viewModel.zoomTimelineIn() }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(NSLocalizedString("타임라인 확대", comment: ""))
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
        // Header (~28) + ruler (24) + 3 default track lanes (3 x 50) must stay visible.
        .frame(minHeight: 210)
        .background(Color(nsColor: .textBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NSLocalizedString("타임라인", comment: ""))
    }

    private var selectedClipToolbar: some View {
        HStack(spacing: 4) {
            Button {
                viewModel.snapPlayheadToSelectedClipStart()
            } label: {
                Image(systemName: "arrow.left.to.line.compact")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.selectedClip == nil)
            .help("Snap Playhead to Clip Start")

            Button {
                viewModel.snapPlayheadToSelectedClipEnd()
            } label: {
                Image(systemName: "arrow.right.to.line.compact")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.selectedClip == nil)
            .help("Snap Playhead to Clip End")

            Button {
                Task { await viewModel.splitClip() }
            } label: {
                Image(systemName: "scissors")
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.canSplitSelectedClip)
            .help("Split at Playhead")

            Button {
                Task { await viewModel.duplicateSelectedClips() }
            } label: {
                Image(systemName: "square.on.square")
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.hasSelectedClips)
            .help("Duplicate Selected Clips")

            Button {
                Task { await viewModel.sendSelectedClipLayerToBack() }
            } label: {
                Image(systemName: "arrow.down.to.line")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.selectedClip == nil)
            .help("Send Selected Clip to Back")

            Button {
                Task { await viewModel.bringSelectedClipLayerToFront() }
            } label: {
                Image(systemName: "arrow.up.to.line")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.selectedClip == nil)
            .help("Bring Selected Clip to Front")

            Button {
                Task { await viewModel.deleteClip() }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.hasSelectedClips)
            .help("Delete Selected Clips")

            Button {
                Task { await viewModel.rippleDeleteSelectedClip() }
            } label: {
                Image(systemName: "delete.left")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.selectedClip == nil)
            .help("Ripple Delete Selected Clip")
        }
        .font(.caption)
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

            ZStack(alignment: .topLeading) {
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
                .frame(width: timelineContentWidth, height: rulerHeight)

                ForEach(sortedMarkers) { marker in
                    if marker.kind == .beat {
                        // Beat markers render as compact ticks: a full flag per
                        // beat would flood the ruler on real music tracks.
                        Rectangle()
                            .fill(Color.orange.opacity(0.85))
                            .frame(width: 2, height: rulerHeight / 3)
                            .offset(x: markerX(marker), y: rulerHeight * 2 / 3)
                            .onTapGesture {
                                viewModel.goToMarker(marker)
                            }
                            .help(markerHelp(marker))
                            .accessibilityLabel(NSLocalizedString("비트 마커", comment: ""))
                            .accessibilityValue(timelineSecondsString(marker.time))
                    } else {
                        TimelineMarkerFlag(marker: marker)
                            .frame(width: markerLabelWidth, height: rulerHeight, alignment: .leading)
                            .offset(x: markerX(marker), y: 0)
                            .onTapGesture {
                                viewModel.goToMarker(marker)
                            }
                            .help(markerHelp(marker))
                    }
                }
            }
            .frame(width: timelineContentWidth, height: rulerHeight, alignment: .leading)
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel(trackHeaderAccessibilityLabel(for: track))

            // Clips area
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(nsColor: .textBackgroundColor))

                ForEach(clipsForDisplay(track)) { clip in
                    clipView(clip, trackKind: track.kind)
                }

                // Auto-cut preview: ranges scheduled for removal (F-18).
                ForEach(Array(viewModel.autoCutPreviewRanges.enumerated()), id: \.offset) { _, range in
                    Rectangle()
                        .fill(Color.red.opacity(0.28))
                        .overlay(Rectangle().strokeBorder(Color.red.opacity(0.7), lineWidth: 1))
                        .frame(width: max(1, CGFloat(range.duration) * CGFloat(pixelsPerSecond)), height: trackHeight)
                        .offset(x: CGFloat(range.start) * CGFloat(pixelsPerSecond))
                        .allowsHitTesting(false)
                        .accessibilityLabel(NSLocalizedString("자동 컷 제거 예정 구간", comment: ""))
                }

                ForEach(sortedMarkers.filter { $0.kind != .beat }) { marker in
                    TimelineMarkerLine(marker: marker, height: trackHeight)
                        .offset(x: markerX(marker))
                        .onTapGesture {
                            viewModel.goToMarker(marker)
                        }
                        .help(markerHelp(marker))
                }

                // Playhead
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2)
                    .offset(x: CGFloat(viewModel.playheadTime) * CGFloat(pixelsPerSecond))
                    .accessibilityElement()
                    .accessibilityLabel(NSLocalizedString("재생 헤드", comment: ""))
                    .accessibilityValue(timelineSecondsString(viewModel.playheadTime))

            }
            .frame(width: timelineContentWidth, height: trackHeight, alignment: .leading)
            .onDrop(of: [.fileURL, .movie, .image, .movieCutMediaAssetID], isTargeted: nil) { providers, location in
                handleTrackDrop(providers: providers, location: location, trackId: track.id)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(format: NSLocalizedString("%@ 클립 추가 영역", comment: ""), trackHeaderAccessibilityLabel(for: track)))
            .accessibilityHint(NSLocalizedString("Drop media files or library assets here to add clips at the drop position.", comment: ""))
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
                .fill(colorForClip(clip: clip, trackKind: trackKind, selected: isSelected))
                .overlay {
                    clipMediaBackground(for: clip, trackKind: trackKind, selected: isSelected)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .overlay(alignment: .leading) {
                    Text(clipLabel(clip))
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
                .overlay(alignment: .trailing) {
                    HStack(spacing: 2) {
                        if clip.groupId != nil {
                            Image(systemName: "link")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.85))
                                .accessibilityLabel(NSLocalizedString("Linked clip", comment: ""))
                        }
                        if isStickerClip(clip) {
                            Image(systemName: "face.smiling")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .padding(.trailing, 4)
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.9), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
                .gesture(moveGesture(for: clip))
                .accessibilityElement()
                .accessibilityLabel(clipAccessibilityLabel(for: clip))
                .accessibilityValue(
                    String(
                        format: NSLocalizedString("Starts at %@, duration %@, layer %d", comment: ""),
                        timelineSecondsString(clip.timelineRange.start),
                        timelineSecondsString(clip.timelineRange.duration),
                        clip.zIndex
                    )
                )
                .accessibilityHint(NSLocalizedString("Selects the clip. Drag to move it on the timeline. Layer actions adjust its zIndex.", comment: ""))
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
                    .accessibilityLabel(String(format: NSLocalizedString("%@ 왼쪽 트림 핸들", comment: ""), clipAccessibilityLabel(for: clip)))
                    .accessibilityHint(NSLocalizedString("Drag to trim the clip start.", comment: ""))

                Spacer(minLength: 0)

                Rectangle()
                    .fill(Color.clear)
                    .frame(width: trimHandleWidth)
                    .contentShape(Rectangle())
                    .gesture(rightTrimGesture(for: clip))
                    .accessibilityElement()
                    .accessibilityLabel(String(format: NSLocalizedString("%@ 오른쪽 트림 핸들", comment: ""), clipAccessibilityLabel(for: clip)))
                    .accessibilityHint(NSLocalizedString("Drag to trim the clip end.", comment: ""))
            }
        }
            .frame(width: max(2, width), height: trackHeight - 8)
            .offset(x: x, y: 4)
            .zIndex(Double(clip.zIndex) + (isActiveDrag || isSelected ? 10_000 : 0))
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .highPriorityGesture(
                TapGesture()
                    .modifiers(.command)
                    .onEnded {
                        selectClip(clip.id, extendingSelection: true)
                    }
            )
            .onTapGesture {
                selectClip(clip.id, extendingSelection: false)
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
                Button(NSLocalizedString("Group Clips", comment: "")) {
                    _ = contextMenuClipIds(anchor: clip.id)
                    Task { await viewModel.groupSelectedClips() }
                }
                .disabled(!viewModel.canGroupSelectedClips && !viewModel.selectedClipIds.contains(clip.id))
                Button(NSLocalizedString("Ungroup Clips", comment: "")) {
                    _ = contextMenuClipIds(anchor: clip.id)
                    Task { await viewModel.ungroupSelectedClips() }
                }
                .disabled(clip.groupId == nil && !viewModel.hasGroupedSelection)
                Divider()
                Button("Snap Playhead to Start") {
                    selectClip(clip.id, extendingSelection: false)
                    viewModel.snapPlayheadToSelectedClipStart()
                }
                Button("Snap Playhead to End") {
                    selectClip(clip.id, extendingSelection: false)
                    viewModel.snapPlayheadToSelectedClipEnd()
                }
                Divider()
                Button("Bring to Front") {
                    selectClip(clip.id, extendingSelection: false)
                    Task { await viewModel.bringSelectedClipLayerToFront() }
                }
                Button("Send to Back") {
                    selectClip(clip.id, extendingSelection: false)
                    Task { await viewModel.sendSelectedClipLayerToBack() }
                }
                Divider()
                Button(NSLocalizedString("Ripple Delete", comment: "")) {
                    selectClip(clip.id, extendingSelection: false)
                    Task { await viewModel.rippleDeleteClip(clipId: clip.id) }
                }
            }
    }

    @ViewBuilder
    private func clipMediaBackground(for clip: Clip, trackKind: TrackKind, selected: Bool) -> some View {
        if let image = thumbnailImage(for: clip) {
            thumbnailStrip(image)
            Color.black.opacity(selected ? 0.28 : 0.16)
                .allowsHitTesting(false)
        } else if shouldRenderWaveform(for: clip, trackKind: trackKind) {
            waveformCanvas(for: clip)
        }
    }

    private func thumbnailImage(for clip: Clip) -> NSImage? {
        guard
            clip.kind == .video || clip.kind == .image,
            let thumbnailData = viewModel.thumbnailData(for: clip)
        else {
            return nil
        }

        return NSImage(data: thumbnailData)
    }

    private func thumbnailStrip(_ image: NSImage) -> some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            let tileWidth = min(max(height * 16 / 9, 44), 72)
            let tileCount = max(1, Int(ceil(max(proxy.size.width, tileWidth) / tileWidth)))

            HStack(spacing: 1) {
                ForEach(0..<tileCount, id: \.self) { _ in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: tileWidth, height: height)
                        .clipped()
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func shouldRenderWaveform(for clip: Clip, trackKind: TrackKind) -> Bool {
        trackKind != .text && (clip.kind == .audio || clip.kind == .video)
    }

    private func waveformCanvas(for clip: Clip) -> some View {
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

    @MainActor
    private func selectClip(_ clipId: UUID, extendingSelection: Bool) {
        viewModel.selectTimelineClip(clipId, extendSelection: extendingSelection)
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

    private func clipsForDisplay(_ track: Track) -> [Clip] {
        track.clipsForLayerDisplay
    }

    private func snappedTime(_ rawTime: Double, allClips: [Clip], threshold: Double = 5.0) -> Double {
        let snapPoints = allClips.flatMap { [$0.timelineRange.start, $0.timelineRange.start + $0.timelineRange.duration] }
            + sortedMarkers.map(\.time)
            + [viewModel.playheadTime, 0.0]
        let thresholdTime = threshold / pixelsPerSecond
        for point in snapPoints {
            if abs(rawTime - point) < thresholdTime {
                return point
            }
        }
        return rawTime
    }

    private func colorForClip(clip: Clip, trackKind: TrackKind, selected: Bool) -> Color {
        if isStickerClip(clip) {
            return selected ? .pink : .pink.opacity(0.68)
        }

        switch trackKind {
        case .video: return selected ? .blue : .blue.opacity(0.6)
        case .audio: return selected ? .green : .green.opacity(0.6)
        case .text: return selected ? .orange : .orange.opacity(0.6)
        }
    }

    private func clipLabel(_ clip: Clip) -> String {
        if let textContent = clip.textContent {
            if isStickerClip(clip) {
                return "Sticker \(textContent.text)"
            }
            return String(textContent.text.prefix(20))
        }
        return String(describing: clip.kind)
    }

    private func isStickerClip(_ clip: Clip) -> Bool {
        guard clip.kind == .text, let textContent = clip.textContent else {
            return false
        }

        return textContent.isSticker || textContent.fontFamily == "Apple Color Emoji"
    }

    private func markerX(_ marker: Marker) -> CGFloat {
        CGFloat(marker.time) * CGFloat(pixelsPerSecond)
    }

    private func markerHelp(_ marker: Marker) -> String {
        "\(marker.name) at \(timelineSecondsString(marker.time))"
    }

    private func clipAccessibilityLabel(for clip: Clip) -> String {
        switch clip.kind {
        case .video, .image:
            return NSLocalizedString("비디오 클립", comment: "")
        case .audio:
            return NSLocalizedString("오디오 클립", comment: "")
        case .text:
            if isStickerClip(clip) {
                return NSLocalizedString("스티커 클립", comment: "")
            }
            return NSLocalizedString("텍스트 클립", comment: "")
        }
    }

    private func trackHeaderAccessibilityLabel(for track: Track) -> String {
        switch track.kind {
        case .video:
            return NSLocalizedString("비디오 트랙 헤더", comment: "")
        case .audio:
            return NSLocalizedString("오디오 트랙 헤더", comment: "")
        case .text:
            return NSLocalizedString("텍스트 트랙 헤더", comment: "")
        }
    }

    private func timelineSecondsString(_ time: TimeInterval) -> String {
        String(format: NSLocalizedString("%.2fs", comment: ""), time)
    }

    /// Closure-based drop handling. The previous DropDelegate-based registration
    /// silently rejected live Finder drags on macOS, so timeline drops share the
    /// same onDrop(of:isTargeted:perform:) path that the media library uses.
    private func handleTrackDrop(providers: [NSItemProvider], location: CGPoint, trackId: UUID) -> Bool {
        let startTime = max(0, Double(location.x) / max(pixelsPerSecond, 1))

        let assetProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.movieCutMediaAssetID.identifier)
        }
        if !assetProviders.isEmpty {
            TimelineDropPayloadLoader.loadAssetIDs(from: assetProviders) { assetIds in
                guard !assetIds.isEmpty else {
                    Task { @MainActor in
                        viewModel.reportInvalidTimelineLibraryAssetDrop()
                    }
                    return
                }
                Task { @MainActor in
                    await viewModel.addImportedAssetsToTimeline(
                        assetIds,
                        preferredTrackId: trackId,
                        startTime: startTime
                    )
                }
            }
            return true
        }

        let externalProviders = providers.filter {
            DragDropHandler.providesExternalMedia($0)
        }
        guard !externalProviders.isEmpty else {
            Task { @MainActor in
                viewModel.reportUnsupportedTimelineDrop()
            }
            return false
        }
        DragDropHandler.loadExternalMediaURLs(from: externalProviders) { urls in
            guard !urls.isEmpty else {
                Task { @MainActor in
                    viewModel.reportInvalidTimelineFileDrop()
                }
                return
            }
            Task { @MainActor in
                await viewModel.importMediaAndAddToTimeline(
                    urls,
                    preferredTrackId: trackId,
                    startTime: startTime
                )
            }
        }
        return true
    }
}

private enum TimelineDropPayloadLoader {
    static func loadAssetIDs(from providers: [NSItemProvider], completion: @escaping ([UUID]) -> Void) {
        guard !providers.isEmpty else {
            completion([])
            return
        }

        let accumulator = OrderedDropPayloadAccumulator<UUID>(count: providers.count, completion: completion)
        for (index, provider) in providers.enumerated() {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.movieCutMediaAssetID.identifier) { data, _ in
                let id = data
                    .flatMap { String(data: $0, encoding: .utf8) }
                    .flatMap { UUID(uuidString: $0) }
                accumulator.complete(index: index, value: id)
            }
        }
    }
}

private final class OrderedDropPayloadAccumulator<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Value?]
    private var remaining: Int
    private let completion: ([Value]) -> Void

    init(count: Int, completion: @escaping ([Value]) -> Void) {
        self.values = Array(repeating: nil, count: count)
        self.remaining = count
        self.completion = completion
    }

    func complete(index: Int, value: Value?) {
        let finishedValues: [Value]?
        lock.lock()
        values[index] = value
        remaining -= 1
        finishedValues = remaining == 0 ? values.compactMap { $0 } : nil
        lock.unlock()

        if let finishedValues {
            completion(finishedValues)
        }
    }
}

private struct TimelineMarkerFlag: View {
    var marker: Marker

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flag.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 0) {
                Text(marker.name)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                Text(String(format: "%.1fs", marker.time))
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(marker.name), \(String(format: "%.1fs", marker.time))")
    }
}

private struct TimelineMarkerLine: View {
    var marker: Marker
    var height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(Color.yellow)
                .frame(width: 8, height: 6)
            Rectangle()
                .fill(Color.yellow.opacity(0.72))
                .frame(width: 2, height: max(0, height - 6))
        }
        .frame(width: 8, height: height)
        .offset(x: -4)
        .accessibilityElement()
        .accessibilityLabel("\(marker.name), \(String(format: "%.1fs", marker.time))")
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
