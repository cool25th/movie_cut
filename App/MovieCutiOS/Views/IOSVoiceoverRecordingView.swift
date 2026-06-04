#if os(iOS)
import MovieCutCore
import SwiftUI
import AVFoundation

struct IOSVoiceoverRecordingView: View {
    @Bindable var viewModel: IOSEditorViewModel

    @State private var isRecording = false
    @State private var isSavingToTimeline = false
    @State private var elapsedTime: TimeInterval = 0
    @State private var audioLevel: Float = 0
    @State private var recorder: VoiceoverRecorder?

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Voiceover Recording")
                .font(.headline)

            recordingTimer
            audioLevelMeter
            recordingControls
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private var recordingTimer: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isRecording ? Color.red : Color.secondary.opacity(0.35))
                .frame(width: 10, height: 10)

            Text(timeString(from: elapsedTime))
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(.primary)

            if isSavingToTimeline {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isRecording ? "Recording time \(timeString(from: elapsedTime))" : "Recording time \(timeString(from: elapsedTime))")
    }

    private var audioLevelMeter: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Input Level")
                .font(.caption)
                .foregroundStyle(.secondary)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(uiColor: .tertiarySystemFill))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(levelColor)
                        .frame(width: geometry.size.width * CGFloat(audioLevel))
                }
            }
            .frame(height: 8)
        }
    }

    @ViewBuilder
    private var recordingControls: some View {
        HStack(spacing: 12) {
            if isRecording {
                Button(action: stopRecording) {
                    Label("Stop & Save", systemImage: "stop.circle")
                }
                .buttonStyle(.borderedProminent)

                Button(role: .cancel, action: cancelRecording) {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            } else {
                Button(action: startRecording) {
                    Label("Record", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isSavingToTimeline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

        guard await requestRecordingPermission() else {
            viewModel.lastErrorMessage = "Microphone access is required to record a voiceover."
            return
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MovieCutVoiceovers", isDirectory: true)
        let url = tempDir.appendingPathComponent("voiceover_\(UUID().uuidString).caf")

        do {
            try configureRecordingSession()

            let newRecorder = VoiceoverRecorder()
            try newRecorder.startRecording(to: url)
            recorder = newRecorder
            isRecording = true
            elapsedTime = 0
            audioLevel = 0
        } catch {
            endRecordingSession()
            viewModel.lastErrorMessage = "Failed to start recording: \(error.localizedDescription)"
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
            endRecordingSession()

            Task {
                await addVoiceoverToTimeline(url: url, fallbackDuration: finalDuration)
            }
        } catch {
            self.recorder = nil
            isRecording = false
            audioLevel = 0
            endRecordingSession()
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
        endRecordingSession()
    }

    @MainActor
    private func addVoiceoverToTimeline(url: URL, fallbackDuration: TimeInterval) async {
        isSavingToTimeline = true
        defer { isSavingToTimeline = false }

        let duration = await audioDuration(for: url) ?? max(fallbackDuration, 0.1)
        let voiceoverTrack = MovieCutCore.MusicTrack(
            title: "Voiceover",
            artist: "MovieCut",
            duration: duration,
            fileURL: url,
            tags: ["voiceover"],
            isBuiltIn: false
        )

        await viewModel.addMusicTrack(voiceoverTrack)
    }

    private func configureRecordingSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
        try session.setActive(true)
    }

    private func endRecordingSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestRecordingPermission() async -> Bool {
        let session = AVAudioSession.sharedInstance()

        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func audioDuration(for url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0 else {
            return nil
        }
        return duration.seconds
    }

    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        let tenths = Int((interval.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}
#endif
