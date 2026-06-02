import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

/// Applies simple noise reduction to audio buffers.
public struct NoiseReductionProcessor: Sendable {
    /// The noise reduction level from 0.0 to 1.0.
    public var level: Float {
        didSet {
            level = Self.clampedLevel(level)
        }
    }

    /// Creates a noise reduction processor.
    public init(level: Float = 0.5) {
        self.level = Self.clampedLevel(level)
    }

    private static func clampedLevel(_ level: Float) -> Float {
        min(max(level, 0), 1)
    }
}

#if canImport(AVFoundation)
extension NoiseReductionProcessor {
    /// Returns a new audio buffer with samples below the level-based threshold zeroed out.
    public static func process(audioBuffer: AVAudioPCMBuffer, level: Float) -> AVAudioPCMBuffer? {
        guard let inputData = audioBuffer.floatChannelData,
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: audioBuffer.format, frameCapacity: audioBuffer.frameCapacity),
              let outputData = outputBuffer.floatChannelData
        else {
            return nil
        }

        let channelCount = Int(audioBuffer.format.channelCount)
        let frameLength = Int(audioBuffer.frameLength)
        guard channelCount > 0, frameLength > 0 else {
            outputBuffer.frameLength = audioBuffer.frameLength
            return outputBuffer
        }

        let stride = audioBuffer.stride
        var maxAmplitude: Float = 0

        for channel in 0 ..< channelCount {
            let samples = inputData[channel]
            for frame in 0 ..< frameLength {
                maxAmplitude = max(maxAmplitude, abs(samples[frame * stride]))
            }
        }

        let threshold = clampedLevel(level) * maxAmplitude
        outputBuffer.frameLength = audioBuffer.frameLength

        for channel in 0 ..< channelCount {
            let inputSamples = inputData[channel]
            let outputSamples = outputData[channel]
            for frame in 0 ..< frameLength {
                let index = frame * stride
                let sample = inputSamples[index]
                outputSamples[index] = abs(sample) < threshold ? 0 : sample
            }
        }

        return outputBuffer
    }
}
#endif
