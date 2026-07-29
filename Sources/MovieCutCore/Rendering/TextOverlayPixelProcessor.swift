import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// A text-backed overlay scheduled for pixel rendering.
public struct TextOverlayRenderItem: Sendable, Equatable {
    public var textContent: TextClipContent
    public var transform: ClipTransform
    public var opacity: Double
    public var timeRangeStart: TimeInterval
    public var timeRangeDuration: TimeInterval
    public var clipProgress: Double?

    public init(
        textContent: TextClipContent = TextClipContent(text: ""),
        transform: ClipTransform = ClipTransform(),
        opacity: Double = 1,
        timeRangeStart: TimeInterval = 0,
        timeRangeDuration: TimeInterval = .greatestFiniteMagnitude,
        clipProgress: Double? = nil
    ) {
        self.textContent = textContent
        self.transform = transform
        self.opacity = opacity
        self.timeRangeStart = timeRangeStart
        self.timeRangeDuration = timeRangeDuration
        self.clipProgress = clipProgress
    }
}

/// Renders text/subtitle overlays into Core Image frames for preview and export.
public enum TextOverlayPixelProcessor {
    public static func apply(
        _ items: [TextOverlayRenderItem],
        to image: CIImage,
        at time: TimeInterval
    ) -> CIImage {
        let activeItems = items.filter { isActive($0, at: time) }
        guard !activeItems.isEmpty else { return image }

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

        context.clear(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(true)

        for item in activeItems {
            draw(item, in: context, renderSize: renderSize, at: time)
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

    public static func apply(
        _ textContent: TextClipContent,
        to image: CIImage,
        transform: ClipTransform = ClipTransform(),
        opacity: Double = 1,
        timeRangeStart: TimeInterval = 0,
        timeRangeDuration: TimeInterval = .greatestFiniteMagnitude,
        progress: Double? = nil,
        at time: TimeInterval
    ) -> CIImage {
        apply(
            [
                TextOverlayRenderItem(
                    textContent: textContent,
                    transform: transform,
                    opacity: opacity,
                    timeRangeStart: timeRangeStart,
                    timeRangeDuration: timeRangeDuration,
                    clipProgress: progress
                )
            ],
            to: image,
            at: time
        )
    }

    private static func draw(
        _ item: TextOverlayRenderItem,
        in context: CGContext,
        renderSize: CGSize,
        at time: TimeInterval
    ) {
        let textContent = item.textContent
        let textState = animatedTextState(for: textContent, item: item, renderSize: renderSize, at: time)
        guard !textState.visibleText.isEmpty else { return }

        let effectiveOpacity = min(max(item.opacity * textState.opacity, 0), 1)
        guard effectiveOpacity > 0 else { return }

        let fontSize = max(CGFloat(textContent.fontSize), 1)
        let fontName = textContent.fontFamily == "System" ? "Helvetica Neue" : textContent.fontFamily
        let font = resolvedFont(
            name: fontName,
            size: fontSize,
            bold: textContent.isBold,
            italic: textContent.isItalic
        )
        let textColor = cgColor(hexRGB: textContent.fontColor)
        let localTime = karaokeLocalTime(for: item, at: time)
        let attributedString = karaokeAttributedText(
            for: textContent,
            visibleText: textState.visibleText,
            font: font,
            baseColor: textColor,
            alignment: textContent.alignment,
            localTime: localTime
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

        let basePosition = textPosition(for: textContent, transform: item.transform, renderSize: renderSize)
        let center = CGPoint(
            x: basePosition.x + item.transform.offset.x + textState.translation.x,
            y: renderSize.height - basePosition.y - item.transform.offset.y + textState.translation.y
        )
        let scaleX = item.transform.scale.width * textState.scale
        let scaleY = item.transform.scale.height * textState.scale

        context.saveGState()
        context.setAlpha(CGFloat(effectiveOpacity))
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: CGFloat((item.transform.rotation + textState.rotationDegrees) * .pi / 180))
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

        // Drop shadow applies to the glyph passes only, not the background box.
        if let shadowColor = textContent.shadowColor {
            let offset = textContent.shadowOffset ?? CGPoint(x: 2, y: 2)
            let blur = CGFloat(textContent.shadowBlur ?? 4)
            // The CG context is bottom-left origin; UI-positive y (downward)
            // becomes a negative CG y offset.
            context.setShadow(
                offset: CGSize(width: offset.x, height: -offset.y),
                blur: blur,
                color: cgColor(hexRGB: shadowColor)
            )
        }

        // Outline pass first so the fill sits on top of the stroke.
        if let strokeColor = textContent.strokeColor,
           let strokeWidth = textContent.strokeWidth,
           strokeWidth > 0 {
            // CoreText stroke width is a percentage of the font point size.
            let strokePercent = strokeWidth / Double(fontSize) * 100
            let strokeString = attributedText(
                textState.visibleText,
                font: font,
                color: textColor,
                alignment: textContent.alignment,
                stroke: (color: cgColor(hexRGB: strokeColor), widthPercent: strokePercent)
            )
            let strokeFramesetter = CTFramesetterCreateWithAttributedString(strokeString)
            let strokeFrame = CTFramesetterCreateFrame(
                strokeFramesetter,
                CFRange(location: 0, length: strokeString.length),
                path,
                nil
            )
            CTFrameDraw(strokeFrame, context)
        }

        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributedString.length),
            path,
            nil
        )
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    /// Resolves the font with bold/italic symbolic traits when the face
    /// supports them, falling back to the plain font otherwise.
    private static func resolvedFont(
        name: String,
        size: CGFloat,
        bold: Bool,
        italic: Bool
    ) -> CTFont {
        let base = CTFontCreateWithName(name as CFString, size, nil)
        var traits: CTFontSymbolicTraits = []
        if bold { traits.insert(.boldTrait) }
        if italic { traits.insert(.italicTrait) }
        guard !traits.isEmpty else { return base }

        if let styled = CTFontCreateCopyWithSymbolicTraits(base, size, nil, traits, traits) {
            return styled
        }
        return base
    }

    private static func animatedTextState(
        for textContent: TextClipContent,
        item: TextOverlayRenderItem,
        renderSize: CGSize,
        at time: TimeInterval
    ) -> TextAnimationRenderState {
        guard let animation = textContent.animation else {
            return TextAnimationRenderState(visibleText: textContent.text)
        }

        if let clipProgress = item.clipProgress {
            return animation.renderState(
                for: textContent.text,
                clipProgress: clipProgress,
                clipDuration: item.timeRangeDuration,
                canvasSize: renderSize
            )
        }

        let rawLocalTime = time - item.timeRangeStart
        let localTime = rawLocalTime.isFinite ? max(0, rawLocalTime) : 0
        return animation.renderState(
            for: textContent.text,
            localTime: localTime,
            clipDuration: item.timeRangeDuration,
            canvasSize: renderSize
        )
    }

    private static func attributedText(
        _ text: String,
        font: CTFont,
        color: CGColor,
        alignment: TextAlignment,
        stroke: (color: CGColor, widthPercent: Double)? = nil
    ) -> NSAttributedString {
        var ctAlignment = coreTextAlignment(for: alignment)
        return withUnsafePointer(to: &ctAlignment) { alignmentPointer in
            let paragraphStyle = CTParagraphStyleCreate([
                CTParagraphStyleSetting(
                    spec: .alignment,
                    valueSize: MemoryLayout<CTTextAlignment>.size,
                    value: alignmentPointer
                )
            ], 1)

            var attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle
            ]
            if let stroke {
                // Positive stroke width renders stroke-only glyphs.
                attributes[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] = stroke.color
                attributes[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = stroke.widthPercent
            }

            return NSAttributedString(string: text, attributes: attributes)
        }
    }

    /// Clip-relative time used to pick the active karaoke word.
    private static func karaokeLocalTime(for item: TextOverlayRenderItem, at time: TimeInterval) -> TimeInterval {
        guard time.isFinite, item.timeRangeStart.isFinite else { return 0 }
        let local = time - item.timeRangeStart
        return local.isFinite ? max(0, local) : 0
    }

    /// Returns a per-word colored attributed string when karaoke mode is on and
    /// the clip carries word timings. Falls back to the uniform single-color
    /// string otherwise, preserving prior render behavior exactly.
    ///
    /// Karaoke style: words whose `startTime` has already passed (including the
    /// currently active word) render in the highlight color; words still to come
    /// render in the base color. Matching pairs the visible text's whitespace-
    /// split tokens with `wordTimings` in order; if counts differ the feature is
    /// skipped and the uniform fallback is used.
    private static func karaokeAttributedText(
        for textContent: TextClipContent,
        visibleText: String,
        font: CTFont,
        baseColor: CGColor,
        alignment: TextAlignment,
        localTime: TimeInterval
    ) -> NSAttributedString {
        let wordTimings = textContent.wordTimings ?? []
        guard textContent.karaokeEnabled, !wordTimings.isEmpty else {
            return attributedText(visibleText, font: font, color: baseColor, alignment: alignment)
        }

        // Preserve original whitespace exactly so the highlighted string still
        // matches the layout of the uniform version.
        let tokens = visibleText.unicodeScalars.split(omittingEmptySubsequences: false) { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar)
        }.map { String($0) }

        guard tokens.count == wordTimings.count else {
            return attributedText(visibleText, font: font, color: baseColor, alignment: alignment)
        }

        let highlightColor = cgColor(hexRGB: textContent.highlightFontColor ?? textContent.fontColor)

        var ctAlignment = coreTextAlignment(for: alignment)
        let paragraphStyle = withUnsafePointer(to: &ctAlignment) { alignmentPointer in
            CTParagraphStyleCreate([
                CTParagraphStyleSetting(
                    spec: .alignment,
                    valueSize: MemoryLayout<CTTextAlignment>.size,
                    value: alignmentPointer
                )
            ], 1)
        }

        let result = NSMutableAttributedString()
        for (index, token) in tokens.enumerated() {
            let hasBegun = wordTimings[index].startTime <= localTime
            let color = hasBegun ? highlightColor : baseColor
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle
            ]
            result.append(NSAttributedString(string: token, attributes: attributes))
        }
        return result
    }

    private static func coreTextAlignment(for alignment: TextAlignment) -> CTTextAlignment {
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

    private static func textPosition(
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

    private static func isActive(_ item: TextOverlayRenderItem, at time: TimeInterval) -> Bool {
        guard time.isFinite, item.timeRangeStart.isFinite else {
            return false
        }

        let duration = item.timeRangeDuration
        guard duration > 0 else {
            return false
        }

        guard time >= item.timeRangeStart else {
            return false
        }

        guard duration.isFinite else {
            return true
        }

        return time < item.timeRangeStart + duration
    }

    private static func isZeroPoint(_ point: CGPoint) -> Bool {
        abs(point.x) <= 1.0e-9 && abs(point.y) <= 1.0e-9
    }

    private static func cgColor(hexRGB: String) -> CGColor {
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
}
