import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import ImageIO

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


@MainActor
enum ReverseCompositionInserter {
    static func insertReversedFrames(
        from sourceTrack: AVAssetTrack,
        sourceTimeRange: CMTimeRange,
        into compositionTrack: AVMutableCompositionTrack,
        at destinationTime: CMTime
    ) async throws -> CMTime {
        let availableRange = try await sourceTrack.load(.timeRange)
        let effectiveRange = CMTimeRangeGetIntersection(sourceTimeRange, otherRange: availableRange)
        guard effectiveRange.isValid,
              effectiveRange.duration.isNumeric,
              effectiveRange.duration > .zero else {
            throw ReverseCompositionInserterError.invalidSourceRange
        }

        let minimumFrameDuration = try await sourceTrack.load(.minFrameDuration)
        let nominalFrameRate = try await sourceTrack.load(.nominalFrameRate)
        let frameDuration: CMTime
        if minimumFrameDuration.isNumeric, minimumFrameDuration > .zero {
            frameDuration = minimumFrameDuration
        } else if nominalFrameRate > 0 {
            frameDuration = CMTime(
                seconds: 1 / Double(nominalFrameRate),
                preferredTimescale: 60_000
            )
        } else {
            frameDuration = CMTime(value: 1, timescale: 30)
        }

        var sourceEnd = CMTimeRangeGetEnd(effectiveRange)
        var insertedDuration = CMTime.zero
        while sourceEnd > effectiveRange.start {
            try Task.checkCancellation()
            let candidateStart = CMTimeSubtract(sourceEnd, frameDuration)
            let segmentStart = candidateStart > effectiveRange.start
                ? candidateStart
                : effectiveRange.start
            let segmentDuration = CMTimeSubtract(sourceEnd, segmentStart)
            guard segmentDuration.isNumeric, segmentDuration > .zero else { break }

            try compositionTrack.insertTimeRange(
                CMTimeRange(start: segmentStart, duration: segmentDuration),
                of: sourceTrack,
                at: CMTimeAdd(destinationTime, insertedDuration)
            )
            insertedDuration = CMTimeAdd(insertedDuration, segmentDuration)
            sourceEnd = segmentStart
        }

        guard insertedDuration.isNumeric, insertedDuration > .zero else {
            throw ReverseCompositionInserterError.noFramesInserted
        }
        return insertedDuration
    }
}

private enum ReverseCompositionInserterError: LocalizedError {
    case invalidSourceRange
    case noFramesInserted

    var errorDescription: String? {
        switch self {
        case .invalidSourceRange:
            return "The reverse clip source range is invalid."
        case .noFramesInserted:
            return "The reverse clip did not contain any insertable frames."
        }
    }
}
