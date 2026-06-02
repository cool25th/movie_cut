import Foundation

/// Placeholder analysis provider used before a real analysis backend is wired in.
public final class StubAnalysisProvider: AnalysisProvider, @unchecked Sendable {
    /// Whether this provider can be used in the current environment.
    public let isAvailable = false

    /// User-visible provider name.
    public let providerName = "Stub"

    /// Creates a stub provider.
    public init() {}

    public func analyze(asset: MediaAsset, in project: Project) async throws -> AnalysisResult {
        AnalysisResult(suggestions: [], sourceAssetID: asset.id.uuidString, providerName: providerName)
    }
}
