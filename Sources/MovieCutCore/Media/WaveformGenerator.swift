import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Serialized waveform samples for an audio asset.
public struct WaveformData: Codable, Sendable, Equatable {
    /// Normalized audio samples.
    public var samples: [Float]

    /// The number of source samples represented by this waveform.
    public var sampleCount: Int

    /// Creates waveform data.
    public init(samples: [Float], sampleCount: Int) {
        self.samples = samples
        self.sampleCount = sampleCount
    }
}

/// Placeholder waveform generation API until audio decoding is introduced.
public struct WaveformGenerator: Sendable {
    /// Generates waveform sample data for an imported media asset.
    public static func generate(for asset: MediaAsset) -> WaveformData? {
        #if canImport(AVFoundation)
        let avAsset = AVAsset(url: asset.originalURL)
        guard let audioTrack = avAsset.tracks(withMediaType: .audio).first else {
            return nil
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        guard let reader = try? AVAssetReader(asset: avAsset) else {
            return nil
        }

        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            return nil
        }
        reader.add(output)

        guard reader.startReading() else {
            return nil
        }

        let binCount = 200
        let sampleRate = 44_100.0
        let duration = CMTimeGetSeconds(audioTrack.timeRange.duration)
        let estimatedSampleCount = max(1, Int((duration.isFinite ? duration : 0) * sampleRate))
        let bytesPerSample = 2
        let maxSampleValue = Float(Int16.max)
        var bins = [Float](repeating: 0, count: binCount)
        var totalSamplesRead = 0

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                continue
            }

            let length = CMBlockBufferGetDataLength(blockBuffer)
            guard length >= bytesPerSample else {
                continue
            }

            var data = [UInt8](repeating: 0, count: length)
            guard CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: length,
                destination: &data
            ) == noErr else {
                continue
            }

            var offset = 0
            while offset + bytesPerSample <= data.count {
                let low = UInt16(data[offset])
                let high = UInt16(data[offset + 1]) << 8
                let sample = Int16(bitPattern: high | low)
                let normalized = min(Float(abs(Int(sample))) / maxSampleValue, 1)
                let binIndex = min(totalSamplesRead * binCount / estimatedSampleCount, binCount - 1)
                bins[binIndex] = max(bins[binIndex], normalized)

                totalSamplesRead += 1
                offset += bytesPerSample
            }
        }

        guard reader.status != .failed, reader.status != .cancelled, totalSamplesRead > 0 else {
            return nil
        }

        return WaveformData(samples: bins, sampleCount: totalSamplesRead)
        #else
        nil
        #endif
    }
}
