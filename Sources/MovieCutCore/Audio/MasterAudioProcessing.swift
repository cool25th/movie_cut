import Foundation

/// G-26 — the project-level master audio processing choice. The graph
/// builder expands the preset into the spec's master bus (the chain's
/// FULL parameters plus the §6 preset algorithm version), so preview and
/// export consume the same serialized values by construction and a
/// deserialized graph renders identically anywhere.
///
/// The project stores the PRESET NAME (not raw parameters): the preset is
/// the versioned unit per spec §6, and per-clip tweaks arrive with a
/// later inspector increment — the serialized parameter surface lives on
/// the graph's master bus, not on the project.
public enum MasterAudioProcessing: String, Codable, Sendable, Equatable {
    /// The SNS "좋은 소리" preset: gentle compression → −1 dBTP limiting →
    /// subtle room reverb (spec §7's processing).
    case sns
}
