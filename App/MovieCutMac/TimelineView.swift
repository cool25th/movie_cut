import SwiftUI
import MovieCutCore

struct TimelineView: View {
    var viewModel: EditorViewModel

    private let trackHeight: CGFloat = 50
    private let rulerHeight: CGFloat = 24

    private var pixelsPerSecond: Double {
        viewModel.timelineZoom
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Timeline")
                    .font(.headline)
                Spacer()
                Button(action: { viewModel.timelineZoom = max(20, viewModel.timelineZoom - 20) }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                Button(action: { viewModel.timelineZoom = min(300, viewModel.timelineZoom + 20) }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
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
    }

    private var timeRuler: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .frame(width: 80, height: rulerHeight)
                .overlay(alignment: .leading) {
                    Text("Time")
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
            }
        }
        .frame(height: trackHeight)
        .overlay(alignment: .bottom) { Divider() }
    }

    @MainActor
    private func clipView(_ clip: Clip, trackKind: TrackKind) -> some View {
        let x = CGFloat(clip.timelineRange.start) * CGFloat(pixelsPerSecond)
        let width = CGFloat(clip.timelineRange.duration) * CGFloat(pixelsPerSecond)
        let isSelected = clip.id == viewModel.selectedClipId

        return RoundedRectangle(cornerRadius: 4)
            .fill(colorForClip(trackKind: trackKind, selected: isSelected))
            .frame(width: max(2, width), height: trackHeight - 8)
            .offset(x: x, y: 4)
            .overlay(alignment: .leading) {
                Text(clipLabel(clip))
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.selectedClipId = clip.id
            }
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
        return clip.kind.rawValue
    }
}
