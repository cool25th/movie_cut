import Foundation
#if canImport(AVFoundation)
import AVFoundation
import CoreImage
#endif

public struct ThumbnailGenerator: Sendable {
    public static func generate(for asset: MediaAsset, at time: TimeInterval, size: CGSize) -> Data? {
        #if canImport(AVFoundation)
        let context = CIContext()

        if isImageFile(asset.originalURL) {
            guard let image = CIImage(contentsOf: asset.originalURL) else {
                return nil
            }

            return pngData(from: image, fitting: size, context: context)
        }

        guard time.isFinite else {
            return nil
        }

        let avAsset = AVAsset(url: asset.originalURL)
        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        if size.width > 0, size.height > 0 {
            generator.maximumSize = size
        }

        let requestedTime = CMTime(seconds: max(0, time), preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: requestedTime, actualTime: nil) else {
            return nil
        }

        return pngData(from: CIImage(cgImage: cgImage), fitting: size, context: context)
        #else
        return nil
        #endif
    }

    #if canImport(AVFoundation)
    private static func isImageFile(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "heic", "jpg", "jpeg", "png":
            return true
        default:
            return false
        }
    }

    private static func pngData(from image: CIImage, fitting size: CGSize, context: CIContext) -> Data? {
        let image = image.oriented(.up)
        let scaledImage = image.transformed(by: scaleTransform(for: image.extent.size, fitting: size))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        return context.pngRepresentation(
            of: scaledImage,
            format: .RGBA8,
            colorSpace: colorSpace
        )
    }

    private static func scaleTransform(for imageSize: CGSize, fitting targetSize: CGSize) -> CGAffineTransform {
        guard imageSize.width > 0,
              imageSize.height > 0,
              targetSize.width > 0,
              targetSize.height > 0 else {
            return .identity
        }

        let scale = min(targetSize.width / imageSize.width, targetSize.height / imageSize.height, 1)
        return CGAffineTransform(scaleX: scale, y: scale)
    }
    #endif
}
