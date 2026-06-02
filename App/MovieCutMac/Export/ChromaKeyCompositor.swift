import AVFoundation
import CoreImage
import MovieCutCore

final class ChromaKeyCompositor: NSObject, AVVideoCompositing {
    let sourcePixelBufferAttributes: [String: any Sendable]? = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    var chromaKeySettingsByTrackID: [CMPersistentTrackID: ChromaKeySettings] = [:]
    private let context = CIContext()

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
    func cancelAllPendingVideoCompositionRequests() {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let id = request.sourceTrackIDs.first?.int32Value,
              let source = request.sourceFrame(byTrackID: id),
              let destination = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "MovieCut", code: -1))
            return
        }
        let image = CIImage(cvPixelBuffer: source)
        let output = chromaKeySettingsByTrackID[id].map { applyChromaKey(to: image, settings: $0) } ?? image
        context.render(output, to: destination)
        request.finish(withComposedVideoFrame: destination)
    }

    func renderPixelBuffer(for request: AVAsynchronousCIImageFilteringRequest) {
        let output = request.sourceTrackID.flatMap { chromaKeySettingsByTrackID[$0] }.map {
            applyChromaKey(to: request.sourceImage, settings: $0)
        } ?? request.sourceImage
        request.finish(with: output, context: context)
    }

    private func applyChromaKey(to image: CIImage, settings: ChromaKeySettings) -> CIImage {
        let size = 32, key = rgb(settings.keyColor)
        let tolerance = Float(settings.tolerance), softness = max(Float(settings.softness), 0.001)
        var cube = [Float](repeating: 0, count: size * size * size * 4)
        var offset = 0
        for bIndex in 0..<size { for gIndex in 0..<size { for rIndex in 0..<size {
            let r = Float(rIndex) / Float(size - 1), g = Float(gIndex) / Float(size - 1), b = Float(bIndex) / Float(size - 1)
            let d = sqrt(pow(r - key.0, 2) + pow(g - key.1, 2) + pow(b - key.2, 2))
            let alpha = min(max((d - tolerance) / softness, 0), 1)
            let spill = (1 - alpha) * Float(settings.spillSuppression)
            cube[offset] = r * (1 - spill); cube[offset + 1] = g * (1 - spill); cube[offset + 2] = b * (1 - spill); cube[offset + 3] = alpha
            offset += 4
        } } }
        let data = cube.withUnsafeBufferPointer { Data(buffer: $0) }
        let filter = CIFilter(name: "CIColorCube")
        filter?.setValue(size, forKey: "inputCubeDimension")
        filter?.setValue(data, forKey: "inputCubeData")
        filter?.setValue(image, forKey: kCIInputImageKey)
        return filter?.outputImage ?? image
    }

    private func rgb(_ hex: String) -> (Float, Float, Float) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6, let value = Int(clean, radix: 16) else { return (0, 1, 0) }
        return (Float((value >> 16) & 255) / 255, Float((value >> 8) & 255) / 255, Float(value & 255) / 255)
    }
}

private extension AVAsynchronousCIImageFilteringRequest {
    var sourceTrackID: CMPersistentTrackID? {
        guard responds(to: Selector(("sourceTrackID"))) else { return nil }
        return (value(forKey: "sourceTrackID") as? NSNumber)?.int32Value
    }
}
