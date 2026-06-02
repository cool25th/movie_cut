import Foundation

/// Plugin interface for project exporters.
public protocol ExporterPlugin: Sendable {
    /// Plugin metadata.
    var manifest: PluginManifest { get }

    /// Exports a project to a destination URL.
    func export(project: Project, to url: URL, settings: ExportSettings) async throws
}
