import CoreGraphics
import Foundation

/// A built-in subtitle style preset (G-01 Inc 3): a fixed combination of
/// border / background / font / size / relative position / karaoke
/// active-word color that can be applied to a subtitle clip in one click.
///
/// Style fields ride on `UserTextStylePreset` (the same capture/apply contract
/// as user-saved styles, F-12R); the two fields that model does not carry —
/// the karaoke highlight color and a relative canvas position — live here.
/// Applying a preset never flips `karaokeEnabled` itself: that is the
/// AutoSubtitles toggle's decision (G-01 Inc 2). Fixed UUIDs keep the picker
/// selection stable across launches.
public struct SubtitleStylePreset: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let style: UserTextStylePreset
    /// Karaoke active-word color. nil keeps the clip's existing highlight.
    public let highlightFontColor: String?
    /// Position as a fraction of the canvas (0…1, top-left origin, matching
    /// `TextClipContent.position`). nil keeps the clip's existing position.
    public let relativePosition: CGPoint?

    public init(
        id: UUID,
        name: String,
        style: UserTextStylePreset,
        highlightFontColor: String? = nil,
        relativePosition: CGPoint? = nil
    ) {
        self.id = id
        self.name = name
        self.style = style
        self.highlightFontColor = highlightFontColor
        self.relativePosition = relativePosition
    }

    /// Applies the preset to a subtitle clip's content. Text, word timings,
    /// the karaoke flag, and animation stay with the clip.
    public func applying(to content: TextClipContent, canvasSize: CGSize) -> TextClipContent {
        var updated = style.applying(to: content)
        if let highlightFontColor {
            updated.highlightFontColor = highlightFontColor
        }
        if let relativePosition {
            updated.position = CGPoint(
                x: relativePosition.x * canvasSize.width,
                y: relativePosition.y * canvasSize.height
            )
        }
        return updated
    }
}

/// The fixed built-in subtitle style presets (2026-08-17). Six distinct
/// feature combinations, one click each: every renderer-visible axis the
/// preset system owns (font color, stroke, background, weight, size,
/// position, karaoke highlight) is exercised by at least one preset.
public enum SubtitleStylePresets {
    public static let builtins: [SubtitleStylePreset] = [
        SubtitleStylePreset(
            id: UUID(uuidString: "D5A3B7E1-0001-4A61-9C2A-000000000000")!,
            name: "Clean White",
            style: UserTextStylePreset(
                id: UUID(),
                name: "Clean White",
                capturing: TextClipContent(
                    text: "",
                    fontFamily: "Helvetica Neue",
                    fontSize: 34,
                    fontColor: "#FFFFFF",
                    alignment: .center,
                    strokeColor: "#000000",
                    strokeWidth: 2
                )
            ),
            highlightFontColor: "#FFD60A",
            relativePosition: CGPoint(x: 0.5, y: 0.86)
        ),
        SubtitleStylePreset(
            id: UUID(uuidString: "D5A3B7E1-0002-4A61-9C2A-000000000000")!,
            name: "Bold Box",
            style: UserTextStylePreset(
                id: UUID(),
                name: "Bold Box",
                capturing: TextClipContent(
                    text: "",
                    fontFamily: "Helvetica Neue",
                    fontSize: 30,
                    fontColor: "#FFFFFF",
                    alignment: .center,
                    backgroundColor: "#000000",
                    isBold: true
                )
            ),
            highlightFontColor: "#FFD60A",
            relativePosition: CGPoint(x: 0.5, y: 0.86)
        ),
        SubtitleStylePreset(
            id: UUID(uuidString: "D5A3B7E1-0003-4A61-9C2A-000000000000")!,
            name: "Yellow Pop",
            style: UserTextStylePreset(
                id: UUID(),
                name: "Yellow Pop",
                capturing: TextClipContent(
                    text: "",
                    fontFamily: "Helvetica Neue",
                    fontSize: 36,
                    fontColor: "#FFD60A",
                    alignment: .center,
                    strokeColor: "#1C1C1E",
                    strokeWidth: 3,
                    isBold: true
                )
            ),
            highlightFontColor: "#FFFFFF",
            relativePosition: CGPoint(x: 0.5, y: 0.86)
        ),
        SubtitleStylePreset(
            id: UUID(uuidString: "D5A3B7E1-0004-4A61-9C2A-000000000000")!,
            name: "Shadow Soft",
            style: UserTextStylePreset(
                id: UUID(),
                name: "Shadow Soft",
                capturing: TextClipContent(
                    text: "",
                    fontFamily: "Helvetica Neue",
                    fontSize: 32,
                    fontColor: "#FFFFFF",
                    alignment: .center,
                    shadowColor: "#000000",
                    shadowOffset: CGPoint(x: 2, y: 2),
                    shadowBlur: 6
                )
            ),
            relativePosition: CGPoint(x: 0.5, y: 0.86)
        ),
        SubtitleStylePreset(
            id: UUID(uuidString: "D5A3B7E1-0005-4A61-9C2A-000000000000")!,
            name: "Mint Outline",
            style: UserTextStylePreset(
                id: UUID(),
                name: "Mint Outline",
                capturing: TextClipContent(
                    text: "",
                    fontFamily: "Helvetica Neue",
                    fontSize: 34,
                    fontColor: "#66D4CF",
                    alignment: .center,
                    strokeColor: "#0B3B39",
                    strokeWidth: 2
                )
            ),
            highlightFontColor: "#FFFFFF",
            relativePosition: CGPoint(x: 0.5, y: 0.86)
        ),
        SubtitleStylePreset(
            id: UUID(uuidString: "D5A3B7E1-0006-4A61-9C2A-000000000000")!,
            name: "Classic Serif",
            style: UserTextStylePreset(
                id: UUID(),
                name: "Classic Serif",
                capturing: TextClipContent(
                    text: "",
                    fontFamily: "Georgia",
                    fontSize: 32,
                    fontColor: "#FFF4E0",
                    alignment: .center,
                    strokeColor: "#3B2A1A",
                    strokeWidth: 1.5,
                    isItalic: false
                )
            ),
            highlightFontColor: "#FF9F0A",
            relativePosition: CGPoint(x: 0.5, y: 0.86)
        )
    ]
}
