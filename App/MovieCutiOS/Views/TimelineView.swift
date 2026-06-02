import SwiftUI
import MovieCutCore

struct TimelineView: View {
    @Bindable var viewModel: IOSEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button("Split", systemImage: "scissors") {
                    Task {
                        await viewModel.splitClip()
                    }
                }
                .disabled(viewModel.selectedClipId == nil)

                Button("Delete", systemImage: "trash", role: .destructive) {
                    Task {
                        await viewModel.deleteClip()
                    }
                }
                .disabled(viewModel.selectedClipId == nil)
            }
            .buttonStyle(.bordered)

            ScrollView(.vertical) {
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.currentProject.timeline.tracks) { track in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(track.name)
                                    .font(.headline)

                                HStack(spacing: 8) {
                                    ForEach(track.clips) { clip in
                                        clipCard(clip)
                                    }
                                }
                                .frame(minHeight: 64, alignment: .leading)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
    }

    private func clipCard(_ clip: Clip) -> some View {
        let isSelected = viewModel.selectedClipId == clip.id

        return ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(fillColor(for: clip.kind))

            HStack(spacing: 6) {
                Image(systemName: iconName(for: clip.kind))
                Text(durationText(clip.timelineRange.duration))
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
        }
        .frame(width: width(for: clip), height: 52)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
        }
        .onTapGesture {
            viewModel.selectedClipId = clip.id
            viewModel.playheadTime = clip.timelineRange.start
        }
    }

    private func width(for clip: Clip) -> CGFloat {
        max(96, min(240, clip.timelineRange.duration * 32))
    }

    private func fillColor(for kind: ClipKind) -> Color {
        switch kind {
        case .video: .indigo
        case .audio: .teal
        case .image: .orange
        case .text: .gray
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

    private func durationText(_ duration: TimeInterval) -> String {
        String(format: "%.1fs", duration)
    }
}
