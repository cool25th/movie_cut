#if os(iOS)

import AVFoundation
import CoreImage
import CoreText
import MovieCutCore
import Vision

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
    let effects: [Effect]
    let textContent: TextClipContent?
    let stickerEmoji: String?
    let isBackgroundRemoved: Bool

    init?(
        trackID: CMPersistentTrackID,
        timeRange: CMTimeRange,
        transform: ClipTransform = ClipTransform(),
        opacity: Double = 1.0,
        keyframes: [Keyframe] = [],
        colorCorrection: ColorCorrection?,
        chromaKeyColor: SIMD3<Float>? = nil,
        chromaKeyThreshold: Float = 0.3,
        mask: Mask?,
        effects: [Effect] = [],
        textContent: TextClipContent? = nil,
        stickerEmoji: String? = nil,
        isBackgroundRemoved: Bool = false
    ) {
        let clampedOpacity = min(max(opacity, 0), 1)
        guard colorCorrection != nil
            || chromaKeyColor != nil
            || mask != nil
            || !effects.isEmpty
            || textContent != nil
            || stickerEmoji != nil
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
        self.chromaKeyColor = chromaKeyColor
        self.chromaKeyThreshold = min(max(chromaKeyThreshold, 0), 1)
        self.mask = mask
        self.effects = effects
        self.textContent = textContent
        self.stickerEmoji = stickerEmoji
        self.isBackgroundRemoved = isBackgroundRemoved
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
    let textContent: TextClipContent?
    let stickerEmoji: String?
    var chromaKeyColor: SIMD3<Float>?
    var chromaKeyThreshold: Float = 0.3
    let mask: Mask?
    let clipEffects: [CustomCompositionClipEffect]

    init(
        timeRange: CMTimeRange,
        trackIDs: [CMPersistentTrackID],
        colorCorrection: ColorCorrection? = nil,
        textContent: TextClipContent? = nil,
        stickerEmoji: String? = nil,
        chromaKeyColor: SIMD3<Float>? = nil,
        chromaKeyThreshold: Float = 0.3,
        mask: Mask? = nil
    ) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = trackIDs.map { NSNumber(value: $0) }
        self.colorCorrection = colorCorrection
        self.textContent = textContent
        self.stickerEmoji = stickerEmoji
        self.chromaKeyColor = chromaKeyColor
        self.chromaKeyThreshold = min(max(chromaKeyThreshold, 0), 1)
        self.mask = mask
        self.clipEffects = []
    }

    init(timeRange: CMTimeRange, trackIDs: [CMPersistentTrackID], clipEffects: [CustomCompositionClipEffect]) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = trackIDs.map { NSNumber(value: $0) }
        self.colorCorrection = nil
        self.textContent = nil
        self.stickerEmoji = nil
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
    private let personSegmentationHandler = VNSequenceRequestHandler()
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
                let clipEffects = effect?.effects ?? []
                let isBackgroundRemoved = effect?.isBackgroundRemoved ?? false

                // Apply CIFilter-based effects (blur, grayscale, sepia, temperature, exposure, style transfer)
                if !clipEffects.isEmpty {
                    image = self.applyEffects(clipEffects, to: image)
                }

                // Apply background removal
                if isBackgroundRemoved {
                    image = self.applyPersonSegmentation(to: image, request: request)
                }

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

                image = self.renderTextOverlay(
                    for: effect,
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

    // MARK: - Effects Rendering

    private func applyEffects(_ effects: [Effect], to image: CIImage) -> CIImage {
        var result = image
        for effect in effects {
            switch effect.type {
            case .blur:
                let radius = effect.parameters["radius"] ?? 5.0
                result = result.applyingFilter(
                    "CIGaussianBlur",
                    parameters: [kCIInputRadiusKey: radius]
                )
            case .grayscale:
                result = result.applyingFilter("CIPhotoEffectMono", parameters: [:])
            case .sepia:
                result = result.applyingFilter("CIPhotoEffectSepia", parameters: [:])
            case .temperature:
                let neutral = CGPoint(
                    x: effect.parameters["neutralX"] ?? 6500,
                    y: effect.parameters["neutralY"] ?? 6500
                )
                let target = CGPoint(
                    x: effect.parameters["targetX"] ?? 6500,
                    y: effect.parameters["targetY"] ?? 6500
                )
                result = result.applyingFilter(
                    "CITemperatureAndTint",
                    parameters: [
                        "inputNeutral": CIVector(cgPoint: neutral),
                        "inputTargetNeutral": CIVector(cgPoint: target)
                    ]
                )
            case .exposure:
                let ev = effect.parameters["ev"] ?? effect.parameters["amount"] ?? 0.5
                result = result.applyingFilter(
                    "CIExposureAdjust",
                    parameters: [kCIInputEVKey: ev]
                )
            case .styleTransfer:
                result = applyStyleTransfer(effect, to: result)
            default:
                break
            }
        }
        return result
    }

    private func renderTextOverlay(
        for clipEffect: CustomCompositionClipEffect?,
        instruction: CustomCompositionInstruction,
        onto image: CIImage,
        at time: CMTime
    ) -> CIImage {
        _ = clipEffect

        let activeTextEffects = instruction.clipEffects.filter { effect in
            effect.textContent != nil && CMTimeRangeContainsTime(effect.timeRange, time: time)
        }
        let hasInstructionText = instruction.textContent != nil
            && CMTimeRangeContainsTime(instruction.timeRange, time: time)

        guard !activeTextEffects.isEmpty || hasInstructionText else {
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

        for textEffect in activeTextEffects {
            drawTextEffect(textEffect, in: context, renderSize: renderSize, at: time)
        }

        if let textContent = instruction.textContent {
            drawTextContent(
                textContent,
                transform: ClipTransform(),
                opacity: 1,
                timeRange: instruction.timeRange,
                in: context,
                renderSize: renderSize,
                at: time
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

    private func renderStickerOverlay(
        for clipEffect: CustomCompositionClipEffect?,
        instruction: CustomCompositionInstruction,
        onto image: CIImage,
        at time: CMTime
    ) -> CIImage {
        _ = clipEffect

        let activeStickerEffects = instruction.clipEffects.filter { effect in
            effect.stickerEmoji != nil && CMTimeRangeContainsTime(effect.timeRange, time: time)
        }
        let hasInstructionSticker = instruction.stickerEmoji != nil
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
        guard let stickerEmoji = stickerEffect.stickerEmoji else { return }

        let animationState = stickerEffect.animationState(at: time)
        drawStickerEmoji(
            stickerEmoji,
            transform: animationState?.transform ?? stickerEffect.transform,
            opacity: animationState?.opacity ?? stickerEffect.opacity,
            in: context,
            renderSize: renderSize
        )
    }

    private func drawStickerEmoji(
        _ stickerEmoji: String,
        transform: ClipTransform,
        opacity: Double,
        in context: CGContext,
        renderSize: CGSize
    ) {
        let emoji = stickerEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !emoji.isEmpty else { return }

        let effectiveOpacity = min(max(opacity, 0), 1)
        guard effectiveOpacity > 0 else { return }

        let fontSize = CGFloat(88)
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

    private func drawTextEffect(
        _ textEffect: CustomCompositionClipEffect,
        in context: CGContext,
        renderSize: CGSize,
        at time: CMTime
    ) {
        guard let textContent = textEffect.textContent else { return }

        let animationState = textEffect.animationState(at: time)
        drawTextContent(
            textContent,
            transform: animationState?.transform ?? textEffect.transform,
            opacity: animationState?.opacity ?? textEffect.opacity,
            timeRange: textEffect.timeRange,
            in: context,
            renderSize: renderSize,
            at: time
        )
    }

    private func drawTextContent(
        _ textContent: TextClipContent,
        transform: ClipTransform,
        opacity: Double,
        timeRange: CMTimeRange,
        in context: CGContext,
        renderSize: CGSize,
        at time: CMTime
    ) {
        let textState = animatedTextState(for: textContent, timeRange: timeRange, at: time)
        guard !textState.text.isEmpty else { return }

        let effectiveOpacity = min(max(opacity * textState.alpha, 0), 1)
        guard effectiveOpacity > 0 else { return }

        let fontSize = max(CGFloat(textContent.fontSize), 1)
        let fontName = textContent.fontFamily == "System" ? "Helvetica Neue" : textContent.fontFamily
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let textColor = cgColor(hexRGB: textContent.fontColor)
        let attributedString = attributedText(
            textState.text,
            font: font,
            color: textColor,
            alignment: textContent.alignment
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let paddingX = max(fontSize * 0.35, 10)
        let paddingY = max(fontSize * 0.2, 6)
        let minimumWidth = min(max(fontSize * 5, 160), renderSize.width)
        let constrainedWidth = max(renderSize.width * 0.8 - paddingX * 2, 1)
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedString.length),
            nil,
            CGSize(width: constrainedWidth, height: .greatestFiniteMagnitude),
            nil
        )
        let boxWidth = min(max(ceil(suggestedSize.width) + paddingX * 2, minimumWidth), renderSize.width)
        let boxHeight = min(
            max(ceil(suggestedSize.height) + paddingY * 2, fontSize + paddingY * 2),
            renderSize.height
        )

        let basePosition = textPosition(for: textContent, transform: transform, renderSize: renderSize)
        let center = CGPoint(
            x: basePosition.x + transform.offset.x + textState.translation.x,
            y: renderSize.height - basePosition.y - transform.offset.y + textState.translation.y
        )
        let scaleX = transform.scale.width * textState.scale
        let scaleY = transform.scale.height * textState.scale

        context.saveGState()
        context.setAlpha(CGFloat(effectiveOpacity))
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: CGFloat(transform.rotation * .pi / 180))
        context.scaleBy(x: scaleX, y: scaleY)

        let textBox = CGRect(x: -boxWidth * 0.5, y: -boxHeight * 0.5, width: boxWidth, height: boxHeight)
        if let backgroundColor = textContent.backgroundColor {
            context.setFillColor(cgColor(hexRGB: backgroundColor))
            context.fill(textBox)
        }

        let textRect = textBox.insetBy(dx: paddingX, dy: paddingY)
        let path = CGMutablePath()
        path.addRect(textRect)
        context.textMatrix = .identity
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributedString.length),
            path,
            nil
        )
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private func animatedTextState(
        for textContent: TextClipContent,
        timeRange: CMTimeRange,
        at time: CMTime
    ) -> (text: String, alpha: Double, translation: CGPoint, scale: CGFloat) {
        guard let animation = textContent.animation else {
            return (textContent.text, 1, CGPoint(x: 0, y: 0), 1)
        }

        let rawLocalTime = CMTimeSubtract(time, timeRange.start).seconds
        let localTime = rawLocalTime.isFinite ? max(0, rawLocalTime) : 0
        let delay = max(animation.delay, 0)
        let duration = max(animation.duration, 1.0e-6)
        let elapsed = localTime - delay
        let progress = min(max(elapsed / duration, 0), 1)
        let isBeforeDelay = elapsed < 0

        switch animation.type {
        case .fadeIn:
            return (textContent.text, isBeforeDelay ? 0 : progress, CGPoint(x: 0, y: 0), 1)
        case .fadeOut:
            return (textContent.text, isBeforeDelay ? 1 : 1 - progress, CGPoint(x: 0, y: 0), 1)
        case .typewriter:
            guard !isBeforeDelay else {
                return ("", 1, CGPoint(x: 0, y: 0), 1)
            }
            let characterCount = Int(floor(progress * Double(textContent.text.count)))
            return (String(textContent.text.prefix(characterCount)), 1, CGPoint(x: 0, y: 0), 1)
        case .slideUp:
            return (
                textContent.text,
                1,
                CGPoint(x: 0, y: -40 * (1 - progress)),
                1
            )
        case .slideDown:
            return (
                textContent.text,
                1,
                CGPoint(x: 0, y: 40 * (1 - progress)),
                1
            )
        case .scale:
            return (textContent.text, 1, CGPoint(x: 0, y: 0), max(CGFloat(progress), 0.001))
        case .bounce:
            let offset = sin(progress * .pi * 3) * 20 * (1 - progress)
            return (textContent.text, 1, CGPoint(x: 0, y: offset), 1)
        }
    }

    private func attributedText(
        _ text: String,
        font: CTFont,
        color: CGColor,
        alignment: TextAlignment
    ) -> NSAttributedString {
        var ctAlignment = coreTextAlignment(for: alignment)
        let paragraphStyle = CTParagraphStyleCreate([
            CTParagraphStyleSetting(
                spec: .alignment,
                valueSize: MemoryLayout<CTTextAlignment>.size,
                value: &ctAlignment
            )
        ], 1)

        return NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle
            ]
        )
    }

    private func coreTextAlignment(for alignment: TextAlignment) -> CTTextAlignment {
        switch alignment {
        case .leading:
            return .left
        case .center:
            return .center
        case .trailing:
            return .right
        case .justified:
            return .justified
        }
    }

    private func textPosition(
        for textContent: TextClipContent,
        transform: ClipTransform,
        renderSize: CGSize
    ) -> CGPoint {
        if !isZeroPoint(textContent.position) {
            return textContent.position
        }

        if !isZeroPoint(transform.position) {
            return transform.position
        }

        return CGPoint(x: renderSize.width * 0.5, y: renderSize.height * 0.5)
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

    private func cgColor(hexRGB: String) -> CGColor {
        let hex = hexRGB.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else {
            return CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        }

        return CGColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private func applyStyleTransfer(_ effect: Effect, to image: CIImage) -> CIImage {
        let intensity = min(max(effect.parameters["intensity"] ?? 0.75, 0), 1)
        guard intensity > 0 else { return image }

        let styleIndex = Int((effect.parameters["styleIndex"] ?? 1).rounded())
        guard let gradientImage = gradientMapImage(for: styleIndex) else {
            return image
        }

        let colorMapFilter = CIFilter(name: "CIColorMap")
        colorMapFilter?.setValue(image, forKey: kCIInputImageKey)
        colorMapFilter?.setValue(gradientImage, forKey: "inputGradientImage")
        guard let mappedImage = colorMapFilter?.outputImage?.cropped(to: image.extent) else {
            return image
        }

        let blendFilterName = styleIndex == 2 ? "CIMultiplyBlendMode" : "CISoftLightBlendMode"
        let blendFilter = CIFilter(name: blendFilterName)
        blendFilter?.setValue(mappedImage, forKey: kCIInputImageKey)
        blendFilter?.setValue(image, forKey: kCIInputBackgroundImageKey)
        let blendedImage = blendFilter?.outputImage?.cropped(to: image.extent) ?? mappedImage

        let dissolveFilter = CIFilter(name: "CIDissolveTransition")
        dissolveFilter?.setValue(image, forKey: kCIInputImageKey)
        dissolveFilter?.setValue(blendedImage, forKey: kCIInputTargetImageKey)
        dissolveFilter?.setValue(intensity, forKey: kCIInputTimeKey)

        return dissolveFilter?.outputImage?.cropped(to: image.extent) ?? blendedImage
    }

    private func gradientMapImage(for styleIndex: Int) -> CIImage? {
        let width = 256
        let height = 1
        let stops = gradientStops(for: styleIndex)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        for index in 0..<width {
            let t = CGFloat(index) / CGFloat(width - 1)
            let color = interpolatedColor(at: t, stops: stops)
            let offset = index * 4
            pixels[offset] = UInt8(min(max(color.red * 255, 0), 255).rounded())
            pixels[offset + 1] = UInt8(min(max(color.green * 255, 0), 255).rounded())
            pixels[offset + 2] = UInt8(min(max(color.blue * 255, 0), 255).rounded())
            pixels[offset + 3] = 255
        }

        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }

        return CIImage(cgImage: cgImage)
    }

    private func gradientStops(
        for styleIndex: Int
    ) -> [(position: CGFloat, red: CGFloat, green: CGFloat, blue: CGFloat)] {
        switch styleIndex {
        case 2:
            return [
                (0, 0.02, 0.02, 0.02),
                (0.5, 0.45, 0.45, 0.45),
                (1, 0.96, 0.96, 0.92)
            ]
        case 3:
            return [
                (0, 0.12, 0.07, 0.03),
                (0.45, 0.68, 0.43, 0.23),
                (1, 1.0, 0.87, 0.58)
            ]
        case 4:
            return [
                (0, 0.03, 0.0, 0.12),
                (0.45, 0.0, 0.72, 0.95),
                (1, 1.0, 0.08, 0.58)
            ]
        case 5:
            return [
                (0, 0.16, 0.22, 0.30),
                (0.5, 0.53, 0.72, 0.78),
                (1, 0.96, 0.92, 0.82)
            ]
        default:
            return [
                (0, 0.04, 0.04, 0.05),
                (0.5, 0.88, 0.22, 0.12),
                (1, 1.0, 0.92, 0.18)
            ]
        }
    }

    private func interpolatedColor(
        at value: CGFloat,
        stops: [(position: CGFloat, red: CGFloat, green: CGFloat, blue: CGFloat)]
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

    // MARK: - Background Removal

    private func applyPersonSegmentation(
        to image: CIImage,
        request: AVAsynchronousVideoCompositionRequest
    ) -> CIImage {
        _ = request

        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        guard let sourceImage = ciContext.createCGImage(image, from: extent) else {
            return applyBackgroundRemoval(to: image)
        }

        let segmentationRequest = VNGeneratePersonSegmentationRequest()
        segmentationRequest.qualityLevel = .accurate
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8

        do {
            try personSegmentationHandler.perform([segmentationRequest], on: sourceImage)
        } catch {
            return applyBackgroundRemoval(to: image)
        }

        guard let maskPixelBuffer = segmentationRequest.results?.first?.pixelBuffer else {
            return applyBackgroundRemoval(to: image)
        }

        let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
        guard !maskImage.extent.isEmpty else {
            return applyBackgroundRemoval(to: image)
        }

        let scaleX = extent.width / maskImage.extent.width
        let scaleY = extent.height / maskImage.extent.height
        var scaledMask = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        scaledMask = scaledMask.transformed(by: CGAffineTransform(
            translationX: extent.minX - scaledMask.extent.minX,
            y: extent.minY - scaledMask.extent.minY
        ))
        let alignedMask = scaledMask.cropped(to: extent)
        guard maskContainsForeground(alignedMask, extent: extent) else {
            return applyBackgroundRemoval(to: image)
        }

        let backgroundColor = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: extent)

        return image.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputMaskImageKey: alignedMask,
                kCIInputBackgroundImageKey: backgroundColor
            ]
        ).cropped(to: extent)
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

#endif
