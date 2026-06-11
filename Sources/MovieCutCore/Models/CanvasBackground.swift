import Foundation

/// Fills the canvas area that the video frame does not cover, such as the
/// letterbox bands when a 16:9 source sits on a 9:16 canvas.
public enum CanvasBackground: Codable, Sendable, Equatable {
    /// A solid color fill from a 6-digit RGB hex string such as "1A1A1A".
    case color(hex: String)

    /// The source frame scaled to fill the canvas and gaussian-blurred.
    case sourceBlur(radius: Double)

    /// A still image scaled to fill the canvas.
    case image(url: URL)

    /// Display name used by settings UI.
    public var displayName: String {
        switch self {
        case .color: return "Color"
        case .sourceBlur: return "Blur"
        case .image: return "Image"
        }
    }
}
