import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import MovieCutCore
import Vision

/// Renders the effect-browser thumbnail through the clip-local pipeline used by
/// the product compositor. The expensive Vision request executes in the caller's
/// detached task; only `Data`/`Clip`/`Effect` cross the concurrency boundary.
enum EffectBrowserPreviewRenderer {
    static func render(
        sourceData: Data,
        clip: Clip,
        effects: [Effect],
        localTime: Double = 0
    ) -> Data? {
        guard let sourceImage = CIImage(data: sourceData) else { return nil }

        let context = CIContext()
        let rendered = EffectBrowserPreviewPipeline.apply(
            clip: clip,
            effects: effects,
            to: sourceImage,
            at: localTime,
            backgroundRemoval: { image in
                removeBackground(from: image, context: context)
            }
        )

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return context.pngRepresentation(
            of: rendered,
            format: .RGBA8,
            colorSpace: colorSpace,
            options: [:]
        )
    }

    private static func removeBackground(from image: CIImage, context: CIContext) -> CIImage {
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
            // Match the product compositor's fail-open contract when Vision
            // cannot produce a mask for this representative thumbnail.
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
