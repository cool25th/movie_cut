import SwiftUI
import MovieCutCore

struct MusicLibraryView: View {
    var viewModel: EditorViewModel

    @State private var searchQuery = ""
    @State private var previewTrackId: UUID?
    @State private var previewEngine: PlaybackEngine

    init(viewModel: EditorViewModel) {
        self.viewModel = viewModel
        _previewEngine = State(initialValue: PlaybackEngine())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search music", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 8)

            if filteredTracks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No matching tracks")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredTracks) { track in
                    HStack(spacing: 8) {
                        Button {
                            togglePreview(for: track)
                        } label: {
                            Image(systemName: previewIcon(for: track))
                        }
                        .buttonStyle(.borderless)
                        .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.caption)
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if !track.tags.isEmpty {
                                Text(track.tags.joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(durationText(track.duration))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Button("Add") {
                                Task { await viewModel.addMusicTrack(track) }
                            }
                            .controlSize(.mini)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
    }

    private var filteredTracks: [MusicTrack] {
        viewModel.musicLibrary.search(query: searchQuery)
    }

    private func togglePreview(for track: MusicTrack) {
        if previewTrackId == track.id, previewEngine.isPlaying {
            previewEngine.pause()
            return
        }

        let asset = MediaAsset(
            originalURL: track.fileURL,
            kind: .audio,
            duration: track.duration
        )
        previewEngine.load(asset: asset)
        previewEngine.play()
        previewTrackId = track.id
    }

    private func previewIcon(for track: MusicTrack) -> String {
        previewTrackId == track.id && previewEngine.isPlaying ? "pause.fill" : "play.fill"
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
