import Foundation

/// Text alignment options for generated text clips.
public enum TextAlignment: String, Codable, Sendable, Equatable, Hashable {
    /// Align text to the leading edge.
    case leading

    /// Center text.
    case center

    /// Align text to the trailing edge.
    case trailing

    /// Justify text.
    case justified
}

/// Editable text payload and style values for a text clip.
public struct TextClipContent: Codable, Sendable, Equatable {
    /// The displayed text.
    public var text: String

    /// The font family name.
    public var fontFamily: String

    /// The font size in points.
    public var fontSize: Double

    /// The foreground color as a hex string.
    public var fontColor: String

    /// The text alignment.
    public var alignment: TextAlignment

    /// The optional background color as a hex string.
    public var backgroundColor: String?

    /// The text position on the canvas.
    public var position: CGPoint

    /// Optional animation applied when rendering this text clip.
    public var animation: TextAnimation?

    /// Creates text clip content.
    public init(
        text: String,
        fontFamily: String = "System",
        fontSize: Double = 48,
        fontColor: String = "#FFFFFF",
        alignment: TextAlignment = .center,
        backgroundColor: String? = nil,
        position: CGPoint = .zero,
        animation: TextAnimation? = nil
    ) {
        self.text = text
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontColor = fontColor
        self.alignment = alignment
        self.backgroundColor = backgroundColor
        self.position = position
        self.animation = animation
    }
}
