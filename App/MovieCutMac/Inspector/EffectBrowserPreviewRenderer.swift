import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import MovieCutCore
import Vision

/// Renders the effect-browser thumbnail through the same color and clip-local
/// contracts used by the product compositor.
enum EffectBrowserPreviewRenderer {
    private static let context = CIContext(options: RenderColorConfiguration.contextOptions)
    private static let renderLock = NSLock()

    static func render(
        sourceData: Data,
        clip: Clip,
        effects: [Effect],
        canvasSize: CGSize,
        localTime: Double = 0
    ) -> Data? {
        // Vision's synchronous segmentation request cannot be reliably cancelled
        // once it has started. Keep one process-wide render permit so dismissing
        // and immediately reopening the sheet cannot overlap expensive work from
        // two sheet-local workers.
        renderLock.lock()
        defer { renderLock.unlock() }

        guard let sourceImage = CIImage(
            data: sourceData,
            options: [.colorSpace: RenderColorConfiguration.workingColorSpace]
        ) else { return nil }

        let renderSize = previewRenderSize(for: canvasSize)
        let rendered = EffectBrowserPreviewPipeline.apply(
            clip: clip,
            effects: effects,
            to: sourceImage,
            canvasSize: canvasSize,
            renderSize: renderSize,
            at: localTime,
            backgroundRemoval: { image in
                removeBackground(from: image)
            }
        )

        return context.pngRepresentation(
            of: rendered,
            format: .RGBA8,
            colorSpace: RenderColorConfiguration.destinationColorSpace,
            options: [:]
        )
    }

    private static func previewRenderSize(for canvasSize: CGSize) -> CGSize {
        let width = max(canvasSize.width, 1)
        let height = max(canvasSize.height, 1)
        let longestEdge: CGFloat = 320
        let scale = min(longestEdge / max(width, height), 1)
        return CGSize(
            width: max((width * scale).rounded(), 1),
            height: max((height * scale).rounded(), 1)
        )
    }

    private static func removeBackground(from image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.width > 0,
              extent.height > 0,
              let sourceImage = context.createCGImage(image, from: extent)
        else {
            return image
        }

        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .fast
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        do {
            try VNImageRequestHandler(cgImage: sourceImage).perform([request])
        } catch {
            return image
        }

        guard let maskBuffer = request.results?.first?.pixelBuffer else {
            return image
        }

        let mask = PersonSegmentationCompositor.align(CIImage(cvPixelBuffer: maskBuffer), to: extent)
        guard PersonSegmentationCompositor.maskContainsForeground(mask, extent: extent, in: context) else {
            return image
        }

        return PersonSegmentationCompositor.removeBackground(from: image, mask: mask)
    }
}
