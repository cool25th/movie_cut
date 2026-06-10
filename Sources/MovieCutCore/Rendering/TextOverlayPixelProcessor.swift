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

    public init(
        textContent: TextClipContent = TextClipContent(text: ""),
        transform: ClipTransform = ClipTransform(),
        opacity: Double = 1,
        timeRangeStart: TimeInterval = 0,
        timeRangeDuration: TimeInterval = .greatestFiniteMagnitude
    ) {
        self.textContent = textContent
        self.transform = transform
        self.opacity = opacity
        self.timeRangeStart = timeRangeStart
        self.timeRangeDuration = timeRangeDuration
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
        at time: TimeInterval
    ) -> CIImage {
        apply(
            [
                TextOverlayRenderItem(
                    textContent: textContent,
                    transform: transform,
                    opacity: opacity,
                    timeRangeStart: timeRangeStart,
                    timeRangeDuration: timeRangeDuration
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
        let textState = animatedTextState(for: textContent, timeRangeStart: item.timeRangeStart, at: time)
        guard !textState.text.isEmpty else { return }

        let effectiveOpacity = min(max(item.opacity * textState.alpha, 0), 1)
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
        context.rotate(by: CGFloat(item.transform.rotation * .pi / 180))
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

    private static func animatedTextState(
        for textContent: TextClipContent,
        timeRangeStart: TimeInterval,
        at time: TimeInterval
    ) -> (text: String, alpha: Double, translation: CGPoint, scale: CGFloat) {
        guard let animation = textContent.animation else {
            return (textContent.text, 1, CGPoint(x: 0, y: 0), 1)
        }

        let rawLocalTime = time - timeRangeStart
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

    private static func attributedText(
        _ text: String,
        font: CTFont,
        color: CGColor,
        alignment: TextAlignment
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

            return NSAttributedString(
                string: text,
                attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
                    NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle
                ]
            )
        }
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
