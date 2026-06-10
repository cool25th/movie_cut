import AVFoundation
import MovieCutCore
import SwiftUI

struct VoiceoverRecordingView: View {
    var viewModel: EditorViewModel

    @State private var isRecording = false
    @State private var isSavingToTimeline = false
    @State private var elapsedTime: TimeInterval = 0
    @State private var audioLevel: Float = 0
    @State private var recorder: VoiceoverRecorder?

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voiceover Recording")
                .font(.headline)

            recordingIndicator
            audioLevelMeter
            recordingControls
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(timer) { _ in
            guard let recorder, isRecording else { return }
            elapsedTime = recorder.currentTime
            audioLevel = recorder.audioLevel
        }
        .onDisappear {
            if isRecording {
                cancelRecording()
            }
        }
    }

    @ViewBuilder
    private var recordingIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isRecording ? .red : .secondary.opacity(0.35))
                .frame(width: 10, height: 10)

            Text(timeString(from: elapsedTime))
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(.primary)

            if isSavingToTimeline {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 4)
                    .accessibilityLabel("Saving voiceover to timeline")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Voiceover timer \(timeString(from: elapsedTime))")
        .accessibilityHint(isRecording ? "Shows the elapsed recording time." : "Shows the last voiceover recording time.")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Input level")
        .accessibilityValue("\(Int((audioLevel * 100).rounded())) percent")
        .accessibilityHint("Shows the current microphone input level.")
    }

    @ViewBuilder
    private var recordingControls: some View {
        HStack(spacing: 16) {
            if isRecording {
                Button(action: stopRecording) {
                    Label("Stop & Save", systemImage: "stop.circle")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Stop and save voiceover")
                .accessibilityHint("Stops recording and adds the voiceover at the playhead.")

                Button(role: .cancel, action: cancelRecording) {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Cancel voiceover recording")
                .accessibilityHint("Stops recording and discards the audio.")
            } else {
                Button(action: startRecording) {
                    Label("Record", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isSavingToTimeline)
                .accessibilityLabel("Record voiceover")
                .accessibilityHint("Starts recording from the default microphone.")
            }
        }
    }

    private var levelColor: Color {
        if audioLevel < 0.3 { return .green }
        if audioLevel < 0.7 { return .yellow }
        return .red
    }

    private func startRecording() {
        Task {
            await beginRecording()
        }
    }

    @MainActor
    private func beginRecording() async {
        guard !isRecording, !isSavingToTimeline else { return }

        guard await requestMicrophoneAccessIfNeeded() else {
            viewModel.lastErrorMessage = microphoneHelpMessage
            return
        }

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
            recorder = nil
            isRecording = false
            audioLevel = 0
            viewModel.lastErrorMessage = recordingErrorMessage(for: error)
        }
    }

    private func stopRecording() {
        guard let recorder else { return }
        do {
            let finalDuration = max(recorder.currentTime, elapsedTime)
            let url = try recorder.stopRecording()
            self.recorder = nil
            isRecording = false
            audioLevel = 0
            elapsedTime = finalDuration

            Task {
                await addVoiceoverToTimeline(url: url, fallbackDuration: finalDuration)
            }
        } catch {
            self.recorder = nil
            isRecording = false
            audioLevel = 0
            viewModel.lastErrorMessage = "Failed to stop recording: \(error.localizedDescription)"
        }
    }

    private func cancelRecording() {
        recorder?.cancelRecording()
        recorder = nil
        isRecording = false
        isSavingToTimeline = false
        elapsedTime = 0
        audioLevel = 0
    }

    @MainActor
    private func addVoiceoverToTimeline(url: URL, fallbackDuration: TimeInterval) async {
        isSavingToTimeline = true
        defer { isSavingToTimeline = false }

        await viewModel.addVoiceoverAudio(from: url, fallbackDuration: fallbackDuration)
    }

    private func requestMicrophoneAccessIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func recordingErrorMessage(for error: any Error) -> String {
        if let recorderError = error as? VoiceoverRecorderError, recorderError == .inputUnavailable {
            return "Failed to start recording. Connect or select a microphone, then try again."
        }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .denied || status == .restricted {
            return microphoneHelpMessage
        }

        return "Failed to start recording: \(error.localizedDescription)"
    }

    private var microphoneHelpMessage: String {
        "Microphone access is required to record a voiceover. Enable MovieCut in System Settings > Privacy & Security > Microphone, and make sure an input device is available."
    }

    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        let tenths = Int((interval.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}
