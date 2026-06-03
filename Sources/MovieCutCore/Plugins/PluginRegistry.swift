import Foundation
import os

/// Registry for installed and built-in plugins.
public final class PluginRegistry: Sendable {
    /// Shared process-wide plugin registry.
    public static let shared = PluginRegistry()

    private let pluginStorage = OSAllocatedUnfairLock(initialState: [PluginManifest]())

    /// Registered plugin manifests.
    public private(set) var plugins: [PluginManifest] {
        get {
            pluginStorage.withLock { $0 }
        }
        set {
            pluginStorage.withLock { $0 = newValue }
        }
    }

    /// Creates an empty plugin registry.
    public init() {}

    /// Registers an effect plugin.
    public func register(plugin: any EffectPlugin) {
        register(manifest: plugin.manifest)
    }

    /// Registers a transition plugin.
    public func register(plugin: any TransitionPlugin) {
        register(manifest: plugin.manifest)
    }

    /// Registers an exporter plugin.
    public func register(plugin: any ExporterPlugin) {
        register(manifest: plugin.manifest)
    }

    /// Returns plugin manifests matching a plugin type.
    public func plugins(ofType type: PluginType) -> [PluginManifest] {
        pluginStorage.withLock { pluginStorage in
            pluginStorage.filter { $0.pluginTypes.contains(type) }
        }
    }

    private func register(manifest: PluginManifest) {
        pluginStorage.withLock { pluginStorage in
            if let index = pluginStorage.firstIndex(where: { $0.identifier == manifest.identifier }) {
                pluginStorage[index] = manifest
            } else {
                pluginStorage.append(manifest)
            }
        }
    }
}
