import Foundation

/// Metadata describing a MovieCut plugin.
public struct PluginManifest: Codable, Sendable, Equatable {
    /// Reverse-DNS plugin identifier, for example `com.moviecut.plugin.grayscale`.
    public var identifier: String

    /// User-visible plugin name.
    public var name: String

    /// Plugin version string.
    public var version: String

    /// Plugin author or organization.
    public var author: String

    /// User-visible plugin description.
    public var description: String

    /// Entry-point class or type name.
    public var entryPoint: String

    /// Capabilities exposed by this plugin.
    public var pluginTypes: Set<PluginType>

    /// Creates plugin metadata.
    public init(
        identifier: String,
        name: String,
        version: String,
        author: String,
        description: String,
        entryPoint: String,
        pluginTypes: Set<PluginType>
    ) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.author = author
        self.description = description
        self.entryPoint = entryPoint
        self.pluginTypes = pluginTypes
    }
}

/// Plugin capability categories.
public enum PluginType: String, Codable, Sendable, Hashable {
    /// Image or video-frame effect plugin.
    case effect

    /// Transition renderer plugin.
    case transition

    /// Project exporter plugin.
    case exporter

    /// Media importer plugin.
    case importer

    /// Automation or command plugin.
    case automation
}
