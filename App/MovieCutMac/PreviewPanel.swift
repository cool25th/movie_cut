import SwiftUI
import MovieCutCore

struct PreviewPanel: View {
    var viewModel: EditorViewModel
    @State private var playbackEngine: PlaybackEngine
    @State private var loadedAssetId: UUID?

    init(viewModel: EditorViewModel) {
        self.viewModel = viewModel
        _playbackEngine = State(initialValue: viewModel.playbackEngine)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black

                if let clip = viewModel.selectedClip {
                    VideoPreviewView(player: playbackEngine.player)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay {
                            if clip.assetId == nil {
                                clipPlaceholder(for: clip)
                            }
                        }
                } else {
                    Text("No clip selected")
                        .foregroundStyle(.white.opacity(0.4))
                        .font(.title3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                loadSelectedClipAsset()
            }
            .onChange(of: viewModel.selectedClipId) { _, _ in
                loadSelectedClipAsset()
            }
            .onChange(of: playbackEngine.currentTime) { _, currentTime in
                syncTimelinePlayhead(to: currentTime)
            }

            HStack(spacing: 12) {
                Text(timecodeString(playbackEngine.currentTime))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 80)

                Spacer()

                Button(action: { playbackEngine.togglePlayPause() }) {
                    Image(systemName: playbackEngine.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderless)
                .font(.title3)
                .disabled(playbackEngine.playerItem == nil)

                Button(action: {
                    seekByFrames(-1)
                }) {
                    Image(systemName: "backward.frame")
                }
                .buttonStyle(.borderless)
                .disabled(playbackEngine.playerItem == nil)

                Button(action: {
                    seekByFrames(1)
                }) {
                    Image(systemName: "forward.frame")
                }
                .buttonStyle(.borderless)
                .disabled(playbackEngine.playerItem == nil)

                Spacer()

                Text(timecodeString(playbackEngine.duration))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 80)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func clipPlaceholder(for clip: Clip) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "play.rectangle")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.5))
            Text(clip.kind.rawValue)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func loadSelectedClipAsset() {
        guard
            let clip = viewModel.selectedClip,
            let assetId = clip.assetId,
            let asset = viewModel.currentProject.mediaLibrary.assets[assetId]
        else {
            loadedAssetId = nil
            playbackEngine.clear()
            return
        }

        if loadedAssetId != asset.id {
            playbackEngine.load(asset: asset)
            loadedAssetId = asset.id
        }

        playbackEngine.seek(to: clip.sourceRange.start)
        syncTimelinePlayhead(to: clip.sourceRange.start)
    }

    private func seekByFrames(_ frameCount: Int) {
        let frameDuration = 1.0 / 30.0
        let nextTime = playbackEngine.currentTime + (Double(frameCount) * frameDuration)
        playbackEngine.seek(to: nextTime)
        syncTimelinePlayhead(to: nextTime)
    }

    private func syncTimelinePlayhead(to playbackTime: TimeInterval) {
        guard let clip = viewModel.selectedClip else {
            viewModel.playheadTime = playbackTime
            return
        }

        let sourceOffset = max(0, playbackTime - clip.sourceRange.start)
        let timelineTime = clip.timelineRange.start + sourceOffset
        viewModel.playheadTime = min(timelineTime, clip.timelineRange.end)
    }

    private func timecodeString(_ time: TimeInterval) -> String {
        let t = max(0, time)
        let totalSeconds = Int(t)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let frames = Int((t - Double(totalSeconds)) * 30)
        return String(format: "%02d:%02d:%02d", minutes, seconds, abs(frames))
    }
}
