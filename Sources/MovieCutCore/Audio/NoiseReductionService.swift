import Foundation

#if canImport(AVFoundation)
import AVFoundation

public struct NoiseReductionService: Sendable {
    public init() {}

    public func applyNoiseReduction(to asset: AVAsset, threshold: Float = 0.05) async throws -> URL {
        let assetDuration = try await asset.load(.duration)
        guard assetDuration.isValid, assetDuration > .zero else {
            throw NoiseReductionServiceError.emptyAsset
        }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw NoiseReductionServiceError.noAudioTracks
        }

        let passThroughURL = try await exportPassThroughAudio(
            from: asset,
            duration: assetDuration,
            audioTracks: audioTracks
        )

        do {
            return try renderNoiseReducedAudio(inputURL: passThroughURL, threshold: threshold)
        } catch {
            return passThroughURL
        }
    }

    private func exportPassThroughAudio(
        from asset: AVAsset,
        duration assetDuration: CMTime,
        audioTracks: [AVAssetTrack]
    ) async throws -> URL {
        let composition = AVMutableComposition()

        for track in audioTracks {
            let trackRange = try await track.load(.timeRange)
            let sourceRange = trackRange.duration > .zero
                ? trackRange
                : CMTimeRange(start: .zero, duration: assetDuration)

            let compositionTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            try compositionTrack?.insertTimeRange(
                sourceRange,
                of: track,
                at: .zero
            )
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("denoised_passthrough_\(UUID().uuidString).m4a")

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw NoiseReductionServiceError.exportSessionCreationFailed
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        try await export.export(to: outputURL, as: .m4a)
        return outputURL
    }

    private func renderNoiseReducedAudio(inputURL: URL, threshold: Float) throws -> URL {
        let inputFile = try AVAudioFile(forReading: inputURL)
        let inputFormat = inputFile.processingFormat
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw NoiseReductionServiceError.invalidInputFormat
        }
        guard inputFile.length > 0 else {
            throw NoiseReductionServiceError.emptyAsset
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("denoised_\(UUID().uuidString).m4a")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: Int(inputFormat.channelCount),
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings)

        let frameCapacity: AVAudioFrameCount = 4_096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCapacity),
              let channels = buffer.floatChannelData else {
            throw NoiseReductionServiceError.renderBufferUnavailable
        }

        let channelCount = Int(inputFormat.channelCount)
        let sampleRate = Float(inputFormat.sampleRate)
        let voiceLowAlpha = Self.onePoleAlpha(cutoff: 90, sampleRate: sampleRate)
        let noiseLowpassAlpha = Self.onePoleAlpha(cutoff: 3_400, sampleRate: sampleRate)
        let noiseAttenuation = Self.noiseAttenuation(from: threshold)
        var voiceLowState = Array(repeating: Float(0), count: channelCount)
        var noiseLowpassState = Array(repeating: Float(0), count: channelCount)

        while inputFile.framePosition < inputFile.length {
            let remaining = AVAudioFrameCount(inputFile.length - inputFile.framePosition)
            let framesToRead = min(frameCapacity, remaining)
            try inputFile.read(into: buffer, frameCount: framesToRead)
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { break }

            for channel in 0..<channelCount {
                let samples = channels[channel]
                var voiceLow = voiceLowState[channel]
                var noiseLowpass = noiseLowpassState[channel]
                for frame in 0..<frameLength {
                    let input = samples[frame]
                    // Remove sub-voice rumble, keep the voice band, and attenuate the
                    // high-frequency residual. This is deterministic and safe in the
                    // app/export path, unlike AVAudioEngine offline render in tests.
                    voiceLow += voiceLowAlpha * (input - voiceLow)
                    let highPassed = input - voiceLow
                    noiseLowpass += noiseLowpassAlpha * (highPassed - noiseLowpass)
                    let highNoise = highPassed - noiseLowpass
                    let output = noiseLowpass + highNoise * noiseAttenuation
                    samples[frame] = max(-1, min(1, output))
                }
                voiceLowState[channel] = voiceLow
                noiseLowpassState[channel] = noiseLowpass
            }

            try outputFile.write(from: buffer)
        }

        return outputURL
    }

    private static func noiseAttenuation(from threshold: Float) -> Float {
        let clamped = min(max(threshold, 0), 1)
        // Default threshold 0.05 yields strong but not destructive high-frequency
        // attenuation; larger thresholds attenuate more aggressively.
        return max(0.08, 0.35 - clamped * 2.0)
    }

    private static func onePoleAlpha(cutoff: Float, sampleRate: Float) -> Float {
        guard sampleRate > 0, cutoff > 0 else { return 1 }
        return 1 - exp(-2 * .pi * cutoff / sampleRate)
    }
}

private enum NoiseReductionServiceError: Error, Sendable, Equatable {
    case emptyAsset
    case noAudioTracks
    case exportSessionCreationFailed
    case invalidInputFormat
    case renderBufferUnavailable
}
#endif
