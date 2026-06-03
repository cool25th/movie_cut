import AVFoundation
import CoreImage
import MovieCutCore

struct CustomCompositionClipEffect {
    let trackID: CMPersistentTrackID
    let timeRange: CMTimeRange
    let colorCorrection: ColorCorrection?
    let mask: Mask?

    init?(
        trackID: CMPersistentTrackID,
        timeRange: CMTimeRange,
        colorCorrection: ColorCorrection?,
        mask: Mask?
    ) {
        guard colorCorrection != nil || mask != nil else {
            return nil
        }

        self.trackID = trackID
        self.timeRange = timeRange
        self.colorCorrection = colorCorrection
        self.mask = mask
    }

    func applies(to trackID: CMPersistentTrackID, at time: CMTime) -> Bool {
        self.trackID == trackID && CMTimeRangeContainsTime(timeRange, time: time)
    }
}

final class CustomCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = true
    let containsTweening: Bool = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    let colorCorrection: ColorCorrection?
    let mask: Mask?
    let clipEffects: [CustomCompositionClipEffect]

    init(timeRange: CMTimeRange, trackIDs: [CMPersistentTrackID], colorCorrection: ColorCorrection? = nil, mask: Mask? = nil) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = trackIDs.map { NSNumber(value: $0) }
        self.colorCorrection = colorCorrection
        self.mask = mask
        self.clipEffects = []
    }

    init(timeRange: CMTimeRange, trackIDs: [CMPersistentTrackID], clipEffects: [CustomCompositionClipEffect]) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = trackIDs.map { NSNumber(value: $0) }
        self.colorCorrection = nil
        self.mask = nil
        self.clipEffects = clipEffects
    }

    func effect(for trackID: CMPersistentTrackID, at time: CMTime) -> CustomCompositionClipEffect? {
        clipEffects.first { $0.applies(to: trackID, at: time) }
    }
}

final class CustomVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    let sourcePixelBufferAttributes: [String : any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    let requiredPixelBufferAttributesForRenderContext: [String : any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    private let renderQueue = DispatchQueue(label: "com.moviecut.compositor")
    private let ciContext = CIContext()
    private var renderContext: AVVideoCompositionRenderContext?
    
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContext = newRenderContext
    }
    
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async {
            guard let (trackID, sourceBuffer) = self.firstSourceFrame(in: request) else {
                request.finish(with: NSError(domain: "MovieCut", code: -1, userInfo: nil))
                return
            }
            
            var image = CIImage(cvPixelBuffer: sourceBuffer)
            
            if let instruction = request.videoCompositionInstruction as? CustomCompositionInstruction {
                let effect = instruction.effect(for: trackID, at: request.compositionTime)
                let colorCorrection = effect?.colorCorrection ?? instruction.colorCorrection
                let mask = effect?.mask ?? instruction.mask

                if let colorCorrection {
                    image = self.apply(colorCorrection: colorCorrection, to: image)
                }

                if let mask {
                    image = MaskCompositor.apply(mask: mask, to: image, at: request.compositionTime.seconds)
                }
            }
            
            guard let outputBuffer = request.renderContext.newPixelBuffer() else {
                request.finish(with: NSError(domain: "MovieCut", code: -2, userInfo: nil))
                return
            }
            
            self.ciContext.render(image, to: outputBuffer)
            request.finish(withComposedVideoFrame: outputBuffer)
        }
    }
    
    func cancelAllPendingVideoCompositionRequests() {}

    private func firstSourceFrame(
        in request: AVAsynchronousVideoCompositionRequest
    ) -> (CMPersistentTrackID, CVPixelBuffer)? {
        for sourceTrackID in request.sourceTrackIDs {
            let trackID = sourceTrackID.int32Value
            if let sourceBuffer = request.sourceFrame(byTrackID: trackID) {
                return (trackID, sourceBuffer)
            }
        }

        return nil
    }

    private func apply(colorCorrection: ColorCorrection, to image: CIImage) -> CIImage {
        var parameters: [String: Any] = [:]
        if colorCorrection.brightness != 0 {
            parameters[kCIInputBrightnessKey] = colorCorrection.brightness
        }
        if colorCorrection.contrast != 1 {
            parameters[kCIInputContrastKey] = colorCorrection.contrast
        }
        if colorCorrection.saturation != 1 {
            parameters[kCIInputSaturationKey] = colorCorrection.saturation
        }

        guard !parameters.isEmpty else {
            return image
        }

        return image.applyingFilter("CIColorControls", parameters: parameters)
    }
}
