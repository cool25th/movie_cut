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
    let colorGrade: ColorGrade?
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
    let blendMode: BlendMode

    init?(
        trackID: CMPersistentTrackID,
        timeRange: CMTimeRange,
        transform: ClipTransform = ClipTransform(),
        opacity: Double = 1.0,
        keyframes: [Keyframe] = [],
        colorCorrection: ColorCorrection?,
        colorGrade: ColorGrade? = nil,
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
        isBackgroundRemoved: Bool = false,
        blendMode: BlendMode = .normal,
        includeIdentitySource: Bool = false
    ) {
        let clampedOpacity = min(max(opacity, 0), 1)
        guard colorCorrection != nil
            || colorGrade != nil
            || chromaKey != nil
            || chromaKeyColor != nil
            || mask != nil
            || !effects.isEmpty
            || textContent != nil
            || stickerEmoji != nil
            || stickerImageURL != nil
            || isBackgroundRemoved
            || blendMode != .normal
            || Self.hasVisualAnimation(transform: transform, opacity: clampedOpacity, keyframes: keyframes)
            || (includeIdentitySource && trackID != kCMPersistentTrackID_Invalid)
        else {
            return nil
        }

        self.trackID = trackID
        self.timeRange = timeRange
        self.transform = transform
        self.opacity = clampedOpacity
        self.keyframes = keyframes
        self.colorCorrection = colorCorrection
        self.colorGrade = colorGrade
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
        self.blendMode = blendMode
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
        !ClipAnimationCompositor.isIdentityTransform(transform)
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

            let instruction = request.videoCompositionInstruction as? CustomCompositionInstruction
            guard let (trackID, sourceBuffer) = self.firstSourceFrame(in: request, instruction: instruction) else {
                request.finish(with: NSError(domain: "MovieCut", code: -1, userInfo: nil))
                return
            }

            var image = CIImage(cvPixelBuffer: sourceBuffer)

            if let instruction {
                let effect = instruction.effect(for: trackID, at: request.compositionTime)
                image = self.applyClipEffects(
                    to: image,
                    effect: effect,
                    instruction: instruction,
                    request: request
                )

                // Layer any additional active tracks beneath/over the primary
                // frame so a clip with a non-`.normal` blend mode is composited
                // over the frame beneath it (Requirement 4.2 / 4.5). `.normal`
                // clips take plain source-over compositing, byte-identical to
                // the pre-feature layering step (Requirement 4.3).
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
                    renderSize: request.renderContext.size
                )
            }

            self.finishRequest(request, with: image)
        }
    }

    /// Composites the remaining active source tracks over the primary frame.
    ///
    /// The primary track (the top-most active clip, already rendered into
    /// `primaryImage`) is composited last so its blend mode can apply against
    /// the frame beneath it. Each lower track is fetched, has its per-clip
    /// effects applied, and is layered bottom-to-top: `.normal` clips take plain
    /// source-over compositing (no blend filter, so the pre-feature pixels are
    /// unchanged); any other mode routes through `BlendPixelProcessor` so
    /// opacity and blending are both reflected. Finally the primary is laid on
    /// top using its own blend mode.
    ///
    /// **Pixel-identity gate (Requirement 4.3).** This step is skipped entirely
    /// — returning `primaryImage` untouched — unless at least one active clip
    /// (the primary included) carries a non-`.normal` blend mode. A project
    /// that never sets a blend mode therefore renders byte-identically to
    /// before this feature existed, including the pre-existing single-track
    /// custom-compositor behavior. The multi-track layering only engages when
    /// blending is actually requested.
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

        // Pixel-identity gate: if no active clip (primary included) uses a blend
        // mode, the frame is returned as-is so exports are unchanged for
        // `.normal`-only projects (Requirement 4.3).
        let primaryBlendMode = primaryEffect?.blendMode ?? .normal
        let needsBlending = primaryBlendMode != .normal
            || activeEffects.contains { $0.blendMode != .normal }
        guard needsBlending else {
            return primaryImage
        }

        // No other active track beneath the primary: there is nothing to blend
        // against, so the primary frame is returned as-is. The canvas background
        // is composited separately afterwards by CanvasBackgroundPixelProcessor.
        guard !activeEffects.isEmpty else {
            return primaryImage
        }

        // `clipEffects` is ordered bottom-to-top by z-order (matching the
        // layer-instruction construction in the engines). Build the backdrop by
        // compositing lower tracks first; `a.composited(over: b)` draws `a` in
        // front of `b`, so each accumulated result becomes the foreground over
        // the next lower track, preserving z-order.
        var backdrop = CIImage.empty()
        for effect in activeEffects {
            guard let sourceBuffer = request.sourceFrame(byTrackID: effect.trackID) else {
                continue
            }

            var layerImage = CIImage(cvPixelBuffer: sourceBuffer)
            layerImage = applyClipEffects(
                to: layerImage,
                effect: effect,
                instruction: instruction,
                request: request
            )

            // `.normal` MUST bypass the blend processor so the export frame is
            // pixel-identical to the layering step that predates this feature
            // (Requirement 4.3). The processor itself routes `.normal` to plain
            // source-over, but bypassing here avoids any color-space round trip.
            if effect.blendMode == .normal {
                backdrop = layerImage.composited(over: backdrop)
            } else {
                // Routes through the shared Core processor, which applies the
                // Core Image blend filter and crops back to the base extent.
                // Note on the `.add` quirk: `CIAdditionBlendMode` collapses to
                // transparent black on opaque inputs under the *software*
                // renderer (the committed golden in BlendPixelProcessorGoldenTests).
                // This export path uses the default GPU `CIContext`, where `.add`
                // produces the expected clamped-to-white additive result, and
                // the processor's extent crop keeps the frame from collapsing to
                // an empty extent regardless of renderer.
                backdrop = BlendPixelProcessor.apply(layerImage, over: backdrop, mode: effect.blendMode)
            }
        }

        // Lay the primary (top-most) clip over the built backdrop, applying its
        // own blend mode. Bypass the processor for `.normal` to preserve the
        // exact pre-feature compositing pixels for the default case.
        if primaryBlendMode == .normal {
            return primaryImage.composited(over: backdrop)
        } else {
            return BlendPixelProcessor.apply(primaryImage, over: backdrop, mode: primaryBlendMode)
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
            image = applyPersonSegmentation(
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
        let items = textOverlayRenderItems(
            in: instruction,
            at: time,
            renderSize: image.extent.size
        )
        guard !items.isEmpty else {
            return image
        }

        return TextOverlayPixelProcessor.apply(items, to: image, at: time.seconds)
    }

    private func textOverlayRenderItems(
        in instruction: CustomCompositionInstruction,
        at time: CMTime,
        renderSize: CGSize
    ) -> [TextOverlayRenderItem] {
        var items = instruction.clipEffects.compactMap { effect -> TextOverlayRenderItem? in
            guard let textContent = effect.textContent,
                  CMTimeRangeContainsTime(effect.timeRange, time: time)
            else {
                return nil
            }

            let animationState = effect.animationState(at: time)
            let textAnimationState = resolvedTextAnimationState(
                for: textContent,
                timeRange: effect.timeRange,
                at: time,
                renderSize: renderSize
            )
            var resolvedTextContent = textContent
            var resolvedTransform = animationState?.transform ?? effect.transform
            var resolvedOpacity = animationState?.opacity ?? effect.opacity

            if let textAnimationState {
                resolvedTextContent.text = textAnimationState.visibleText
                resolvedTextContent.animation = nil
                resolvedTransform.offset.x += textAnimationState.translation.x
                resolvedTransform.offset.y += textAnimationState.translation.y
                resolvedTransform.scale.width *= textAnimationState.scale
                resolvedTransform.scale.height *= textAnimationState.scale
                resolvedTransform.rotation += textAnimationState.rotationDegrees
                resolvedOpacity *= textAnimationState.opacity
            }

            return TextOverlayRenderItem(
                textContent: resolvedTextContent,
                transform: resolvedTransform,
                opacity: resolvedOpacity,
                timeRangeStart: effect.timeRange.start.seconds,
                timeRangeDuration: effect.timeRange.duration.seconds,
                clipProgress: nil
            )
        }

        if let textContent = instruction.textContent,
           CMTimeRangeContainsTime(instruction.timeRange, time: time) {
            let textAnimationState = resolvedTextAnimationState(
                for: textContent,
                timeRange: instruction.timeRange,
                at: time,
                renderSize: renderSize
            )
            var resolvedTextContent = textContent
            var resolvedTransform = ClipTransform()
            var resolvedOpacity = 1.0
            if let textAnimationState {
                resolvedTextContent.text = textAnimationState.visibleText
                resolvedTextContent.animation = nil
                resolvedTransform.offset = textAnimationState.translation
                resolvedTransform.scale.width *= textAnimationState.scale
                resolvedTransform.scale.height *= textAnimationState.scale
                resolvedTransform.rotation += textAnimationState.rotationDegrees
                resolvedOpacity *= textAnimationState.opacity
            }
            items.append(TextOverlayRenderItem(
                textContent: resolvedTextContent,
                transform: resolvedTransform,
                opacity: resolvedOpacity,
                timeRangeStart: instruction.timeRange.start.seconds,
                timeRangeDuration: instruction.timeRange.duration.seconds,
                clipProgress: nil
            ))
        }

        return items
    }

    private func resolvedTextAnimationState(
        for textContent: TextClipContent,
        timeRange: CMTimeRange,
        at time: CMTime,
        renderSize: CGSize
    ) -> TextAnimationRenderState? {
        guard let animation = textContent.animation else { return nil }

        let duration = timeRange.duration.seconds
        guard duration.isFinite, duration > 0 else { return nil }

        let elapsed = CMTimeSubtract(time, timeRange.start).seconds
        let localTime = elapsed.isFinite ? max(0, elapsed) : 0
        return animation.renderState(
            for: textContent.text,
            localTime: localTime,
            clipDuration: duration,
            canvasSize: renderSize
        )
    }

    private func clipProgress(in timeRange: CMTimeRange, at time: CMTime) -> Double {
        let duration = timeRange.duration.seconds
        guard duration.isFinite, duration > 0 else {
            return 0
        }

        let elapsed = CMTimeSubtract(time, timeRange.start).seconds
        guard elapsed.isFinite else {
            return 0
        }

        return min(max(elapsed / duration, 0), 1)
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
        PersonSegmentationCompositor.maskContainsForeground(maskImage, extent: extent, in: ciContext)
    }

    private func applyBackgroundRemoval(to image: CIImage) -> CIImage {
        PersonSegmentationCompositor.applyBackgroundRemoval(to: image)
    }

    // MARK: - Source Frame Helpers

    private func firstSourceFrame(
        in request: AVAsynchronousVideoCompositionRequest,
        instruction: CustomCompositionInstruction?
    ) -> (CMPersistentTrackID, CVPixelBuffer)? {
        if let instruction {
            for trackID in instruction.activeSourceTrackIDs(at: request.compositionTime) {
                if let sourceBuffer = request.sourceFrame(byTrackID: trackID) {
                    return (trackID, sourceBuffer)
                }
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
