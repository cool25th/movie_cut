import Foundation
import Testing
@testable import MovieCutCore

@Suite("PluginRegistry dynamic loading security")
struct PluginRegistryTests {
    @Test("read-only sandbox rejects sibling path prefix escape")
    func testReadOnlySandboxRejectsSiblingPrefixEscape() {
        let registry = PluginRegistry()
        registry.setSandboxPolicy(.readOnly)
        let pluginURL = URL(fileURLWithPath: "/tmp/MovieCutSafe.moviecutplugin")
        let siblingURL = URL(fileURLWithPath: "/tmp/MovieCutSafe.moviecutplugin-evil/payload.dat")

        #expect(registry.isResourceAllowed(siblingURL, in: pluginURL) == false)
    }

    @Test("read-only sandbox allows resources inside plugin bundle")
    func testReadOnlySandboxAllowsBundleResource() {
        let registry = PluginRegistry()
        registry.setSandboxPolicy(.readOnly)
        let pluginURL = URL(fileURLWithPath: "/tmp/MovieCutSafe.moviecutplugin")
        let nestedURL = pluginURL.appendingPathComponent("Resources/preset.json")

        #expect(registry.isResourceAllowed(nestedURL, in: pluginURL) == true)
        #expect(registry.isResourceAllowed(nestedURL, in: pluginURL, write: true) == false)
    }

    @Test("read-only sandbox rejects symlink escape from plugin bundle")
    func testReadOnlySandboxRejectsSymlinkEscape() throws {
        let registry = PluginRegistry()
        registry.setSandboxPolicy(.readOnly)
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutPluginRegistryTests-\(UUID().uuidString)", isDirectory: true)
        let pluginURL = rootURL.appendingPathComponent("Safe.moviecutplugin", isDirectory: true)
        let outsideURL = rootURL.appendingPathComponent("Outside", isDirectory: true)
        let escapedResourceURL = pluginURL
            .appendingPathComponent("LinkedOutside", isDirectory: true)
            .appendingPathComponent("payload.dat")

        try FileManager.default.createDirectory(at: pluginURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: pluginURL.appendingPathComponent("LinkedOutside"),
            withDestinationURL: outsideURL
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        #expect(registry.isResourceAllowed(escapedResourceURL, in: pluginURL) == false)
    }

    @Test("minimal sandbox only allows top-level manifest read")
    func testMinimalSandboxOnlyAllowsTopLevelManifest() {
        let registry = PluginRegistry()
        registry.setSandboxPolicy(.minimal)
        let pluginURL = URL(fileURLWithPath: "/tmp/MovieCutSafe.moviecutplugin")
        let manifestURL = pluginURL.appendingPathComponent("manifest.json")
        let nestedManifestURL = pluginURL.appendingPathComponent("Nested/manifest.json")

        #expect(registry.isResourceAllowed(manifestURL, in: pluginURL) == true)
        #expect(registry.isResourceAllowed(manifestURL, in: pluginURL, write: true) == false)
        #expect(registry.isResourceAllowed(nestedManifestURL, in: pluginURL) == false)
    }

    @Test("minimal sandbox rejects top-level manifest symlink escape")
    func testMinimalSandboxRejectsTopLevelManifestSymlinkEscape() throws {
        let registry = PluginRegistry()
        registry.setSandboxPolicy(.minimal)
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutPluginRegistryTests-\(UUID().uuidString)", isDirectory: true)
        let pluginURL = rootURL.appendingPathComponent("Safe.moviecutplugin", isDirectory: true)
        let outsideURL = rootURL.appendingPathComponent("Outside", isDirectory: true)
        let outsideManifestURL = outsideURL.appendingPathComponent("manifest.json")
        let manifestURL = pluginURL.appendingPathComponent("manifest.json")

        try FileManager.default.createDirectory(at: pluginURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        try "{}".write(to: outsideManifestURL, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: manifestURL,
            withDestinationURL: outsideManifestURL
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        #expect(registry.isResourceAllowed(manifestURL, in: pluginURL) == false)
    }

    @Test("manifest validation rejects path-like entry points")
    func testValidatePluginRejectsPathLikeEntryPoints() throws {
        let registry = PluginRegistry()
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutPluginRegistryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let traversalPluginURL = try Self.makePluginBundle(
            rootURL: rootURL,
            name: "Traversal.moviecutplugin",
            entryPoint: "../OutsidePlugin"
        )
        let absolutePluginURL = try Self.makePluginBundle(
            rootURL: rootURL,
            name: "Absolute.moviecutplugin",
            entryPoint: "/tmp/OutsidePlugin"
        )
        let typeNamePluginURL = try Self.makePluginBundle(
            rootURL: rootURL,
            name: "TypeName.moviecutplugin",
            entryPoint: "MovieCutPlugin.SampleEffect"
        )

        if case .invalid(let reason) = registry.validatePlugin(at: traversalPluginURL) {
            #expect(reason.contains("entryPoint"))
        } else {
            Issue.record("Path traversal entryPoint must be rejected.")
        }

        if case .invalid(let reason) = registry.validatePlugin(at: absolutePluginURL) {
            #expect(reason.contains("entryPoint"))
        } else {
            Issue.record("Absolute path entryPoint must be rejected.")
        }

        if case .valid(let manifest) = registry.validatePlugin(at: typeNamePluginURL) {
            #expect(manifest.entryPoint == "MovieCutPlugin.SampleEffect")
        } else {
            Issue.record("Module-qualified type-name entryPoint should remain valid.")
        }
    }

    @Test("manifest validation normalizes boundary whitespace before registration")
    func testValidatePluginNormalizesBoundaryWhitespace() throws {
        let registry = PluginRegistry()
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutPluginRegistryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let pluginURL = try Self.makePluginBundle(
            rootURL: rootURL,
            name: "Whitespace.moviecutplugin",
            identifier: "  com.moviecut.tests.whitespace  ",
            displayName: "  Whitespace Plugin  ",
            version: "  1.0.0  ",
            author: "  MovieCut QA  ",
            description: "  Safe dynamic plugin fixture  ",
            entryPoint: "  MovieCutPlugin.SampleEffect  "
        )

        if case .valid(let manifest) = registry.validatePlugin(at: pluginURL) {
            #expect(manifest.identifier == "com.moviecut.tests.whitespace")
            #expect(manifest.name == "Whitespace Plugin")
            #expect(manifest.version == "1.0.0")
            #expect(manifest.author == "MovieCut QA")
            #expect(manifest.description == "Safe dynamic plugin fixture")
            #expect(manifest.entryPoint == "MovieCutPlugin.SampleEffect")
        } else {
            Issue.record("Plugin manifest boundary whitespace should be normalized, not persisted.")
        }
    }

    @Test("manifest validation rejects malformed type-name entry points")
    func testValidatePluginRejectsMalformedTypeNameEntryPoints() throws {
        let registry = PluginRegistry()
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutPluginRegistryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        for entryPoint in [".HiddenPlugin", "MovieCutPlugin.", "123Plugin", "MovieCutPlugin.9PatchEffect"] {
            let pluginURL = try Self.makePluginBundle(
                rootURL: rootURL,
                name: "Malformed-\(UUID().uuidString).moviecutplugin",
                entryPoint: entryPoint
            )

            if case .invalid(let reason) = registry.validatePlugin(at: pluginURL) {
                #expect(reason.contains("entryPoint"))
            } else {
                Issue.record("Malformed type-name entryPoint must be rejected: \(entryPoint)")
            }
        }
    }

    private static func makePluginBundle(
        rootURL: URL,
        name: String,
        identifier: String = "com.moviecut.tests.\(UUID().uuidString)",
        displayName: String = "Test Plugin",
        version: String = "1.0.0",
        author: String? = nil,
        description: String? = nil,
        entryPoint: String
    ) throws -> URL {
        let pluginURL = rootURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: pluginURL, withIntermediateDirectories: true)
        var manifestFields = [
            "\"identifier\": \"\(identifier)\"",
            "\"name\": \"\(displayName)\"",
            "\"version\": \"\(version)\"",
            "\"entryPoint\": \"\(entryPoint)\"",
            "\"pluginTypes\": [\"effect\"]"
        ]
        if let author {
            manifestFields.insert("\"author\": \"\(author)\"", at: 3)
        }
        if let description {
            manifestFields.insert("\"description\": \"\(description)\"", at: author == nil ? 3 : 4)
        }
        let manifest = "{\n  \(manifestFields.joined(separator: ",\n  "))\n}\n"
        try manifest.write(to: pluginURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        return pluginURL
    }
}
