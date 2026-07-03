import Foundation

#if canImport(AVFoundation)
import AVFoundation

/// Applies five-band equalizer presets to audio files or live AVAudioEngine playback.
@MainActor
public final class AudioEqualizerService: Sendable {
    private let engine = AVAudioEngine()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 5)

    /// Creates an audio equalizer service.
    public init() {}

    /// Applies an equalizer preset to an audio file and writes the processed output.
    public func apply(preset: EqualizerPreset, inputURL: URL, outputURL: URL) async throws {
        try render(preset: preset, inputURL: inputURL, outputURL: outputURL)
    }

    /// Returns an AVAudioEngine configured with the equalizer on the main output path.
    public func applyRealtime(preset: EqualizerPreset) -> AVAudioEngine {
        engine.stop()
        engine.reset()
        engine.disableManualRenderingMode()
        attachEQIfNeeded()
        configureEQNode(with: preset)

        engine.disconnectNodeOutput(engine.mainMixerNode)
        engine.disconnectNodeOutput(eqNode)
        engine.connect(engine.mainMixerNode, to: eqNode, format: nil)
        engine.connect(eqNode, to: engine.outputNode, format: nil)

        return engine
    }

    private func render(preset: EqualizerPreset, inputURL: URL, outputURL: URL) throws {
        let inputFile = try AVAudioFile(forReading: inputURL)
        let inputFormat = inputFile.processingFormat
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw AudioEqualizerServiceError.invalidInputFormat
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let outputFile = try AVAudioFile(forWriting: outputURL, settings: inputFormat.settings)
        let channelCount = Int(inputFormat.channelCount)
        let frameCapacity: AVAudioFrameCount = 4_096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCapacity),
              let channels = buffer.floatChannelData else {
            throw AudioEqualizerServiceError.renderBufferUnavailable
        }

        let gains = Self.renderGains(for: preset)
        let sampleRate = Float(inputFormat.sampleRate)
        let lowAlpha = Self.onePoleAlpha(cutoff: 180, sampleRate: sampleRate)
        let highAlpha = Self.onePoleAlpha(cutoff: 3_000, sampleRate: sampleRate)
        var lowState = Array(repeating: Float(0), count: channelCount)
        var highState = Array(repeating: Float(0), count: channelCount)

        while inputFile.framePosition < inputFile.length {
            let remaining = AVAudioFrameCount(inputFile.length - inputFile.framePosition)
            let framesToRead = min(frameCapacity, remaining)
            try inputFile.read(into: buffer, frameCount: framesToRead)
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { break }

            for channel in 0..<channelCount {
                let samples = channels[channel]
                var low = lowState[channel]
                var highLowpass = highState[channel]
                for frame in 0..<frameLength {
                    let input = samples[frame]
                    low += lowAlpha * (input - low)
                    highLowpass += highAlpha * (input - highLowpass)
                    let high = input - highLowpass
                    let mid = input - low - high
                    let output = low * gains.low + mid * gains.mid + high * gains.high
                    samples[frame] = max(-1, min(1, output))
                }
                lowState[channel] = low
                highState[channel] = highLowpass
            }

            try outputFile.write(from: buffer)
        }
    }

    private static func renderGains(for preset: EqualizerPreset) -> (low: Float, mid: Float, high: Float) {
        let bands = ClipEqualizerSettings.normalizedBands(preset.bands)
        let lowGainDb = (bands[0].gain + bands[1].gain) / 2
        let midGainDb = bands[2].gain
        let highGainDb = (bands[3].gain + bands[4].gain) / 2
        return (
            low: linearGain(db: lowGainDb),
            mid: linearGain(db: midGainDb),
            high: linearGain(db: highGainDb)
        )
    }

    private static func linearGain(db: Float) -> Float {
        pow(10, db / 20)
    }

    private static func onePoleAlpha(cutoff: Float, sampleRate: Float) -> Float {
        guard sampleRate > 0, cutoff > 0 else { return 1 }
        return 1 - exp(-2 * .pi * cutoff / sampleRate)
    }

    private func attachEQIfNeeded() {
        if eqNode.engine == nil {
            engine.attach(eqNode)
        }
    }

    private func configureEQNode(with preset: EqualizerPreset) {
        eqNode.globalGain = 0

        for (index, band) in eqNode.bands.enumerated() {
            guard index < preset.bands.count else {
                band.bypass = true
                continue
            }

            let presetBand = preset.bands[index]
            band.filterType = Self.filterType(forBandAt: index, bandCount: eqNode.bands.count)
            band.frequency = presetBand.frequency
            band.bandwidth = 1
            band.gain = presetBand.gain
            band.bypass = false
        }
    }

    private static func filterType(forBandAt index: Int, bandCount: Int) -> AVAudioUnitEQFilterType {
        if index == 0 {
            return .lowShelf
        }
        if index == bandCount - 1 {
            return .highShelf
        }
        return .parametric
    }
}

#else

/// Applies five-band equalizer presets to audio files or live AVAudioEngine playback.
@MainActor
public final class AudioEqualizerService: Sendable {
    /// Creates an audio equalizer service.
    public init() {}

    /// Applies an equalizer preset to an audio file and writes the processed output.
    public func apply(preset _: EqualizerPreset, inputURL _: URL, outputURL _: URL) async throws {
        throw AudioEqualizerServiceError.avFoundationUnavailable
    }
}

#endif

/// Errors produced by audio equalizer processing.
public enum AudioEqualizerServiceError: Error, Sendable, Equatable {
    /// AVFoundation is unavailable on the current platform.
    case avFoundationUnavailable

    /// The input file does not expose a renderable PCM format.
    case invalidInputFormat

    /// A render buffer could not be created.
    case renderBufferUnavailable

    /// AVAudioEngine failed during offline rendering.
    case renderingFailed
}
