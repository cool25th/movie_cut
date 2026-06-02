import Foundation

/// Plugin interface for transitions that blend two frames into an output frame.
public protocol TransitionPlugin: Sendable {
    /// Plugin metadata.
    var manifest: PluginManifest { get }

    /// Renders the transition at the supplied progress value.
    func render(
        fromFrame: UnsafeMutableRawPointer,
        toFrame: UnsafeMutableRawPointer,
        output: UnsafeMutableRawPointer,
        width: Int,
        height: Int,
        progress: Float
    ) throws
}
