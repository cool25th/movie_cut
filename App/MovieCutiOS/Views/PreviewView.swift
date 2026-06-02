import SwiftUI
import MovieCutCore

struct PreviewView: View {
    @Bindable var viewModel: IOSEditorViewModel

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Rectangle()
                    .fill(.black)

                if viewModel.selectedClip == nil {
                    Text("No media loaded")
                        .foregroundStyle(.white.secondary)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 12) {
                Button {
                    viewModel.togglePlayPause()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Text("\(timeText(viewModel.playheadTime)) / \(timeText(viewModel.currentProject.timeline.duration))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()
            }
        }
        .padding()
    }

    private func timeText(_ time: TimeInterval) -> String {
        let clampedTime = max(0, time)
        let minutes = Int(clampedTime) / 60
        let seconds = Int(clampedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
