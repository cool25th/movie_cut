import AppKit
import AVFoundation
import CoreGraphics
import MovieCutCore
import QuartzCore

/// Composition-time helpers shared by the preview and export engines.
///
/// These wrap AppKit/Core Animation types (`NSColor`, `CATextLayerAlignmentMode`),
/// so they live in the App target rather than the AppKit-free Core. Previously
/// each engine carried its own private copy of this logic; consolidating it here
/// keeps the two composition builders in lockstep (the same concern as the
/// shared `ClipTransform.affineTransform` and `RenderColorConfiguration`).
enum CompositionRenderHelpers {
    /// Resolves an `#rrggbb` hex string to an sRGB `CGColor`, falling back to
    /// white on parse failure. Routes through `HexColorMath` so the parse rule
    /// is the single one shared with the rest of the codebase.
    static func cgColor(hexRGB hex: String) -> CGColor {
        guard let rgb = HexColorMath.rgb(fromHex: hex) else {
            return NSColor.white.cgColor
        }
        return NSColor(
            srgbRed: CGFloat(rgb.red),
            green: CGFloat(rgb.green),
            blue: CGFloat(rgb.blue),
            alpha: 1
        ).cgColor
    }

    /// Maps the editor's text-alignment enum to Core Animation's layer
    /// alignment mode (used by karaoke/sticker overlay layers).
    static func textAlignmentMode(for alignment: TextAlignment) -> CATextLayerAlignmentMode {
        switch alignment {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        case .justified: return .justified
        }
    }
}

// MARK: - Compositor request carrying

/// `@unchecked Sendable` carrier for an `AVAsynchronousVideoCompositionRequest`
/// handed to a render queue. The request is not Sendable on the macOS 15 SDK
/// (later SDKs relaxed this), so `renderQueue.async { ... request ... }` fails
/// strict concurrency on the pinned Xcode 16. Each request is finished exactly
/// once inside the queued closure by the code that boxed it — no cross-task
/// sharing occurs.
struct CompositionRequestBox: @unchecked Sendable {
    let request: AVAsynchronousVideoCompositionRequest
}
