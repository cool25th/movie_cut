import AVFoundation
import CoreGraphics
import CoreVideo
import ImageIO

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


final class ImageVideoRenderService {
    private static let frameRate: Int32 = 30

    func render(
        imageURL: URL,
        duration: TimeInterval,
        renderSize: CGSize,
        outputURL: URL
    ) async throws -> URL {
        let duration = max(duration.isFinite ? duration : 0, 1.0 / Double(Self.frameRate))
        let outputSize = Self.evenPixelSize(renderSize)
        let image = try Self.loadImage(at: imageURL, maxPixelSize: max(outputSize.width, outputSize.height))

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(outputSize.width),
                AVVideoHeightKey: Int(outputSize.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 4_000_000,
                    AVVideoExpectedSourceFrameRateKey: Int(Self.frameRate)
                ],
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
                ]
            ]
        )
        writerInput.expectsMediaDataInRealTime = false

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(outputSize.width),
            kCVPixelBufferHeightKey as String: Int(outputSize.height),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: attributes
        )

        guard writer.canAdd(writerInput) else {
            throw ImageVideoRenderServiceError.cannotAddWriterInput
        }
        writer.add(writerInput)

        guard writer.startWriting() else {
            throw writer.error ?? ImageVideoRenderServiceError.writerFailed
        }
        writer.startSession(atSourceTime: .zero)

        let totalFrames = max(Int(ceil(duration * Double(Self.frameRate))), 1)
        for frameIndex in 0..<totalFrames {
            try Task.checkCancellation()
            try await Self.waitForWriterInput(writerInput, writer: writer)
            guard let pool = adaptor.pixelBufferPool else {
                throw ImageVideoRenderServiceError.pixelBufferPoolUnavailable
            }

            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
            guard status == kCVReturnSuccess, let pixelBuffer else {
                throw ImageVideoRenderServiceError.pixelBufferCreationFailed(status)
            }
            try Self.draw(image, into: pixelBuffer, size: outputSize)

            let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: Self.frameRate)
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw writer.error ?? ImageVideoRenderServiceError.appendFailed
            }
        }

        writerInput.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }

        switch writer.status {
        case .completed:
            return outputURL
        case .cancelled:
            throw CancellationError()
        case .failed:
            throw writer.error ?? ImageVideoRenderServiceError.writerFailed
        default:
            return outputURL
        }
    }

    private static func loadImage(at url: URL, maxPixelSize: CGFloat) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageVideoRenderServiceError.imageLoadFailed
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(Int(maxPixelSize.rounded(.up)), 1)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageVideoRenderServiceError.imageLoadFailed
        }
        return image
    }

    private static func draw(_ image: CGImage, into pixelBuffer: CVPixelBuffer, size: CGSize) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw ImageVideoRenderServiceError.pixelBufferBaseAddressUnavailable
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw ImageVideoRenderServiceError.contextCreationFailed
        }

        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))

        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = CGRect(
            x: (size.width - drawSize.width) / 2,
            y: (size.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        ).integral
        context.interpolationQuality = .high
        context.draw(image, in: drawRect)
    }

    private static func evenPixelSize(_ size: CGSize) -> CGSize {
        let width = max(Int(size.width.rounded()), 2)
        let height = max(Int(size.height.rounded()), 2)
        return CGSize(width: width - (width % 2), height: height - (height % 2))
    }

    private static func waitForWriterInput(_ writerInput: AVAssetWriterInput, writer: AVAssetWriter) async throws {
        while !writerInput.isReadyForMoreMediaData {
            try Task.checkCancellation()
            if writer.status == .failed {
                throw writer.error ?? ImageVideoRenderServiceError.writerFailed
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private enum ImageVideoRenderServiceError: LocalizedError, Sendable {
    case imageLoadFailed
    case cannotAddWriterInput
    case writerFailed
    case pixelBufferPoolUnavailable
    case pixelBufferCreationFailed(CVReturn)
    case pixelBufferBaseAddressUnavailable
    case contextCreationFailed
    case appendFailed

    var errorDescription: String? {
        switch self {
        case .imageLoadFailed:
            return "The image renderer could not load the still image."
        case .cannotAddWriterInput:
            return "The image renderer could not add the video writer input."
        case .writerFailed:
            return "The image renderer failed while writing the video segment."
        case .pixelBufferPoolUnavailable:
            return "The image renderer could not create a pixel buffer pool."
        case .pixelBufferCreationFailed(let status):
            return "The image renderer could not create a pixel buffer. CVReturn: \(status)."
        case .pixelBufferBaseAddressUnavailable:
            return "The image renderer could not access the pixel buffer memory."
        case .contextCreationFailed:
            return "The image renderer could not create a drawing context."
        case .appendFailed:
            return "The image renderer failed to append an image frame."
        }
    }
}
