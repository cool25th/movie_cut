import Foundation

#if canImport(CoreImage)
import CoreImage
#endif

/// Applies lightweight Core Image filter chains that simulate common visual styles.
public final class StyleTransferProvider: AnalysisProvider, @unchecked Sendable {
    /// The supported style identifiers.
    public let availableStyles = ["comic", "noir", "vintage", "cyberpunk", "watercolor"]

    /// Whether Core Image style filters can run on this platform.
    public var isAvailable: Bool {
        #if canImport(CoreImage)
        true
        #else
        false
        #endif
    }

    /// User-visible provider name.
    public let providerName = "StyleTransfer"

    /// Creates a style transfer provider.
    public init() {}

    public func analyze(asset: MediaAsset, in project: Project) async throws -> AnalysisResult {
        AnalysisResult(suggestions: [], sourceAssetID: asset.id.uuidString, providerName: providerName)
    }

    #if canImport(CoreImage)
    /// Applies a named Core Image style chain to an image.
    public func apply(style: String, to image: CIImage) -> CIImage? {
        switch style.lowercased() {
        case "comic":
            return image
                .applyingFilter("CIPhotoEffectProcess")
                .applyingFilter("CIEdges", parameters: ["inputIntensity": 1.2])
        case "noir":
            return image
                .applyingFilter("CIPhotoEffectNoir")
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1.35
                ])
        case "vintage":
            return image
                .applyingFilter("CIPhotoEffectInstant")
                .applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: 0.8,
                    kCIInputRadiusKey: max(image.extent.width, image.extent.height) * 0.75
                ])
        case "cyberpunk":
            return applyCyberpunkStyle(to: image)
        case "watercolor":
            return image
                .applyingFilter("CIMedianFilter")
                .applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: 1.2
                ])
                .cropped(to: image.extent)
        default:
            return nil
        }
    }

    private func applyCyberpunkStyle(to image: CIImage) -> CIImage? {
        let gradient = CIFilter(
            name: "CILinearGradient",
            parameters: [
                "inputPoint0": CIVector(x: 0, y: 0),
                "inputPoint1": CIVector(x: 256, y: 0),
                "inputColor0": CIColor(red: 0.05, green: 0, blue: 0.15),
                "inputColor1": CIColor(red: 0, green: 1, blue: 0.95)
            ]
        )?
        .outputImage?
        .cropped(to: CGRect(x: 0, y: 0, width: 256, height: 1))

        guard let gradient else { return nil }

        return image
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.7,
                kCIInputContrastKey: 1.25
            ])
            .applyingFilter("CIColorMap", parameters: [
                "inputGradientImage": gradient
            ])
    }
    #endif
}
