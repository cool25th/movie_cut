import CoreGraphics
import CoreImage
import CoreMedia
import CoreText
import Foundation
import ImageIO
import Vision

/// Platform-neutral canvas display orientation & aspect-fit geometry shared by
/// both Mac (`CustomVideoCompositor`) and iOS (`IOSCustomVideoCompositor`).
public enum SharedCanvasGeometry {
    /// Aspect-fits and centers a source frame into the render canvas (BUG-06 / CA-04).
    public static func fittedToCanvas(_ image: CIImage, canvasSize: CGSize) -> CIImage {
        let extent = image.extent
        guard !extent.isEmpty,
              extent.width > 0, extent.height > 0,
              canvasSize.width > 0, canvasSize.height > 0 else { return image }
        let scale = min(
            canvasSize.width / extent.width,
            canvasSize.height / extent.height
        )
        let scaledWidth = extent.width * scale
        let scaledHeight = extent.height * scale
        let dx = (canvasSize.width - scaledWidth) / 2 - extent.minX * scale
        let dy = (canvasSize.height - scaledHeight) / 2 - extent.minY * scale
        return image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: dx, y: dy))
            .cropped(to: CGRect(origin: .zero, size: canvasSize))
    }

    /// Orients a storage-oriented source frame upright using the track's cardinal
    /// rotation metadata (BUG-07). Non-cardinal transforms pass through untouched.
    public static func orientedForDisplay(
        _ image: CIImage,
        preferredTransform: CGAffineTransform
    ) -> CIImage {
        guard preferredTransform != .identity else { return image }
        let angle = atan2(preferredTransform.b, preferredTransform.a)
        let orientation: CGImagePropertyOrientation
        if abs(angle - .pi / 2) < 0.01 {
            orientation = .right
        } else if abs(angle + .pi / 2) < 0.01 {
            orientation = .left
        } else if abs(abs(angle) - .pi) < 0.01 {
            orientation = .down
        } else {
            return image
        }
        return image.oriented(orientation)
    }
}

/// Shared text-overlay & text-animation resolver ensuring identical Mac/iOS
/// text animation rendering (typewriter, fade, pop, slide, scale, rotation).
public enum SharedTextOverlayResolver {
    public static func renderItems(
        clipEffects: [CustomCompositionClipEffect],
        instructionTextContent: TextClipContent?,
        instructionTimeRange: CMTimeRange,
        at time: CMTime,
        renderSize: CGSize
    ) -> [TextOverlayRenderItem] {
        var items = clipEffects.compactMap { effect -> TextOverlayRenderItem? in
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

        if let textContent = instructionTextContent,
           CMTimeRangeContainsTime(instructionTimeRange, time: time) {
            let textAnimationState = resolvedTextAnimationState(
                for: textContent,
                timeRange: instructionTimeRange,
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
                timeRangeStart: instructionTimeRange.start.seconds,
                timeRangeDuration: instructionTimeRange.duration.seconds,
                clipProgress: nil
            ))
        }

        return items
    }

    public static func resolvedTextAnimationState(
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
}

/// Shared GPU-composited sticker renderer with bounded `NSCache` for decoded
/// sticker images and tight-bounds rasterized emoji/fallback `CIImage`s.
/// Eliminates per-frame full-canvas CPU `CGContext` allocation on both Mac and iOS.
public final class SharedStickerOverlayRenderer: @unchecked Sendable {
    private let stickerImageCache: NSCache<NSURL, CGImage>
    private let stickerRasterCache: NSCache<NSString, CIImage>
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    public init(countLimit: Int = 64) {
        let imageCache = NSCache<NSURL, CGImage>()
        imageCache.countLimit = countLimit
        self.stickerImageCache = imageCache

        let rasterCache = NSCache<NSString, CIImage>()
        rasterCache.countLimit = countLimit
        self.stickerRasterCache = rasterCache
    }

    public func renderOverlay(
        clipEffects: [CustomCompositionClipEffect],
        instructionEmoji: String?,
        instructionImageURL: URL?,
        instructionTimeRange: CMTimeRange,
        onto image: CIImage,
        at time: CMTime
    ) -> CIImage {
        let activeStickerEffects = clipEffects.filter { effect in
            effect.hasStickerOverlay && CMTimeRangeContainsTime(effect.timeRange, time: time)
        }
        let hasInstructionSticker = (instructionEmoji != nil || instructionImageURL != nil)
            && CMTimeRangeContainsTime(instructionTimeRange, time: time)

        guard !activeStickerEffects.isEmpty || hasInstructionSticker else {
            return image
        }

        let renderBounds = image.extent
        let renderSize = renderBounds.size
        guard renderSize.width > 0, renderSize.height > 0 else {
            return image
        }

        var output = image
        for stickerEffect in activeStickerEffects {
            output = compositeStickerEffect(
                stickerEffect,
                onto: output,
                renderBounds: renderBounds,
                at: time
            )
        }

        if let instructionEmoji,
           let sticker = cachedStickerEmojiImage(instructionEmoji, fontSize: 88) {
            output = compositeCenteredSticker(
                sticker,
                transform: ClipTransform(),
                opacity: 1,
                onto: output,
                renderBounds: renderBounds
            )
        }

        if let instructionImageURL,
           let sticker = stickerImageCIImage(from: instructionImageURL, fontSize: 88, renderSize: renderSize) {
            output = compositeCenteredSticker(
                sticker,
                transform: ClipTransform(),
                opacity: 1,
                onto: output,
                renderBounds: renderBounds
            )
        }

        return output
    }

    public func cachedStickerEmojiImage(
        _ stickerEmoji: String,
        fontSize: CGFloat = 88
    ) -> CIImage? {
        let emoji = stickerEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !emoji.isEmpty else { return nil }

        let safeFontSize = max(fontSize, 1)
        let cacheKey = "emoji:\(emoji):\(Int(safeFontSize.rounded()))" as NSString
        if let cached = stickerRasterCache.object(forKey: cacheKey) {
            return cached
        }

        let font = CTFontCreateWithName("Apple Color Emoji" as CFString, safeFontSize, nil)
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
            safeFontSize
        )
        let glyphHeight = max(ascent + descent, safeFontSize)
        let pad = ceil(safeFontSize * 0.25)
        let width = max(Int(ceil(lineWidth + pad * 2)), 1)
        let height = max(Int(ceil(glyphHeight + pad * 2)), 1)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: Self.colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.translateBy(x: CGFloat(width) * 0.5, y: CGFloat(height) * 0.5)
        context.textMatrix = .identity
        context.textPosition = CGPoint(
            x: -lineWidth * 0.5,
            y: (descent - ascent) * 0.5
        )
        CTLineDraw(line, context)

        guard let cgImage = context.makeImage() else { return nil }
        let centered = CIImage(cgImage: cgImage).transformed(
            by: CGAffineTransform(translationX: -CGFloat(width) * 0.5, y: -CGFloat(height) * 0.5)
        )
        stickerRasterCache.setObject(centered, forKey: cacheKey)
        return centered
    }

    public func cachedStickerFallbackTextImage(
        _ text: String,
        fontSize: CGFloat,
        renderSize: CGSize
    ) -> CIImage? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        let label = String(trimmedText.prefix(12)).uppercased()
        let baseFontSize = max(fontSize * 0.54, 24)
        let cacheKey = "fallback:\(label):\(Int(baseFontSize.rounded())):\(Int(renderSize.width.rounded()))x\(Int(renderSize.height.rounded()))" as NSString
        if let cached = stickerRasterCache.object(forKey: cacheKey) {
            return cached
        }

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
        let strokeWidth = max(baseFontSize * 0.08, 3)
        let margin = ceil(strokeWidth) + 2
        let width = max(Int(ceil(boxSize.width + margin * 2)), 1)
        let height = max(Int(ceil(boxSize.height + margin * 2)), 1)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: Self.colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.translateBy(x: CGFloat(width) * 0.5, y: CGFloat(height) * 0.5)
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
        context.setLineWidth(strokeWidth)
        context.addPath(boxPath)
        context.strokePath()

        context.textMatrix = .identity
        context.textPosition = CGPoint(
            x: -lineWidth * 0.5,
            y: -((ascent + descent) * 0.5) + descent
        )
        CTLineDraw(line, context)

        guard let cgImage = context.makeImage() else { return nil }
        let centered = CIImage(cgImage: cgImage).transformed(
            by: CGAffineTransform(translationX: -CGFloat(width) * 0.5, y: -CGFloat(height) * 0.5)
        )
        stickerRasterCache.setObject(centered, forKey: cacheKey)
        return centered
    }

    private func compositeStickerEffect(
        _ stickerEffect: CustomCompositionClipEffect,
        onto image: CIImage,
        renderBounds: CGRect,
        at time: CMTime
    ) -> CIImage {
        let animationState = stickerEffect.animationState(at: time)
        let transform = animationState?.transform ?? stickerEffect.transform
        let opacity = animationState?.opacity ?? stickerEffect.opacity
        let fontSize = stickerEffect.stickerFontSize ?? 88
        let renderSize = renderBounds.size

        if let stickerImageURL = stickerEffect.stickerImageURL {
            if let sticker = stickerImageCIImage(from: stickerImageURL, fontSize: fontSize, renderSize: renderSize) {
                return compositeCenteredSticker(
                    sticker,
                    transform: transform,
                    opacity: opacity,
                    onto: image,
                    renderBounds: renderBounds
                )
            }
            if let fallbackText = stickerEffect.stickerFallbackText ?? stickerEffect.stickerEmoji,
               let fallback = cachedStickerFallbackTextImage(fallbackText, fontSize: fontSize, renderSize: renderSize) {
                return compositeCenteredSticker(
                    fallback,
                    transform: transform,
                    opacity: opacity,
                    onto: image,
                    renderBounds: renderBounds
                )
            }
            return image
        }

        if let stickerEmoji = stickerEffect.stickerEmoji,
           let sticker = cachedStickerEmojiImage(stickerEmoji, fontSize: fontSize) {
            return compositeCenteredSticker(
                sticker,
                transform: transform,
                opacity: opacity,
                onto: image,
                renderBounds: renderBounds
            )
        }

        return image
    }

    private func compositeCenteredSticker(
        _ centeredSticker: CIImage,
        transform: ClipTransform,
        opacity: Double,
        onto image: CIImage,
        renderBounds: CGRect
    ) -> CIImage {
        let effectiveOpacity = min(max(opacity, 0), 1)
        guard effectiveOpacity > 0 else { return image }

        let renderSize = renderBounds.size
        let basePosition = stickerPosition(transform: transform, renderSize: renderSize)
        let center = CGPoint(
            x: renderBounds.origin.x + basePosition.x + transform.offset.x,
            y: renderBounds.origin.y + renderSize.height - basePosition.y - transform.offset.y
        )

        var affine = CGAffineTransform(translationX: center.x, y: center.y)
        affine = affine.rotated(by: CGFloat(transform.rotation * .pi / 180))
        affine = affine.scaledBy(x: transform.scale.width, y: transform.scale.height)

        var overlay = centeredSticker.transformed(by: affine)
        if effectiveOpacity < 0.9999,
           let alphaFilter = CIFilter(name: "CIColorMatrix") {
            alphaFilter.setValue(overlay, forKey: kCIInputImageKey)
            alphaFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
            alphaFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
            alphaFilter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
            alphaFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(effectiveOpacity)), forKey: "inputAVector")
            alphaFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
            if let faded = alphaFilter.outputImage {
                overlay = faded
            }
        }

        return overlay
            .composited(over: image)
            .cropped(to: renderBounds)
    }

    private func stickerImageCIImage(
        from imageURL: URL,
        fontSize: CGFloat,
        renderSize: CGSize
    ) -> CIImage? {
        guard let cgImage = loadStickerImage(from: imageURL) else {
            return nil
        }
        let sourceWidth = CGFloat(cgImage.width)
        let sourceHeight = CGFloat(cgImage.height)
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        let displaySize = stickerDisplaySize(
            sourceSize: CGSize(width: sourceWidth, height: sourceHeight),
            fontSize: fontSize,
            renderSize: renderSize
        )
        let scaleX = displaySize.width / sourceWidth
        let scaleY = displaySize.height / sourceHeight
        let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            .translatedBy(x: -sourceWidth * 0.5, y: -sourceHeight * 0.5)
        return CIImage(cgImage: cgImage).transformed(by: transform)
    }

    private func loadStickerImage(from url: URL) -> CGImage? {
        let nsURL = url as NSURL
        if let cached = stickerImageCache.object(forKey: nsURL) {
            return cached
        }
        guard FileManager.default.fileExists(atPath: url.path),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(
                  source,
                  0,
                  [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ) else {
            return nil
        }
        stickerImageCache.setObject(cgImage, forKey: nsURL)
        return cgImage
    }

    private func stickerDisplaySize(sourceSize: CGSize, fontSize: CGFloat, renderSize: CGSize) -> CGSize {
        let aspectRatio = (sourceSize.width > 0 && sourceSize.height > 0)
            ? (sourceSize.width / sourceSize.height)
            : 1
        let shorterRenderEdge = max(min(renderSize.width, renderSize.height), 1)
        let width = min(max(fontSize * 2.8, 96), shorterRenderEdge * 0.45)
        let height = max(width / max(aspectRatio, 0.01), 1)
        return CGSize(width: width, height: height)
    }

    private func stickerPosition(
        transform: ClipTransform,
        renderSize: CGSize
    ) -> CGPoint {
        if abs(transform.position.x) > 1.0e-9 || abs(transform.position.y) > 1.0e-9 {
            return transform.position
        }
        return CGPoint(x: renderSize.width * 0.5, y: renderSize.height * 0.5)
    }
}

/// Shared zero-copy Vision person-segmentation runner for Mac and iOS compositors.
public enum SharedPersonSegmentationHelper {
    public static func apply(
        to image: CIImage,
        prefersFast: Bool,
        handler: VNSequenceRequestHandler,
        ciContext: CIContext
    ) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }

        let normalizedInput: CIImage
        if extent.origin == .zero {
            normalizedInput = image
        } else {
            normalizedInput = image.transformed(
                by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
            )
        }

        let segmentationRequest = VNGeneratePersonSegmentationRequest()
        segmentationRequest.qualityLevel = prefersFast ? .fast : .accurate
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8

        do {
            try handler.perform([segmentationRequest], on: normalizedInput)
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
        guard PersonSegmentationCompositor.maskContainsForeground(alignedMask, extent: extent, in: ciContext) else {
            return image
        }

        return PersonSegmentationCompositor.removeBackground(from: image, mask: alignedMask)
    }
}
