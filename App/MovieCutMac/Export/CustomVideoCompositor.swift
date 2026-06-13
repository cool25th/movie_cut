import AVFoundation
import CoreImage
import CoreText
import ImageIO
import MovieCutCore
import Vision

struct CustomCompositionClipEffect {
    let trackID: CMPersistentTrackID
    let timeRange: CMTimeRange
    let transform: ClipTransform
    let opacity: Double
    let keyframes: [Keyframe]
    let colorCorrection: ColorCorrection?
    let chromaKey: ChromaKeySettings?
    let chromaKeyColor: SIMD3<Float>?
    let chromaKeyThreshold: Float
    let mask: Mask?
    let effects: [Effect]
    let textContent: TextClipContent?
    let stickerEmoji: String?
    let stickerFallbackText: String?
    let stickerImageURL: URL?
    let stickerFontSize: CGFloat?
    let isBackgroundRemoved: Bool

    init?(
        trackID: CMPersistentTrackID,
        timeRange: CMTimeRange,
        transform: ClipTransform = ClipTransform(),
        opacity: Double = 1.0,
        keyframes: [Keyframe] = [],
        colorCorrection: ColorCorrection?,
        chromaKey: ChromaKeySettings? = nil,
        chromaKeyColor: SIMD3<Float>? = nil,
        chromaKeyThreshold: Float = 0.3,
        mask: Mask?,
        effects: [Effect] = [],
        textContent: TextClipContent? = nil,
        stickerEmoji: String? = nil,
        stickerFallbackText: String? = nil,
        stickerImageURL: URL? = nil,
        stickerFontSize: CGFloat? = nil,
        isBackgroundRemoved: Bool = false
    ) {
        let clampedOpacity = min(max(opacity, 0), 1)
        guard colorCorrection != nil
            || chromaKey != nil
            || chromaKeyColor != nil
            || mask != nil
            || !effects.isEmpty
            || textContent != nil
            || stickerEmoji != nil
            || stickerImageURL != nil
            || isBackgroundRemoved
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
        self.chromaKey = chromaKey
        self.chromaKeyColor = chromaKeyColor
        self.chromaKeyThreshold = min(max(chromaKeyThreshold, 0), 1)
        self.mask = mask
        self.effects = effects
        self.textContent = textContent
        self.stickerEmoji = stickerEmoji
        self.stickerFallbackText = stickerFallbackText
        self.stickerImageURL = stickerImageURL
        self.stickerFontSize = stickerFontSize
        self.isBackgroundRemoved = isBackgroundRemoved
    }

    var hasStickerOverlay: Bool {
        stickerEmoji != nil || stickerImageURL != nil
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

struct CustomCompositionTransitionEffect {
    let outgoingTrackID: CMPersistentTrackID
    let incomingTrackID: CMPersistentTrackID
    let timeRange: CMTimeRange
    let type: TransitionType

    func applies(at time: CMTime) -> Bool {
        CMTimeRangeContainsTime(timeRange, time: time)
    }

    func progress(at time: CMTime) -> Double {
        let durationSeconds = timeRange.duration.seconds
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            return 1
        }

        let elapsedSeconds = CMTimeSubtract(time, timeRange.start).seconds
        guard elapsedSeconds.isFinite else {
            return 0
        }

        return min(max(elapsedSeconds / durationSeconds, 0), 1)
    }
}

final class CustomCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = true
    let containsTweening: Bool = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    let colorCorrection: ColorCorrection?
    let textContent: TextClipContent?
    let stickerEmoji: String?
    let stickerImageURL: URL?
    var chromaKey: ChromaKeySettings?
    var chromaKeyColor: SIMD3<Float>?
    var chromaKeyThreshold: Float = 0.3
    let mask: Mask?
    let clipEffects: [CustomCompositionClipEffect]
    let transitionEffects: [CustomCompositionTransitionEffect]
    let canvasBackground: CanvasBackground?
    let prefersFastSegmentation: Bool

    init(
        timeRange: CMTimeRange,
        trackIDs: [CMPersistentTrackID],
        colorCorrection: ColorCorrection? = nil,
        textContent: TextClipContent? = nil,
        stickerEmoji: String? = nil,
        stickerImageURL: URL? = nil,
        chromaKey: ChromaKeySettings? = nil,
        chromaKeyColor: SIMD3<Float>? = nil,
        chromaKeyThreshold: Float = 0.3,
        mask: Mask? = nil,
        transitionEffects: [CustomCompositionTransitionEffect] = [],
        canvasBackground: CanvasBackground? = nil,
        prefersFastSegmentation: Bool = false
    ) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = Self.requiredTrackIDValues(
            trackIDs: trackIDs,
            transitionEffects: transitionEffects
        )
        self.colorCorrection = colorCorrection
        self.textContent = textContent
        self.stickerEmoji = stickerEmoji
        self.stickerImageURL = stickerImageURL
        self.chromaKey = chromaKey
        self.chromaKeyColor = chromaKeyColor
        self.chromaKeyThreshold = min(max(chromaKeyThreshold, 0), 1)
        self.mask = mask
        self.clipEffects = []
        self.transitionEffects = transitionEffects
        self.canvasBackground = canvasBackground
        self.prefersFastSegmentation = prefersFastSegmentation
    }

    init(
        timeRange: CMTimeRange,
        trackIDs: [CMPersistentTrackID],
        clipEffects: [CustomCompositionClipEffect],
        transitionEffects: [CustomCompositionTransitionEffect] = [],
        canvasBackground: CanvasBackground? = nil,
        prefersFastSegmentation: Bool = false
    ) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = Self.requiredTrackIDValues(
            trackIDs: trackIDs,
            transitionEffects: transitionEffects
        )
        self.colorCorrection = nil
        self.textContent = nil
        self.stickerEmoji = nil
        self.stickerImageURL = nil
        self.chromaKey = nil
        self.chromaKeyColor = nil
        self.mask = nil
        self.clipEffects = clipEffects
        self.transitionEffects = transitionEffects
        self.canvasBackground = canvasBackground
        self.prefersFastSegmentation = prefersFastSegmentation
    }

    func effect(for trackID: CMPersistentTrackID, at time: CMTime) -> CustomCompositionClipEffect? {
        clipEffects.first { $0.applies(to: trackID, at: time) }
    }

    func activeTransition(at time: CMTime) -> CustomCompositionTransitionEffect? {
        transitionEffects.first { $0.applies(at: time) }
    }

    private static func requiredTrackIDValues(
        trackIDs: [CMPersistentTrackID],
        transitionEffects: [CustomCompositionTransitionEffect]
    ) -> [NSValue] {
        var seenTrackIDs = Set<CMPersistentTrackID>()
        var requiredTrackIDs: [CMPersistentTrackID] = []

        func append(_ trackID: CMPersistentTrackID) {
            guard trackID != kCMPersistentTrackID_Invalid, seenTrackIDs.insert(trackID).inserted else {
                return
            }

            requiredTrackIDs.append(trackID)
        }

        for trackID in trackIDs {
            append(trackID)
        }

        for transitionEffect in transitionEffects {
            append(transitionEffect.outgoingTrackID)
            append(transitionEffect.incomingTrackID)
        }

        return requiredTrackIDs.map { NSNumber(value: $0) }
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
    private let personSegmentationHandler = VNSequenceRequestHandler()
    private var renderContext: AVVideoCompositionRenderContext?
    
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContext = newRenderContext
    }
    
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async {
            if let instruction = request.videoCompositionInstruction as? CustomCompositionInstruction,
               let transition = instruction.activeTransition(at: request.compositionTime),
               let outgoingBuffer = request.sourceFrame(byTrackID: transition.outgoingTrackID),
               let incomingBuffer = request.sourceFrame(byTrackID: transition.incomingTrackID) {
                let outgoingEffect = instruction.effect(
                    for: transition.outgoingTrackID,
                    at: request.compositionTime
                )
                let incomingEffect = instruction.effect(
                    for: transition.incomingTrackID,
                    at: request.compositionTime
                )
                let outgoingImage = self.applyClipEffects(
                    to: CIImage(cvPixelBuffer: outgoingBuffer),
                    effect: outgoingEffect,
                    instruction: instruction,
                    request: request
                )
                let incomingImage = self.applyClipEffects(
                    to: CIImage(cvPixelBuffer: incomingBuffer),
                    effect: incomingEffect,
                    instruction: instruction,
                    request: request
                )

                var transitionedImage = TransitionPixelProcessor.apply(
                    type: transition.type,
                    from: outgoingImage,
                    to: incomingImage,
                    progress: transition.progress(at: request.compositionTime)
                )
                transitionedImage = self.renderTextOverlay(
                    instruction: instruction,
                    onto: transitionedImage,
                    at: request.compositionTime
                )
                transitionedImage = self.renderStickerOverlay(
                    for: nil,
                    instruction: instruction,
                    onto: transitionedImage,
                    at: request.compositionTime
                )
                transitionedImage = CanvasBackgroundPixelProcessor.compose(
                    frame: transitionedImage,
                    over: instruction.canvasBackground,
                    renderSize: request.renderContext.size
                )
                self.finishRequest(request, with: transitionedImage)
                return
            }

            guard let (trackID, sourceBuffer) = self.firstSourceFrame(in: request) else {
                request.finish(with: NSError(domain: "MovieCut", code: -1, userInfo: nil))
                return
            }
            
            var image = CIImage(cvPixelBuffer: sourceBuffer)
            
            if let instruction = request.videoCompositionInstruction as? CustomCompositionInstruction {
                let effect = instruction.effect(for: trackID, at: request.compositionTime)
                image = self.applyClipEffects(
                    to: image,
                    effect: effect,
                    instruction: instruction,
                    request: request
                )

                image = self.renderTextOverlay(
                    instruction: instruction,
                    onto: image,
                    at: request.compositionTime
                )

                image = self.renderStickerOverlay(
                    for: effect,
                    instruction: instruction,
                    onto: image,
                    at: request.compositionTime
                )

                image = CanvasBackgroundPixelProcessor.compose(
                    frame: image,
                    over: instruction.canvasBackground,
                    renderSize: request.renderContext.size
                )
            }

            self.finishRequest(request, with: image)
        }
    }
    
    func cancelAllPendingVideoCompositionRequests() {}

    private func applyClipEffects(
        to image: CIImage,
        effect: CustomCompositionClipEffect?,
        instruction: CustomCompositionInstruction,
        request: AVAsynchronousVideoCompositionRequest
    ) -> CIImage {
        var image = image
        let colorCorrection = effect?.colorCorrection ?? instruction.colorCorrection
        let chromaKey = effect?.chromaKey ?? instruction.chromaKey
        let chromaKeyColor = effect?.chromaKeyColor ?? instruction.chromaKeyColor
        let chromaKeyThreshold = effect?.chromaKeyThreshold ?? instruction.chromaKeyThreshold
        let mask = effect?.mask ?? instruction.mask
        let animationState = effect?.animationState(at: request.compositionTime)
        let clipEffects = effect?.effects ?? []
        let isBackgroundRemoved = effect?.isBackgroundRemoved ?? false

        if !clipEffects.isEmpty {
            image = VisualEffectPixelProcessor.apply(clipEffects, to: image)
        }

        if isBackgroundRemoved {
            image = applyPersonSegmentation(
                to: image,
                request: request,
                prefersFast: instruction.prefersFastSegmentation
            )
        }

        if let colorCorrection {
            image = ColorCorrectionPixelProcessor.apply(colorCorrection, to: image)
        }

        if let chromaKey {
            image = ChromaKeyPixelProcessor.apply(chromaKey, to: image)
        } else if let chromaKeyColor {
            image = ChromaKeyPixelProcessor.apply(
                keyColor: chromaKeyColor,
                threshold: chromaKeyThreshold,
                to: image
            )
        }

        if let mask {
            image = MaskPixelProcessor.apply(mask, to: image, at: request.compositionTime.seconds)
        }

        if let animationState {
            image = apply(
                animationState: animationState,
                to: image,
                renderSize: request.renderContext.size
            )
        }

        return image
    }

    private func finishRequest(_ request: AVAsynchronousVideoCompositionRequest, with image: CIImage) {
        guard let outputBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "MovieCut", code: -2, userInfo: nil))
            return
        }

        ciContext.render(image, to: outputBuffer)
        request.finish(withComposedVideoFrame: outputBuffer)
    }

    private func renderTextOverlay(
        instruction: CustomCompositionInstruction,
        onto image: CIImage,
        at time: CMTime
    ) -> CIImage {
        let items = textOverlayRenderItems(in: instruction, at: time)
        guard !items.isEmpty else {
            return image
        }

        return TextOverlayPixelProcessor.apply(items, to: image, at: time.seconds)
    }

    private func textOverlayRenderItems(
        in instruction: CustomCompositionInstruction,
        at time: CMTime
    ) -> [TextOverlayRenderItem] {
        var items = instruction.clipEffects.compactMap { effect -> TextOverlayRenderItem? in
            guard let textContent = effect.textContent,
                  CMTimeRangeContainsTime(effect.timeRange, time: time)
            else {
                return nil
            }

            let animationState = effect.animationState(at: time)
            return TextOverlayRenderItem(
                textContent: textContent,
                transform: animationState?.transform ?? effect.transform,
                opacity: animationState?.opacity ?? effect.opacity,
                timeRangeStart: effect.timeRange.start.seconds,
                timeRangeDuration: effect.timeRange.duration.seconds
            )
        }

        if let textContent = instruction.textContent,
           CMTimeRangeContainsTime(instruction.timeRange, time: time) {
            items.append(TextOverlayRenderItem(
                textContent: textContent,
                transform: ClipTransform(),
                opacity: 1,
                timeRangeStart: instruction.timeRange.start.seconds,
                timeRangeDuration: instruction.timeRange.duration.seconds
            ))
        }

        return items
    }

    private func renderStickerOverlay(
        for clipEffect: CustomCompositionClipEffect?,
        instruction: CustomCompositionInstruction,
        onto image: CIImage,
        at time: CMTime
    ) -> CIImage {
        _ = clipEffect

        let activeStickerEffects = instruction.clipEffects.filter { effect in
            effect.hasStickerOverlay && CMTimeRangeContainsTime(effect.timeRange, time: time)
        }
        let hasInstructionSticker = (instruction.stickerEmoji != nil || instruction.stickerImageURL != nil)
            && CMTimeRangeContainsTime(instruction.timeRange, time: time)

        guard !activeStickerEffects.isEmpty || hasInstructionSticker else {
            return image
        }

        let renderBounds = image.extent
        let renderSize = renderBounds.size
        guard renderSize.width > 0, renderSize.height > 0 else {
            return image
        }

        let width = max(Int(ceil(renderSize.width)), 1)
        let height = max(Int(ceil(renderSize.height)), 1)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return image
        }

        context.clear(CGRect(x: 0, y: 0, width: renderSize.width, height: renderSize.height))

        for stickerEffect in activeStickerEffects {
            drawStickerEffect(stickerEffect, in: context, renderSize: renderSize, at: time)
        }

        if let stickerEmoji = instruction.stickerEmoji {
            drawStickerEmoji(
                stickerEmoji,
                transform: ClipTransform(),
                opacity: 1,
                in: context,
                renderSize: renderSize
            )
        }

        if let stickerImageURL = instruction.stickerImageURL {
            drawStickerImage(
                stickerImageURL,
                fallbackText: nil,
                transform: ClipTransform(),
                opacity: 1,
                fontSize: 88,
                in: context,
                renderSize: renderSize
            )
        }

        guard let cgImage = context.makeImage() else {
            return image
        }

        var overlay = CIImage(cgImage: cgImage)
        if !isZeroPoint(renderBounds.origin) {
            overlay = overlay.transformed(
                by: CGAffineTransform(
                    translationX: renderBounds.origin.x,
                    y: renderBounds.origin.y
                )
            )
        }

        return overlay
            .composited(over: image)
            .cropped(to: renderBounds)
    }

    private func drawStickerEffect(
        _ stickerEffect: CustomCompositionClipEffect,
        in context: CGContext,
        renderSize: CGSize,
        at time: CMTime
    ) {
        let animationState = stickerEffect.animationState(at: time)
        let transform = animationState?.transform ?? stickerEffect.transform
        let opacity = animationState?.opacity ?? stickerEffect.opacity
        let fontSize = stickerEffect.stickerFontSize ?? 88

        if let stickerImageURL = stickerEffect.stickerImageURL {
            drawStickerImage(
                stickerImageURL,
                fallbackText: stickerEffect.stickerFallbackText ?? stickerEffect.stickerEmoji,
                transform: transform,
                opacity: opacity,
                fontSize: fontSize,
                in: context,
                renderSize: renderSize
            )
            return
        }

        if let stickerEmoji = stickerEffect.stickerEmoji {
            drawStickerEmoji(
                stickerEmoji,
                transform: transform,
                opacity: opacity,
                fontSize: fontSize,
                in: context,
                renderSize: renderSize
            )
        }
    }

    private func drawStickerImage(
        _ imageURL: URL,
        fallbackText: String?,
        transform: ClipTransform,
        opacity: Double,
        fontSize: CGFloat,
        in context: CGContext,
        renderSize: CGSize
    ) {
        let effectiveOpacity = min(max(opacity, 0), 1)
        guard effectiveOpacity > 0 else { return }

        guard let cgImage = loadStickerImage(from: imageURL) else {
            if let fallbackText, !fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                drawStickerFallbackText(
                    fallbackText,
                    transform: transform,
                    opacity: opacity,
                    fontSize: fontSize,
                    in: context,
                    renderSize: renderSize
                )
            }
            return
        }

        let sourceSize = CGSize(width: cgImage.width, height: cgImage.height)
        let displaySize = stickerDisplaySize(sourceSize: sourceSize, fontSize: fontSize, renderSize: renderSize)
        let basePosition = stickerPosition(transform: transform, renderSize: renderSize)
        let center = CGPoint(
            x: basePosition.x + transform.offset.x,
            y: renderSize.height - basePosition.y - transform.offset.y
        )

        context.saveGState()
        context.setAlpha(CGFloat(effectiveOpacity))
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: CGFloat(transform.rotation * .pi / 180))
        context.scaleBy(x: transform.scale.width, y: transform.scale.height)
        context.draw(
            cgImage,
            in: CGRect(
                x: -displaySize.width * 0.5,
                y: -displaySize.height * 0.5,
                width: displaySize.width,
                height: displaySize.height
            )
        )
        context.restoreGState()
    }

    private func loadStickerImage(from imageURL: URL) -> CGImage? {
        guard
            let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            return nil
        }

        return cgImage
    }

    private func stickerDisplaySize(sourceSize: CGSize, fontSize: CGFloat, renderSize: CGSize) -> CGSize {
        let aspectRatio: CGFloat
        if sourceSize.width > 0, sourceSize.height > 0 {
            aspectRatio = sourceSize.width / sourceSize.height
        } else {
            aspectRatio = 1
        }

        let shorterRenderEdge = max(min(renderSize.width, renderSize.height), 1)
        let width = min(max(fontSize * 2.8, 96), shorterRenderEdge * 0.45)
        let height = max(width / max(aspectRatio, 0.01), 1)
        return CGSize(width: width, height: height)
    }

    private func drawStickerFallbackText(
        _ text: String,
        transform: ClipTransform,
        opacity: Double,
        fontSize: CGFloat,
        in context: CGContext,
        renderSize: CGSize
    ) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let effectiveOpacity = min(max(opacity, 0), 1)
        guard effectiveOpacity > 0 else { return }

        let label = String(trimmedText.prefix(12)).uppercased()
        let baseFontSize = max(fontSize * 0.54, 24)
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, baseFontSize, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: label,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            ]
        ))
        var ascent = CGFloat(0)
        var descent = CGFloat(0)
        var leading = CGFloat(0)
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let paddingX = max(baseFontSize * 0.55, 18)
        let paddingY = max(baseFontSize * 0.35, 12)
        let boxSize = CGSize(
            width: min(max(lineWidth + paddingX * 2, baseFontSize * 3.0), renderSize.width * 0.7),
            height: min(max(ascent + descent + paddingY * 2, baseFontSize * 1.7), renderSize.height * 0.35)
        )
        let basePosition = stickerPosition(transform: transform, renderSize: renderSize)
        let center = CGPoint(
            x: basePosition.x + transform.offset.x,
            y: renderSize.height - basePosition.y - transform.offset.y
        )

        context.saveGState()
        context.setAlpha(CGFloat(effectiveOpacity))
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: CGFloat(transform.rotation * .pi / 180))
        context.scaleBy(x: transform.scale.width, y: transform.scale.height)

        let box = CGRect(x: -boxSize.width * 0.5, y: -boxSize.height * 0.5, width: boxSize.width, height: boxSize.height)
        let boxPath = CGPath(
            roundedRect: box,
            cornerWidth: boxSize.height * 0.24,
            cornerHeight: boxSize.height * 0.24,
            transform: nil
        )
        context.setFillColor(CGColor(red: 0.95, green: 0.18, blue: 0.28, alpha: 1))
        context.addPath(boxPath)
        context.fillPath()
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        context.setLineWidth(max(baseFontSize * 0.08, 3))
        context.addPath(boxPath)
        context.strokePath()

        context.textMatrix = .identity
        context.textPosition = CGPoint(
            x: -lineWidth * 0.5,
            y: -((ascent + descent) * 0.5) + descent
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func drawStickerEmoji(
        _ stickerEmoji: String,
        transform: ClipTransform,
        opacity: Double,
        fontSize: CGFloat = 88,
        in context: CGContext,
        renderSize: CGSize
    ) {
        let emoji = stickerEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !emoji.isEmpty else { return }

        let effectiveOpacity = min(max(opacity, 0), 1)
        guard effectiveOpacity > 0 else { return }

        let fontSize = max(fontSize, 1)
        let font = CTFontCreateWithName("Apple Color Emoji" as CFString, fontSize, nil)
        let attributedString = NSAttributedString(
            string: emoji,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
                    red: 1,
                    green: 1,
                    blue: 1,
                    alpha: 1
                )
            ]
        )
        let line = CTLineCreateWithAttributedString(attributedString)
        var ascent = CGFloat(0)
        var descent = CGFloat(0)
        var leading = CGFloat(0)
        let lineWidth = max(
            CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading)),
            fontSize
        )

        let basePosition = stickerPosition(transform: transform, renderSize: renderSize)
        let center = CGPoint(
            x: basePosition.x + transform.offset.x,
            y: renderSize.height - basePosition.y - transform.offset.y
        )

        context.saveGState()
        context.setAlpha(CGFloat(effectiveOpacity))
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: CGFloat(transform.rotation * .pi / 180))
        context.scaleBy(x: transform.scale.width, y: transform.scale.height)
        context.textMatrix = .identity
        context.textPosition = CGPoint(
            x: -lineWidth * 0.5,
            y: (descent - ascent) * 0.5
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func stickerPosition(
        transform: ClipTransform,
        renderSize: CGSize
    ) -> CGPoint {
        if !isZeroPoint(transform.position) {
            return transform.position
        }

        return CGPoint(x: renderSize.width * 0.5, y: renderSize.height * 0.5)
    }

    private func isZeroPoint(_ point: CGPoint) -> Bool {
        abs(point.x) <= 1.0e-9 && abs(point.y) <= 1.0e-9
    }

    // MARK: - Background Removal

    private func applyPersonSegmentation(
        to image: CIImage,
        request: AVAsynchronousVideoCompositionRequest,
        prefersFast: Bool
    ) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        guard let sourceImage = ciContext.createCGImage(image, from: extent) else {
            // Vision unavailable on this frame: leave it unchanged (F-08 AC④).
            return image
        }

        let segmentationRequest = VNGeneratePersonSegmentationRequest()
        // Preview favors speed (fast quality + cache); export favors accuracy.
        segmentationRequest.qualityLevel = prefersFast ? .fast : .accurate
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8

        do {
            try personSegmentationHandler.perform([segmentationRequest], on: sourceImage)
        } catch {
            return image
        }

        guard let maskPixelBuffer = segmentationRequest.results?.first?.pixelBuffer else {
            return image
        }

        let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
        guard !maskImage.extent.isEmpty else {
            return image
        }

        let alignedMask = PersonSegmentationCompositor.align(maskImage, to: extent)
        // No person detected → leave the frame unchanged (F-08 AC④).
        guard maskContainsForeground(alignedMask, extent: extent) else {
            return image
        }

        return PersonSegmentationCompositor.removeBackground(from: image, mask: alignedMask)
    }

    private func maskContainsForeground(_ maskImage: CIImage, extent: CGRect) -> Bool {
        guard let maximumImage = CIFilter(
            name: "CIAreaMaximum",
            parameters: [
                kCIInputImageKey: maskImage,
                kCIInputExtentKey: CIVector(cgRect: extent)
            ]
        )?.outputImage else {
            return true
        }

        var maximumPixel = [UInt8](repeating: 0, count: 4)
        maximumPixel.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            ciContext.render(
                maximumImage,
                toBitmap: baseAddress,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }

        return maximumPixel[0] > 8 || maximumPixel[1] > 8 || maximumPixel[2] > 8
    }

    private func applyBackgroundRemoval(to image: CIImage) -> CIImage {
        let size = image.extent.size
        guard size.width > 0, size.height > 0 else { return image }

        // Create a simple center-biased elliptical mask to approximate foreground.
        let maskImage = CIImage(color: .white).cropped(to: image.extent)

        // Generate a vignette-based mask: brighter in center, darker at edges.
        // This serves as a fallback when Vision cannot produce a person mask.
        let vignetteRadius = min(size.width, size.height) * 0.4

        let backgroundColor = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: image.extent)

        // Create a simple radial gradient mask for the center region.
        let gradientMask = CIFilter(
            name: "CIRadialGradient",
            parameters: [
                "inputCenter": CIVector(x: size.width / 2, y: size.height / 2),
                "inputRadius0": NSNumber(value: Float(vignetteRadius)),
                "inputRadius1": NSNumber(value: Float(max(size.width, size.height) * 0.7)),
                "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
                "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0)
            ]
        )?.outputImage?.cropped(to: image.extent) ?? maskImage

        return image.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputMaskImageKey: gradientMask,
                kCIInputBackgroundImageKey: backgroundColor
            ]
        )
    }

    // MARK: - Source Frame Helpers

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

}
