#if os(iOS)

import AVFoundation
import CoreImage
import CoreText
import MovieCutCore
import Vision

final class CustomCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = true
    let containsTweening: Bool = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    let colorCorrection: ColorCorrection?
    let colorGrade: ColorGrade?
    let textContent: TextClipContent?
    let stickerEmoji: String?
    var chromaKeyColor: SIMD3<Float>?
    var chromaKeyThreshold: Float = 0.3
    let mask: Mask?
    let clipEffects: [CustomCompositionClipEffect]
    let canvasBackground: CanvasBackground?

    init(
        timeRange: CMTimeRange,
        trackIDs: [CMPersistentTrackID],
        colorCorrection: ColorCorrection? = nil,
        colorGrade: ColorGrade? = nil,
        textContent: TextClipContent? = nil,
        stickerEmoji: String? = nil,
        chromaKeyColor: SIMD3<Float>? = nil,
        chromaKeyThreshold: Float = 0.3,
        mask: Mask? = nil,
        canvasBackground: CanvasBackground? = nil
    ) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = trackIDs.map { NSNumber(value: $0) }
        self.colorCorrection = colorCorrection
        self.colorGrade = colorGrade
        self.textContent = textContent
        self.stickerEmoji = stickerEmoji
        self.chromaKeyColor = chromaKeyColor
        self.chromaKeyThreshold = min(max(chromaKeyThreshold, 0), 1)
        self.mask = mask
        self.clipEffects = []
        self.canvasBackground = canvasBackground
    }

    init(
        timeRange: CMTimeRange,
        trackIDs: [CMPersistentTrackID],
        clipEffects: [CustomCompositionClipEffect],
        canvasBackground: CanvasBackground? = nil
    ) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = trackIDs.map { NSNumber(value: $0) }
        self.colorCorrection = nil
        self.colorGrade = nil
        self.textContent = nil
        self.stickerEmoji = nil
        self.chromaKeyColor = nil
        self.mask = nil
        self.clipEffects = clipEffects
        self.canvasBackground = canvasBackground
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
    private let ciContext = CIContext(options: RenderColorConfiguration.contextOptions)
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
                let colorGrade = effect?.colorGrade ?? instruction.colorGrade
                let chromaKeyColor = effect?.chromaKeyColor ?? instruction.chromaKeyColor
                let chromaKeyThreshold = effect?.chromaKeyThreshold ?? instruction.chromaKeyThreshold
                let mask = effect?.mask ?? instruction.mask
                let animationState = effect?.animationState(at: request.compositionTime)
                let clipEffects = effect?.effects ?? []
                let isBackgroundRemoved = effect?.isBackgroundRemoved ?? false

                // Apply CIFilter-based effects via the shared core processor (matches Mac).
                if !clipEffects.isEmpty {
                    image = VisualEffectPixelProcessor.apply(clipEffects, to: image)
                }

                // Apply background removal
                if isBackgroundRemoved {
                    image = self.applyPersonSegmentation(to: image, request: request)
                }

                if let colorCorrection {
                    image = self.apply(colorCorrection: colorCorrection, to: image)
                }

                if let colorGrade {
                    image = ColorGradePixelProcessor.apply(colorGrade, to: image)
                }

                if let chromaKeyColor {
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
                    image = self.apply(
                        animationState: animationState,
                        to: image,
                        renderSize: request.renderContext.size
                    )
                }

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
            
            guard let outputBuffer = request.renderContext.newPixelBuffer() else {
                request.finish(with: NSError(domain: "MovieCut", code: -2, userInfo: nil))
                return
            }
            
            self.ciContext.render(image, to: outputBuffer)
            request.finish(withComposedVideoFrame: outputBuffer)
        }
    }
    
    func cancelAllPendingVideoCompositionRequests() {}

    // MARK: - Text & Sticker Rendering

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
            fontSize: stickerEffect.stickerFontSize ?? 88,
            in: context,
            renderSize: renderSize
        )
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
        PersonSegmentationCompositor.maskContainsForeground(maskImage, extent: extent, in: ciContext)
    }

    private func applyBackgroundRemoval(to image: CIImage) -> CIImage {
        PersonSegmentationCompositor.applyBackgroundRemoval(to: image)
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
        // Delegate to the shared Core processor so iOS export matches Mac and the
        // warmth/tint stage is applied consistently. Previously this applied only
        // brightness/contrast/saturation here while warmth/tint diverged (with the
        // opposite sign) in the preview path.
        ColorCorrectionPixelProcessor.apply(colorCorrection, to: image)
    }

    private func apply(
        animationState: CustomCompositionAnimationState,
        to image: CIImage,
        renderSize: CGSize
    ) -> CIImage {
        ClipAnimationCompositor.apply(animationState: animationState, to: image, renderSize: renderSize)
    }
}

#endif
