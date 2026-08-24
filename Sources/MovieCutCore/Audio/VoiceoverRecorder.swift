import AVFoundation

/// Records voiceover audio to a file using the default audio input.
@MainActor
public final class VoiceoverRecorder: ObservableObject {
    /// Whether recording is currently active.
    @Published public private(set) var isRecording = false

    /// Current recording time in seconds.
    @Published public private(set) var currentTime: TimeInterval = 0

    /// Current input level from 0.0 to 1.0.
    @Published public private(set) var audioLevel: Float = 0

    private var engine: AVAudioEngine?
    private var recordingURL: URL?
    private var startDate: Date?
    private var meterTask: Task<Void, Never>?
    private var writeFailure: WriteFailureFlag?

    /// Creates a voiceover recorder.
    public init() {}

    /// Starts recording audio to the supplied URL.
    public func startRecording(to url: URL) throws {
        guard !isRecording else {
            throw VoiceoverRecorderError.alreadyRecording
        }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw VoiceoverRecorderError.inputUnavailable
        }

        let audioFile = try AVAudioFile(forWriting: url, settings: inputFormat.settings)
        // BUG-IOS-05 (external review, verified): per-buffer write failures
        // (e.g. disk filling mid-recording) were swallowed by `try?` — the
        // recording "succeeded" with missing audio. Record the first failure
        // and surface it from stopRecording().
        let writeFailure = WriteFailureFlag()
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { buffer, _ in
            do {
                try audioFile.write(from: buffer)
            } catch {
                writeFailure.record(error)
            }
            let level = Self.audioLevel(from: buffer)
            Task { @MainActor [weak self] in
                self?.audioLevel = level
            }
        }

        try engine.start()

        self.engine = engine
        self.writeFailure = writeFailure
        recordingURL = url
        startDate = Date()
        currentTime = 0
        audioLevel = 0
        isRecording = true
        startMeterTask()
    }

    /// Stops recording and returns the written file URL. Throws
    /// `writeFailed(underlying:)` when any buffer write failed — the file on
    /// disk is incomplete, so the caller must treat the take as failed.
    public func stopRecording() throws -> URL {
        guard isRecording else {
            throw VoiceoverRecorderError.notRecording
        }
        guard let url = recordingURL else {
            throw VoiceoverRecorderError.recordingURLUnavailable
        }

        let failure = writeFailure?.error
        finishRecording(resetTime: false)
        if let failure {
            throw VoiceoverRecorderError.writeFailed(underlying: failure.localizedDescription)
        }
        return url
    }

    /// Cancels recording and removes any partially written file.
    public func cancelRecording() {
        let url = recordingURL
        finishRecording(resetTime: true)

        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func startMeterTask() {
        meterTask?.cancel()
        meterTask = Task { @MainActor [weak self] in
            while let self, self.isRecording {
                if let startDate = self.startDate {
                    self.currentTime = Date().timeIntervalSince(startDate)
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func finishRecording(resetTime: Bool) {
        meterTask?.cancel()
        meterTask = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        recordingURL = nil
        startDate = nil
        writeFailure = nil
        isRecording = false
        audioLevel = 0

        if resetTime {
            currentTime = 0
        }
    }

    private nonisolated static func audioLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else {
            return 0
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard channelCount > 0, frameLength > 0 else {
            return 0
        }

        var total: Float = 0
        for channel in 0 ..< channelCount {
            let samples = channelData[channel]
            for frame in 0 ..< frameLength {
                let sample = samples[frame]
                total += sample * sample
            }
        }

        let meanSquare = total / Float(channelCount * frameLength)
        return min(max(sqrt(meanSquare) * 4, 0), 1)
    }
}

/// Errors produced by voiceover recording.
public enum VoiceoverRecorderError: Error, Sendable, Equatable {
    /// A recording is already active.
    case alreadyRecording

    /// There is no active recording to stop.
    case notRecording

    /// The input device is unavailable.
    case inputUnavailable

    /// The recording URL was lost before stopping.
    case recordingURLUnavailable

    /// A buffer write failed mid-recording (e.g. disk full) — the file is
    /// incomplete and the take must be discarded.
    case writeFailed(underlying: String)
}

/// Thread-safe first-write-failure latch, readable from the main actor after
/// the tap stops.
final class WriteFailureFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: (any Error)?

    func record(_ error: any Error) {
        lock.lock()
        defer { lock.unlock() }
        if stored == nil { stored = error }
    }

    var error: (any Error)? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
