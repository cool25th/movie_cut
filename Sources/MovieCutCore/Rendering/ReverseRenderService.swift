import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import ImageIO

/// Renders a reversed copy of a clip's video range by reading all frames and
/// writing them back in reverse order. Shared by the Mac and iOS export
/// pipelines so reverse-playback clips render identically on both platforms.
public final class ReverseRenderService: Sendable {
    public init() {}

    public func renderReversed(
        clip: AVAsset,
        timeRange: CMTimeRange,
        outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CMTimeRange {
        let videoTracks = try await clip.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw ReverseRenderServiceError.noVideoTrack
        }
        let availableRange = try await videoTrack.load(.timeRange)
        let effectiveTimeRange = CMTimeRangeGetIntersection(timeRange, otherRange: availableRange)
        guard effectiveTimeRange.isValid,
              effectiveTimeRange.duration.isNumeric,
              effectiveTimeRange.duration > .zero else {
            throw ReverseRenderServiceError.invalidTimeRange
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let width = max(Int(abs(naturalSize.width).rounded()), 1)
        let height = max(Int(abs(naturalSize.height).rounded()), 1)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: Self.fileType(for: outputURL))
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        writerInput.expectsMediaDataInRealTime = false

        guard writer.canAdd(writerInput) else {
            throw ReverseRenderServiceError.cannotAddWriterInput
        }
        writer.add(writerInput)
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        // OOM guard: instead of accumulating the ENTIRE range's decompressed
        // 32BGRA frames in one array, decode at most 1-second windows from
        // the END of the range backwards, appending each window reversed
        // before reading the next.
        let chunkWindows = Self.chunkWindows(in: effectiveTimeRange, maxSeconds: 1.0)
        let durationSeconds = effectiveTimeRange.duration.seconds

        let defaultFrameDuration = try await Self.defaultFrameDuration(for: videoTrack)
        let imageContext = CIContext(options: RenderColorConfiguration.contextOptions.merging([.useSoftwareRenderer: false]) { _, new in new })

        var writerStarted = false
        var totalDecodedFrames = 0
        var nextPresentationTime = CMTime.zero

        do {
            for (chunkIndex, window) in chunkWindows.enumerated() {
                try Task.checkCancellation()

                let reader = try AVAssetReader(asset: clip)
                reader.timeRange = window
                let readerOutput = AVAssetReaderTrackOutput(
                    track: videoTrack,
                    outputSettings: [
                        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                    ]
                )
                readerOutput.alwaysCopiesSampleData = false
                guard reader.canAdd(readerOutput) else {
                    throw ReverseRenderServiceError.cannotAddReaderOutput
                }
                reader.add(readerOutput)
                guard reader.startReading() else {
                    throw reader.error ?? ReverseRenderServiceError.readerFailed
                }

                var chunkSamples: [CMSampleBuffer] = []
                while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                    try Task.checkCancellation()
                    chunkSamples.append(sampleBuffer)
                }

                switch reader.status {
                case .completed:
                    break
                case .cancelled:
                    throw CancellationError()
                case .failed:
                    throw reader.error ?? ReverseRenderServiceError.readerFailed
                default:
                    break
                }
                reader.cancelReading()

                guard !chunkSamples.isEmpty else {
                    Self.report(
                        progress,
                        readFraction: Double(chunkIndex) / Double(max(chunkWindows.count, 1)),
                        writeFraction: Self.writeFraction(of: nextPresentationTime, in: durationSeconds)
                    )
                    continue
                }

                // The writer starts only once the first (rearmost) non-empty
                // chunk is decoded, so an all-empty range never opens a
                // writing session.
                if !writerStarted {
                    guard writer.startWriting() else {
                        throw writer.error ?? ReverseRenderServiceError.writerFailed
                    }
                    writer.startSession(atSourceTime: .zero)
                    writerStarted = true
                }
                totalDecodedFrames += chunkSamples.count

                let sampleDurations = chunkSamples.enumerated().map { index, sampleBuffer in
                    Self.duration(
                        for: sampleBuffer,
                        at: index,
                        in: chunkSamples,
                        defaultDuration: defaultFrameDuration
                    )
                }

                for (writeIndex, sampleBuffer) in chunkSamples.reversed().enumerated() {
                    try Task.checkCancellation()
                    try await Self.waitForWriterInput(writerInput, writer: writer)

                    let sourceIndex = chunkSamples.count - 1 - writeIndex
                    let duration = sampleDurations[sourceIndex]
                    guard let sourcePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                          let pixelBufferPool = pixelBufferAdaptor.pixelBufferPool else {
                        throw ReverseRenderServiceError.appendFailed
                    }
                    var normalizedPixelBuffer: CVPixelBuffer?
                    let poolStatus = CVPixelBufferPoolCreatePixelBuffer(
                        kCFAllocatorDefault,
                        pixelBufferPool,
                        &normalizedPixelBuffer
                    )
                    guard poolStatus == kCVReturnSuccess, let normalizedPixelBuffer else {
                        throw ReverseRenderServiceError.appendFailed
                    }
                    imageContext.render(CIImage(cvPixelBuffer: sourcePixelBuffer), to: normalizedPixelBuffer)
                    guard pixelBufferAdaptor.append(
                        normalizedPixelBuffer,
                        withPresentationTime: nextPresentationTime
                    ) else {
                        throw writer.error ?? ReverseRenderServiceError.appendFailed
                    }

                    nextPresentationTime = CMTimeAdd(nextPresentationTime, duration)
                }

                Self.report(
                    progress,
                    readFraction: Double(chunkIndex + 1) / Double(max(chunkWindows.count, 1)),
                    writeFraction: Self.writeFraction(of: nextPresentationTime, in: durationSeconds)
                )
                chunkSamples.removeAll(keepingCapacity: false)
            }

            guard totalDecodedFrames > 0, writerStarted else {
                throw ReverseRenderServiceError.noSamples
            }

            writerInput.markAsFinished()
            await withCheckedContinuation { continuation in
                writer.finishWriting {
                    continuation.resume()
                }
            }

            switch writer.status {
            case .completed:
                progress(1)
                let renderedAsset = AVURLAsset(url: outputURL)
                guard let renderedTrack = try await renderedAsset.loadTracks(withMediaType: .video).first else {
                    throw ReverseRenderServiceError.noOutputTrack
                }
                let renderedRange = try await renderedTrack.load(.timeRange)
                guard renderedRange.isValid,
                      CMTIME_IS_NUMERIC(renderedRange.duration),
                      renderedRange.duration > .zero else {
                    throw ReverseRenderServiceError.invalidOutputDuration
                }
                return renderedRange
            case .cancelled:
                throw CancellationError()
            case .failed:
                throw writer.error ?? ReverseRenderServiceError.writerFailed
            default:
                throw writer.error ?? ReverseRenderServiceError.writerFailed
            }
        } catch {
            writer.cancelWriting()
            let underlyingError = error as NSError
            throw NSError(
                domain: "MovieCut.ReverseRenderService",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Reverse rendering failed: \(underlyingError.localizedDescription)",
                    NSUnderlyingErrorKey: underlyingError
                ]
            )
        }
    }

    /// Splits a range into equal windows of at most `maxSeconds`, ordered
    /// from the END of the range backwards (the reverse-render order).
    private static func chunkWindows(in range: CMTimeRange, maxSeconds: Double) -> [CMTimeRange] {
        let totalSeconds = range.duration.seconds
        guard totalSeconds.isFinite, totalSeconds > 0 else {
            return [range]
        }

        let chunkCount = max(1, Int((totalSeconds / maxSeconds).rounded(.up)))
        let chunkDuration = CMTime(seconds: totalSeconds / Double(chunkCount), preferredTimescale: range.start.timescale)
        return (0..<chunkCount).map { index in
            let start = CMTimeAdd(
                range.start,
                CMTimeMultiply(chunkDuration, multiplier: Int32(chunkCount - 1 - index))
            )
            // index 0 is the rearmost window — pin its end to the range end so
            // timescale rounding can never truncate the final chunk.
            let end: CMTime
            if index == 0 {
                end = CMTimeRangeGetEnd(range)
            } else {
                end = CMTimeAdd(range.start, CMTimeMultiply(chunkDuration, multiplier: Int32(chunkCount - index)))
            }
            return CMTimeRange(start: start, duration: CMTimeSubtract(end, start))
        }
    }

    private static func writeFraction(of presentationTime: CMTime, in durationSeconds: Double) -> Double {
        guard durationSeconds.isFinite, durationSeconds > 0 else { return 0 }
        return presentationTime.seconds / durationSeconds
    }

    private static func waitForWriterInput(_ writerInput: AVAssetWriterInput, writer: AVAssetWriter) async throws {
        while !writerInput.isReadyForMoreMediaData {
            try Task.checkCancellation()

            switch writer.status {
            case .failed:
                throw writer.error ?? ReverseRenderServiceError.writerFailed
            case .cancelled:
                throw CancellationError()
            default:
                break
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private static func duration(
        for sampleBuffer: CMSampleBuffer,
        at index: Int,
        in sampleBuffers: [CMSampleBuffer],
        defaultDuration: CMTime
    ) -> CMTime {
        let sampleDuration = CMSampleBufferGetDuration(sampleBuffer)
        if isPositive(sampleDuration) {
            return sampleDuration
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if index + 1 < sampleBuffers.count {
            let nextPresentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffers[index + 1])
            let delta = CMTimeSubtract(nextPresentationTime, presentationTime)
            if isPositive(delta) {
                return delta
            }
        }

        if index > 0 {
            let previousPresentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffers[index - 1])
            let delta = CMTimeSubtract(presentationTime, previousPresentationTime)
            if isPositive(delta) {
                return delta
            }
        }

        return defaultDuration
    }

    private static func defaultFrameDuration(for videoTrack: AVAssetTrack) async throws -> CMTime {
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        guard nominalFrameRate > 0 else {
            return CMTime(value: 1, timescale: 30)
        }

        return CMTime(seconds: 1 / Double(nominalFrameRate), preferredTimescale: 600)
    }

    private static func isPositive(_ time: CMTime) -> Bool {
        time.isValid && time.seconds.isFinite && time.seconds > 0
    }

    private static func report(
        _ progress: (Double) -> Void,
        readFraction: Double,
        writeFraction: Double
    ) {
        let value = (clamped(readFraction) + clamped(writeFraction)) / 2
        progress(value)
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func fileType(for url: URL) -> AVFileType {
        switch url.pathExtension.lowercased() {
        case "mp4":
            return .mp4
        case "m4v":
            return .m4v
        default:
            return .mov
        }
    }
}

public enum ReverseRenderServiceError: LocalizedError, Sendable {
    case noVideoTrack
    case invalidTimeRange
    case noSamples
    case cannotAddReaderOutput
    case cannotAddWriterInput
    case readerFailed
    case writerFailed
    case appendFailed
    case noOutputTrack
    case invalidOutputDuration

    public var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "The asset does not contain a video track."
        case .invalidTimeRange:
            return "The requested reverse range does not intersect the source video track."
        case .noSamples:
            return "The reverse renderer found no video samples in the requested range."
        case .cannotAddReaderOutput:
            return "The reverse renderer could not add the asset reader output."
        case .cannotAddWriterInput:
            return "The reverse renderer could not add the asset writer input."
        case .readerFailed:
            return "The reverse renderer failed while reading samples."
        case .writerFailed:
            return "The reverse renderer failed while writing samples."
        case .appendFailed:
            return "The reverse renderer failed to append a reversed frame."
        case .noOutputTrack:
            return "The reverse renderer produced no readable video track."
        case .invalidOutputDuration:
            return "The reverse renderer produced a video track with no valid duration."
        }
    }
}
