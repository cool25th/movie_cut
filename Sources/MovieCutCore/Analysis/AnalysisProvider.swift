import Foundation

/// A provider capable of analyzing media and producing edit suggestions.
public protocol AnalysisProvider: Sendable {
    /// Analyzes an asset in the context of a project.
    func analyze(asset: MediaAsset, in project: Project) async throws -> AnalysisResult
}
