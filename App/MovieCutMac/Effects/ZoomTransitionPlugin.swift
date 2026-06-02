import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import MovieCutCore

final class ZoomTransitionPlugin: TransitionPlugin {
    var identifier: String { "zoom" }
    var displayName: String { "Zoom" }
    var manifest: PluginManifest {
        PluginManifest(
            identifier: identifier,
            name: displayName,
            version: "1.0.0",
            author: "MovieCut",
            description: "Center zoom transition between two frames.",
            entryPoint: "\(Self.self)",
            pluginTypes: [.transition]
        )
    }

    func renderFrame(from source: CVPixelBuffer, to destination: CVPixelBuffer, progress: Float, output: CVPixelBuffer) throws {
        let bounds = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(output), height: CVPixelBufferGetHeight(output))
        CIContext().render(
            image(from: CIImage(cvPixelBuffer: source), to: CIImage(cvPixelBuffer: destination), progress: progress).cropped(to: bounds),
            to: output,
            bounds: bounds,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
    }

    func render(fromFrame: UnsafeMutableRawPointer, toFrame: UnsafeMutableRawPointer, output: UnsafeMutableRawPointer, width: Int, height: Int, progress: Float) throws {
        guard width > 0, height > 0 else { return }

        let rowBytes = width * 4
        let bytes = rowBytes * height
        let size = CGSize(width: width, height: height)
        let bounds = CGRect(origin: CGPoint(x: 0, y: 0), size: size)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let source = CIImage(
            bitmapData: Data(bytesNoCopy: fromFrame, count: bytes, deallocator: .none),
            bytesPerRow: rowBytes,
            size: size,
            format: .RGBA8,
            colorSpace: colorSpace
        )
        let destination = CIImage(
            bitmapData: Data(bytesNoCopy: toFrame, count: bytes, deallocator: .none),
            bytesPerRow: rowBytes,
            size: size,
            format: .RGBA8,
            colorSpace: colorSpace
        )

        CIContext().render(
            image(from: source, to: destination, progress: progress).cropped(to: bounds),
            toBitmap: output,
            rowBytes: rowBytes,
            bounds: bounds,
            format: .RGBA8,
            colorSpace: colorSpace
        )
    }

    private func image(from source: CIImage, to destination: CIImage, progress: Float) -> CIImage {
        let progress = clamped(progress)
        let extent = source.extent
        let scale = 1 + progress
        let zoomedSource = source
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: extent.midX * (1 - scale), y: extent.midY * (1 - scale)))
        let fadedSource = zoomedSource.applyingFilter(
            "CIColorMatrix",
            parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1 - progress)]
        )

        return fadedSource.composited(over: destination).cropped(to: extent)
    }

    private func clamped(_ progress: Float) -> CGFloat {
        min(max(CGFloat(progress), 0), 1)
    }
}
