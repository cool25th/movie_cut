import Foundation

/// An edit suggestion produced by an analysis provider.
public enum AnalysisSuggestion: Sendable, Codable, Equatable {
    /// Timeline ranges that can be removed because they are silent.
    case silenceRemoval(ranges: [TimeRange])

    /// Timeline times where scene boundaries were detected.
    case sceneChanges(times: [TimeInterval])

    /// Timeline ranges selected for automatic cutting.
    case autoCut(editedRanges: [TimeRange])
}

/// The complete result returned from an analysis pass.
public struct AnalysisResult: Sendable, Codable {
    /// Suggested edits for the source asset.
    public let suggestions: [AnalysisSuggestion]

    /// The source media asset identifier.
    public let sourceAssetID: String

    /// User-visible name of the provider that produced the result.
    public let providerName: String

    /// Creates an analysis result.
    public init(suggestions: [AnalysisSuggestion], sourceAssetID: String, providerName: String = "Unknown") {
        self.suggestions = suggestions
        self.sourceAssetID = sourceAssetID
        self.providerName = providerName
    }
}
