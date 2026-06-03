import CoreGraphics
import CoreImage
import CoreText
import Foundation
import MovieCutCore
import QuartzCore

final class TextAnimationRenderer {
    static func applyCoreAnimation(
        _ textAnimation: TextAnimation,
        to textLayer: CATextLayer,
        canvasSize: CGSize,
        fontSize: CGFloat,
        text: String
    ) {
        let duration = max(textAnimation.duration, 0)
        guard duration > 0 else { return }

        let delay = max(textAnimation.delay, 0)
        let targetPositionY = textLayer.position.y
        let targetOpacity = textLayer.opacity

        switch textAnimation.type {
        case .fadeIn:
            let fadeAnimation = CABasicAnimation(keyPath: "opacity")
            fadeAnimation.fromValue = 0
            fadeAnimation.toValue = targetOpacity
            configure(fadeAnimation, duration: duration, delay: delay)
            textLayer.add(fadeAnimation, forKey: "fadeIn")
        case .fadeOut:
            let fadeAnimation = CABasicAnimation(keyPath: "opacity")
            fadeAnimation.fromValue = targetOpacity
            fadeAnimation.toValue = 0
            configure(fadeAnimation, duration: duration, delay: delay)
            textLayer.add(fadeAnimation, forKey: "fadeOut")
        case .slideUp:
            let slideAnimation = CABasicAnimation(keyPath: "position.y")
            slideAnimation.fromValue = canvasSize.height + fontSize
            slideAnimation.toValue = targetPositionY
            configure(slideAnimation, duration: duration, delay: delay)
            textLayer.add(slideAnimation, forKey: "slideUp")
        case .slideDown:
            let slideAnimation = CABasicAnimation(keyPath: "position.y")
            slideAnimation.fromValue = -fontSize
            slideAnimation.toValue = targetPositionY
            configure(slideAnimation, duration: duration, delay: delay)
            textLayer.add(slideAnimation, forKey: "slideDown")
        case .scale:
            let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
            scaleAnimation.fromValue = 0
            scaleAnimation.toValue = 1
            configure(scaleAnimation, duration: duration, delay: delay)
            textLayer.add(scaleAnimation, forKey: "scale")
        case .bounce:
            let bounceAnimation = CAKeyframeAnimation(keyPath: "position.y")
            bounceAnimation.values = [
                NSNumber(value: Double(targetPositionY)),
                NSNumber(value: Double(targetPositionY + 20)),
                NSNumber(value: Double(targetPositionY - 8)),
                NSNumber(value: Double(targetPositionY + 3)),
                NSNumber(value: Double(targetPositionY))
            ]
            bounceAnimation.keyTimes = [0, 0.35, 0.6, 0.8, 1].map(NSNumber.init(value:))
            configure(bounceAnimation, duration: duration, delay: delay)
            textLayer.add(bounceAnimation, forKey: "bounce")
        case .typewriter:
            guard !text.isEmpty else { return }

            let characters = Array(text)
            let typewriterAnimation = CAKeyframeAnimation(keyPath: "string")
            typewriterAnimation.values = (0...characters.count).map { characterCount in
                String(characters.prefix(characterCount))
            }
            typewriterAnimation.keyTimes = (0...characters.count).map { characterCount in
                NSNumber(value: Double(characterCount) / Double(characters.count))
            }
            typewriterAnimation.calculationMode = .discrete
            configure(typewriterAnimation, duration: duration, delay: delay)
            textLayer.add(typewriterAnimation, forKey: "typewriter")
        }
    }

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

    private static func configure(
        _ animation: CAAnimation,
        duration: TimeInterval,
        delay: TimeInterval
    ) {
        animation.duration = duration
        animation.beginTime = delay
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
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
