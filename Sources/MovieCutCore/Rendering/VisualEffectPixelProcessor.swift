import CoreGraphics
import CoreImage
import Foundation

/// Applies per-clip visual effects to Core Image frames for preview and export.
public enum VisualEffectPixelProcessor {
    /// Returns true when at least one effect has an implemented pixel renderer.
    public static func hasRenderableEffects(_ effects: [Effect]) -> Bool {
        effects.contains(where: hasRenderableEffect)
    }

    /// Returns true when the effect type has an implemented pixel renderer.
    public static func hasRenderableEffect(_ effect: Effect) -> Bool {
        switch effect.type {
        case .brightness,
             .contrast,
             .saturation,
             .temperature,
             .exposure,
             .grayscale,
             .sepia,
             .blur,
             .styleTransfer,
             .cinematicLUT,
             .vintageLUT,
             .noirLUT,
             .vividLUT,
             .coolLUT,
             .externalLUT:
            return true
        case .fadeIn, .fadeOut, .crossDissolve:
            return false
        }
    }

    /// Applies effects in timeline order, preserving the input extent after each filter.
    public static func apply(_ effects: [Effect], to image: CIImage) -> CIImage {
        guard hasRenderableEffects(effects) else {
            return image
        }

        return effects.reduce(image) { result, effect in
            apply(effect, to: result).cropped(to: result.extent)
        }
    }

    /// Applies a single effect, preserving the input extent.
    public static func apply(_ effect: Effect, to image: CIImage) -> CIImage {
        let extent = image.extent
        let output: CIImage

        switch effect.type {
        case .brightness:
            output = colorControls(image, brightness: effect.parameters["amount"] ?? 0, contrast: 1, saturation: 1)
        case .contrast:
            output = colorControls(image, brightness: 0, contrast: effect.parameters["amount"] ?? 1, saturation: 1)
        case .saturation:
            output = colorControls(image, brightness: 0, contrast: 1, saturation: effect.parameters["amount"] ?? 1)
        case .temperature:
            output = applyTemperature(effect, to: image)
        case .exposure:
            output = filtered(
                image,
                name: "CIExposureAdjust",
                parameters: [kCIInputEVKey: effect.parameters["ev"] ?? effect.parameters["amount"] ?? 0]
            )
        case .grayscale:
            let intensity = clamped(effect.parameters["intensity"] ?? 1, lowerBound: 0, upperBound: 1)
            let mono = colorControls(image, brightness: 0, contrast: 1, saturation: 0)
            output = blend(original: image, styled: mono, intensity: intensity)
        case .sepia:
            output = filtered(
                image,
                name: "CISepiaTone",
                parameters: [kCIInputIntensityKey: clamped(effect.parameters["intensity"] ?? 0.9, lowerBound: 0, upperBound: 1)]
            )
        case .blur:
            output = filtered(
                image,
                name: "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: max(effect.parameters["radius"] ?? 5, 0)]
            )
        case .styleTransfer:
            output = applyStyleTransfer(effect, to: image)
        case .cinematicLUT:
            output = applyLUTPreset(.cinematic, effect: effect, to: image)
        case .vintageLUT:
            output = applyLUTPreset(.vintage, effect: effect, to: image)
        case .noirLUT:
            output = applyLUTPreset(.noir, effect: effect, to: image)
        case .vividLUT:
            output = applyLUTPreset(.vivid, effect: effect, to: image)
        case .coolLUT:
            output = applyLUTPreset(.cool, effect: effect, to: image)
        case .externalLUT:
            output = applyExternalLUT(effect, to: image)
        case .fadeIn, .fadeOut, .crossDissolve:
            output = image
        }

        return output.cropped(to: extent)
    }

    private static func applyTemperature(_ effect: Effect, to image: CIImage) -> CIImage {
        let amount = clamped(effect.parameters["amount"] ?? legacyTemperatureAmount(effect), lowerBound: -1, upperBound: 1)
        let tint = clamped(effect.parameters["tint"] ?? 0, lowerBound: -1, upperBound: 1)
        let targetTemperature = 6500 + amount * 2_000
        let targetTint = tint * 150

        return filtered(
            image,
            name: "CITemperatureAndTint",
            parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: targetTemperature, y: targetTint)
            ]
        )
    }

    private static func legacyTemperatureAmount(_ effect: Effect) -> Double {
        if let targetX = effect.parameters["targetX"] {
            return (targetX - 6500) / 2_000
        }

        return 0
    }

    private static func applyStyleTransfer(_ effect: Effect, to image: CIImage) -> CIImage {
        let styleIndex = Int((effect.parameters["styleIndex"] ?? 1).rounded())
        let preset = LUTPreset(styleIndex: styleIndex)
        return applyLUTPreset(preset, effect: effect, to: image)
    }

    // Parsed cubes are cached by path so the .cube file is not re-read per frame.
    private nonisolated(unsafe) static let cubeCache = NSCache<NSString, CubeLUTBox>()

    private static func applyExternalLUT(_ effect: Effect, to image: CIImage) -> CIImage {
        guard let path = effect.lutPath else { return image }
        let intensity = clamped(effect.parameters["intensity"] ?? 1, lowerBound: 0, upperBound: 1)
        guard intensity > 0, let cube = loadCube(path: path) else { return image }

        guard let filter = CIFilter(name: "CIColorCube") else { return image }
        filter.setValue(cube.dimension, forKey: "inputCubeDimension")
        filter.setValue(cube.dataObject, forKey: "inputCubeData")
        filter.setValue(image, forKey: kCIInputImageKey)
        guard let styled = filter.outputImage else { return image }

        return blend(original: image, styled: styled.cropped(to: image.extent), intensity: intensity)
    }

    private static func loadCube(path: String) -> CubeLUTBox? {
        let key = path as NSString
        if let cached = cubeCache.object(forKey: key) {
            return cached
        }
        guard let lut = try? CubeLUTParser.parse(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        let box = CubeLUTBox(lut: lut)
        cubeCache.setObject(box, forKey: key)
        return box
    }

    private static func applyLUTPreset(_ preset: LUTPreset, effect: Effect, to image: CIImage) -> CIImage {
        let intensity = clamped(effect.parameters["intensity"] ?? preset.defaultIntensity, lowerBound: 0, upperBound: 1)
        guard intensity > 0 else { return image }

        let styled: CIImage
        switch preset {
        case .cinematic:
            styled = applyGradientMap(
                to: colorControls(image, brightness: 0.01, contrast: 1.12, saturation: 1.05),
                stops: [
                    GradientStop(0.00, 0.02, 0.08, 0.11),
                    GradientStop(0.45, 0.16, 0.47, 0.52),
                    GradientStop(1.00, 1.00, 0.82, 0.50)
                ],
                blendFilterName: "CISoftLightBlendMode"
            )
        case .vintage:
            styled = applyGradientMap(
                to: colorControls(image, brightness: 0.03, contrast: 0.92, saturation: 0.82),
                stops: [
                    GradientStop(0.00, 0.10, 0.06, 0.03),
                    GradientStop(0.48, 0.72, 0.45, 0.25),
                    GradientStop(1.00, 1.00, 0.88, 0.60)
                ],
                blendFilterName: "CISoftLightBlendMode"
            )
        case .noir:
            styled = colorControls(image, brightness: -0.02, contrast: 1.28, saturation: 0)
        case .vivid:
            styled = applyGradientMap(
                to: colorControls(image, brightness: 0.02, contrast: 1.15, saturation: 1.42),
                stops: [
                    GradientStop(0.00, 0.04, 0.02, 0.14),
                    GradientStop(0.44, 0.05, 0.70, 0.92),
                    GradientStop(1.00, 1.00, 0.18, 0.58)
                ],
                blendFilterName: "CIOverlayBlendMode"
            )
        case .cool:
            let cooled = filtered(
                image,
                name: "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: 0.90, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 1.02, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 1.16, w: 0),
                    "inputBiasVector": CIVector(x: -0.01, y: 0.00, z: 0.04, w: 0)
                ]
            )
            styled = colorControls(cooled, brightness: 0, contrast: 1.04, saturation: 1.08)
        }

        return blend(original: image, styled: styled.cropped(to: image.extent), intensity: intensity)
    }

    private static func applyGradientMap(
        to image: CIImage,
        stops: [GradientStop],
        blendFilterName: String
    ) -> CIImage {
        guard let gradientImage = gradientMapImage(stops: stops) else {
            return image
        }

        let mapped = filtered(
            image,
            name: "CIColorMap",
            parameters: ["inputGradientImage": gradientImage]
        )
        let blended = filtered(
            mapped,
            name: blendFilterName,
            parameters: [kCIInputBackgroundImageKey: image]
        )
        return blended.cropped(to: image.extent)
    }

    private static func colorControls(
        _ image: CIImage,
        brightness: Double,
        contrast: Double,
        saturation: Double
    ) -> CIImage {
        filtered(
            image,
            name: "CIColorControls",
            parameters: [
                kCIInputBrightnessKey: brightness,
                kCIInputContrastKey: contrast,
                kCIInputSaturationKey: saturation
            ]
        )
    }

    private static func blend(original: CIImage, styled: CIImage, intensity: Double) -> CIImage {
        let clampedIntensity = clamped(intensity, lowerBound: 0, upperBound: 1)
        guard clampedIntensity > 0 else { return original }
        guard clampedIntensity < 1 else { return styled.cropped(to: original.extent) }

        return filtered(
            original,
            name: "CIDissolveTransition",
            parameters: [
                kCIInputTargetImageKey: styled.cropped(to: original.extent),
                kCIInputTimeKey: clampedIntensity
            ]
        )
    }

    private static func filtered(_ image: CIImage, name: String, parameters: [String: Any] = [:]) -> CIImage {
        guard let filter = CIFilter(name: name) else {
            return image
        }

        if filter.inputKeys.contains(kCIInputImageKey) {
            filter.setValue(image, forKey: kCIInputImageKey)
        }

        for (key, value) in parameters where filter.inputKeys.contains(key) {
            filter.setValue(value, forKey: key)
        }

        return filter.outputImage?.cropped(to: image.extent) ?? image
    }

    private static func gradientMapImage(stops: [GradientStop]) -> CIImage? {
        let width = 256
        let height = 1
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        for index in 0..<width {
            let value = CGFloat(index) / CGFloat(width - 1)
            let color = interpolatedColor(at: value, stops: stops)
            let offset = index * 4
            pixels[offset] = UInt8(min(max(color.red * 255, 0), 255).rounded())
            pixels[offset + 1] = UInt8(min(max(color.green * 255, 0), 255).rounded())
            pixels[offset + 2] = UInt8(min(max(color.blue * 255, 0), 255).rounded())
            pixels[offset + 3] = UInt8.max
        }

        return CIImage(
            bitmapData: Data(pixels),
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        )
    }

    private static func interpolatedColor(
        at value: CGFloat,
        stops: [GradientStop]
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        guard let first = stops.first else {
            return (value, value, value)
        }

        guard value > first.position else {
            return (first.red, first.green, first.blue)
        }

        for index in 0..<(stops.count - 1) {
            let start = stops[index]
            let end = stops[index + 1]
            guard value <= end.position else { continue }

            let span = max(end.position - start.position, 1.0e-6)
            let progress = min(max((value - start.position) / span, 0), 1)
            return (
                start.red + (end.red - start.red) * progress,
                start.green + (end.green - start.green) * progress,
                start.blue + (end.blue - start.blue) * progress
            )
        }

        let last = stops[stops.count - 1]
        return (last.red, last.green, last.blue)
    }

    private static func clamped(_ value: Double, lowerBound: Double, upperBound: Double) -> Double {
        min(max(value, lowerBound), upperBound)
    }
}

private enum LUTPreset {
    case cinematic
    case vintage
    case noir
    case vivid
    case cool

    init(styleIndex: Int) {
        switch styleIndex {
        case 2:
            self = .noir
        case 3:
            self = .vintage
        case 4:
            self = .vivid
        case 5:
            self = .cool
        default:
            self = .cinematic
        }
    }

    var defaultIntensity: Double {
        switch self {
        case .cinematic:
            return 0.85
        case .vintage, .vivid, .cool:
            return 0.8
        case .noir:
            return 0.9
        }
    }
}

private struct GradientStop {
    var position: CGFloat
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat

    init(_ position: CGFloat, _ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) {
        self.position = position
        self.red = red
        self.green = green
        self.blue = blue
    }
}
