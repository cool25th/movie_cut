import Foundation

/// A provider capable of analyzing media and producing edit suggestions.
public protocol AnalysisProvider: Sendable {
    /// Whether this provider can be used in the current environment.
    var isAvailable: Bool { get }

    /// User-visible provider name.
    var providerName: String { get }

    /// Analyzes an asset in the context of a project.
    func analyze(asset: MediaAsset, in project: Project) async throws -> AnalysisResult
}

public extension AnalysisProvider {
    /// Default availability for platform-backed providers.
    var isAvailable: Bool { true }

    /// Default user-visible provider name.
    var providerName: String { String(describing: Self.self) }
}
