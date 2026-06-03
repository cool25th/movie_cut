import AVFoundation
import CoreGraphics
import Foundation

#if canImport(Vision)
import Vision
#endif

/// A source-time crop rectangle calculated for automatic reframing.
public struct CropFrame: Sendable {
    /// Source time in seconds.
    public var time: TimeInterval

    /// Normalized crop rectangle in source image coordinates.
    public var rect: CGRect

    /// Creates a crop-frame value.
    public init(time: TimeInterval, rect: CGRect) {
        self.time = time
        self.rect = rect
    }
}

/// Detects subjects in frames and calculates crop rectangles for a target aspect ratio.
public final class AutoReframeProvider: AnalysisProvider {
    /// Whether Vision-backed auto reframe can run on this platform.
    public var isAvailable: Bool {
        #if canImport(Vision)
        true
        #else
        false
        #endif
    }

    /// User-visible provider name.
    public let providerName = "AutoReframe"

    /// Creates an auto-reframe provider.
    public init() {}

    public func analyze(asset: MediaAsset, in project: Project) async throws -> AnalysisResult {
        AnalysisResult(suggestions: [], sourceAssetID: asset.id.uuidString, providerName: providerName)
    }

    /// Samples an asset at 1 fps and returns normalized crop rectangles centered on detected subjects.
    public func calculateCropFrames(for asset: AVAsset, targetAspect: CGFloat) async -> [CropFrame] {
        #if canImport(Vision)
        guard targetAspect.isFinite, targetAspect > 0 else { return [] }

        guard let duration = try? await asset.load(.duration),
              duration.isValid,
              duration.seconds > 0,
              let tracks = try? await asset.load(.tracks),
              tracks.contains(where: { $0.mediaType == .video }) else {
            return []
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true

        var frames: [CropFrame] = []
        var time = 0.0

        while time < duration.seconds {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)

            guard let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil) else {
                time += 1.0
                continue
            }

            let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
            let subjectBox = detectSubject(in: cgImage)
            let cropRect = Self.cropRect(
                targetAspect: targetAspect,
                sourceSize: imageSize,
                subjectBox: subjectBox
            )

            frames.append(CropFrame(time: time, rect: cropRect))
            time += 1.0
        }

        return frames
        #else
        return []
        #endif
    }

    #if canImport(Vision)
    private func detectSubject(in cgImage: CGImage) -> CGRect? {
        let faceRequest = VNDetectFaceRectanglesRequest()
        let humanRequest = VNDetectHumanRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([faceRequest, humanRequest])
        } catch {
            return nil
        }

        if let faceBox = Self.largestBoundingBox(faceRequest.results?.map(\.boundingBox) ?? []) {
            return faceBox
        }

        return Self.largestBoundingBox(humanRequest.results?.map(\.boundingBox) ?? [])
    }
    #endif

    private static func largestBoundingBox(_ boxes: [CGRect]) -> CGRect? {
        boxes.max { lhs, rhs in
            (lhs.width * lhs.height) < (rhs.width * rhs.height)
        }
    }

    private static func cropRect(targetAspect: CGFloat, sourceSize: CGSize, subjectBox: CGRect?) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        let sourceAspect = sourceSize.width / sourceSize.height
        let cropSize: CGSize

        if sourceAspect > targetAspect {
            cropSize = CGSize(width: targetAspect / sourceAspect, height: 1)
        } else {
            cropSize = CGSize(width: 1, height: sourceAspect / targetAspect)
        }

        let subjectCenter = CGPoint(
            x: subjectBox?.midX ?? 0.5,
            y: subjectBox?.midY ?? 0.5
        )

        return CGRect(
            x: clamp(subjectCenter.x - cropSize.width / 2, lower: 0, upper: 1 - cropSize.width),
            y: clamp(subjectCenter.y - cropSize.height / 2, lower: 0, upper: 1 - cropSize.height),
            width: cropSize.width,
            height: cropSize.height
        )
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), max(lower, upper))
    }
}
