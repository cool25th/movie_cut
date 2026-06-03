import CoreGraphics
import CoreImage
import CoreText
import Foundation
import MovieCutCore

final class TextAnimationRenderer {
    static func render(
        text: String,
        font: CGFont,
        fontSize: CGFloat,
        color: CGColor,
        animation: TextAnimation,
        progress: Double,
        into context: CIContext,
        size: CGSize
    ) -> CIImage? {
        _ = context

        let progress = min(max(progress, 0), 1)
        let visibleText = renderedText(text, animation: animation, progress: progress)
        guard !visibleText.isEmpty, size.width > 0, size.height > 0 else { return nil }

        let alpha = alphaValue(for: animation, progress: progress)
        guard alpha > 0 else { return nil }

        let bounds = CGRect(origin: CGPoint(x: 0, y: 0), size: size)
        guard let textImage = drawText(
            visibleText,
            font: font,
            fontSize: fontSize,
            color: color,
            alpha: CGFloat(alpha),
            size: size
        ) else {
            return nil
        }

        let transformed = applyTransform(
            to: textImage,
            animation: animation,
            progress: progress,
            size: size
        )
        let clear = CIImage(color: CIColor.clear).cropped(to: bounds)
        return transformed.composited(over: clear).cropped(to: bounds)
    }

    private static func renderedText(_ text: String, animation: TextAnimation, progress: Double) -> String {
        switch animation.type {
        case .typewriter:
            let characterCount = Int(floor(progress * Double(text.count)))
            return String(text.prefix(characterCount))
        case .fadeIn, .fadeOut, .bounce, .slideUp, .slideDown, .scale:
            return text
        }
    }

    private static func alphaValue(for animation: TextAnimation, progress: Double) -> Double {
        switch animation.type {
        case .fadeIn:
            return progress
        case .fadeOut:
            return 1 - progress
        case .typewriter, .bounce, .slideUp, .slideDown, .scale:
            return 1
        }
    }

    private static func applyTransform(
        to image: CIImage,
        animation: TextAnimation,
        progress: Double,
        size: CGSize
    ) -> CIImage {
        switch animation.type {
        case .bounce:
            let offset = sin(progress * .pi * 3) * 20 * (1 - progress)
            return image.transformed(by: CGAffineTransform(translationX: 0, y: offset))
        case .slideUp:
            let offset = (1 - progress) * size.height * 0.5
            return image.transformed(by: CGAffineTransform(translationX: 0, y: offset))
        case .slideDown:
            let offset = -(1 - progress) * size.height * 0.5
            return image.transformed(by: CGAffineTransform(translationX: 0, y: offset))
        case .scale:
            let scale = 0.5 + progress * 0.5
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -center.x, y: -center.y)
            return image.transformed(by: transform)
        case .fadeIn, .fadeOut, .typewriter:
            return image
        }
    }

    private static func drawText(
        _ text: String,
        font: CGFont,
        fontSize: CGFloat,
        color: CGColor,
        alpha: CGFloat,
        size: CGSize
    ) -> CIImage? {
        let width = max(Int(ceil(size.width)), 1)
        let height = max(Int(ceil(size.height)), 1)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setAlpha(alpha)

        let ctFont = CTFontCreateWithGraphicsFont(font, fontSize, nil, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedString)
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

        let lineHeight = ascent + descent + leading
        let x = max((size.width - textWidth) * 0.5, 0)
        let y = max((size.height - lineHeight) * 0.5 + descent, 0)
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)

        guard let cgImage = context.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }
}
