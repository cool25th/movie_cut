#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation

/// Detects musical beats with an energy-flux onset detector (F-15). The
/// detection math is a pure function over mono samples so it can be tested
/// with synthesized click tracks; the AVFoundation wrapper mirrors the
/// silence provider's PCM reading.
public struct BeatDetectionProvider: Sendable {
    /// Detection tuning.
    public struct Configuration: Sendable {
        /// Analysis frame size in samples.
        public var frameSize: Int

        /// Hop between frames in samples.
        public var hopSize: Int

        /// Minimum spacing between reported beats in seconds (~240 BPM cap).
        public var minimumBeatInterval: TimeInterval

        /// Multiplier over the local mean flux required to count as an onset.
        public var sensitivity: Double

        public init(
            frameSize: Int = 1024,
            hopSize: Int = 512,
            minimumBeatInterval: TimeInterval = 0.25,
            sensitivity: Double = 1.5
        ) {
            self.frameSize = max(64, frameSize)
            self.hopSize = max(32, hopSize)
            self.minimumBeatInterval = max(0.05, minimumBeatInterval)
            self.sensitivity = max(1.0, sensitivity)
        }
    }

    public var configuration: Configuration

    /// Creates a beat detection provider.
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Pure detection math

    /// Detects beat times (seconds) in mono floating-point samples.
    ///
    /// Energy flux onset detection: per-frame energy, positive energy
    /// differences (flux), an adaptive threshold from the local flux mean,
    /// then peak picking with a minimum beat interval.
    public func detectBeats(monoSamples: [Float], sampleRate: Double) -> [TimeInterval] {
        guard sampleRate > 0, monoSamples.count >= configuration.frameSize else { return [] }

        let frameSize = configuration.frameSize
        let hopSize = configuration.hopSize

        // Pre-size the per-hop accumulators: one entry per hop position.
        let expectedFrames = (monoSamples.count - frameSize) / hopSize + 1
        var energies: [Double] = []
        energies.reserveCapacity(expectedFrames)
        var start = 0
        while start + frameSize <= monoSamples.count {
            var energy = 0.0
            for index in start..<(start + frameSize) {
                let sample = Double(monoSamples[index])
                energy += sample * sample
            }
            energies.append(energy / Double(frameSize))
            start += hopSize
        }
        guard energies.count > 2 else { return [] }

        var flux: [Double] = [0]
        flux.reserveCapacity(expectedFrames)
        for index in 1..<energies.count {
            flux.append(max(0, energies[index] - energies[index - 1]))
        }

        let meanFlux = flux.reduce(0, +) / Double(flux.count)
        guard meanFlux > 0 else { return [] }
        // The adaptive threshold alone fires on the tiny frame-boundary energy
        // ripple of steady tones, so require onsets to also jump by a fraction
        // of the loudest frame's energy.
        let peakEnergy = energies.max() ?? 0
        let threshold = max(meanFlux * configuration.sensitivity, peakEnergy * 0.1)

        var beats: [TimeInterval] = []
        let hopDuration = Double(hopSize) / sampleRate
        var lastBeat = -configuration.minimumBeatInterval

        for index in 1..<(flux.count - 1) {
            let value = flux[index]
            guard value > threshold,
                  value >= flux[index - 1],
                  value >= flux[index + 1]
            else { continue }

            let time = Double(index) * hopDuration
            guard time - lastBeat >= configuration.minimumBeatInterval else { continue }

            beats.append(time)
            lastBeat = time
        }

        return beats
    }

    /// Estimates BPM from detected beat times using the median interval.
    public static func estimatedBPM(from beats: [TimeInterval]) -> Double? {
        guard beats.count >= 2 else { return nil }
        let intervals = zip(beats.dropFirst(), beats).map(-).sorted()
        let median = intervals[intervals.count / 2]
        guard median > 0 else { return nil }
        return 60.0 / median
    }

    #if canImport(AVFoundation)
    // MARK: - AVFoundation wrapper

    /// Reads the asset's first audio track as mono PCM and detects beats in
    /// source-time seconds. The blocking PCM decode is moved off the
    /// cooperative thread pool onto a non-cooperative GCD thread.
    public func analyze(asset: MediaAsset) async throws -> [TimeInterval] {
        let url = asset.proxy?.proxyURL ?? asset.originalURL
        let avAsset = AVAsset(url: url)

        let tracks = try await avAsset.load(.tracks)
        guard tracks.contains(where: { $0.mediaType == .audio }) else {
            return []
        }

        let samples = try await Self.decodeSamples { try readMonoSamples(at: url) }
        return detectBeats(monoSamples: samples, sampleRate: Self.analysisSampleRate)
    }

    private static let analysisSampleRate: Double = 22050

    /// Moves a blocking decode closure off the cooperative thread pool onto a
    /// non-cooperative GCD thread. `Task.detached` still runs on the
    /// cooperative pool and would not relieve thread starvation, so it is
    /// intentionally avoided.
    private static func decodeSamples<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Synchronously reads the asset's first audio track as mono PCM. Blocking.
    private func readMonoSamples(at url: URL) throws -> [Float] {
        let avAsset = AVAsset(url: url)
        guard let reader = try? AVAssetReader(asset: avAsset) else { return [] }

        let audioTracks = avAsset.tracks(withMediaType: .audio)
        guard let track = audioTracks.first else { return [] }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.analysisSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        trackOutput.alwaysCopiesSampleData = false
        reader.add(trackOutput)
        guard reader.startReading() else { return [] }

        var samples: [Float] = []
        let durationSeconds = CMTimeGetSeconds(track.timeRange.duration)
        if durationSeconds.isFinite && durationSeconds > 0 {
            samples.reserveCapacity(Int(durationSeconds * Self.analysisSampleRate))
        }
        // Zero-copy: contiguous block buffers are walked in place through
        // their data pointer; only a non-contiguous one pays a copy, into a
        // scratch buffer reused across every remaining sample buffer. The
        // normalization keeps the original division (NOT a reciprocal
        // multiply) so sample values stay bit-identical.
        var scratchBytes: [UInt8] = []

        func absorb(_ rawBytes: UnsafeRawBufferPointer) {
            var index = 0
            while index + 1 < rawBytes.count {
                let value = Int16(littleEndian: Int16(bitPattern: UInt16(rawBytes[index]) | (UInt16(rawBytes[index + 1]) << 8)))
                samples.append(Float(value) / Float(Int16.max))
                index += 2
            }
        }

        while let buffer = trackOutput.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            guard length >= 2 else { continue }

            var dataPointer: UnsafeMutablePointer<Int8>?
            var dataLength = 0
            var totalLength = 0
            if CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: &dataLength,
                totalLengthOut: &totalLength,
                dataPointerOut: &dataPointer
            ) == noErr,
               let dataPointer,
               dataLength >= length {
                absorb(UnsafeRawBufferPointer(start: dataPointer, count: length))
            } else {
                if scratchBytes.count < length {
                    scratchBytes = [UInt8](repeating: 0, count: length)
                }
                guard CMBlockBufferCopyDataBytes(
                    blockBuffer,
                    atOffset: 0,
                    dataLength: length,
                    destination: &scratchBytes
                ) == noErr else {
                    continue
                }
                scratchBytes.withUnsafeBytes { raw in
                    absorb(UnsafeRawBufferPointer(rebasing: raw.prefix(length)))
                }
            }
        }

        reader.cancelReading()
        return samples
    }
    #endif
}
