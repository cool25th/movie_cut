import Foundation
import AVFoundation
import os

private struct SilenceDetectionConfiguration: Sendable {
    var silenceThresholdDB: Float
    var minimumSilenceDuration: TimeInterval
    var chunkDuration: TimeInterval
}

/// Detects silent ranges in a media asset by analysing RMS audio power.
public final class SilenceDetectionProvider: AnalysisProvider {
    private let configuration: OSAllocatedUnfairLock<SilenceDetectionConfiguration>

    /// User-visible provider name used consistently in provider lists and analysis results.
    public let providerName = "SilenceDetection"

    /// Minimum RMS power in dB to consider non-silent (default: -40 dB).
    public var silenceThresholdDB: Float {
        get {
            configuration.withLock { $0.silenceThresholdDB }
        }
        set {
            configuration.withLock { $0.silenceThresholdDB = newValue }
        }
    }

    /// Minimum duration in seconds for a silence range to be reported (default: 0.5 s).
    public var minimumSilenceDuration: TimeInterval {
        get {
            configuration.withLock { $0.minimumSilenceDuration }
        }
        set {
            configuration.withLock { $0.minimumSilenceDuration = newValue }
        }
    }

    /// Audio chunk duration used for RMS measurement (default: 0.1 s).
    public var chunkDuration: TimeInterval {
        get {
            configuration.withLock { $0.chunkDuration }
        }
        set {
            configuration.withLock { $0.chunkDuration = newValue }
        }
    }

    /// Whether this provider can run on the current platform (always true for AVFoundation).

    /// Creates a silence detection provider with configurable thresholds.
    public init(
        silenceThresholdDB: Float = -40,
        minimumSilenceDuration: TimeInterval = 0.5,
        chunkDuration: TimeInterval = 0.1
    ) {
        self.configuration = OSAllocatedUnfairLock(initialState: SilenceDetectionConfiguration(
            silenceThresholdDB: silenceThresholdDB,
            minimumSilenceDuration: minimumSilenceDuration,
            chunkDuration: chunkDuration
        ))
    }

    /// Analyzes the asset audio track and returns silence-removal suggestions.
    public func analyze(asset: MediaAsset, in project: Project) async throws -> AnalysisResult {
        let url = asset.originalURL

        let silentRanges = try await detectSilentRanges(at: url)

        let suggestions: [AnalysisSuggestion]
        if silentRanges.isEmpty {
            suggestions = []
        } else {
            suggestions = [.silenceRemoval(ranges: silentRanges)]
        }

        return AnalysisResult(
            suggestions: suggestions,
            sourceAssetID: asset.id.uuidString,
            providerName: providerName
        )
    }

    // MARK: - Private

    private func detectSilentRanges(at url: URL) async throws -> [TimeRange] {
        let configuration = configuration.withLock { $0 }
        // The PCM decode below is a synchronous, blocking AVAssetReader read.
        // Capture only Sendable inputs (URL + config) and open the asset
        // inside the off-pool closure so no non-Sendable object is captured.
        // Running this on a cooperative thread starves the pool and deadlocks
        // concurrent test runs.
        return try await Self.decodeSamples {
            try Self.decodeSilentRanges(at: url, configuration: configuration)
        }
    }

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

    /// Synchronously decodes silence ranges from the asset audio track. Blocking.
    private static func decodeSilentRanges(
        at url: URL,
        configuration: SilenceDetectionConfiguration
    ) throws -> [TimeRange] {
        let avAsset = AVAsset(url: url)
        let totalDuration = CMTimeGetSeconds(avAsset.duration)
        guard totalDuration > 0 else { return [] }

        guard let reader = try? AVAssetReader(asset: avAsset) else { return [] }
        let audioTracks = avAsset.tracks(withMediaType: .audio)
        guard let firstAudioTrack = audioTracks.first else { return [] }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let trackOutput = AVAssetReaderTrackOutput(
            track: firstAudioTrack,
            outputSettings: outputSettings
        )
        trackOutput.alwaysCopiesSampleData = false
        reader.add(trackOutput)

        guard reader.startReading() else { return [] }

        let sampleRate: Double = 44100
        let samplesPerChunk = Int(sampleRate * configuration.chunkDuration)
        let bytesPerSample = 2 // 16-bit PCM
        let bytesPerChunk = samplesPerChunk * bytesPerSample

        var silentRanges: [TimeRange] = []
        var currentSilenceStart: TimeInterval?
        var chunkIndex: Int = 0
        var pendingBytes = [UInt8]()
        pendingBytes.reserveCapacity(bytesPerChunk * 2)

        func processChunk(_ chunkData: ArraySlice<UInt8>) {
            let rms = Self.computeRMS(chunkData)

            let chunkStartTime = Double(chunkIndex) * configuration.chunkDuration
            let isSilent = rms < configuration.silenceThresholdDB

            if isSilent {
                if currentSilenceStart == nil {
                    currentSilenceStart = chunkStartTime
                }
            } else {
                if let start = currentSilenceStart {
                    let silenceDuration = chunkStartTime - start
                    if silenceDuration >= configuration.minimumSilenceDuration {
                        silentRanges.append(TimeRange(start: start, duration: silenceDuration))
                    }
                    currentSilenceStart = nil
                }
            }

            chunkIndex += 1
        }

        while true {
            let buffer = trackOutput.copyNextSampleBuffer()
            guard let buffer = buffer else { break }

            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            guard length > 0 else { continue }

            let pendingCount = pendingBytes.count
            pendingBytes.append(contentsOf: repeatElement(0, count: length))
            pendingBytes.withUnsafeMutableBytes { bytes in
                if let baseAddress = bytes.baseAddress {
                    CMBlockBufferCopyDataBytes(
                        blockBuffer,
                        atOffset: 0,
                        dataLength: length,
                        destination: baseAddress.advanced(by: pendingCount)
                    )
                }
            }

            // Process fixed-size chunks across CMSampleBuffer boundaries. Keeping the
            // tail avoids dropping partial audio frames from every reader buffer, which
            // can shift detected silence ranges and hide short gaps in fixture-sized
            // media files.
            var offset = 0
            while offset + bytesPerChunk <= pendingBytes.count {
                processChunk(pendingBytes[offset..<(offset + bytesPerChunk)])
                offset += bytesPerChunk
            }

            if offset > 0 {
                pendingBytes.removeFirst(offset)
            }
        }

        if !pendingBytes.isEmpty {
            processChunk(pendingBytes[...])
        }

        // Handle trailing silence
        if let start = currentSilenceStart {
            let silenceDuration = totalDuration - start
            if silenceDuration >= configuration.minimumSilenceDuration {
                silentRanges.append(TimeRange(start: start, duration: silenceDuration))
            }
        }

        reader.cancelReading()
        return silentRanges
    }

    /// Computes RMS power in dB for a chunk of 16-bit PCM samples.
    private static func computeRMS(_ data: ArraySlice<UInt8>) -> Float {
        var sumSquares: Float = 0
        let sampleCount = data.count / 2

        guard sampleCount > 0 else { return -Float.infinity }

        for i in stride(from: data.startIndex, to: data.endIndex - 1, by: 2) {
            let lo = Int16(data[i])
            let hi = Int16(data[i + 1]) << 8
            let sample = Float(lo | hi)
            sumSquares += sample * sample
        }

        let meanSquare = sumSquares / Float(sampleCount)
        let rms = sqrtf(meanSquare)

        // Convert to dB (reference: Int16.max = 32767)
        let db = 20 * log10f(rms / 32767.0)
        return db.isFinite ? db : -Float.infinity
    }
}
