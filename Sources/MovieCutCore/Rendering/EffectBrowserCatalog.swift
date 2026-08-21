import Foundation

/// A numeric control exposed by the G-28 effect browser before an effect is
/// committed to a clip.
public struct EffectBrowserParameter: Sendable, Equatable, Identifiable {
    public var id: String { key }

    public let key: String
    public let title: String
    public let range: ClosedRange<Double>
    public let defaultValue: Double
    public let previewValue: Double
    public let valueFormat: String

    public init(
        key: String,
        title: String,
        range: ClosedRange<Double>,
        defaultValue: Double,
        previewValue: Double? = nil,
        valueFormat: String = "%.2f"
    ) {
        self.key = key
        self.title = title
        self.range = range
        self.defaultValue = Self.clamped(defaultValue, to: range)
        self.previewValue = Self.clamped(previewValue ?? defaultValue, to: range)
        self.valueFormat = valueFormat
    }

    public func clamped(_ value: Double) -> Double {
        Self.clamped(value, to: range)
    }

    private static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// One discoverable visual effect and the browser-specific metadata required
/// to search, preview, tune, and apply it correctly.
public struct EffectBrowserCatalogItem: Sendable, Equatable, Identifiable {
    public var id: EffectType { type }

    public let type: EffectType
    public let tags: [String]
    public let parameters: [EffectBrowserParameter]

    public init(
        type: EffectType,
        tags: [String],
        parameters: [EffectBrowserParameter]
    ) {
        self.type = type
        self.tags = tags
        self.parameters = parameters
    }

    public var displayName: String { type.displayName }

    /// Browser previews should be visible immediately. Neutral renderer
    /// defaults remain available through `defaultValue`, while `previewValue`
    /// intentionally starts color adjustments at a small, visible delta.
    public var initialParameters: [String: Double] {
        Dictionary(uniqueKeysWithValues: parameters.map { ($0.key, $0.previewValue) })
    }

    /// Builds a renderer-compatible effect while dropping unknown keys,
    /// filling missing controls from the preview defaults, and clamping values
    /// to the same ranges presented by the UI.
    public func makeEffect(parameters overrides: [String: Double]? = nil) -> Effect {
        let overrides = overrides ?? [:]
        let normalized = Dictionary(uniqueKeysWithValues: parameters.map { definition in
            let proposed = overrides[definition.key] ?? definition.previewValue
            return (definition.key, definition.clamped(proposed))
        })
        return Effect(type: type, parameters: normalized)
    }
}

/// Single source of truth for the built-in effects that can be meaningfully
/// previewed in the G-28 browser.
///
/// Timeline transitions are edited in the dedicated Transition inspector and
/// imported LUTs require a file path, so neither belongs in this preview grid.
public enum EffectBrowserCatalog {
    public static let items: [EffectBrowserCatalogItem] = [
        EffectBrowserCatalogItem(
            type: .brightness,
            tags: ["color", "adjustment", "light"],
            parameters: [
                EffectBrowserParameter(
                    key: "amount",
                    title: "Amount",
                    range: -1 ... 1,
                    defaultValue: 0,
                    previewValue: 0.15
                )
            ]
        ),
        EffectBrowserCatalogItem(
            type: .contrast,
            tags: ["color", "adjustment", "contrast"],
            parameters: [
                EffectBrowserParameter(
                    key: "amount",
                    title: "Amount",
                    range: 0 ... 2,
                    defaultValue: 1,
                    previewValue: 1.2
                )
            ]
        ),
        EffectBrowserCatalogItem(
            type: .saturation,
            tags: ["color", "adjustment", "saturation"],
            parameters: [
                EffectBrowserParameter(
                    key: "amount",
                    title: "Amount",
                    range: 0 ... 2,
                    defaultValue: 1,
                    previewValue: 1.25
                )
            ]
        ),
        EffectBrowserCatalogItem(
            type: .temperature,
            tags: ["color", "adjustment", "warm", "cool"],
            parameters: [
                EffectBrowserParameter(
                    key: "amount",
                    title: "Temperature",
                    range: -1 ... 1,
                    defaultValue: 0,
                    previewValue: 0.2
                )
            ]
        ),
        EffectBrowserCatalogItem(
            type: .exposure,
            tags: ["color", "adjustment", "exposure", "light"],
            parameters: [
                EffectBrowserParameter(
                    key: "ev",
                    title: "Exposure",
                    range: -2 ... 2,
                    defaultValue: 0,
                    previewValue: 0.35
                )
            ]
        ),
        EffectBrowserCatalogItem(
            type: .grayscale,
            tags: ["color", "mono", "black and white"],
            parameters: [
                EffectBrowserParameter(
                    key: "intensity",
                    title: "Intensity",
                    range: 0 ... 1,
                    defaultValue: 1
                )
            ]
        ),
        EffectBrowserCatalogItem(
            type: .sepia,
            tags: ["color", "vintage", "warm"],
            parameters: [
                EffectBrowserParameter(
                    key: "intensity",
                    title: "Intensity",
                    range: 0 ... 1,
                    defaultValue: 0.9
                )
            ]
        ),
        EffectBrowserCatalogItem(
            type: .blur,
            tags: ["focus", "soft", "blur"],
            parameters: [
                EffectBrowserParameter(
                    key: "radius",
                    title: "Radius",
                    range: 1 ... 12,
                    defaultValue: 1,
                    previewValue: 6,
                    valueFormat: "%.0f"
                )
            ]
        ),
        EffectBrowserCatalogItem(
            type: .styleTransfer,
            tags: ["style", "creative", "lut"],
            parameters: [
                EffectBrowserParameter(
                    key: "styleIndex",
                    title: "Style",
                    range: 1 ... 5,
                    defaultValue: 1,
                    valueFormat: "%.0f"
                ),
                EffectBrowserParameter(
                    key: "intensity",
                    title: "Intensity",
                    range: 0 ... 1,
                    defaultValue: 0.75
                )
            ]
        ),
        EffectBrowserCatalogItem(
            type: .cinematicLUT,
            tags: ["lut", "color", "cinematic"],
            parameters: [
                EffectBrowserParameter(
                    key: "intensity",
                    title: "Intensity",
                    range: 0 ... 1,
                    defaultValue: 0.85
                )
            ]
        ),
        EffectBrowserCatalogItem(
            type: .vintageLUT,
            tags: ["lut", "color", "vintage"],
            parameters: [
                EffectBrowserParameter(
                    key: "intensity",
                    title: "Intensity",
                    range: 0 ... 1,
                    defaultValue: 0.8
                )
            ]
        ),
        EffectBrowserCatalogItem(
            type: .noirLUT,
            tags: ["lut", "color", "noir", "mono"],
            parameters: [
                EffectBrowserParameter(
                    key: "intensity",
                    title: "Intensity",
                    range: 0 ... 1,
                    defaultValue: 0.9
                )
            ]
        ),
        EffectBrowserCatalogItem(
            type: .vividLUT,
            tags: ["lut", "color", "vivid"],
            parameters: [
                EffectBrowserParameter(
                    key: "intensity",
                    title: "Intensity",
                    range: 0 ... 1,
                    defaultValue: 0.8
                )
            ]
        ),
        EffectBrowserCatalogItem(
            type: .coolLUT,
            tags: ["lut", "color", "cool"],
            parameters: [
                EffectBrowserParameter(
                    key: "intensity",
                    title: "Intensity",
                    range: 0 ... 1,
                    defaultValue: 0.8
                )
            ]
        )
    ]

    public static func item(for type: EffectType) -> EffectBrowserCatalogItem? {
        items.first { $0.type == type }
    }
}
