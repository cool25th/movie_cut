import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import MovieCutCore

enum BuiltinTransitionPlugins {
    static func registerAll(in registry: PluginRegistry) {
        registry.register(plugin: FadeTransitionPlugin())
        registry.register(plugin: SlideTransitionPlugin())
        registry.register(plugin: WipeTransitionPlugin())
        registry.register(plugin: DissolveTransitionPlugin())
    }
}

private protocol BuiltinTransitionPlugin: TransitionPlugin {
    static var id: String { get }
    static var name: String { get }
    static var details: String { get }
    func image(from source: CIImage, to destination: CIImage, progress: Float) -> CIImage
}

extension BuiltinTransitionPlugin {
    var identifier: String { Self.id }
    var displayName: String { Self.name }
    var manifest: PluginManifest {
        PluginManifest(identifier: Self.id, name: Self.name, version: "1.0.0", author: "MovieCut", description: Self.details, entryPoint: "\(Self.self)", pluginTypes: [.transition])
    }

    func renderFrame(from source: CVPixelBuffer, to destination: CVPixelBuffer, progress: Float, output: CVPixelBuffer) throws {
        let bounds = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(output), height: CVPixelBufferGetHeight(output))
        CIContext().render(image(from: CIImage(cvPixelBuffer: source), to: CIImage(cvPixelBuffer: destination), progress: clamped(progress)).cropped(to: bounds), to: output, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    func render(fromFrame: UnsafeMutableRawPointer, toFrame: UnsafeMutableRawPointer, output: UnsafeMutableRawPointer, width: Int, height: Int, progress: Float) throws {
        guard width > 0, height > 0 else { return }
        let rowBytes = width * 4, bytes = rowBytes * height, size = CGSize(width: width, height: height), cs = CGColorSpaceCreateDeviceRGB()
        let source = CIImage(bitmapData: Data(bytesNoCopy: fromFrame, count: bytes, deallocator: .none), bytesPerRow: rowBytes, size: size, format: .RGBA8, colorSpace: cs)
        let destination = CIImage(bitmapData: Data(bytesNoCopy: toFrame, count: bytes, deallocator: .none), bytesPerRow: rowBytes, size: size, format: .RGBA8, colorSpace: cs)
        CIContext().render(image(from: source, to: destination, progress: clamped(progress)), toBitmap: output, rowBytes: rowBytes, bounds: CGRect(origin: CGPoint(x: 0, y: 0), size: size), format: .RGBA8, colorSpace: cs)
    }

    private func clamped(_ progress: Float) -> Float { min(max(progress, 0), 1) }
}

final class FadeTransitionPlugin: BuiltinTransitionPlugin {
    static let id = "com.moviecut.plugin.transition.fade", name = "Fade", details = "Alpha cross-dissolve between two frames."
    func image(from source: CIImage, to destination: CIImage, progress: Float) -> CIImage {
        source.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(1 - progress))]).composited(over: destination)
    }
}

final class SlideTransitionPlugin: BuiltinTransitionPlugin {
    static let id = "com.moviecut.plugin.transition.slide", name = "Slide", details = "Horizontal slide from left to right."
    func image(from source: CIImage, to destination: CIImage, progress: Float) -> CIImage {
        let dx = source.extent.width * CGFloat(progress)
        return destination.transformed(by: CGAffineTransform(translationX: dx - source.extent.width, y: 0)).composited(over: source.transformed(by: CGAffineTransform(translationX: dx, y: 0))).cropped(to: source.extent)
    }
}

final class WipeTransitionPlugin: BuiltinTransitionPlugin {
    static let id = "com.moviecut.plugin.transition.wipe", name = "Wipe", details = "Horizontal wipe from source to destination."
    func image(from source: CIImage, to destination: CIImage, progress: Float) -> CIImage {
        guard progress > 0 else { return source }
        guard progress < 1 else { return destination }
        let rect = CGRect(x: source.extent.minX, y: source.extent.minY, width: source.extent.width * CGFloat(progress), height: source.extent.height)
        return destination.cropped(to: rect).composited(over: source).cropped(to: source.extent)
    }
}

final class DissolveTransitionPlugin: BuiltinTransitionPlugin {
    static let id = "com.moviecut.plugin.transition.dissolve", name = "Dissolve", details = "Pixel blend between two frames."
    func image(from source: CIImage, to destination: CIImage, progress: Float) -> CIImage {
        source.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": destination, "inputTime": progress])
    }
}
