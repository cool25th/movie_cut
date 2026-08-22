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
    private static let permitStateLock = NSLock()
    private static var latestPermitGeneration: UInt64 = 0

    static func render(
        sourceData: Data,
        clip: Clip,
        effects: [Effect],
        canvasSize: CGSize,
        localTime: Double = 0
    ) -> Data? {
        withLatestRenderPermit {
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
    }

    /// Process-wide permit for expensive Core Image/Vision browser rendering.
    /// Vision's synchronous segmentation request cannot be reliably cancelled
    /// once started, so this serialization must outlive any individual sheet.
    static func withRenderPermit<T>(_ operation: () -> T) -> T {
        renderLock.lock()
        defer { renderLock.unlock() }
        return operation()
    }

    /// Coalescing process-wide permit used by product preview rendering.
    ///
    /// A synchronous Vision request that already owns `renderLock` is allowed to
    /// finish. While it runs, however, each new preview supersedes the previous
    /// waiter. Superseded waiters observe that their generation is stale and
    /// return before acquiring the expensive render permit, so repeated sheet
    /// dismissal/reopen cycles cannot build an unbounded queue of stale renders.
    static func withLatestRenderPermit<T>(_ operation: () -> T?) -> T? {
        let generation = reserveLatestPermitGeneration()

        while isLatestPermitGeneration(generation) {
            if renderLock.try() {
                defer { renderLock.unlock() }
                guard isLatestPermitGeneration(generation) else { return nil }
                return operation()
            }

            // `NSLock.lock()` is not cancellation-aware. Polling with a short
            // sleep lets superseded callers leave the queue without waiting for
            // the currently-running synchronous Vision request to finish.
            Thread.sleep(forTimeInterval: 0.005)
        }

        return nil
    }

    private static func reserveLatestPermitGeneration() -> UInt64 {
        permitStateLock.lock()
        defer { permitStateLock.unlock() }
        latestPermitGeneration &+= 1
        return latestPermitGeneration
    }

    private static func isLatestPermitGeneration(_ generation: UInt64) -> Bool {
        permitStateLock.lock()
        defer { permitStateLock.unlock() }
        return latestPermitGeneration == generation
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
