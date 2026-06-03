import Foundation

#if canImport(AVFoundation)
import AVFoundation

/// Applies five-band equalizer presets to audio files or live AVAudioEngine playback.
public final class AudioEqualizerService: @unchecked Sendable {
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
        engine.stop()
        engine.reset()
        engine.disableManualRenderingMode()

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
        let player = AVAudioPlayerNode()

        attachEQIfNeeded()
        engine.attach(player)
        configureEQNode(with: preset)
        engine.disconnectNodeOutput(player)
        engine.disconnectNodeOutput(eqNode)
        engine.disconnectNodeOutput(engine.mainMixerNode)
        engine.connect(player, to: eqNode, format: inputFormat)
        engine.connect(eqNode, to: engine.mainMixerNode, format: inputFormat)

        defer {
            player.stop()
            engine.stop()
            engine.disableManualRenderingMode()
            engine.disconnectNodeOutput(player)
            engine.disconnectNodeOutput(eqNode)
            engine.detach(player)
        }

        try engine.enableManualRenderingMode(
            .offline,
            format: inputFormat,
            maximumFrameCount: 4_096
        )

        try engine.start()
        player.scheduleFile(inputFile, at: nil)
        player.play()

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        ) else {
            throw AudioEqualizerServiceError.renderBufferUnavailable
        }

        let totalFrames = inputFile.length
        while engine.manualRenderingSampleTime < totalFrames {
            let remainingFrames = totalFrames - engine.manualRenderingSampleTime
            let frameCount = min(
                AVAudioFrameCount(remainingFrames),
                engine.manualRenderingMaximumFrameCount
            )

            let status = try engine.renderOffline(frameCount, to: buffer)
            switch status {
            case .success:
                try outputFile.write(from: buffer)
            case .insufficientDataFromInputNode:
                break
            case .cannotDoInCurrentContext:
                continue
            case .error:
                throw AudioEqualizerServiceError.renderingFailed
            @unknown default:
                throw AudioEqualizerServiceError.renderingFailed
            }
        }
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
public final class AudioEqualizerService: @unchecked Sendable {
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
