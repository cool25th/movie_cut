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

        let reader = try AVAssetReader(asset: clip)
        reader.timeRange = effectiveTimeRange

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

        var sampleBuffers: [CMSampleBuffer] = []

        do {
            guard reader.startReading() else {
                throw reader.error ?? ReverseRenderServiceError.readerFailed
            }

            let durationSeconds = effectiveTimeRange.duration.seconds
            while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                try Task.checkCancellation()
                sampleBuffers.append(sampleBuffer)

                if durationSeconds.isFinite, durationSeconds > 0 {
                    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    let elapsedSeconds: Double = CMTimeSubtract(
                        presentationTime,
                        effectiveTimeRange.start
                    ).seconds
                    Self.report(progress, readFraction: elapsedSeconds / durationSeconds, writeFraction: 0)
                }
            }

            switch reader.status {
            case .completed:
                Self.report(progress, readFraction: 1, writeFraction: 0)
            case .cancelled:
                throw CancellationError()
            case .failed:
                throw reader.error ?? ReverseRenderServiceError.readerFailed
            default:
                break
            }

            guard !sampleBuffers.isEmpty else {
                throw ReverseRenderServiceError.noSamples
            }

            guard writer.startWriting() else {
                throw writer.error ?? ReverseRenderServiceError.writerFailed
            }
            writer.startSession(atSourceTime: .zero)

            let defaultFrameDuration = try await Self.defaultFrameDuration(for: videoTrack)
            let sampleDurations = sampleBuffers.enumerated().map { index, sampleBuffer in
                Self.duration(
                    for: sampleBuffer,
                    at: index,
                    in: sampleBuffers,
                    defaultDuration: defaultFrameDuration
                )
            }

            var nextPresentationTime = CMTime.zero
            let totalSamples = max(sampleBuffers.count, 1)
            let imageContext = CIContext(options: RenderColorConfiguration.contextOptions.merging([.useSoftwareRenderer: false]) { _, new in new })

            for (writeIndex, sampleBuffer) in sampleBuffers.reversed().enumerated() {
                try Task.checkCancellation()
                try await Self.waitForWriterInput(writerInput, writer: writer)

                let sourceIndex = sampleBuffers.count - 1 - writeIndex
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
                Self.report(
                    progress,
                    readFraction: 1,
                    writeFraction: Double(writeIndex + 1) / Double(totalSamples)
                )
            }

            writerInput.markAsFinished()
            await withCheckedContinuation { continuation in
                writer.finishWriting {
                    continuation.resume()
                }
            }
            sampleBuffers.removeAll(keepingCapacity: false)
            reader.cancelReading()

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
            reader.cancelReading()
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
