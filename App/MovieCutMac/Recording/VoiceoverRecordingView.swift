import SwiftUI
import MovieCutCore

struct VoiceoverRecordingView: View {
    var viewModel: EditorViewModel

    @State private var isRecording = false
    @State private var elapsedTime: TimeInterval = 0
    @State private var audioLevel: Float = 0
    @State private var recorder: VoiceoverRecorder?

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voiceover Recording")
                .font(.headline)

            if isRecording {
                recordingIndicator
            }

            audioLevelMeter

            HStack(spacing: 16) {
                if !isRecording {
                    Button(action: startRecording) {
                        Label("Record", systemImage: "record.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button(action: stopRecording) {
                        Label("Stop", systemImage: "stop.circle")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: cancelRecording) {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var recordingIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .opacity(isRecording ? 1 : 0.3)

            Text(timeString(from: elapsedTime))
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .onReceive(timer) { _ in
            if let recorder {
                elapsedTime = recorder.currentTime
                audioLevel = recorder.audioLevel
            }
        }
    }

    @ViewBuilder
    private var audioLevelMeter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Input Level")
                .font(.caption)
                .foregroundStyle(.secondary)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Rectangle()
                        .fill(levelColor)
                        .frame(width: geometry.size.width * CGFloat(audioLevel))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .frame(height: 8)
        }
    }

    private var levelColor: Color {
        if audioLevel < 0.3 { return .green }
        if audioLevel < 0.7 { return .yellow }
        return .red
    }

    private func startRecording() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MovieCutVoiceovers", isDirectory: true)
        let url = tempDir.appendingPathComponent("voiceover_\(UUID().uuidString).caf")

        let newRecorder = VoiceoverRecorder()
        do {
            try newRecorder.startRecording(to: url)
            recorder = newRecorder
            isRecording = true
            elapsedTime = 0
            audioLevel = 0
        } catch {
            viewModel.lastErrorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        guard let recorder else { return }
        do {
            let url = try recorder.stopRecording()
            isRecording = false

            Task {
                await addVoiceoverToTimeline(url: url)
            }
        } catch {
            viewModel.lastErrorMessage = "Failed to stop recording: \(error.localizedDescription)"
            isRecording = false
        }
    }

    private func cancelRecording() {
        recorder?.cancelRecording()
        recorder = nil
        isRecording = false
        elapsedTime = 0
        audioLevel = 0
    }

    private func addVoiceoverToTimeline(url: URL) async {
        await viewModel.addVoiceoverAudio(from: url)
    }

    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        let tenths = Int((interval.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}
