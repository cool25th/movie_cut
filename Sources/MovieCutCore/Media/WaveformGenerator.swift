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

/// Generates waveform sample data for an imported media asset by decoding the
/// audio track into peak bins.
///
/// The underlying `AVAssetReader` performs **synchronous blocking reads**. Such
/// work must never run on Swift Concurrency's cooperative thread pool, because
/// a long decode starves the limited cooperative threads and can deadlock a
/// test suite (or stall the UI). Always prefer ``generateAsync(for:)``, which
/// dispatches the decode onto a non-cooperative GCD thread. The synchronous
/// ``generate(for:)`` is retained only for non-concurrent callers; do not call
/// it from a `Task`/`async`/`@MainActor` context.
public struct WaveformGenerator: Sendable {
    /// Asynchronously generates waveform sample data, decoding the asset audio
    /// track on a non-cooperative GCD thread so the cooperative pool and the UI
    /// thread are never blocked.
    public static func generateAsync(for asset: MediaAsset) async -> WaveformData? {
        // Capture only Sendable data (the URL); construct the non-Sendable
        // AVAsset/AVAssetReader inside the off-pool closure.
        let url = asset.originalURL
        return await Self.decodeSamples { decodeWaveform(at: url) }
    }

    /// Generates waveform sample data for an imported media asset.
    ///
    /// - Warning: This performs a synchronous, blocking `AVAssetReader` read.
    ///   Do **not** call from a `Task`/`async`/`@MainActor` context — it will
    ///   block the cooperative pool (deadlock risk) or the UI thread. Use
    ///   ``generateAsync(for:)`` instead.
    public static func generate(for asset: MediaAsset) -> WaveformData? {
        #if canImport(AVFoundation)
        return decodeWaveform(at: asset.originalURL)
        #else
        return nil
        #endif
    }

    /// Moves a blocking decode closure off the cooperative thread pool onto a
    /// non-cooperative GCD thread. `Task.detached` is intentionally **not**
    /// used: it still runs on the cooperative pool and would not relieve thread
    /// starvation.
    private static func decodeSamples<T: Sendable>(
        _ work: @escaping @Sendable () -> T?
    ) async -> T? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }

    #if canImport(AVFoundation)
    /// Synchronously decodes the audio track at `url` into peak bins. Blocking.
    private static func decodeWaveform(at url: URL) -> WaveformData? {
        let avAsset = AVAsset(url: url)
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
    }
    #endif
}
