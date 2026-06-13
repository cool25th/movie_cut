#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation

/// A selectable system voice, exposed as a value type so UI and tests do not
/// depend on AVFoundation directly (F-17).
public struct TextToSpeechVoice: Sendable, Equatable, Identifiable, Hashable {
    /// Stable voice identifier passed back to the synthesizer.
    public var id: String

    /// User-facing voice name.
    public var name: String

    /// BCP-47 language identifier (e.g. "en-US").
    public var language: String

    public init(id: String, name: String, language: String) {
        self.id = id
        self.name = name
        self.language = language
    }

    /// Display label combining name and language.
    public var displayName: String {
        "\(name) (\(language))"
    }
}

/// Errors produced by text-to-speech synthesis.
public enum TextToSpeechError: Error, Sendable, Equatable {
    /// The supplied text was empty after trimming.
    case emptyText

    /// The platform produced no audio for the request.
    case noAudioProduced

    /// Synthesis is unavailable on this platform.
    case unsupported
}

/// Renders text to a spoken audio file using the system speech synthesizer.
public struct TextToSpeechSynthesizer: Sendable {
    /// Synthesis tuning, mapped onto `AVSpeechUtterance`.
    public struct Options: Sendable, Equatable {
        /// Voice identifier, or nil for the system default.
        public var voiceIdentifier: String?

        /// Speaking rate 0...1 (AVSpeechUtterance scale).
        public var rate: Float

        /// Pitch multiplier 0.5...2.0.
        public var pitchMultiplier: Float

        /// Output volume 0...1.
        public var volume: Float

        public init(
            voiceIdentifier: String? = nil,
            // Matches AVSpeechUtteranceDefaultSpeechRate without depending on
            // the AVFoundation symbol from the always-compiled struct.
            rate: Float = 0.5,
            pitchMultiplier: Float = 1.0,
            volume: Float = 1.0
        ) {
            self.voiceIdentifier = voiceIdentifier
            self.rate = rate
            self.pitchMultiplier = pitchMultiplier
            self.volume = volume
        }
    }

    public init() {}

    /// Lists the available system voices, sorted by language then name.
    public static func availableVoices() -> [TextToSpeechVoice] {
        #if canImport(AVFoundation)
        return AVSpeechSynthesisVoice.speechVoices()
            .map { TextToSpeechVoice(id: $0.identifier, name: $0.name, language: $0.language) }
            .sorted { lhs, rhs in
                lhs.language == rhs.language ? lhs.name < rhs.name : lhs.language < rhs.language
            }
        #else
        return []
        #endif
    }

    #if canImport(AVFoundation)
    /// Synthesizes `text` to a CAF file at `url` and returns its duration.
    ///
    /// Uses `AVSpeechSynthesizer.write(_:toBufferCallback:)`, accumulating the
    /// PCM buffers into an `AVAudioFile`. The first non-empty buffer fixes the
    /// output format; an empty buffer signals completion.
    @MainActor
    public func synthesize(text: String, to url: URL, options: Options = Options()) async throws -> TimeInterval {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TextToSpeechError.emptyText
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let utterance = AVSpeechUtterance(string: trimmed)
        if let voiceIdentifier = options.voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        }
        utterance.rate = options.rate
        utterance.pitchMultiplier = options.pitchMultiplier
        utterance.volume = options.volume

        // The synthesizer must outlive the async callbacks.
        let synthesizer = AVSpeechSynthesizer()
        let writer = SpeechFileWriter(url: url)

        return try await withCheckedThrowingContinuation { continuation in
            synthesizer.write(utterance) { buffer in
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

                if pcmBuffer.frameLength == 0 {
                    // Empty buffer marks completion. The callback can fire more
                    // than once, so finish() returns a result only on the first
                    // call and nil thereafter to keep the continuation one-shot.
                    guard let result = writer.finish() else { return }
                    continuation.resume(with: result)
                    return
                }

                writer.append(pcmBuffer)
            }
        }
    }
    #endif
}

#if canImport(AVFoundation)
/// Accumulates speech PCM buffers into a single audio file. Class reference so
/// the escaping write-callback can mutate shared state safely on its serial
/// callback queue.
private final class SpeechFileWriter: @unchecked Sendable {
    private let url: URL
    private var file: AVAudioFile?
    private var totalFrames: AVAudioFramePosition = 0
    private var sampleRate: Double = 0
    private var resumed = false

    init(url: URL) {
        self.url = url
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        do {
            if file == nil {
                file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
                sampleRate = buffer.format.sampleRate
            }
            try file?.write(from: buffer)
            totalFrames += AVAudioFramePosition(buffer.frameLength)
        } catch {
            // Drop unwritable buffers; finish() reports if nothing was written.
        }
    }

    /// Closes the file and returns the rendered duration on the first call.
    /// Returns nil on subsequent calls so the caller resumes exactly once.
    func finish() -> Result<TimeInterval, Error>? {
        guard !resumed else { return nil }
        resumed = true

        file = nil  // flush + close
        guard totalFrames > 0, sampleRate > 0 else {
            try? FileManager.default.removeItem(at: url)
            return .failure(TextToSpeechError.noAudioProduced)
        }
        return .success(TimeInterval(totalFrames) / sampleRate)
    }
}
#endif
