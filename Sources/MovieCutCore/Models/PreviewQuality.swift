import Foundation
import CoreGraphics

/// User-selectable editing-preview render quality (Requirement 5).
///
/// This is the "Performance Priority" dial CapCut exposes: the editor can lower
/// the preview render resolution to keep scrubbing responsive on heavy media.
/// It governs **preview only** — `ExportEngine` always renders from
/// `project.canvas`, so export output resolution is unaffected by this setting.
///
/// `PlaybackEngine` derives its composition `renderSize` by scaling the project
/// canvas down by `scaleFactor`, fitting the result to even pixel dimensions so
/// AVFoundation accepts it. `.full` (the default) leaves the canvas untouched,
/// which is why a project saved before this setting existed renders identically.
public enum PreviewQuality: String, Codable, Sendable, CaseIterable, Equatable {
    /// Full canvas resolution. The default; preview renders at
    /// `project.canvas`.
    case full
    /// Half resolution (e.g. 960x540 for a 1080p canvas).
    case half
    /// Quarter resolution (e.g. 480x270 for a 1080p canvas).
    case quarter

    /// The value used when a project carries no `previewQuality` key (projects
    /// saved before this setting existed) or an unrecognized raw value.
    public static let `default`: PreviewQuality = .full

    /// Multiplier applied to the project canvas to get the preview render size.
    /// `.full` is `1.0` so the default is a no-op.
    public var scaleFactor: CGFloat {
        switch self {
        case .full: return 1.0
        case .half: return 0.5
        case .quarter: return 0.25
        }
    }

    /// Short label for menus, e.g. "Full", "1/2", "1/4".
    public var shortLabel: String {
        switch self {
        case .full: return "Full"
        case .half: return "1/2"
        case .quarter: return "1/4"
        }
    }
}

/// Pure resolution helper for the preview-quality setting (Requirement 5).
///
/// Extracted so the canvas-scaling math is unit-testable in Core without
/// `AVFoundation`, and so `PlaybackEngine` has a single, reused entry point.
/// `ExportEngine` does **not** call this — it derives its render size from
/// `project.canvas` and `ExportSettings.resolution`, which is why lowering the
/// preview quality never touches the exported file.
public enum PreviewRenderSize {
    /// Scales a canvas size down by `quality.scaleFactor`, fitting both
    /// dimensions to even integers (AVFoundation requires even render sizes)
    /// and clamping the shortest edge to at least 2 px.
    ///
    /// `.full` returns the canvas unchanged (no even-rounding applied), so the
    /// default is a true no-op and existing previews render identically.
    public static func resolve(canvas: CGSize, quality: PreviewQuality) -> CGSize {
        guard quality != .full else { return canvas }
        guard canvas.width > 0, canvas.height > 0 else { return canvas }
        let scale = quality.scaleFactor
        return CGSize(
            width: evenDimension(canvas.width * scale),
            height: evenDimension(canvas.height * scale)
        )
    }

    private static func evenDimension(_ value: CGFloat) -> CGFloat {
        let rounded = max(2, Int(value.rounded()))
        return CGFloat(rounded - (rounded % 2))
    }
}
