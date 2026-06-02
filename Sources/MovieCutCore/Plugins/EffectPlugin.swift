import Foundation

/// Plugin interface for effects that mutate a frame in place.
public protocol EffectPlugin: Sendable {
    /// Plugin metadata.
    var manifest: PluginManifest { get }

    /// Applies the effect to a mutable pixel buffer.
    func apply(
        to pixelBuffer: UnsafeMutableRawPointer,
        width: Int,
        height: Int,
        time: TimeInterval
    ) throws
}
