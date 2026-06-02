import Foundation

/// Common editing canvas aspect ratios.
public enum AspectRatio: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    /// Landscape 16:9 canvas.
    case landscape16x9

    /// Portrait 9:16 canvas.
    case portrait9x16

    /// Portrait 4:5 canvas.
    case portrait4x5

    /// Square 1:1 canvas.
    case square1x1

    /// Wide 21:9 cinema canvas.
    case wide21x9

    /// Ultrawide 21:9 canvas.
    case ultrawide21x9

    /// User-defined canvas dimensions.
    case custom

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case Self.landscape16x9.rawValue, "ratio16x9":
            self = .landscape16x9
        case Self.portrait9x16.rawValue, "ratio9x16":
            self = .portrait9x16
        case Self.portrait4x5.rawValue, "ratio4x5":
            self = .portrait4x5
        case Self.square1x1.rawValue, "ratio1x1":
            self = .square1x1
        case Self.wide21x9.rawValue:
            self = .wide21x9
        case Self.ultrawide21x9.rawValue:
            self = .ultrawide21x9
        case Self.custom.rawValue:
            self = .custom
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown aspect ratio: \(rawValue)"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// The preset's default pixel size.
    public var size: CGSize {
        switch self {
        case .landscape16x9:
            return CGSize(width: 1920, height: 1080)
        case .portrait9x16:
            return CGSize(width: 1080, height: 1920)
        case .portrait4x5:
            return CGSize(width: 1080, height: 1350)
        case .square1x1:
            return CGSize(width: 1080, height: 1080)
        case .wide21x9:
            return CGSize(width: 2560, height: 1080)
        case .ultrawide21x9:
            return CGSize(width: 2520, height: 1080)
        case .custom:
            return .zero
        }
    }

    /// User-visible preset name.
    public var displayName: String {
        switch self {
        case .landscape16x9:
            return "16:9 Landscape"
        case .portrait9x16:
            return "9:16 Portrait"
        case .portrait4x5:
            return "4:5 Portrait"
        case .square1x1:
            return "1:1 Square"
        case .wide21x9:
            return "21:9 Wide"
        case .ultrawide21x9:
            return "21:9 Ultrawide"
        case .custom:
            return "Custom"
        }
    }
}

/// Canvas and playback-rate defaults for the editable project.
public struct CanvasPreset: Codable, Sendable, Equatable {
    /// The selected aspect-ratio preset.
    public var aspectRatio: AspectRatio

    /// Custom canvas width in pixels when `aspectRatio` is `.custom`.
    public var customWidth: Int?

    /// Custom canvas height in pixels when `aspectRatio` is `.custom`.
    public var customHeight: Int?

    /// Editing and export frame-rate preset.
    public var frameRate: ExportFrameRate

    /// Creates a canvas preset.
    public init(
        aspectRatio: AspectRatio,
        customWidth: Int? = nil,
        customHeight: Int? = nil,
        frameRate: ExportFrameRate = .fps30
    ) {
        self.aspectRatio = aspectRatio
        self.customWidth = customWidth
        self.customHeight = customHeight
        self.frameRate = frameRate
    }

    /// Returns a standard 1080p landscape canvas.
    public static func defaultPreset() -> CanvasPreset {
        CanvasPreset(aspectRatio: .landscape16x9, frameRate: .fps30)
    }

    /// The effective output size for this canvas.
    public var size: CGSize {
        if aspectRatio == .custom {
            return CGSize(
                width: Double(max(1, customWidth ?? Int(AspectRatio.landscape16x9.size.width))),
                height: Double(max(1, customHeight ?? Int(AspectRatio.landscape16x9.size.height)))
            )
        }

        return aspectRatio.size
    }
}
