import AVFoundation
import CoreImage
import MovieCutCore

struct CustomCompositionClipEffect {
    let trackID: CMPersistentTrackID
    let timeRange: CMTimeRange
    let transform: ClipTransform
    let opacity: Double
    let keyframes: [Keyframe]
    let colorCorrection: ColorCorrection?
    let chromaKeyColor: SIMD3<Float>?
    let chromaKeyThreshold: Float
    let mask: Mask?

    init?(
        trackID: CMPersistentTrackID,
        timeRange: CMTimeRange,
        transform: ClipTransform = ClipTransform(),
        opacity: Double = 1.0,
        keyframes: [Keyframe] = [],
        colorCorrection: ColorCorrection?,
        chromaKeyColor: SIMD3<Float>? = nil,
        chromaKeyThreshold: Float = 0.3,
        mask: Mask?
    ) {
        let clampedOpacity = min(max(opacity, 0), 1)
        guard colorCorrection != nil
            || chromaKeyColor != nil
            || mask != nil
            || Self.hasVisualAnimation(transform: transform, opacity: clampedOpacity, keyframes: keyframes)
        else {
            return nil
        }

        self.trackID = trackID
        self.timeRange = timeRange
        self.transform = transform
        self.opacity = clampedOpacity
        self.keyframes = keyframes
        self.colorCorrection = colorCorrection
        self.chromaKeyColor = chromaKeyColor
        self.chromaKeyThreshold = min(max(chromaKeyThreshold, 0), 1)
        self.mask = mask
    }

    func applies(to trackID: CMPersistentTrackID, at time: CMTime) -> Bool {
        self.trackID == trackID && CMTimeRangeContainsTime(timeRange, time: time)
    }

    func animationState(at time: CMTime) -> CustomCompositionAnimationState? {
        guard Self.hasVisualAnimation(transform: transform, opacity: opacity, keyframes: keyframes) else {
            return nil
        }

        let rawLocalTime = CMTimeSubtract(time, timeRange.start).seconds
        let localTime = rawLocalTime.isFinite ? max(0, rawLocalTime) : 0
        return CustomCompositionAnimationState(
            transform: Self.keyframedTransform(base: transform, keyframes: keyframes, at: localTime),
            opacity: Self.keyframedValue(for: .opacity, defaultValue: opacity, keyframes: keyframes, at: localTime)
        )
    }

    private static let transformKeyframeProperties: Set<AnimatableProperty> = [
        .positionX,
        .positionY,
        .scaleX,
        .scaleY,
        .rotation
    ]

    private static let visualKeyframeProperties: Set<AnimatableProperty> = [
        .positionX,
        .positionY,
        .scaleX,
        .scaleY,
        .rotation,
        .opacity
    ]

    private static func hasVisualAnimation(
        transform: ClipTransform,
        opacity: Double,
        keyframes: [Keyframe]
    ) -> Bool {
        !isIdentityTransform(transform)
            || abs(opacity - 1) > 1.0e-9
            || keyframes.contains { visualKeyframeProperties.contains($0.property) }
    }

    private static func keyframedTransform(
        base transform: ClipTransform,
        keyframes: [Keyframe],
        at localTime: TimeInterval
    ) -> ClipTransform {
        guard keyframes.contains(where: { transformKeyframeProperties.contains($0.property) }) else {
            return transform
        }

        var resolvedTransform = transform
        resolvedTransform.position.x = CGFloat(keyframedValue(
            for: .positionX,
            defaultValue: Double(transform.position.x),
            keyframes: keyframes,
            at: localTime
        ))
        resolvedTransform.position.y = CGFloat(keyframedValue(
            for: .positionY,
            defaultValue: Double(transform.position.y),
            keyframes: keyframes,
            at: localTime
        ))
        resolvedTransform.scale.width = CGFloat(keyframedValue(
            for: .scaleX,
            defaultValue: Double(transform.scale.width),
            keyframes: keyframes,
            at: localTime
        ))
        resolvedTransform.scale.height = CGFloat(keyframedValue(
            for: .scaleY,
            defaultValue: Double(transform.scale.height),
            keyframes: keyframes,
            at: localTime
        ))
        resolvedTransform.rotation = keyframedValue(
            for: .rotation,
            defaultValue: transform.rotation,
            keyframes: keyframes,
            at: localTime
        )
        return resolvedTransform
    }

    private static func keyframedValue(
        for property: AnimatableProperty,
        defaultValue: Double,
        keyframes: [Keyframe],
        at localTime: TimeInterval
    ) -> Double {
        let propertyKeyframes = keyframes
            .filter { $0.property == property }
            .sorted { $0.time < $1.time }

        guard let firstKeyframe = propertyKeyframes.first else {
            return defaultValue
        }

        guard localTime >= firstKeyframe.time else {
            return defaultValue
        }

        guard let lastKeyframe = propertyKeyframes.last, localTime < lastKeyframe.time else {
            return propertyKeyframes.last?.value ?? defaultValue
        }

        for index in 0..<(propertyKeyframes.count - 1) {
            let startKeyframe = propertyKeyframes[index]
            let endKeyframe = propertyKeyframes[index + 1]
            guard localTime >= startKeyframe.time && localTime <= endKeyframe.time else {
                continue
            }

            let duration = endKeyframe.time - startKeyframe.time
            guard duration > 0 else {
                return endKeyframe.value
            }

            return Keyframe.interpolate(
                from: startKeyframe.value,
                to: endKeyframe.value,
                progress: (localTime - startKeyframe.time) / duration,
                mode: startKeyframe.interpolation
            )
        }

        return firstKeyframe.value
    }

    private static func isIdentityTransform(_ transform: ClipTransform) -> Bool {
        abs(transform.position.x) <= 1.0e-9
            && abs(transform.position.y) <= 1.0e-9
            && abs(transform.offset.x) <= 1.0e-9
            && abs(transform.offset.y) <= 1.0e-9
            && abs(transform.scale.width - 1) <= 1.0e-9
            && abs(transform.scale.height - 1) <= 1.0e-9
            && abs(transform.rotation) <= 1.0e-9
    }
}

struct CustomCompositionAnimationState {
    let transform: ClipTransform
    let opacity: Double
}

final class CustomCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = true
    let containsTweening: Bool = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    let colorCorrection: ColorCorrection?
    var chromaKeyColor: SIMD3<Float>?
    var chromaKeyThreshold: Float = 0.3
    let mask: Mask?
    let clipEffects: [CustomCompositionClipEffect]

    init(
        timeRange: CMTimeRange,
        trackIDs: [CMPersistentTrackID],
        colorCorrection: ColorCorrection? = nil,
        chromaKeyColor: SIMD3<Float>? = nil,
        chromaKeyThreshold: Float = 0.3,
        mask: Mask? = nil
    ) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = trackIDs.map { NSNumber(value: $0) }
        self.colorCorrection = colorCorrection
        self.chromaKeyColor = chromaKeyColor
        self.chromaKeyThreshold = min(max(chromaKeyThreshold, 0), 1)
        self.mask = mask
        self.clipEffects = []
    }

    init(timeRange: CMTimeRange, trackIDs: [CMPersistentTrackID], clipEffects: [CustomCompositionClipEffect]) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = trackIDs.map { NSNumber(value: $0) }
        self.colorCorrection = nil
        self.chromaKeyColor = nil
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
                let chromaKeyColor = effect?.chromaKeyColor ?? instruction.chromaKeyColor
                let chromaKeyThreshold = effect?.chromaKeyThreshold ?? instruction.chromaKeyThreshold
                let mask = effect?.mask ?? instruction.mask
                let animationState = effect?.animationState(at: request.compositionTime)

                if let colorCorrection {
                    image = self.apply(colorCorrection: colorCorrection, to: image)
                }

                if let chromaKeyColor {
                    image = self.applyChromaKey(to: image, keyColor: chromaKeyColor, threshold: chromaKeyThreshold)
                }

                if let mask {
                    image = MaskCompositor.apply(mask: mask, to: image, at: request.compositionTime.seconds)
                }

                if let animationState {
                    image = self.apply(
                        animationState: animationState,
                        to: image,
                        renderSize: request.renderContext.size
                    )
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

    private func applyChromaKey(to image: CIImage, keyColor: SIMD3<Float>, threshold: Float) -> CIImage {
        let cubeDimension = 32
        let clampedThreshold = min(max(threshold, 0), 1)
        let softness = max(clampedThreshold * 0.5, 0.001)
        let normalizedKeyColor = SIMD3<Float>(
            min(max(keyColor.x, 0), 1),
            min(max(keyColor.y, 0), 1),
            min(max(keyColor.z, 0), 1)
        )

        var cubeData = [Float](repeating: 0, count: cubeDimension * cubeDimension * cubeDimension * 4)
        var offset = 0

        for blueIndex in 0..<cubeDimension {
            for greenIndex in 0..<cubeDimension {
                for redIndex in 0..<cubeDimension {
                    let red = Float(redIndex) / Float(cubeDimension - 1)
                    let green = Float(greenIndex) / Float(cubeDimension - 1)
                    let blue = Float(blueIndex) / Float(cubeDimension - 1)
                    let redDistance = red - normalizedKeyColor.x
                    let greenDistance = green - normalizedKeyColor.y
                    let blueDistance = blue - normalizedKeyColor.z
                    let distance = sqrt(
                        redDistance * redDistance +
                        greenDistance * greenDistance +
                        blueDistance * blueDistance
                    )
                    let alpha = smoothstep(edge0: clampedThreshold, edge1: clampedThreshold + softness, value: distance)

                    cubeData[offset] = red
                    cubeData[offset + 1] = green
                    cubeData[offset + 2] = blue
                    cubeData[offset + 3] = alpha
                    offset += 4
                }
            }
        }

        let cubeDataBuffer = cubeData.withUnsafeBufferPointer { Data(buffer: $0) }
        let chromaFilter = CIFilter(name: "CIColorCube")
        chromaFilter?.setValue(cubeDimension, forKey: "inputCubeDimension")
        chromaFilter?.setValue(cubeDataBuffer, forKey: "inputCubeData")
        chromaFilter?.setValue(image.applyingFilter("CIUnpremultiplyAlpha"), forKey: kCIInputImageKey)

        return chromaFilter?.outputImage?.applyingFilter("CIPremultiplyAlpha") ?? image
    }

    private func apply(
        animationState: CustomCompositionAnimationState,
        to image: CIImage,
        renderSize: CGSize
    ) -> CIImage {
        let renderBounds = CGRect(x: 0, y: 0, width: renderSize.width, height: renderSize.height)
        var animatedImage = image

        if !isIdentityTransform(animationState.transform) {
            animatedImage = animatedImage.transformed(
                by: affineTransform(for: animationState.transform, canvasSize: renderSize)
            )
        }

        let opacity = min(max(animationState.opacity, 0), 1)
        if opacity < 1 {
            animatedImage = animatedImage.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)
                ]
            )
        }

        return animatedImage
            .composited(over: CIImage(color: .clear).cropped(to: renderBounds))
            .cropped(to: renderBounds)
    }

    private func affineTransform(for transform: ClipTransform, canvasSize: CGSize) -> CGAffineTransform {
        let anchorPoint = CGPoint(
            x: canvasSize.width * transform.anchorPoint.x,
            y: canvasSize.height * transform.anchorPoint.y
        )
        let radians = CGFloat(transform.rotation * .pi / 180)

        var affineTransform = CGAffineTransform.identity
        affineTransform = affineTransform.translatedBy(
            x: transform.position.x + transform.offset.x,
            y: transform.position.y + transform.offset.y
        )
        affineTransform = affineTransform.translatedBy(x: anchorPoint.x, y: anchorPoint.y)
        affineTransform = affineTransform.rotated(by: radians)
        affineTransform = affineTransform.scaledBy(
            x: transform.scale.width,
            y: transform.scale.height
        )
        affineTransform = affineTransform.translatedBy(x: -anchorPoint.x, y: -anchorPoint.y)
        return affineTransform
    }

    private func isIdentityTransform(_ transform: ClipTransform) -> Bool {
        abs(transform.position.x) <= 1.0e-9
            && abs(transform.position.y) <= 1.0e-9
            && abs(transform.offset.x) <= 1.0e-9
            && abs(transform.offset.y) <= 1.0e-9
            && abs(transform.scale.width - 1) <= 1.0e-9
            && abs(transform.scale.height - 1) <= 1.0e-9
            && abs(transform.rotation) <= 1.0e-9
    }

    private func smoothstep(edge0: Float, edge1: Float, value: Float) -> Float {
        guard edge1 > edge0 else {
            return value < edge0 ? 0 : 1
        }

        let x = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return x * x * (3 - 2 * x)
    }
}
