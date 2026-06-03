import Foundation

#if canImport(CoreImage)
import CoreImage
#endif

/// Applies Core Image filter chains that simulate common visual styles.
public final class StyleTransferProvider: AnalysisProvider {
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
            return applyComicStyle(to: image)
        case "noir":
            return image
                .filtered("CIPhotoEffectNoir")
                .flatMap { filtered($0, name: "CIVignette", parameters: [kCIInputIntensityKey: 0.8]) }
                .flatMap { filtered($0, name: "CIColorControls", parameters: [kCIInputContrastKey: 1.3]) }?
                .cropped(to: image.extent)
        case "vintage":
            return image
                .filtered("CIPhotoEffectInstant")
                .flatMap { filtered($0, name: "CIVignette", parameters: [kCIInputIntensityKey: 0.5, kCIInputRadiusKey: 1.5]) }
                .flatMap { filtered($0, name: "CIColorControls", parameters: [kCIInputSaturationKey: 0.7]) }?
                .cropped(to: image.extent)
        case "cyberpunk":
            return applyCyberpunkStyle(to: image)
        case "watercolor":
            return image
                .filtered("CIMedianFilter")
                .flatMap { filtered($0, name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.5]) }
                .flatMap { filtered($0, name: "CIColorControls", parameters: [kCIInputSaturationKey: 1.3]) }?
                .cropped(to: image.extent)
        default:
            return nil
        }
    }

    private func applyComicStyle(to image: CIImage) -> CIImage? {
        guard let posterized = filtered(image, name: "CIColorPosterize", parameters: ["inputLevels": 8]),
              let edgeWork = filtered(posterized, name: "CIEdgeWork", parameters: [kCIInputRadiusKey: 2]),
              let colorized = filtered(edgeWork, name: "CIColorCrossPolynomial", parameters: [
                "inputRedCoefficients": coefficientVector([0.06, 1.10, 0.06, 0.00, -0.08, 0.00, 0.00, 0.00, 0.00, 0.00]),
                "inputGreenCoefficients": coefficientVector([0.04, 0.05, 1.08, 0.02, 0.00, -0.06, 0.00, 0.00, 0.00, 0.00]),
                "inputBlueCoefficients": coefficientVector([0.02, 0.00, 0.04, 0.92, 0.00, 0.00, -0.05, 0.00, 0.00, 0.00])
              ]) else {
            return nil
        }

        let overlay = filtered(colorized, name: "CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.55)
        ]) ?? colorized

        return sourceOver(overlay.cropped(to: image.extent), background: image)?
            .cropped(to: image.extent)
    }

    private func applyCyberpunkStyle(to image: CIImage) -> CIImage? {
        guard let saturated = filtered(image, name: "CIColorControls", parameters: [
            kCIInputSaturationKey: 1.5,
            kCIInputContrastKey: 1.2
        ]) else {
            return nil
        }

        let toneMapped = applyToneMapWhitePoint(to: saturated)
        guard let neonTint = constantColor(CIColor(red: 0.95, green: 0.05, blue: 1.0, alpha: 0.18), extent: image.extent) else {
            return toneMapped.cropped(to: image.extent)
        }

        return sourceOver(neonTint, background: toneMapped)?
            .cropped(to: image.extent)
    }

    private func applyToneMapWhitePoint(to image: CIImage) -> CIImage {
        if let toneMapped = filtered(image, name: "CIToneMapWhitePoint", parameters: [
            "inputColor": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
            "inputWhitePoint": CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        ]) {
            return toneMapped
        }

        if let toneMapped = filtered(image, name: "CIToneMapHeadroom", parameters: [
            "inputSourceHeadroom": 1.4,
            "inputTargetHeadroom": 1.0
        ]) {
            return toneMapped
        }

        return image
    }

    private func filtered(_ image: CIImage, name: String, parameters: [String: Any] = [:]) -> CIImage? {
        guard let filter = CIFilter(name: name) else {
            return nil
        }

        if filter.inputKeys.contains(kCIInputImageKey) {
            filter.setValue(image, forKey: kCIInputImageKey)
        }

        for (key, value) in parameters where filter.inputKeys.contains(key) {
            filter.setValue(value, forKey: key)
        }

        return filter.outputImage
    }

    private func sourceOver(_ foreground: CIImage, background: CIImage) -> CIImage? {
        filtered(foreground, name: "CISourceOverCompositing", parameters: [
            kCIInputBackgroundImageKey: background
        ])
    }

    private func constantColor(_ color: CIColor, extent: CGRect) -> CIImage? {
        guard let filter = CIFilter(name: "CIConstantColorGenerator") else {
            return nil
        }

        filter.setValue(color, forKey: kCIInputColorKey)
        return filter.outputImage?.cropped(to: extent)
    }

    private func coefficientVector(_ values: [CGFloat]) -> CIVector {
        values.withUnsafeBufferPointer { buffer in
            CIVector(values: buffer.baseAddress!, count: buffer.count)
        }
    }
    #else
    /// Returns the input unchanged when Core Image is unavailable.
    public func apply<Image>(style: String, to image: Image) -> Image? {
        image
    }
    #endif
}

#if canImport(CoreImage)
private extension CIImage {
    func filtered(_ name: String) -> CIImage? {
        guard let filter = CIFilter(name: name) else {
            return nil
        }

        if filter.inputKeys.contains(kCIInputImageKey) {
            filter.setValue(self, forKey: kCIInputImageKey)
        }

        return filter.outputImage
    }
}
#endif
