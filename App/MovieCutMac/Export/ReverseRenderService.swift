import AVFoundation

final class ReverseRenderService {
    func renderReversed(
        clip: AVAsset,
        timeRange: CMTimeRange,
        outputURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        let videoTracks = try await clip.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw ReverseRenderServiceError.noVideoTrack
        }

        let reader = try AVAssetReader(asset: clip)
        reader.timeRange = timeRange

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
        writerInput.transform = try await videoTrack.load(.preferredTransform)

        guard writer.canAdd(writerInput) else {
            throw ReverseRenderServiceError.cannotAddWriterInput
        }
        writer.add(writerInput)

        var sampleBuffers: [CMSampleBuffer] = []

        do {
            guard reader.startReading() else {
                throw reader.error ?? ReverseRenderServiceError.readerFailed
            }

            let durationSeconds = timeRange.duration.seconds
            while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                try Task.checkCancellation()
                sampleBuffers.append(sampleBuffer)

                if durationSeconds.isFinite, durationSeconds > 0 {
                    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    let elapsed = CMTimeSubtract(presentationTime, timeRange.start).seconds
                    Self.report(progress, readFraction: elapsed / durationSeconds, writeFraction: 0)
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

            for (writeIndex, sampleBuffer) in sampleBuffers.reversed().enumerated() {
                try Task.checkCancellation()
                try await Self.waitForWriterInput(writerInput, writer: writer)

                let sourceIndex = sampleBuffers.count - 1 - writeIndex
                let duration = sampleDurations[sourceIndex]
                let retimedSample = try Self.retimedSampleBuffer(
                    sampleBuffer,
                    presentationTime: nextPresentationTime,
                    duration: duration
                )

                guard writerInput.append(retimedSample) else {
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

            switch writer.status {
            case .completed:
                progress(1)
            case .cancelled:
                throw CancellationError()
            case .failed:
                throw writer.error ?? ReverseRenderServiceError.writerFailed
            default:
                break
            }
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            throw error
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

    private static func retimedSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        presentationTime: CMTime,
        duration: CMTime
    ) throws -> CMSampleBuffer {
        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var retimedSampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &retimedSampleBuffer
        )

        guard status == noErr, let retimedSampleBuffer else {
            throw ReverseRenderServiceError.retimingFailed(status)
        }

        return retimedSampleBuffer
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

private enum ReverseRenderServiceError: LocalizedError, Sendable {
    case noVideoTrack
    case cannotAddReaderOutput
    case cannotAddWriterInput
    case readerFailed
    case writerFailed
    case appendFailed
    case retimingFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "The asset does not contain a video track."
        case .cannotAddReaderOutput:
            return "The reverse renderer could not add the asset reader output."
        case .cannotAddWriterInput:
            return "The reverse renderer could not add the asset writer input."
        case .readerFailed:
            return "The reverse renderer failed while reading samples."
        case .writerFailed:
            return "The reverse renderer failed while writing samples."
        case .appendFailed:
            return "The reverse renderer failed to append a reversed sample."
        case .retimingFailed(let status):
            return "The reverse renderer failed to retime a sample buffer. OSStatus: \(status)."
        }
    }
}
