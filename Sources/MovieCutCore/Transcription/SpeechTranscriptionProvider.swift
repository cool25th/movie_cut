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
            throw TranscriptionError.notSupported
        }

        guard recognizer.isAvailable else {
            throw TranscriptionError.notSupported
        }

        // Request authorization if needed
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus != .authorized {
            let granted = await requestAuthorization()
            guard granted else {
                throw TranscriptionError.notSupported
            }
        }

        // For video files, extract audio first
        let audioFileURL: URL
        let ext = audioURL.pathExtension.lowercased()
        let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]

        if videoExtensions.contains(ext) {
            audioFileURL = try await extractAudio(from: audioURL)
        } else {
            audioFileURL = audioURL
        }

        // Perform recognition
        let request = SFSpeechURLRecognitionRequest(url: audioFileURL)
        request.requiresOnDeviceRecognition = true

        let result = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<TranscriptionResult, Error>) in
            var hasResumed = false

            recognizer.recognitionTask(with: request) { recognitionResult, error in
                guard !hasResumed else { return }

                if let error = error {
                    hasResumed = true
                    continuation.resume(throwing: TranscriptionError.transcriptionFailed(error.localizedDescription))
                    return
                }

                guard let recognitionResult = recognitionResult else { return }

                if recognitionResult.isFinal {
                    hasResumed = true

                    let segments: [TranscriptionSegment] = recognitionResult
                        .bestTranscription
                        .segments
                        .map { segment in
                            TranscriptionSegment(
                                text: segment.substring,
                                startTime: segment.timestamp,
                                endTime: segment.timestamp + segment.duration,
                                confidence: Double(segment.confidence)
                            )
                        }

                    let transcriptionResult = TranscriptionResult(
                        segments: segments,
                        language: resolvedLocale.identifier
                    )
                    continuation.resume(returning: transcriptionResult)
                }
            }
        }

        return result
    }

    // MARK: - Private

    private func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Extracts audio from a video file to a temporary WAV file.
    private func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVAsset(url: videoURL)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        // Delete existing temp file if any
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw TranscriptionError.assetNotReady
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .wav

        _ = await exportSession.export()

        guard exportSession.status == .completed else {
            let error = exportSession.error
            throw TranscriptionError.transcriptionFailed(
                error?.localizedDescription ?? "Audio extraction failed"
            )
        }

        return outputURL
    }
}
