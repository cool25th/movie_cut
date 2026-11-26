import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// Motion-compensated optical-flow slow-motion frame interpolation service
/// shared across MovieCut targets.
///
/// Decodes the clip's source range into BGRA frames, estimates inter-frame
/// translation vectors (foreground centroid tracking with block-matching
/// fallback), synthesizes motion-compensated intermediate frames, and writes
/// a temporary `.mov` asset at `targetFrameRate`.
@MainActor
public final class MotionAwareSlowMotionRenderService {
    private struct Frame {
        var width: Int
        var height: Int
        var data: [UInt8]
    }

    private struct Pixel {
        var b: Double
        var g: Double
        var r: Double
        var a: Double

        static let black = Pixel(b: 0, g: 0, r: 0, a: 255)
    }

    private struct ForegroundStats {
        var count: Int
        var centroidX: Double
        var centroidY: Double
    }

    private struct MotionVector {
        var dx: Double
        var dy: Double
    }

    public init() {}

    public func renderSlowMotion(
        asset: AVAsset,
        track: AVAssetTrack,
        timeRange: CMTimeRange,
        playbackRate: Double,
        targetFrameRate: Int32,
        outputURL: URL
    ) async throws {
        let rate = min(max(playbackRate, 0.25), 1.0)
        let outputFPS = max(targetFrameRate, 1)
        let frames = try decodedFrames(from: asset, track: track, timeRange: timeRange)
        guard let firstFrame = frames.first else {
            throw MotionAwareSlowMotionRenderError.noFrames
        }

        let sourceDuration = timeRange.duration.seconds.isFinite && timeRange.duration.seconds > 0
            ? timeRange.duration.seconds
            : Double(frames.count) / 30.0
        let outputDuration = sourceDuration / rate
        let outputFrameCount = max(1, Int((outputDuration * Double(outputFPS)).rounded()))
        let sourceFPS = Double(frames.count) / max(sourceDuration, 1.0 / 600.0)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: firstFrame.width,
                AVVideoHeightKey: firstFrame.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoExpectedSourceFrameRateKey: Int(outputFPS),
                    AVVideoAverageBitRateKey: max(firstFrame.width * firstFrame.height * 24, 2_000_000)
                ]
            ]
        )
        writerInput.expectsMediaDataInRealTime = false
        writerInput.mediaTimeScale = CMTimeScale(outputFPS)

        guard writer.canAdd(writerInput) else {
            throw MotionAwareSlowMotionRenderError.cannotAddWriterInput
        }
        writer.add(writerInput)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: firstFrame.width,
                kCVPixelBufferHeightKey as String: firstFrame.height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        do {
            guard writer.startWriting() else {
                throw writer.error ?? MotionAwareSlowMotionRenderError.writerFailed
            }
            writer.startSession(atSourceTime: .zero)

            for outputIndex in 0..<outputFrameCount {
                try Task.checkCancellation()
                try await Self.waitForWriterInput(writerInput, writer: writer)

                let outputTime = Double(outputIndex) / Double(outputFPS)
                let sourceFramePosition = min(
                    max(outputTime * rate * sourceFPS, 0),
                    Double(max(frames.count - 1, 0))
                )
                let frame = Self.frame(at: sourceFramePosition, in: frames)
                let pixelBuffer = try Self.pixelBuffer(from: frame)
                let presentationTime = CMTime(value: CMTimeValue(outputIndex), timescale: CMTimeScale(outputFPS))

                guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                    throw writer.error ?? MotionAwareSlowMotionRenderError.appendFailed
                }
            }

            writerInput.markAsFinished()
            await Self.finishWriting(writer)

            switch writer.status {
            case .completed:
                break
            case .cancelled:
                throw CancellationError()
            case .failed:
                throw writer.error ?? MotionAwareSlowMotionRenderError.writerFailed
            default:
                break
            }
        } catch {
            writer.cancelWriting()
            throw error
        }
    }

    private func decodedFrames(
        from asset: AVAsset,
        track: AVAssetTrack,
        timeRange: CMTimeRange
    ) throws -> [Frame] {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = timeRange
        let readerOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
        )
        readerOutput.alwaysCopiesSampleData = false

        guard reader.canAdd(readerOutput) else {
            throw MotionAwareSlowMotionRenderError.cannotAddReaderOutput
        }
        reader.add(readerOutput)

        guard reader.startReading() else {
            throw reader.error ?? MotionAwareSlowMotionRenderError.readerFailed
        }

        var frames: [Frame] = []
        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }
            frames.append(try Self.copyFrame(from: pixelBuffer))
        }

        switch reader.status {
        case .completed:
            return frames
        case .cancelled:
            throw CancellationError()
        case .failed:
            throw reader.error ?? MotionAwareSlowMotionRenderError.readerFailed
        default:
            return frames
        }
    }

    private static func frame(at sourceFramePosition: Double, in frames: [Frame]) -> Frame {
        guard frames.count > 1 else {
            return frames[0]
        }

        let lowerIndex = min(max(Int(floor(sourceFramePosition)), 0), frames.count - 1)
        let upperIndex = min(lowerIndex + 1, frames.count - 1)
        let fraction = min(max(sourceFramePosition - Double(lowerIndex), 0), 1)

        guard lowerIndex != upperIndex, fraction > 1.0e-9 else {
            return frames[lowerIndex]
        }

        let previous = frames[lowerIndex]
        let next = frames[upperIndex]
        let vector = motionVector(from: previous, to: next)
        return motionCompensatedFrame(from: previous, to: next, fraction: fraction, vector: vector)
    }

    private static func motionVector(from previous: Frame, to next: Frame) -> MotionVector {
        if let previousStats = foregroundStats(in: previous),
           let nextStats = foregroundStats(in: next),
           previousStats.count > 24,
           nextStats.count > 24 {
            return MotionVector(
                dx: nextStats.centroidX - previousStats.centroidX,
                dy: nextStats.centroidY - previousStats.centroidY
            )
        }

        return blockMotionVector(from: previous, to: next)
    }

    private static func foregroundStats(in frame: Frame) -> ForegroundStats? {
        var count = 0
        var sumX = 0.0
        var sumY = 0.0

        for y in 0..<frame.height {
            let row = y * frame.width * 4
            for x in 0..<frame.width {
                let offset = row + x * 4
                let luma = luminance(
                    b: Double(frame.data[offset]),
                    g: Double(frame.data[offset + 1]),
                    r: Double(frame.data[offset + 2])
                )
                guard luma > 32 else { continue }
                count += 1
                sumX += Double(x)
                sumY += Double(y)
            }
        }

        guard count > 0 else { return nil }
        return ForegroundStats(
            count: count,
            centroidX: sumX / Double(count),
            centroidY: sumY / Double(count)
        )
    }

    private static func blockMotionVector(from previous: Frame, to next: Frame) -> MotionVector {
        let maxSearch = 24
        let sampleStride = 8
        var samplePoints: [(x: Int, y: Int)] = []

        for y in stride(from: sampleStride, to: previous.height - sampleStride, by: sampleStride) {
            for x in stride(from: sampleStride, to: previous.width - sampleStride, by: sampleStride) {
                let previousLuma = luma(atX: x, y: y, in: previous)
                let nextLuma = luma(atX: x, y: y, in: next)
                if previousLuma > 24 || nextLuma > 24 || abs(previousLuma - nextLuma) > 16 {
                    samplePoints.append((x, y))
                }
            }
        }

        guard !samplePoints.isEmpty else {
            return MotionVector(dx: 0, dy: 0)
        }

        var bestVector = MotionVector(dx: 0, dy: 0)
        var bestScore = Double.greatestFiniteMagnitude

        for dy in stride(from: -maxSearch, through: maxSearch, by: 2) {
            for dx in stride(from: -maxSearch, through: maxSearch, by: 2) {
                var score = 0.0
                var compared = 0
                for point in samplePoints {
                    let shiftedX = point.x + dx
                    let shiftedY = point.y + dy
                    guard shiftedX >= 0,
                          shiftedX < next.width,
                          shiftedY >= 0,
                          shiftedY < next.height else {
                        continue
                    }
                    score += abs(luma(atX: point.x, y: point.y, in: previous) - luma(atX: shiftedX, y: shiftedY, in: next))
                    compared += 1
                }

                guard compared > 0 else { continue }
                let normalizedScore = score / Double(compared)
                if normalizedScore < bestScore {
                    bestScore = normalizedScore
                    bestVector = MotionVector(dx: Double(dx), dy: Double(dy))
                }
            }
        }

        return bestVector
    }

    private static func motionCompensatedFrame(
        from previous: Frame,
        to next: Frame,
        fraction: Double,
        vector: MotionVector
    ) -> Frame {
        guard previous.width == next.width, previous.height == next.height else {
            return previous
        }

        let width = previous.width
        let height = previous.height
        let clampedFraction = min(max(fraction, 0), 1)
        var output = [UInt8](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let xf = Double(x)
                let yf = Double(y)
                let movedPrevious = sample(
                    previous,
                    x: xf - vector.dx * clampedFraction,
                    y: yf - vector.dy * clampedFraction
                )
                let movedNext = sample(
                    next,
                    x: xf + vector.dx * (1.0 - clampedFraction),
                    y: yf + vector.dy * (1.0 - clampedFraction)
                )
                let previousAlpha = foregroundAlpha(movedPrevious)
                let nextAlpha = foregroundAlpha(movedNext)
                let pixel: Pixel

                if previousAlpha + nextAlpha > 0.01 {
                    let previousWeight = previousAlpha * (1.0 - clampedFraction)
                    let nextWeight = nextAlpha * clampedFraction
                    let denominator = max(previousWeight + nextWeight, 1.0e-6)
                    pixel = Pixel(
                        b: (movedPrevious.b * previousWeight + movedNext.b * nextWeight) / denominator,
                        g: (movedPrevious.g * previousWeight + movedNext.g * nextWeight) / denominator,
                        r: (movedPrevious.r * previousWeight + movedNext.r * nextWeight) / denominator,
                        a: 255
                    )
                } else {
                    pixel = backgroundPixel(
                        previous: sample(previous, x: xf, y: yf),
                        next: sample(next, x: xf, y: yf),
                        fraction: clampedFraction
                    )
                }

                let offset = (y * width + x) * 4
                output[offset] = UInt8(min(max(pixel.b.rounded(), 0), 255))
                output[offset + 1] = UInt8(min(max(pixel.g.rounded(), 0), 255))
                output[offset + 2] = UInt8(min(max(pixel.r.rounded(), 0), 255))
                output[offset + 3] = 255
            }
        }

        return Frame(width: width, height: height, data: output)
    }

    private static func backgroundPixel(previous: Pixel, next: Pixel, fraction: Double) -> Pixel {
        if foregroundAlpha(previous) > 0.05 || foregroundAlpha(next) > 0.05 {
            return Pixel(
                b: min(previous.b, next.b),
                g: min(previous.g, next.g),
                r: min(previous.r, next.r),
                a: 255
            )
        }

        return Pixel(
            b: previous.b * (1.0 - fraction) + next.b * fraction,
            g: previous.g * (1.0 - fraction) + next.g * fraction,
            r: previous.r * (1.0 - fraction) + next.r * fraction,
            a: 255
        )
    }

    private static func foregroundAlpha(_ pixel: Pixel) -> Double {
        min(max((luminance(b: pixel.b, g: pixel.g, r: pixel.r) - 12.0) / 80.0, 0), 1)
    }

    private static func sample(_ frame: Frame, x: Double, y: Double) -> Pixel {
        guard x >= 0,
              y >= 0,
              x <= Double(frame.width - 1),
              y <= Double(frame.height - 1) else {
            return .black
        }

        let x0 = min(max(Int(floor(x)), 0), frame.width - 1)
        let y0 = min(max(Int(floor(y)), 0), frame.height - 1)
        let x1 = min(x0 + 1, frame.width - 1)
        let y1 = min(y0 + 1, frame.height - 1)
        let tx = x - Double(x0)
        let ty = y - Double(y0)

        let p00 = pixel(atX: x0, y: y0, in: frame)
        let p10 = pixel(atX: x1, y: y0, in: frame)
        let p01 = pixel(atX: x0, y: y1, in: frame)
        let p11 = pixel(atX: x1, y: y1, in: frame)

        return Pixel(
            b: bilinear(p00.b, p10.b, p01.b, p11.b, tx: tx, ty: ty),
            g: bilinear(p00.g, p10.g, p01.g, p11.g, tx: tx, ty: ty),
            r: bilinear(p00.r, p10.r, p01.r, p11.r, tx: tx, ty: ty),
            a: 255
        )
    }

    private static func bilinear(_ p00: Double, _ p10: Double, _ p01: Double, _ p11: Double, tx: Double, ty: Double) -> Double {
        let top = p00 * (1.0 - tx) + p10 * tx
        let bottom = p01 * (1.0 - tx) + p11 * tx
        return top * (1.0 - ty) + bottom * ty
    }

    private static func pixel(atX x: Int, y: Int, in frame: Frame) -> Pixel {
        let offset = (y * frame.width + x) * 4
        return Pixel(
            b: Double(frame.data[offset]),
            g: Double(frame.data[offset + 1]),
            r: Double(frame.data[offset + 2]),
            a: Double(frame.data[offset + 3])
        )
    }

    private static func luma(atX x: Int, y: Int, in frame: Frame) -> Double {
        let offset = (y * frame.width + x) * 4
        return luminance(
            b: Double(frame.data[offset]),
            g: Double(frame.data[offset + 1]),
            r: Double(frame.data[offset + 2])
        )
    }

    private static func luminance(b: Double, g: Double, r: Double) -> Double {
        0.114 * b + 0.587 * g + 0.299 * r
    }

    private static func copyFrame(from pixelBuffer: CVPixelBuffer) throws -> Frame {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw MotionAwareSlowMotionRenderError.pixelBufferUnavailable
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytesPerOutputRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerOutputRow * height)

        data.withUnsafeMutableBytes { destination in
            guard let destinationBaseAddress = destination.baseAddress else { return }
            for y in 0..<height {
                memcpy(
                    destinationBaseAddress.advanced(by: y * bytesPerOutputRow),
                    baseAddress.advanced(by: y * bytesPerRow),
                    bytesPerOutputRow
                )
            }
        }

        return Frame(width: width, height: height, data: data)
    }

    private static func pixelBuffer(from frame: Frame) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: frame.width,
            kCVPixelBufferHeightKey as String: frame.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            frame.width,
            frame.height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw MotionAwareSlowMotionRenderError.pixelBufferCreationFailed(status)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw MotionAwareSlowMotionRenderError.pixelBufferUnavailable
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytesPerInputRow = frame.width * 4
        frame.data.withUnsafeBytes { source in
            guard let sourceBaseAddress = source.baseAddress else { return }
            for y in 0..<frame.height {
                memcpy(
                    baseAddress.advanced(by: y * bytesPerRow),
                    sourceBaseAddress.advanced(by: y * bytesPerInputRow),
                    bytesPerInputRow
                )
            }
        }

        return pixelBuffer
    }

    private static func waitForWriterInput(_ writerInput: AVAssetWriterInput, writer: AVAssetWriter) async throws {
        while !writerInput.isReadyForMoreMediaData {
            try Task.checkCancellation()

            switch writer.status {
            case .failed:
                throw writer.error ?? MotionAwareSlowMotionRenderError.writerFailed
            case .cancelled:
                throw CancellationError()
            default:
                break
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private static func finishWriting(_ writer: AVAssetWriter) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume(returning: ())
            }
        }
    }
}

public enum MotionAwareSlowMotionRenderError: LocalizedError, Sendable {
    case appendFailed
    case cannotAddReaderOutput
    case cannotAddWriterInput
    case noFrames
    case pixelBufferCreationFailed(CVReturn)
    case pixelBufferUnavailable
    case readerFailed
    case writerFailed

    public var errorDescription: String? {
        switch self {
        case .appendFailed:
            return "Could not append an interpolated slow-motion frame."
        case .cannotAddReaderOutput:
            return "Could not configure the slow-motion frame reader."
        case .cannotAddWriterInput:
            return "Could not configure the slow-motion frame writer."
        case .noFrames:
            return "No source frames were available for slow-motion interpolation."
        case .pixelBufferCreationFailed(let status):
            return "Could not create a slow-motion pixel buffer (\(status))."
        case .pixelBufferUnavailable:
            return "Could not access slow-motion pixel data."
        case .readerFailed:
            return "Could not read source frames for slow-motion interpolation."
        case .writerFailed:
            return "Could not write the interpolated slow-motion asset."
        }
    }
}
