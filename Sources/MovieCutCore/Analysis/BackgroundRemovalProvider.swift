import CoreImage
import Foundation

#if canImport(Vision)
import Vision
#endif

/// Removes video backgrounds by generating a Vision person-segmentation mask.
public final class BackgroundRemovalProvider: AnalysisProvider, @unchecked Sendable {
    private let context = CIContext()

    /// Whether Vision-backed background removal can run on this platform.
    public var isAvailable: Bool {
        #if canImport(Vision)
        true
        #else
        false
        #endif
    }

    /// User-visible provider name.
    public let providerName = "BackgroundRemoval"

    /// Creates a background removal provider.
    public init() {}

    public func analyze(asset: MediaAsset, in project: Project) async throws -> AnalysisResult {
        AnalysisResult(suggestions: [], sourceAssetID: asset.id.uuidString, providerName: providerName)
    }

    /// Applies a Vision person mask to a frame and returns a BGRA buffer with transparent background.
    public func removeBackground(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        #if canImport(Vision)
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let maskPixelBuffer = request.results?.first?.pixelBuffer else {
            return nil
        }

        return applyAlphaMask(maskPixelBuffer, to: pixelBuffer)
        #else
        return nil
        #endif
    }

    #if canImport(Vision)
    private func applyAlphaMask(_ maskPixelBuffer: CVPixelBuffer, to sourcePixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let sourceImage = CIImage(cvPixelBuffer: sourcePixelBuffer)
        let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
        let sourceExtent = sourceImage.extent

        guard !sourceExtent.isEmpty, !maskImage.extent.isEmpty else {
            return nil
        }

        let scaledMask = maskImage
            .transformed(by: CGAffineTransform(
                scaleX: sourceExtent.width / maskImage.extent.width,
                y: sourceExtent.height / maskImage.extent.height
            ))
            .cropped(to: sourceExtent)

        let transparentBackground = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: sourceExtent)

        guard let compositedImage = CIFilter(
            name: "CIBlendWithAlphaMask",
            parameters: [
                kCIInputImageKey: sourceImage,
                kCIInputBackgroundImageKey: transparentBackground,
                kCIInputMaskImageKey: scaledMask
            ]
        )?.outputImage?.cropped(to: sourceExtent) else {
            return nil
        }

        var outputPixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        let status = CVPixelBufferCreate(
            nil,
            CVPixelBufferGetWidth(sourcePixelBuffer),
            CVPixelBufferGetHeight(sourcePixelBuffer),
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &outputPixelBuffer
        )

        guard status == kCVReturnSuccess, let outputPixelBuffer else {
            return nil
        }

        context.render(compositedImage, to: outputPixelBuffer)
        return outputPixelBuffer
    }
    #endif
}
