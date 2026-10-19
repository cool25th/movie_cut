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
    /// Precomputed at init: keyframes grouped per property and time-sorted.
    /// The per-frame animation query previously ran filter+sorted SIX times
    /// per frame (12 heap arrays + 6 O(K log K) sorts); these fields make
    /// `animationState(at:)` allocation-free.
    private let hasVisualAnimationFlag: Bool
    private let hasTransformKeyframesFlag: Bool
    private let sortedKeyframesByProperty: [AnimatableProperty: [Keyframe]]

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
        // Computed once: the guard below and the per-frame
        // `animationState(at:)` flag share this result.
        let hasVisual = Self.hasVisualAnimation(transform: transform, opacity: clampedOpacity, keyframes: keyframes)
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
            || hasVisual
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

        // Group + time-sort each property's keyframes once, at construction.
        var grouped: [AnimatableProperty: [Keyframe]] = [:]
        var hasTransform = false
        if !keyframes.isEmpty {
            for keyframe in keyframes {
                grouped[keyframe.property, default: []].append(keyframe)
                if Self.transformKeyframeProperties.contains(keyframe.property) {
                    hasTransform = true
                }
            }
            for property in grouped.keys {
                grouped[property]?.sort { $0.time < $1.time }
            }
        }
        self.hasVisualAnimationFlag = hasVisual
        self.hasTransformKeyframesFlag = hasTransform
        self.sortedKeyframesByProperty = grouped
    }

    public var hasStickerOverlay: Bool {
        stickerEmoji != nil || stickerImageURL != nil
    }

    public func applies(to trackID: CMPersistentTrackID, at time: CMTime) -> Bool {
        self.trackID == trackID && CMTimeRangeContainsTime(timeRange, time: time)
    }

    public func animationState(at time: CMTime) -> CustomCompositionAnimationState? {
        guard hasVisualAnimationFlag else {
            return nil
        }

        let rawLocalTime = CMTimeSubtract(time, timeRange.start).seconds
        let localTime = rawLocalTime.isFinite ? max(0, rawLocalTime) : 0
        return CustomCompositionAnimationState(
            transform: Self.keyframedTransform(
                base: transform,
                hasTransformKeyframes: hasTransformKeyframesFlag,
                sortedByProperty: sortedKeyframesByProperty,
                at: localTime
            ),
            opacity: Self.keyframedValue(
                for: .opacity,
                defaultValue: opacity,
                sortedByProperty: sortedKeyframesByProperty,
                at: localTime
            )
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
        hasTransformKeyframes: Bool,
        sortedByProperty: [AnimatableProperty: [Keyframe]],
        at localTime: TimeInterval
    ) -> ClipTransform {
        guard hasTransformKeyframes else {
            return transform
        }

        var resolvedTransform = transform
        resolvedTransform.position.x = CGFloat(keyframedValue(
            for: .positionX,
            defaultValue: Double(transform.position.x),
            sortedByProperty: sortedByProperty,
            at: localTime
        ))
        resolvedTransform.position.y = CGFloat(keyframedValue(
            for: .positionY,
            defaultValue: Double(transform.position.y),
            sortedByProperty: sortedByProperty,
            at: localTime
        ))
        resolvedTransform.scale.width = CGFloat(keyframedValue(
            for: .scaleX,
            defaultValue: Double(transform.scale.width),
            sortedByProperty: sortedByProperty,
            at: localTime
        ))
        resolvedTransform.scale.height = CGFloat(keyframedValue(
            for: .scaleY,
            defaultValue: Double(transform.scale.height),
            sortedByProperty: sortedByProperty,
            at: localTime
        ))
        resolvedTransform.rotation = keyframedValue(
            for: .rotation,
            defaultValue: transform.rotation,
            sortedByProperty: sortedByProperty,
            at: localTime
        )
        return resolvedTransform
    }

    /// Interpolation over the pre-sorted per-property keyframes. Same math
    /// as the previous filter+sorted implementation; the segment lookup is
    /// a binary search instead of a linear scan.
    private static func keyframedValue(
        for property: AnimatableProperty,
        defaultValue: Double,
        sortedByProperty: [AnimatableProperty: [Keyframe]],
        at localTime: TimeInterval
    ) -> Double {
        guard let propertyKeyframes = sortedByProperty[property],
              let firstKeyframe = propertyKeyframes.first else {
            return defaultValue
        }

        guard localTime >= firstKeyframe.time else {
            return defaultValue
        }

        guard let lastKeyframe = propertyKeyframes.last, localTime < lastKeyframe.time else {
            return propertyKeyframes.last?.value ?? defaultValue
        }

        // Binary search for the first segment whose end keyframe time is at
        // or after localTime.
        var low = 0
        var high = propertyKeyframes.count - 2
        while low < high {
            let mid = (low + high) / 2
            if propertyKeyframes[mid + 1].time < localTime {
                low = mid + 1
            } else {
                high = mid
            }
        }

        for index in low..<(propertyKeyframes.count - 1) {
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
                mode: startKeyframe.interpolation,
                customCurve: startKeyframe.customCurve
            )
        }

        return firstKeyframe.value
    }
}
