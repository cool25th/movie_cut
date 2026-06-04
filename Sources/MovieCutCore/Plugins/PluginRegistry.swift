import Foundation
import os

/// Errors that can occur during plugin operations.
public enum PluginError: Error, Sendable {
    /// The bundle at the given URL is not a valid plugin bundle.
    case invalidBundle(String)
    /// The manifest.json file is missing from the bundle.
    case missingManifest
    /// The manifest could not be decoded.
    case manifestDecodingFailed(String)
    /// Plugin validation failed for the given reason.
    case validationFailed(String)
    /// No plugin was found with the given identifier.
    case pluginNotFound(String)
}

/// Result of validating a plugin bundle.
public enum PluginValidationResult: Sendable, Equatable {
    /// The plugin bundle is valid and contains the attached manifest.
    case valid(PluginManifest)
    /// The plugin bundle is invalid for the described reason.
    case invalid(String)
}

/// Policy controlling what operations a dynamically-loaded plugin may perform.
public enum PluginSandboxPolicy: String, Codable, Sendable, CaseIterable {
    /// Full access to all system resources.
    case full
    /// Read-only access; plugins may read but not write outside their bundle.
    case readOnly
    /// Minimal access; plugins can only interact through the plugin API.
    case minimal
}

/// Registry for installed and built-in plugins.
public final class PluginRegistry: Sendable {
    /// Shared process-wide plugin registry.
    public static let shared = PluginRegistry()

    private let pluginStorage = OSAllocatedUnfairLock(initialState: [PluginManifest]())

    private let sandboxPolicyStorage = OSAllocatedUnfairLock(initialState: PluginSandboxPolicy.full)

    /// The current sandbox policy applied to dynamically-loaded plugins.
    public var sandboxPolicy: PluginSandboxPolicy {
        get {
            sandboxPolicyStorage.withLock { $0 }
        }
        set {
            sandboxPolicyStorage.withLock { $0 = newValue }
        }
    }

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

    // MARK: - Dynamic Loading

    /// Validates a plugin bundle at the given URL without loading it.
    ///
    /// Checks that the URL points to a `.moviecutplugin` directory, contains a
    /// readable `manifest.json`, and that all required fields are present.
    ///
    /// - Parameter url: File URL of the plugin bundle to validate.
    /// - Returns: `.valid(PluginManifest)` on success, `.invalid(String)` otherwise.
    public func validatePlugin(at url: URL) -> PluginValidationResult {
        // 1. Check file extension
        guard url.pathExtension == "moviecutplugin" else {
            return .invalid("URL does not have .moviecutplugin extension: \(url.path)")
        }

        // 2. Check that it is a directory
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return .invalid("Plugin bundle is not a directory: \(url.path)")
        }

        // 3. Read manifest.json
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard isResourceAllowed(manifestURL, in: url, write: false) else {
            return .invalid("Sandbox policy does not allow reading manifest.json")
        }

        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            return .invalid("Failed to read manifest.json: \(error.localizedDescription)")
        }

        // 4. Decode manifest
        let payload: PluginManifestPayload
        do {
            payload = try JSONDecoder().decode(PluginManifestPayload.self, from: data)
        } catch {
            return .invalid("Failed to decode manifest.json: \(error.localizedDescription)")
        }

        // 5. Validate required fields
        guard !payload.identifier.trimmedForPluginValidation.isEmpty else {
            return .invalid("Manifest identifier must not be empty")
        }
        guard !payload.name.trimmedForPluginValidation.isEmpty else {
            return .invalid("Manifest name must not be empty")
        }
        guard !payload.version.trimmedForPluginValidation.isEmpty else {
            return .invalid("Manifest version must not be empty")
        }
        guard !payload.entryPoint.trimmedForPluginValidation.isEmpty else {
            return .invalid("Manifest entryPoint must not be empty")
        }
        guard !payload.pluginTypes.isEmpty else {
            return .invalid("Manifest pluginTypes must not be empty")
        }

        guard Self.versionComponents(payload.version) != nil else {
            return .invalid("Manifest version must be compatible with semantic version checks")
        }

        guard Self.isCompatible(
            minimumVersion: payload.minimumMovieCutVersion,
            maximumVersion: payload.maximumMovieCutVersion
        ) else {
            return .invalid("Plugin is not compatible with this MovieCut version")
        }

        let manifest = PluginManifest(
            identifier: payload.identifier,
            name: payload.name,
            version: payload.version,
            author: payload.author ?? "Unknown",
            description: payload.description ?? "",
            entryPoint: payload.entryPoint,
            pluginTypes: payload.pluginTypes
        )

        return .valid(manifest)
    }

    /// Dynamically loads a plugin from a bundle directory.
    ///
    /// Validates the bundle first, then registers the manifest with the registry.
    ///
    /// - Parameter url: File URL of the `.moviecutplugin` bundle.
    /// - Returns: The loaded plugin manifest.
    /// - Throws: `PluginError` if validation or registration fails.
    public func loadPlugin(from url: URL) async throws -> PluginManifest {
        let result = validatePlugin(at: url)
        switch result {
        case .valid(let manifest):
            register(manifest: manifest)
            return manifest
        case .invalid(let reason):
            throw PluginError.validationFailed(reason)
        }
    }

    /// Removes a plugin from the registry by its identifier.
    ///
    /// - Parameter identifier: The reverse-DNS identifier of the plugin to unload.
    public func unloadPlugin(identifier: String) {
        pluginStorage.withLock { storage in
            storage.removeAll { $0.identifier == identifier }
        }
    }

    /// Discovers all valid plugin bundles in the given directory.
    ///
    /// Scans for `.moviecutplugin` directories, validates each one, and returns
    /// the manifests of all valid plugins. Invalid bundles are silently skipped.
    ///
    /// - Parameter directory: Directory to scan for plugin bundles.
    /// - Returns: Array of manifests from valid plugin bundles.
    public func discoverPlugins(in directory: URL) -> [PluginManifest] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }

        var validManifests: [PluginManifest] = []
        for itemURL in contents {
            guard itemURL.pathExtension == "moviecutplugin" else { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: itemURL.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            if case .valid(let manifest) = validatePlugin(at: itemURL) {
                validManifests.append(manifest)
            }
        }
        return validManifests
    }

    /// Sets the sandbox policy for dynamically-loaded plugins.
    ///
    /// - Parameter policy: The new sandbox policy to apply.
    public func setSandboxPolicy(_ policy: PluginSandboxPolicy) {
        sandboxPolicyStorage.withLock { $0 = policy }
    }

    /// Returns whether a plugin resource can be accessed under the current sandbox policy.
    public func isResourceAllowed(_ resourceURL: URL, in pluginURL: URL, write: Bool = false) -> Bool {
        switch sandboxPolicy {
        case .full:
            return true
        case .readOnly:
            return !write && resourceURL.standardizedFileURL.path.hasPrefix(pluginURL.standardizedFileURL.path)
        case .minimal:
            return !write
                && resourceURL.lastPathComponent == "manifest.json"
                && resourceURL.deletingLastPathComponent().standardizedFileURL == pluginURL.standardizedFileURL
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

    private static func isCompatible(minimumVersion: String?, maximumVersion: String?) -> Bool {
        if let minimumVersion,
           compareVersions(currentMovieCutVersion, minimumVersion) == .orderedAscending {
            return false
        }

        if let maximumVersion,
           compareVersions(currentMovieCutVersion, maximumVersion) == .orderedDescending {
            return false
        }

        return true
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        guard let lhsComponents = versionComponents(lhs),
              let rhsComponents = versionComponents(rhs) else {
            return lhs.compare(rhs)
        }

        let count = max(lhsComponents.count, rhsComponents.count)
        for index in 0 ..< count {
            let lhsValue = index < lhsComponents.count ? lhsComponents[index] : 0
            let rhsValue = index < rhsComponents.count ? rhsComponents[index] : 0

            if lhsValue < rhsValue {
                return .orderedAscending
            }

            if lhsValue > rhsValue {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    private static func versionComponents(_ version: String) -> [Int]? {
        let components = version.split(separator: ".").map { component -> Int? in
            let numericPrefix = component.prefix { character in
                character.isNumber
            }
            return Int(numericPrefix)
        }

        guard components.isEmpty == false,
              components.allSatisfy({ $0 != nil }) else {
            return nil
        }

        return components.compactMap { $0 }
    }

    private static let currentMovieCutVersion = "0.1.0"
}

private struct PluginManifestPayload: Decodable {
    var identifier: String
    var name: String
    var version: String
    var author: String?
    var description: String?
    var entryPoint: String
    var pluginTypes: Set<PluginType>
    var minimumMovieCutVersion: String?
    var maximumMovieCutVersion: String?
}

private extension String {
    var trimmedForPluginValidation: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
