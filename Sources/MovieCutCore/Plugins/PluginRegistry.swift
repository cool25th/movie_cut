import Foundation

/// Registry for installed and built-in plugins.
public final class PluginRegistry: @unchecked Sendable {
    /// Shared process-wide plugin registry.
    public static let shared = PluginRegistry()

    private let lock = NSLock()
    private var pluginStorage: [PluginManifest]

    /// Registered plugin manifests.
    public private(set) var plugins: [PluginManifest] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return pluginStorage
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            pluginStorage = newValue
        }
    }

    /// Creates an empty plugin registry.
    public init() {
        pluginStorage = []
    }

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
        lock.lock()
        defer { lock.unlock() }
        return pluginStorage.filter { $0.pluginTypes.contains(type) }
    }

    private func register(manifest: PluginManifest) {
        lock.lock()
        defer { lock.unlock() }

        if let index = pluginStorage.firstIndex(where: { $0.identifier == manifest.identifier }) {
            pluginStorage[index] = manifest
        } else {
            pluginStorage.append(manifest)
        }
    }
}
