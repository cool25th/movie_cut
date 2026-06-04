import SwiftUI
import MovieCutCore

struct PreviewPanel: View {
    var viewModel: EditorViewModel
    @State private var playbackEngine: PlaybackEngine
    @State private var loadedAssetId: UUID?
    @State private var previewVolume: Double = 1

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
                        .aspectRatio(canvasAspectRatio, contentMode: .fit)
                        .overlay {
                            if clip.assetId == nil {
                                clipPlaceholder(for: clip)
                            }
                        }
                } else {
                    Text(NSLocalizedString("No clip selected", comment: ""))
                        .foregroundStyle(.white.opacity(0.4))
                        .font(.title3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(NSLocalizedString("Preview", comment: ""))
            .accessibilityValue(previewAccessibilityValue)
            .task {
                loadSelectedClipAsset()
            }
            .onChange(of: viewModel.selectedClipId) { _, _ in
                loadSelectedClipAsset()
            }
            .onChange(of: viewModel.selectedClip?.playbackRate) { _, playbackRate in
                playbackEngine.setRate(Float(playbackRate ?? 1))
            }
            .onChange(of: playbackEngine.currentTime) { _, currentTime in
                syncTimelinePlayhead(to: currentTime)
            }

            HStack(spacing: 12) {
                Text(timecodeString(playbackEngine.currentTime))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 80)
                    .accessibilityElement()
                    .accessibilityLabel(NSLocalizedString("Current Time", comment: ""))
                    .accessibilityValue(timecodeString(playbackEngine.currentTime))

                Spacer()

                Button(action: { playbackEngine.togglePlayPause() }) {
                    Image(systemName: playbackEngine.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderless)
                .font(.title3)
                .disabled(playbackEngine.playerItem == nil)
                .accessibilityLabel(playbackEngine.isPlaying ? NSLocalizedString("Pause", comment: "") : NSLocalizedString("Play", comment: ""))
                .accessibilityHint(NSLocalizedString("Starts or pauses preview playback.", comment: ""))

                Button(action: {
                    seekByFrames(-1)
                }) {
                    Image(systemName: "backward.frame")
                }
                .buttonStyle(.borderless)
                .disabled(playbackEngine.playerItem == nil)
                .accessibilityLabel(NSLocalizedString("Seek Back One Frame", comment: ""))
                .accessibilityHint(NSLocalizedString("Moves the playhead back by one frame.", comment: ""))

                Button(action: {
                    seekByFrames(1)
                }) {
                    Image(systemName: "forward.frame")
                }
                .buttonStyle(.borderless)
                .disabled(playbackEngine.playerItem == nil)
                .accessibilityLabel(NSLocalizedString("Seek Forward One Frame", comment: ""))
                .accessibilityHint(NSLocalizedString("Moves the playhead forward by one frame.", comment: ""))

                Spacer()

                Text(timecodeString(playbackEngine.duration))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 80)
                    .foregroundStyle(.secondary)
                    .accessibilityElement()
                    .accessibilityLabel(NSLocalizedString("Duration", comment: ""))
                    .accessibilityValue(timecodeString(playbackEngine.duration))

                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Slider(value: Binding(
                        get: { previewVolume },
                        set: { newValue in
                            previewVolume = newValue
                            playbackEngine.player.volume = Float(newValue)
                        }
                    ), in: 0 ... 1)
                    .frame(width: 84)
                    .accessibilityLabel(NSLocalizedString("Volume", comment: ""))
                    .accessibilityValue(String(format: NSLocalizedString("%.0f%%", comment: ""), previewVolume * 100))
                    .accessibilityHint(NSLocalizedString("Adjusts preview playback volume.", comment: ""))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .accessibilityElement(children: .contain)
        }
    }

    private var canvasAspectRatio: CGFloat {
        let size = viewModel.currentProject.canvas.size
        return size.width / max(size.height, 1)
    }

    private func clipPlaceholder(for clip: Clip) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "play.rectangle")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.5))
            Text(String(describing: clip.kind))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var previewAccessibilityValue: String {
        if let clip = viewModel.selectedClip {
            return String(format: NSLocalizedString("Selected clip %@", comment: ""), String(describing: clip.kind))
        }
        return NSLocalizedString("No clip selected", comment: "")
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

        playbackEngine.setRate(Float(clip.playbackRate))
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
        let timelineOffset = sourceOffset / max(clip.playbackRate, 0.25)
        let timelineTime = clip.timelineRange.start + timelineOffset
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
