import SwiftUI
import MovieCutCore

struct PreviewPanel: View {
    var viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black

                if let clip = viewModel.selectedClip {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 4) {
                                Image(systemName: "play.rectangle")
                                    .font(.largeTitle)
                                    .foregroundStyle(.white.opacity(0.5))
                                Text(clip.kind.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                } else {
                    Text("No clip selected")
                        .foregroundStyle(.white.opacity(0.4))
                        .font(.title3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                Text(timecodeString(viewModel.playheadTime))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 80)

                Spacer()

                Button(action: { viewModel.isPlaying.toggle() }) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderless)
                .font(.title3)

                Button(action: {
                    viewModel.playheadTime = max(0, viewModel.playheadTime - 1.0 / 30.0)
                }) {
                    Image(systemName: "backward.frame")
                }
                .buttonStyle(.borderless)

                Button(action: {
                    viewModel.playheadTime += 1.0 / 30.0
                }) {
                    Image(systemName: "forward.frame")
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(timecodeString(viewModel.currentProject.timeline.duration))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 80)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
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
