import AVFoundation
import SwiftUI
import MovieCutCore

struct MusicLibraryView: View {
    var viewModel: EditorViewModel

    @State private var searchQuery = ""
    @State private var previewTrackId: UUID?
    @State private var hoverPreviewTrackId: UUID?
    @State private var previewPlayer: AVAudioPlayer?

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
                    .onHover { isHovering in
                        if isHovering {
                            startHoverPreview(for: track)
                        } else {
                            stopHoverPreview(for: track)
                        }
                    }
                    .accessibilityHint("Hover to listen. Use the preview button to toggle playback, or Add to place this track on the timeline.")
                }
                .listStyle(.plain)
            }
        }
        .onDisappear {
            stopPreview()
        }
    }

    private var filteredTracks: [MovieCutCore.MusicTrack] {
        viewModel.musicLibrary.search(query: searchQuery)
    }

    private func togglePreview(for track: MovieCutCore.MusicTrack) {
        if previewTrackId == track.id, let player = previewPlayer, player.isPlaying {
            player.pause()
            hoverPreviewTrackId = nil
            return
        }

        hoverPreviewTrackId = nil
        startPreview(for: track)
    }

    private func startHoverPreview(for track: MovieCutCore.MusicTrack) {
        guard !isPreviewing(track) else { return }

        startPreview(for: track)
        if isPreviewing(track) {
            hoverPreviewTrackId = track.id
        }
    }

    private func stopHoverPreview(for track: MovieCutCore.MusicTrack) {
        guard hoverPreviewTrackId == track.id else { return }
        stopPreview()
    }

    private func startPreview(for track: MovieCutCore.MusicTrack) {
        stopPreview()
        do {
            let player = try AVAudioPlayer(contentsOf: track.fileURL)
            player.numberOfLoops = 0
            player.prepareToPlay()
            player.play()
            previewPlayer = player
            previewTrackId = track.id
        } catch {
            previewPlayer = nil
            previewTrackId = nil
            hoverPreviewTrackId = nil
        }
    }

    private func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        previewTrackId = nil
        hoverPreviewTrackId = nil
    }

    private func previewIcon(for track: MovieCutCore.MusicTrack) -> String {
        if isPreviewing(track) {
            return "pause.fill"
        }
        return "play.fill"
    }

    private func isPreviewing(_ track: MovieCutCore.MusicTrack) -> Bool {
        previewTrackId == track.id && (previewPlayer?.isPlaying ?? false)
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
