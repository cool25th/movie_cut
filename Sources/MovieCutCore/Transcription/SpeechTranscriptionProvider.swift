import Foundation
import AVFoundation
import Speech

/// Transcription provider using Apple's on-device Speech framework.
public struct SpeechTranscriptionProvider: TranscriptionProvider {

    /// The locale used for speech recognition (default: current locale).
    public var locale: Locale

    /// Creates a speech transcription provider.
    public init(locale: Locale = .current) {
        self.locale = locale
    }

    /// Whether Speech Recognition is authorized on this device.
    public var isAvailable: Bool {
        get async {
            let status = SFSpeechRecognizer.authorizationStatus()
            guard status == .authorized else { return false }
            guard let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
            return recognizer.isAvailable
        }
    }

    /// User-visible name for this provider.
    public var providerName: String {
        "Apple Speech"
    }

    /// Transcribes an audio or video file using on-device speech recognition.
    public func transcribe(audioURL: URL, language: String?) async throws -> TranscriptionResult {
        let resolvedLocale: Locale
        if let language = language {
            resolvedLocale = Locale(identifier: language)
        } else {
            resolvedLocale = locale
        }

        guard let recognizer = SFSpeechRecognizer(locale: resolvedLocale) else {
            throw TranscriptionError.transcriptionFailed(
                "Speech recognizer is unavailable for locale \(resolvedLocale.identifier)."
            )
        }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            break
        case .notDetermined:
            let status = await requestAuthorization()
            guard status == .authorized else {
                throw TranscriptionError.transcriptionFailed(
                    "Speech recognition permission was not granted. Enable Speech Recognition for MovieCut in System Settings."
                )
            }
        case .denied:
            throw TranscriptionError.transcriptionFailed(
                "Speech recognition permission is denied. Enable Speech Recognition for MovieCut in System Settings."
            )
        case .restricted:
            throw TranscriptionError.transcriptionFailed(
                "Speech recognition is restricted on this Mac."
            )
        @unknown default:
            throw TranscriptionError.transcriptionFailed(
                "Speech recognition authorization failed with an unknown status."
            )
        }

        guard recognizer.isAvailable else {
            throw TranscriptionError.transcriptionFailed(
                "Speech recognizer is currently unavailable for locale \(resolvedLocale.identifier)."
            )
        }

        // For video files, extract audio first
        let audioFileURL: URL
        let extractedAudioURL: URL?
        let ext = audioURL.pathExtension.lowercased()
        let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]

        if videoExtensions.contains(ext) {
            let extractedURL = try await extractAudio(from: audioURL)
            audioFileURL = extractedURL
            extractedAudioURL = extractedURL
        } else {
            audioFileURL = audioURL
            extractedAudioURL = nil
        }

        defer {
            if let extractedAudioURL {
                try? FileManager.default.removeItem(at: extractedAudioURL)
            }
        }

        // Perform recognition
        let request = SFSpeechURLRecognitionRequest(url: audioFileURL)
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        let result = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<TranscriptionResult, Error>) in
            let resumer = SpeechRecognitionContinuation(continuation)

            _ = recognizer.recognitionTask(with: request) { recognitionResult, error in

                if let error = error {
                    resumer.resume(throwing: TranscriptionError.transcriptionFailed(error.localizedDescription))
                    return
                }

                guard let recognitionResult = recognitionResult else { return }

                if recognitionResult.isFinal {
                    let segments: [TranscriptionSegment] = recognitionResult
                        .bestTranscription
                        .segments
                        .map { segment in
                            let word = WordTiming(
                                text: segment.substring,
                                startTime: segment.timestamp,
                                endTime: segment.timestamp + segment.duration,
                                confidence: Double(segment.confidence)
                            )
                            return TranscriptionSegment(
                                text: segment.substring,
                                startTime: segment.timestamp,
                                endTime: segment.timestamp + segment.duration,
                                confidence: Double(segment.confidence),
                                words: [word]
                            )
                        }

                    let transcriptionResult = TranscriptionResult(
                        segments: segments,
                        language: resolvedLocale.identifier
                    )
                    resumer.resume(returning: transcriptionResult)
                }
            }
        }

        return result
    }

    // MARK: - Private

    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Extracts audio from a video file to a temporary M4A file.
    private func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVAsset(url: videoURL)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        // Delete existing temp file if any
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw TranscriptionError.transcriptionFailed(
                "Audio extraction failed: Apple M4A export is unavailable for this asset."
            )
        }

        guard exportSession.supportedFileTypes.contains(.m4a) else {
            throw TranscriptionError.transcriptionFailed(
                "Audio extraction failed: M4A output is not supported for this asset."
            )
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        _ = await exportSession.export()

        guard exportSession.status == .completed else {
            let error = exportSession.error
            throw TranscriptionError.transcriptionFailed(
                "Audio extraction failed: \(error?.localizedDescription ?? "Unknown export error")"
            )
        }

        return outputURL
    }
}

private final class SpeechRecognitionContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<TranscriptionResult, Error>?

    init(_ continuation: CheckedContinuation<TranscriptionResult, Error>) {
        self.continuation = continuation
    }

    func resume(returning result: TranscriptionResult) {
        guard let continuation = takeContinuation() else { return }
        continuation.resume(returning: result)
    }

    func resume(throwing error: Error) {
        guard let continuation = takeContinuation() else { return }
        continuation.resume(throwing: error)
    }

    private func takeContinuation() -> CheckedContinuation<TranscriptionResult, Error>? {
        lock.lock()
        defer { lock.unlock() }

        let current = continuation
        continuation = nil
        return current
    }
}
