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
        let output = chromaKeySettingsByTrackID[id].map {
            ChromaKeyPixelProcessor.apply($0, to: image)
        } ?? image
        context.render(output, to: destination)
        request.finish(withComposedVideoFrame: destination)
    }

    func renderPixelBuffer(for request: AVAsynchronousCIImageFilteringRequest) {
        let output = request.sourceTrackID.flatMap { chromaKeySettingsByTrackID[$0] }.map {
            ChromaKeyPixelProcessor.apply($0, to: request.sourceImage)
        } ?? request.sourceImage
        request.finish(with: output, context: context)
    }
}

private extension AVAsynchronousCIImageFilteringRequest {
    var sourceTrackID: CMPersistentTrackID? {
        guard responds(to: Selector(("sourceTrackID"))) else { return nil }
        return (value(forKey: "sourceTrackID") as? NSNumber)?.int32Value
    }
}
