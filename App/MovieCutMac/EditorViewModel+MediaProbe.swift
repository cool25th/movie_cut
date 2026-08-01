import Foundation
import MovieCutCore

// Per the established companion-file convention (see EditorViewModel+Compound,
// +SlipSlide, +VocalSeparation, +AssistantProvider, +HomeRouting), best-effort
// media metadata probing lives in its own extension file so EditorViewModel.swift
// itself is not edited for new probe entry points.
//
// The probe implementation moved to `AVFoundationProbe` in MovieCutCore
// (Sources/MovieCutCore/Media/AVFoundationProbe.swift), so it is shared with the
// iOS target and no longer duplicated. These are thin forwarders that the VM's
// `mediaAssetWithAppProbe(for:)` calls through `Self.`.

extension EditorViewModel {
    nonisolated static func appMetadataProbe(
        for url: URL,
        kind: MediaKind,
        baseMetadata: MediaMetadata
    ) async -> (duration: TimeInterval?, metadata: MediaMetadata) {
        await AVFoundationProbe.appMetadataProbe(for: url, kind: kind, baseMetadata: baseMetadata)
    }

    nonisolated static func enrichAssetWithThumbnail(_ asset: MediaAsset) async -> MediaAsset {
        await AVFoundationProbe.enrichAssetWithThumbnail(asset)
    }

    nonisolated static func videoAssetContainsAudioTrack(_ url: URL) async -> Bool {
        await AVFoundationProbe.videoAssetContainsAudioTrack(url)
    }

    nonisolated static func avAssetDuration(for url: URL) async -> TimeInterval? {
        await AVFoundationProbe.avAssetDuration(for: url)
    }

    /// Application-Support-backed proxy directory for a project's transcoded
    /// media. App-only (filesystem layout, not probing), so it stays here
    /// rather than in Core's `AVFoundationProbe`.
    nonisolated static func proxyDirectory(for projectId: UUID) -> URL {
        let baseDirectory = (
            try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        ) ?? FileManager.default.temporaryDirectory

        return baseDirectory
            .appendingPathComponent("MovieCut", isDirectory: true)
            .appendingPathComponent("Proxies", isDirectory: true)
            .appendingPathComponent(projectId.uuidString, isDirectory: true)
    }
}
