import Foundation

#if canImport(AVFoundation)
import AudioToolbox
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
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let highPassEQ = AVAudioUnitEQ(numberOfBands: 1)
        let lowPassEQ = AVAudioUnitEQ(numberOfBands: 1)
        let dynamicsProcessor = makeDynamicsProcessor(threshold: threshold)

        let inputFile = try AVAudioFile(forReading: inputURL)
        let inputFormat = inputFile.processingFormat
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw NoiseReductionServiceError.invalidInputFormat
        }
        guard inputFile.length > 0 else {
            throw NoiseReductionServiceError.emptyAsset
        }
        guard inputFile.length <= AVAudioFramePosition(UInt32.max) else {
            throw NoiseReductionServiceError.inputTooLarge
        }

        let frameCapacity = AVAudioFrameCount(inputFile.length)
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: frameCapacity
        ) else {
            throw NoiseReductionServiceError.renderBufferUnavailable
        }

        try inputFile.read(into: sourceBuffer, frameCount: frameCapacity)
        guard sourceBuffer.frameLength > 0 else {
            throw NoiseReductionServiceError.emptyAsset
        }

        configureHighPass(highPassEQ)
        configureLowPass(lowPassEQ)

        engine.attach(player)
        engine.attach(highPassEQ)
        engine.attach(lowPassEQ)
        engine.attach(dynamicsProcessor)

        engine.connect(player, to: highPassEQ, format: inputFormat)
        engine.connect(highPassEQ, to: lowPassEQ, format: inputFormat)
        engine.connect(lowPassEQ, to: dynamicsProcessor, format: inputFormat)
        engine.connect(dynamicsProcessor, to: engine.mainMixerNode, format: inputFormat)

        defer {
            player.stop()
            engine.stop()
            engine.disableManualRenderingMode()
        }

        try engine.enableManualRenderingMode(
            .offline,
            format: inputFormat,
            maximumFrameCount: 4_096
        )

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

        try engine.start()
        player.scheduleBuffer(sourceBuffer, at: nil, options: [])
        player.play()

        guard let renderBuffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        ) else {
            throw NoiseReductionServiceError.renderBufferUnavailable
        }

        let totalFrames = AVAudioFramePosition(sourceBuffer.frameLength)
        var stalledRenderCount = 0

        while engine.manualRenderingSampleTime < totalFrames {
            let remainingFrames = totalFrames - engine.manualRenderingSampleTime
            let frameCount = min(
                AVAudioFrameCount(remainingFrames),
                engine.manualRenderingMaximumFrameCount
            )

            guard frameCount > 0 else { break }

            let status = try engine.renderOffline(frameCount, to: renderBuffer)
            switch status {
            case .success:
                stalledRenderCount = 0
                if renderBuffer.frameLength > 0 {
                    try outputFile.write(from: renderBuffer)
                }
            case .insufficientDataFromInputNode:
                stalledRenderCount += 1
                if stalledRenderCount > 8 {
                    throw NoiseReductionServiceError.renderingFailed
                }
                continue
            case .cannotDoInCurrentContext:
                continue
            case .error:
                throw NoiseReductionServiceError.renderingFailed
            @unknown default:
                throw NoiseReductionServiceError.renderingFailed
            }
        }

        return outputURL
    }

    private func configureHighPass(_ eq: AVAudioUnitEQ) {
        guard let band = eq.bands.first else { return }
        band.filterType = .highPass
        band.frequency = 80
        band.bandwidth = 0.5
        band.bypass = false
        eq.globalGain = 0
    }

    private func configureLowPass(_ eq: AVAudioUnitEQ) {
        guard let band = eq.bands.first else { return }
        band.filterType = .lowPass
        band.frequency = 12_000
        band.bandwidth = 0.5
        band.bypass = false
        eq.globalGain = 0
    }

    private func makeDynamicsProcessor(threshold: Float) -> AVAudioUnitEffect {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        let processor = AVAudioUnitEffect(audioComponentDescription: description)
        let thresholdDB = compressorThresholdDecibels(from: threshold)

        setParameter(address: 0, value: thresholdDB, on: processor)
        setParameter(address: 1, value: 5, on: processor)
        setParameter(address: 2, value: 4, on: processor)
        setParameter(address: 3, value: thresholdDB, on: processor)
        setParameter(address: 4, value: 0.01, on: processor)
        setParameter(address: 5, value: 0.1, on: processor)
        setParameter(address: 6, value: 0, on: processor)

        return processor
    }

    private func setParameter(address: AUParameterAddress, value: AUValue, on unit: AVAudioUnitEffect) {
        unit.auAudioUnit.parameterTree?.parameter(withAddress: address)?.value = value
    }

    private func compressorThresholdDecibels(from threshold: Float) -> Float {
        let clampedThreshold = min(max(threshold, 0), 1)
        let normalized = min(clampedThreshold / 0.05, 2)
        return -60 + normalized * 20
    }
}

private enum NoiseReductionServiceError: Error, Sendable, Equatable {
    case emptyAsset
    case noAudioTracks
    case exportSessionCreationFailed
    case invalidInputFormat
    case inputTooLarge
    case renderBufferUnavailable
    case renderingFailed
}
#endif
