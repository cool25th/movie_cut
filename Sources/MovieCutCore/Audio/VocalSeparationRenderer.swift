import Foundation

#if canImport(AVFoundation)
import AVFoundation

/// Offline vocal-separation renderer.
///
/// Reads an ``AVAudioFile``, applies block-wise center-channel
/// (mid/side) processing via ``CenterChannelVocalSeparator``, and writes the
/// result to a new file. This is the offline-render → file-production step that
/// mirrors `NoiseReductionService`: it produces a processed audio file which the
/// App layer then swaps in as a clip's source asset via the existing
/// `SetClipSourceAssetCommand` (single undo unit).
///
/// Mono input is an explicit error rather than a silent passthrough: center-
/// channel separation is only defined for stereo content, and quietly copying a
/// mono input unchanged would make the user believe the operation succeeded.
public struct VocalSeparationRenderer: Sendable {
    private let separator: CenterChannelVocalSeparator
    private let mode: VocalSeparationMode
    private let blockFrames: AVAudioFrameCount

    /// Creates a renderer.
    ///
    /// - Parameters:
    ///   - mode: Whether to remove center-panned vocals or isolate them.
    ///   - wetMix: Effect strength in `[0, 1]`; `0` is passthrough, `1` is full
    ///     cancellation/isolation. Clamped to the unit range.
    ///   - blockFrames: Frames processed per read/write block. Defaults to the
    ///     same 4096-frame block size used by `NoiseReductionService`.
    public init(
        mode: VocalSeparationMode,
        wetMix: Float = 1,
        blockFrames: AVAudioFrameCount = 4_096
    ) {
        self.mode = mode
        self.separator = CenterChannelVocalSeparator(wetMix: wetMix)
        self.blockFrames = max(blockFrames, 1)
    }

    /// Renders vocal separation from `inputURL` into a new file in the temporary
    /// directory and returns the output URL.
    public func render(inputURL: URL) async throws -> URL {
        let inputFile = try AVAudioFile(forReading: inputURL)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vocalsep_\(UUID().uuidString).caf")
        return try render(inputFile: inputFile, outputURL: outputURL)
    }

    /// Renders vocal separation from `inputFile` to `outputURL`.
    ///
    /// Output is written as standard PCM `.caf` so the read/write loop never
    /// depends on a lossy encoder while still being readable by `AVAudioFile`.
    public func render(inputFile: AVAudioFile, outputURL: URL) throws -> URL {
        let inputFormat = inputFile.processingFormat
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw VocalSeparationRendererError.invalidInputFormat
        }
        // Center-channel separation is defined only for stereo. Mono must fail
        // explicitly — never a silent passthrough.
        guard inputFormat.channelCount >= 2 else {
            throw VocalSeparationRendererError.monoInputUnsupported
        }
        guard inputFile.length > 0 else {
            throw VocalSeparationRendererError.emptyInput
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        // Write standard float PCM. AVAudioFile always stores non-interleaved
        // float as its processing format regardless of the file's on-disk
        // layout, so the read/process/write loop reuses one buffer shape.
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: Int(inputFormat.channelCount),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: blockFrames),
              buffer.floatChannelData != nil else {
            throw VocalSeparationRendererError.renderBufferUnavailable
        }

        while inputFile.framePosition < inputFile.length {
            let remaining = AVAudioFrameCount(inputFile.length - inputFile.framePosition)
            let framesToRead = min(blockFrames, remaining)
            try inputFile.read(into: buffer, frameCount: framesToRead)
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { break }

            // CenterChannelVocalSeparator.process(buffer:mode:) operates on the
            // first two channels in place and returns the same buffer.
            guard separator.process(buffer: buffer, mode: mode) != nil else {
                throw VocalSeparationRendererError.processingFailed
            }
            try outputFile.write(from: buffer)
        }

        return outputURL
    }
}

/// Errors raised by ``VocalSeparationRenderer``.
public enum VocalSeparationRendererError: Error, Sendable, Equatable {
    /// The input format had no usable channels or sample rate.
    case invalidInputFormat
    /// The input was empty (zero frames).
    case emptyInput
    /// The input has fewer than two channels. Center-channel separation is only
    /// defined for stereo, so mono fails explicitly instead of passthrough.
    case monoInputUnsupported
    /// A render PCM buffer could not be allocated.
    case renderBufferUnavailable
    /// The separator declined to process the buffer (unsupported format).
    case processingFailed
}
#endif
