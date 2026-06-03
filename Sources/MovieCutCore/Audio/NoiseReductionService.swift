import Foundation

#if canImport(AVFoundation)
import AVFoundation

public struct NoiseReductionService: Sendable {
    public init() {}

    public func applyNoiseReduction(to asset: AVAsset, threshold _: Float = 0.05) async throws -> URL {
        // Basic noise gate placeholder: preserves media through an audio export path.
        let composition = AVMutableComposition()
        let assetDuration = try await asset.load(.duration)
        let assetTracks = try await asset.load(.tracks)

        for track in assetTracks {
            let compositionTrack = composition.addMutableTrack(
                withMediaType: track.mediaType,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            try compositionTrack?.insertTimeRange(
                CMTimeRange(start: .zero, duration: assetDuration),
                of: track,
                at: .zero
            )
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("denoised_\(UUID().uuidString).m4a")

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "NoiseReduction", code: 1)
        }
        export.outputURL = outputURL
        export.outputFileType = .m4a
        _ = await export.export()
        return outputURL
    }
}
#endif
