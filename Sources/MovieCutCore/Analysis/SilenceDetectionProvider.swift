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
        let asset = AVAsset(url: url)

        let silentRanges = try await detectSilentRanges(in: asset)

        let suggestions: [AnalysisSuggestion]
        if silentRanges.isEmpty {
            suggestions = []
        } else {
            suggestions = [.silenceRemoval(ranges: silentRanges)]
        }

        return AnalysisResult(
            suggestions: suggestions,
            sourceAssetID: asset.description,
            providerName: "SilenceDetection"
        )
    }

    // MARK: - Private

    private func detectSilentRanges(in avAsset: AVAsset) async throws -> [TimeRange] {
        let duration = try await avAsset.load(.duration)
        guard duration.isValid && duration.seconds > 0 else { return [] }

        let totalDuration = duration.seconds

        // Load audio tracks
        let tracks = try await avAsset.load(.tracks)
        let audioTracks = tracks.filter { $0.mediaType == .audio }
        guard !audioTracks.isEmpty else { return [] }

        // Use AVAssetReader to read PCM samples
        guard let reader = try? AVAssetReader(asset: avAsset) else { return [] }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let trackOutput = AVAssetReaderTrackOutput(
            track: audioTracks[0],
            outputSettings: outputSettings
        )
        trackOutput.alwaysCopiesSampleData = false
        reader.add(trackOutput)

        guard reader.startReading() else { return [] }

        let sampleRate: Double = 44100
        let configuration = configuration.withLock { $0 }
        let samplesPerChunk = Int(sampleRate * configuration.chunkDuration)
        let bytesPerSample = 2 // 16-bit PCM
        let bytesPerChunk = samplesPerChunk * bytesPerSample

        var silentRanges: [TimeRange] = []
        var currentSilenceStart: TimeInterval?
        var chunkIndex: Int = 0

        while true {
            let buffer = trackOutput.copyNextSampleBuffer()
            guard let buffer = buffer else { break }

            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = [UInt8](repeating: 0, count: length)
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &data)

            // Process in chunks
            var offset = 0
            while offset + bytesPerChunk <= data.count {
                let chunkData = data[offset..<(offset + bytesPerChunk)]
                let rms = computeRMS(chunkData)

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
                offset += bytesPerChunk
            }
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
    private func computeRMS(_ data: ArraySlice<UInt8>) -> Float {
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
