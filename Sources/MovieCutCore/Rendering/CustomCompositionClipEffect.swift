import AVFoundation
import CoreGraphics
import Foundation

/// Describes per-clip effects, transforms, and overlays applied during video composition.
///
/// Shared by the Mac and iOS video compositors. The Mac superset carries fields
/// the iOS compositor doesn't populate (chromaKey, stickerFallbackText,
/// stickerImageURL, blendMode); iOS simply leaves those nil/.normal.
public struct CustomCompositionClipEffect: Sendable {
    public let trackID: CMPersistentTrackID
    public let timeRange: CMTimeRange
    public let transform: ClipTransform
    public let opacity: Double
    public let keyframes: [Keyframe]
    public let colorCorrection: ColorCorrection?
    public let colorGrade: ColorGrade?
    public let chromaKey: ChromaKeySettings?
    public let chromaKeyColor: SIMD3<Float>?
    public let chromaKeyThreshold: Float
    public let mask: Mask?
    public let effects: [Effect]
    public let textContent: TextClipContent?
    public let stickerEmoji: String?
    public let stickerFallbackText: String?
    public let stickerImageURL: URL?
    public let stickerFontSize: CGFloat?
    public let isBackgroundRemoved: Bool
    public let blendMode: BlendMode
    public let cropRect: NormalizedRect?
    /// G-24 stabilization plan — non-nil forces the custom compositor and
    /// warps each frame before the rest of the clip chain (the camera-path
    /// correction must see the raw decoded frame).
    public let stabilization: StabilizationPlan?
    /// BUG-07: the source track's rotation metadata. Composition source
    /// frames arrive in storage orientation, so the compositor orients them
    /// with this transform before the canvas fit. Identity for unrotated
    /// sources; does not by itself trigger the custom compositor.
    public let sourcePreferredTransform: CGAffineTransform

    public init?(
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
        cropRect: NormalizedRect? = nil,
        stabilization: StabilizationPlan? = nil,
        sourcePreferredTransform: CGAffineTransform = .identity,
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
            || cropRect != nil
            || stabilization != nil
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
        self.cropRect = cropRect
        self.stabilization = stabilization
        self.sourcePreferredTransform = sourcePreferredTransform
    }

    public var hasStickerOverlay: Bool {
        stickerEmoji != nil || stickerImageURL != nil
    }

    public func applies(to trackID: CMPersistentTrackID, at time: CMTime) -> Bool {
        self.trackID == trackID && CMTimeRangeContainsTime(timeRange, time: time)
    }

    public func animationState(at time: CMTime) -> CustomCompositionAnimationState? {
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
