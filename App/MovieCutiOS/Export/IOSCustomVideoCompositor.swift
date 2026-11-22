#if os(iOS)

import AVFoundation
import CoreImage
import MovieCutCore
import os
import Vision

struct CustomCompositionTransitionEffect: Sendable {
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
    /// G-03: adjustment clips active during this instruction (bottom-first).
    var adjustmentClips: [Clip]? = nil
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    let colorCorrection: ColorCorrection?
    let colorGrade: ColorGrade?
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
    /// LF-ACTION-02 (Mac parity): true only for alpha-capable mastering
    /// (ProRes 4444). iOS delivery is MP4/H.264 — always false here so the
    /// nil-background canvas composites over opaque black and recycled
    /// codec buffers cannot leak the previous scene (LF-ACTION-01).
    let preservesCanvasAlpha: Bool
    let prefersFastSegmentation: Bool

    init(
        timeRange: CMTimeRange,
        trackIDs: [CMPersistentTrackID],
        colorCorrection: ColorCorrection? = nil,
        colorGrade: ColorGrade? = nil,
        textContent: TextClipContent? = nil,
        stickerEmoji: String? = nil,
        stickerImageURL: URL? = nil,
        chromaKey: ChromaKeySettings? = nil,
        chromaKeyColor: SIMD3<Float>? = nil,
        chromaKeyThreshold: Float = 0.3,
        mask: Mask? = nil,
        transitionEffects: [CustomCompositionTransitionEffect] = [],
        canvasBackground: CanvasBackground? = nil,
        preservesCanvasAlpha: Bool = false,
        prefersFastSegmentation: Bool = false
    ) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = Self.requiredTrackIDValues(
            trackIDs: trackIDs,
            transitionEffects: transitionEffects
        )
        self.colorCorrection = colorCorrection
        self.colorGrade = colorGrade
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
        self.preservesCanvasAlpha = preservesCanvasAlpha
        self.prefersFastSegmentation = prefersFastSegmentation
    }

    init(
        timeRange: CMTimeRange,
        trackIDs: [CMPersistentTrackID],
        clipEffects: [CustomCompositionClipEffect],
        transitionEffects: [CustomCompositionTransitionEffect] = [],
        canvasBackground: CanvasBackground? = nil,
        preservesCanvasAlpha: Bool = false,
        prefersFastSegmentation: Bool = false,
        adjustmentClips: [Clip]? = nil
    ) {
        self.adjustmentClips = adjustmentClips
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = Self.requiredTrackIDValues(
            trackIDs: trackIDs,
            transitionEffects: transitionEffects
        )
        self.colorCorrection = nil
        self.colorGrade = nil
        self.textContent = nil
        self.stickerEmoji = nil
        self.stickerImageURL = nil
        self.chromaKey = nil
        self.chromaKeyColor = nil
        self.mask = nil
        self.clipEffects = clipEffects
        self.transitionEffects = transitionEffects
        self.canvasBackground = canvasBackground
        self.preservesCanvasAlpha = preservesCanvasAlpha
        self.prefersFastSegmentation = prefersFastSegmentation
    }

    func effect(for trackID: CMPersistentTrackID, at time: CMTime) -> CustomCompositionClipEffect? {
        clipEffects.first { $0.applies(to: trackID, at: time) }
    }

    func activeTransition(at time: CMTime) -> CustomCompositionTransitionEffect? {
        transitionEffects.first { $0.applies(at: time) }
    }

    func activeSourceTrackIDs(at time: CMTime) -> [CMPersistentTrackID] {
        clipEffects.reversed().compactMap { effect in
            guard effect.trackID != kCMPersistentTrackID_Invalid,
                  CMTimeRangeContainsTime(effect.timeRange, time: time)
            else {
                return nil
            }

            return effect.trackID
        }
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
    /// Fast-scrub cancellation (Mac parity): bumped by
    /// cancelAllPendingVideoCompositionRequests so queued-but-not-started
    /// requests die at the head of the render queue instead of rendering
    /// stale frames to completion.
    private let cancellationGeneration = OSAllocatedUnfairLock<UInt64>(initialState: 0)
    private let stickerRenderer = SharedStickerOverlayRenderer()
    private let ciContext = CIContext(options: RenderColorConfiguration.contextOptions)
    private let personSegmentationHandler = VNSequenceRequestHandler()
    private var renderContext: AVVideoCompositionRenderContext?
    
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContext = newRenderContext
    }
    
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        // Boxed for the @Sendable render-queue closure: the request is not
        // Sendable on the macOS 15 / iOS 18-era SDKs, so capturing it directly
        // fails strict concurrency on Xcode 16. Each request is finished
        // exactly once inside this closure.
        let sendableRequest = RequestBox(request: request)
        let generation = cancellationGeneration.withLock { $0 }
        renderQueue.async {
            let request = sendableRequest.request
            if self.cancellationGeneration.withLock({ $0 != generation }) {
                request.finishCancelledRequest()
                return
            }

            // Two-source transition branch: if an active transition applies,
            // render outgoing and incoming frames and compose via TransitionPixelProcessor.
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
                    to: Self.fittedToCanvas(
                        Self.orientedForDisplay(
                            RenderColorConfiguration.sourceImage(from: outgoingBuffer),
                            preferredTransform: outgoingEffect?.sourcePreferredTransform ?? .identity
                        ),
                        canvasSize: request.renderContext.size
                    ),
                    effect: outgoingEffect,
                    instruction: instruction,
                    request: request
                )
                let incomingImage = self.applyClipEffects(
                    to: Self.fittedToCanvas(
                        Self.orientedForDisplay(
                            RenderColorConfiguration.sourceImage(from: incomingBuffer),
                            preferredTransform: incomingEffect?.sourcePreferredTransform ?? .identity
                        ),
                        canvasSize: request.renderContext.size
                    ),
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
                    renderSize: request.renderContext.size,
                    fillPolicy: instruction.preservesCanvasAlpha ? .alphaPreserving : .opaqueDelivery
                )
                self.finishRequest(request, with: transitionedImage)
                return
            }

            let instruction = request.videoCompositionInstruction as? CustomCompositionInstruction
            guard let (trackID, sourceBuffer) = self.firstSourceFrame(in: request, instruction: instruction) else {
                request.finish(with: NSError(domain: "MovieCut", code: -1, userInfo: nil))
                return
            }
            
            // RENDER-01 / BUG-06 parity with the Mac compositor: aspect-fit
            // + center every source into the render canvas BEFORE effects —
            // a mismatched aspect previously rendered 1:1 at the corner.
            // BUG-IOS-08: orient the storage frame upright FIRST (Mac BUG-07
            // parity) — the custom compositor receives raw decode buffers,
            // so the composition track's preferredTransform never reaches it.
            var image: CIImage
            if let instruction {
                let effect = instruction.effect(for: trackID, at: request.compositionTime)
                image = Self.fittedToCanvas(
                    Self.orientedForDisplay(
                        RenderColorConfiguration.sourceImage(from: sourceBuffer),
                        preferredTransform: effect?.sourcePreferredTransform ?? .identity
                    ),
                    canvasSize: request.renderContext.size
                )
                image = self.applyClipEffects(
                    to: image,
                    effect: effect,
                    instruction: instruction,
                    request: request
                )

                // Multi-track layering and blend mode composition (matches Mac)
                image = self.layerActiveTracks(
                    over: image,
                    primaryEffect: effect,
                    primaryTrackID: trackID,
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
                    renderSize: request.renderContext.size,
                    fillPolicy: instruction.preservesCanvasAlpha ? .alphaPreserving : .opaqueDelivery
                )
            } else {
                image = Self.fittedToCanvas(
                    RenderColorConfiguration.sourceImage(from: sourceBuffer),
                    canvasSize: request.renderContext.size
                )
                // No instruction → no project background to honor; the
                // opaque default decides every canvas pixel (LF-ACTION-01,
                // Mac parity).
                image = CanvasBackgroundPixelProcessor.compose(
                    frame: image,
                    over: nil,
                    renderSize: request.renderContext.size
                )
            }

            self.finishRequest(request, with: image)
        }
    }
    
    func cancelAllPendingVideoCompositionRequests() {
        cancellationGeneration.withLock { $0 &+= 1 }
    }

    private func applyClipEffects(
        to image: CIImage,
        effect: CustomCompositionClipEffect?,
        instruction: CustomCompositionInstruction,
        request: AVAsynchronousVideoCompositionRequest
    ) -> CIImage {
        var image = image
        // G-24 (#9): the stabilization warp runs FIRST — the camera-path
        // correction must see the raw decoded frame before crop/color/
        // transform touch it. Same contract as the Mac compositor: dy
        // negates (analysis rows are top-down, Core Image's y is up) and
        // the cover zoom is constant per plan so it never breathes.
        if let effect,
           let plan = effect.stabilization,
           !plan.isEmpty,
           let correction = plan.correction(
               atLocalTime: CMTimeSubtract(request.compositionTime, effect.timeRange.start).seconds
           ) {
            let extent = image.extent
            let maxTranslation = plan.maxNormalizedTranslation
            let (warped, _) = StabilizationWarpProcessor.apply(
                image,
                correction: (
                    dx: correction.dx * Double(extent.width),
                    dy: -correction.dy * Double(extent.height),
                    cropFraction: correction.cropFraction
                ),
                confidence: correction.confidence,
                coverScale: 1 + 2 * max(maxTranslation.x, maxTranslation.y)
            )
            image = warped
        }
        // Crop runs first so every downstream processor (visual effects,
        // color, chroma key, mask, transform) sees the cropped region — the
        // order a user perceives in the inspector (G-23). Shared processor,
        // so preview and export crop identically.
        if let cropRect = effect?.cropRect {
            image = CropPixelProcessor.apply(
                cropRect,
                to: image,
                renderSize: request.renderContext.size
            )
        }
        let colorCorrection = effect?.colorCorrection ?? instruction.colorCorrection
        let colorGrade = effect?.colorGrade ?? instruction.colorGrade
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
            image = self.applyPersonSegmentation(
                to: image,
                request: request,
                prefersFast: instruction.prefersFastSegmentation
            )
        }

        if let colorCorrection {
            image = ColorCorrectionPixelProcessor.apply(colorCorrection, to: image)
        }

        if let colorGrade {
            image = ColorGradePixelProcessor.apply(colorGrade, to: image)
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
            image = self.apply(
                animationState: animationState,
                to: image,
                renderSize: request.renderContext.size
            )
        }

        // G-03: the adjustment chain applies AFTER the clip's own chain.
        if let adjustments = instruction.adjustmentClips, !adjustments.isEmpty {
            image = AdjustmentLayerChain.applyAdjustments(adjustments, to: image)
        }

        return image
    }

    private func layerActiveTracks(
        over primaryImage: CIImage,
        primaryEffect: CustomCompositionClipEffect?,
        primaryTrackID: CMPersistentTrackID,
        instruction: CustomCompositionInstruction,
        request: AVAsynchronousVideoCompositionRequest
    ) -> CIImage {
        let activeEffects = instruction.clipEffects.filter { effect in
            effect.trackID != kCMPersistentTrackID_Invalid
                && effect.trackID != primaryTrackID
                && CMTimeRangeContainsTime(effect.timeRange, time: request.compositionTime)
        }

        // BUG-08: `.normal`-only projects must still composite their lower
        // tracks. The old pixel-identity gate returned the primary as-is
        // unless some clip carried a non-normal blend mode, so an overlay
        // using plain opacity/mask/crop dropped the track beneath it and
        // showed the canvas background instead. Layering now engages
        // whenever another track is active; single-active-track frames keep
        // the byte-identical passthrough via the empty-collection guard.
        guard !activeEffects.isEmpty else {
            return primaryImage
        }

        let primaryBlendMode = primaryEffect?.blendMode ?? .normal

        var backdrop = CIImage.empty()
        for effect in activeEffects {
            guard let sourceBuffer = request.sourceFrame(byTrackID: effect.trackID) else {
                continue
            }

            var layerImage = Self.fittedToCanvas(
                Self.orientedForDisplay(
                    RenderColorConfiguration.sourceImage(from: sourceBuffer),
                    preferredTransform: effect.sourcePreferredTransform
                ),
                canvasSize: request.renderContext.size
            )
            layerImage = applyClipEffects(
                to: layerImage,
                effect: effect,
                instruction: instruction,
                request: request
            )

            if effect.blendMode == .normal {
                backdrop = layerImage.composited(over: backdrop)
            } else {
                backdrop = BlendPixelProcessor.apply(layerImage, over: backdrop, mode: effect.blendMode)
            }
        }

        if primaryBlendMode == .normal {
            return primaryImage.composited(over: backdrop)
        } else {
            return BlendPixelProcessor.apply(primaryImage, over: backdrop, mode: primaryBlendMode)
        }
    }

    /// BUG-IOS-08 (Mac BUG-07 parity): delegates to shared Core orientation geometry.
    static func orientedForDisplay(
        _ image: CIImage,
        preferredTransform: CGAffineTransform
    ) -> CIImage {
        SharedCanvasGeometry.orientedForDisplay(image, preferredTransform: preferredTransform)
    }

    /// Aspect-fits and centers a source frame into the render canvas (Mac parity).
    static func fittedToCanvas(_ image: CIImage, canvasSize: CGSize) -> CIImage {
        SharedCanvasGeometry.fittedToCanvas(image, canvasSize: canvasSize)
    }

    private func finishRequest(_ request: AVAsynchronousVideoCompositionRequest, with image: CIImage) {
        guard let outputBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "MovieCut", code: -2, userInfo: nil))
            return
        }

        // HDR masters get a 10-bit destination surface from the writer; render
        // through the Rec.2020 HLG color space so the transfer function is
        // applied for real instead of re-tagging 8-bit pixels (capcut-surpass
        // ac589c2 idea, re-cut for this compositor). SDR keeps the original
        // 2-arg render byte-for-byte.
        if CVPixelBufferGetPixelFormatType(outputBuffer) == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
           let hdrColorSpace = CGColorSpace(name: CGColorSpace.itur_2100_HLG) {
            ciContext.render(
                image,
                to: outputBuffer,
                bounds: CGRect(origin: .zero, size: image.extent.size),
                colorSpace: hdrColorSpace
            )
        } else {
            ciContext.render(image, to: outputBuffer)
        }
        request.finish(withComposedVideoFrame: outputBuffer)
    }

    // MARK: - Text & Sticker Rendering

    private func renderTextOverlay(
        instruction: CustomCompositionInstruction,
        onto image: CIImage,
        at time: CMTime
    ) -> CIImage {
        let items = SharedTextOverlayResolver.renderItems(
            clipEffects: instruction.clipEffects,
            instructionTextContent: instruction.textContent,
            instructionTimeRange: instruction.timeRange,
            at: time,
            renderSize: image.extent.size
        )
        guard !items.isEmpty else {
            return image
        }

        return TextOverlayPixelProcessor.apply(items, to: image, at: time.seconds)
    }

    private func renderStickerOverlay(
        for clipEffect: CustomCompositionClipEffect?,
        instruction: CustomCompositionInstruction,
        onto image: CIImage,
        at time: CMTime
    ) -> CIImage {
        _ = clipEffect
        return stickerRenderer.renderOverlay(
            clipEffects: instruction.clipEffects,
            instructionEmoji: instruction.stickerEmoji,
            instructionImageURL: instruction.stickerImageURL,
            instructionTimeRange: instruction.timeRange,
            onto: image,
            at: time
        )
    }

    // MARK: - Background Removal

    private func applyPersonSegmentation(
        to image: CIImage,
        request: AVAsynchronousVideoCompositionRequest,
        prefersFast: Bool = false
    ) -> CIImage {
        _ = request
        return SharedPersonSegmentationHelper.apply(
            to: image,
            prefersFast: prefersFast,
            handler: personSegmentationHandler,
            ciContext: ciContext
        )
    }

    // MARK: - Source Frame Helpers

    private func firstSourceFrame(
        in request: AVAsynchronousVideoCompositionRequest,
        instruction: CustomCompositionInstruction?
    ) -> (CMPersistentTrackID, CVPixelBuffer)? {
        let preferredTrackIDs = instruction?.activeSourceTrackIDs(at: request.compositionTime) ?? []
        for trackID in preferredTrackIDs {
            if let sourceBuffer = request.sourceFrame(byTrackID: trackID) {
                return (trackID, sourceBuffer)
            }
        }

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
        ClipAnimationCompositor.apply(animationState: animationState, to: image, renderSize: renderSize)
    }
}

#endif

private struct RequestBox: @unchecked Sendable {
    let request: AVAsynchronousVideoCompositionRequest
}
