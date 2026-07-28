import Foundation

/// The identity of a waveform decode request.
///
/// A clip's waveform depends on the **asset** it points at, not just the clip.
/// When `SetClipSourceAssetCommand` swaps a clip's asset (e.g. after noise
/// reduction), the clip id stays the same but the audio content changes, so the
/// cached waveform must be invalidated and re-decoded.
///
/// This value bundles `(clipId, assetId)` so that a view's decode-triggering
/// `.task(id:)` re-runs whenever the asset changes — not just when the clip id
/// changes. It is the value-level condition for "the waveform must be
/// re-requested", and is unit-testable in Core without the view lifecycle.
public struct WaveformRequestKey: Hashable, Sendable {
    /// The clip whose waveform is requested.
    public let clipId: UUID
    /// The asset the clip currently points at. `nil` for clips without an asset
    /// (e.g. text); two such clips are distinguished only by `clipId`.
    public let assetId: UUID?

    public init(clipId: UUID, assetId: UUID?) {
        self.clipId = clipId
        self.assetId = assetId
    }

    /// Builds the request key for a clip's current asset binding.
    public init(clip: Clip) {
        self.clipId = clip.id
        self.assetId = clip.assetId
    }
}
