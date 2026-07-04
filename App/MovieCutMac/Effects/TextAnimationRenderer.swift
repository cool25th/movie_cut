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
        text: String,
        beginTime: CFTimeInterval? = nil
    ) {
        _ = fontSize
        applyLayerAnimation(
            textAnimation,
            to: textLayer,
            text: text,
            canvasSize: canvasSize,
            beginTime: beginTime
        )
    }

    static func applyLayerAnimation(
        _ textAnimation: TextAnimation,
        to layer: CALayer,
        text: String? = nil,
        canvasSize: CGSize,
        beginTime: CFTimeInterval? = nil
    ) {
        guard textAnimation.preset != .none else { return }

        let clipDuration = resolvedClipDuration(for: layer, animation: textAnimation)
        guard clipDuration > 0 else { return }

        let samples = animationSamples(
            animation: textAnimation,
            text: text ?? "",
            clipDuration: clipDuration,
            canvasSize: canvasSize
        )
        guard !samples.isEmpty else { return }

        addOpacityAnimation(to: layer, samples: samples, duration: clipDuration, beginTime: beginTime)
        addPositionAnimation(to: layer, samples: samples, duration: clipDuration, beginTime: beginTime)
        addTransformAnimation(to: layer, samples: samples, duration: clipDuration, beginTime: beginTime)

        if let textLayer = layer as? CATextLayer, let text {
            addStringAnimation(to: textLayer, text: text, samples: samples, duration: clipDuration, beginTime: beginTime)
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
        let clipDuration = max(animation.duration + animation.delay, animation.duration, 1.0e-6)
        let state = animation.renderState(
            for: text,
            clipProgress: progress,
            clipDuration: clipDuration,
            canvasSize: size
        )
        guard !state.visibleText.isEmpty, size.width > 0, size.height > 0 else { return nil }
        guard state.opacity > 0 else { return nil }

        let bounds = CGRect(origin: CGPoint(x: 0, y: 0), size: size)
        guard let textImage = drawText(
            state.visibleText,
            font: font,
            fontSize: fontSize,
            color: color,
            alpha: CGFloat(state.opacity),
            size: size
        ) else {
            return nil
        }

        let transformed = applyTransform(to: textImage, state: state, size: size)
        let clear = CIImage(color: CIColor.clear).cropped(to: bounds)
        return transformed.composited(over: clear).cropped(to: bounds)
    }

    private static func animationSamples(
        animation: TextAnimation,
        text: String,
        clipDuration: TimeInterval,
        canvasSize: CGSize
    ) -> [(keyTime: NSNumber, state: TextAnimationRenderState)] {
        let sampleCount = max(8, min(72, Int(ceil(clipDuration * 30))))
        return (0...sampleCount).map { index in
            let progress = Double(index) / Double(sampleCount)
            return (
                keyTime: NSNumber(value: progress),
                state: animation.renderState(
                    for: text,
                    clipProgress: progress,
                    clipDuration: clipDuration,
                    canvasSize: canvasSize
                )
            )
        }
    }

    private static func addOpacityAnimation(
        to layer: CALayer,
        samples: [(keyTime: NSNumber, state: TextAnimationRenderState)],
        duration: TimeInterval,
        beginTime: CFTimeInterval?
    ) {
        let targetOpacity = Double(layer.opacity)
        let values = samples.map { targetOpacity * $0.state.opacity }
        guard valuesVary(values) else { return }

        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = values.map(NSNumber.init(value:))
        configure(animation, keyTimes: samples.map { $0.keyTime }, duration: duration, beginTime: beginTime)
        layer.add(animation, forKey: "textPresetOpacity")
    }

    private static func addPositionAnimation(
        to layer: CALayer,
        samples: [(keyTime: NSNumber, state: TextAnimationRenderState)],
        duration: TimeInterval,
        beginTime: CFTimeInterval?
    ) {
        let basePosition = layer.position
        let xValues = samples.map { Double(basePosition.x + $0.state.translation.x) }
        let yValues = samples.map { Double(basePosition.y + $0.state.translation.y) }

        if valuesVary(xValues) {
            let animation = CAKeyframeAnimation(keyPath: "position.x")
            animation.values = xValues.map(NSNumber.init(value:))
            configure(animation, keyTimes: samples.map { $0.keyTime }, duration: duration, beginTime: beginTime)
            layer.add(animation, forKey: "textPresetPositionX")
        }

        if valuesVary(yValues) {
            let animation = CAKeyframeAnimation(keyPath: "position.y")
            animation.values = yValues.map(NSNumber.init(value:))
            configure(animation, keyTimes: samples.map { $0.keyTime }, duration: duration, beginTime: beginTime)
            layer.add(animation, forKey: "textPresetPositionY")
        }
    }

    private static func addTransformAnimation(
        to layer: CALayer,
        samples: [(keyTime: NSNumber, state: TextAnimationRenderState)],
        duration: TimeInterval,
        beginTime: CFTimeInterval?
    ) {
        let transformChanges = samples.contains { sample in
            abs(Double(sample.state.scale) - 1) > 1.0e-6
                || abs(sample.state.rotationDegrees) > 1.0e-6
        }
        guard transformChanges else { return }

        let baseTransform = layer.affineTransform()
        let values = samples.map { sample in
            let state = sample.state
            let animatedTransform = baseTransform
                .rotated(by: CGFloat(state.rotationDegrees * .pi / 180))
                .scaledBy(x: state.scale, y: state.scale)
            return NSValue(caTransform3D: CATransform3DMakeAffineTransform(animatedTransform))
        }

        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = values
        configure(animation, keyTimes: samples.map { $0.keyTime }, duration: duration, beginTime: beginTime)
        layer.add(animation, forKey: "textPresetTransform")
    }

    private static func addStringAnimation(
        to textLayer: CATextLayer,
        text: String,
        samples: [(keyTime: NSNumber, state: TextAnimationRenderState)],
        duration: TimeInterval,
        beginTime: CFTimeInterval?
    ) {
        let values = samples.map { $0.state.visibleText }
        guard values.contains(where: { $0 != text }) else { return }

        let animation = CAKeyframeAnimation(keyPath: "string")
        animation.values = values
        animation.calculationMode = .discrete
        configure(animation, keyTimes: samples.map { $0.keyTime }, duration: duration, beginTime: beginTime)
        textLayer.add(animation, forKey: "textPresetString")
    }

    private static func configure(
        _ animation: CAKeyframeAnimation,
        keyTimes: [NSNumber],
        duration: TimeInterval,
        beginTime: CFTimeInterval?
    ) {
        animation.duration = max(duration, 1.0e-6)
        animation.beginTime = beginTime ?? 0
        animation.keyTimes = keyTimes
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
    }

    private static func resolvedClipDuration(for layer: CALayer, animation: TextAnimation) -> TimeInterval {
        if layer.duration.isFinite, layer.duration > 0 {
            return layer.duration
        }

        return max(animation.duration + animation.delay, animation.duration, 1.0e-6)
    }

    private static func valuesVary(_ values: [Double]) -> Bool {
        guard let first = values.first else { return false }
        return values.contains { abs($0 - first) > 1.0e-6 }
    }

    private static func applyTransform(
        to image: CIImage,
        state: TextAnimationRenderState,
        size: CGSize
    ) -> CIImage {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let centeredTransform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: CGFloat(state.rotationDegrees * .pi / 180))
            .scaledBy(x: state.scale, y: state.scale)
            .translatedBy(x: -center.x, y: -center.y)
        return image
            .transformed(by: centeredTransform)
            .transformed(by: CGAffineTransform(translationX: state.translation.x, y: state.translation.y))
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
