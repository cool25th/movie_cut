import AppKit
import Foundation
import MovieCutCore

// Media boundary of the EditorViewModel decomposition (roadmap:
// timeline → selection → transport → inspector → MEDIA → effects → audio →
// export). Pure method moves — no behavior change. Stored @Observable state
// stays in the main file.
//
// Deliberately NOT moved (pure-move rule — shared private helpers also used
// by non-media features): importMedia / importMediaAndAddToTimeline /
// addImportedAssetsToTimeline / addImportedAssetToTimeline /
// addClipToTimeline(asset:) / addMediaAssetToTimeline /
// insertMediaAssetOnTimeline / mediaAssetWithAppProbe (probe + insert are
// shared with the card-element image replacement and the photo-slideshow
// builder), relinkMedia (reportMediaNeedingRelocation is also called from
// the project-load path). Moving them would require promoting those
// helpers' access — a separately approved change, not a pure move.
extension EditorViewModel {
    func thumbnailData(for clip: Clip) -> Data? {
        guard
            clip.kind == .video || clip.kind == .image,
            let assetId = clip.assetId,
            let asset = currentProject.mediaLibrary.assets[assetId],
            asset.kind == .video || asset.kind == .image
        else {
            return nil
        }

        return asset.thumbnailData
    }


    func presentRelinkMissingMedia() async {
        // Snapshot the list: relinkMedia re-evaluates missingMediaAssets after
        // each success, so iterate over a stable copy.
        let toRelink = missingMediaAssets
        guard !toRelink.isEmpty else { return }

        for asset in toRelink {
            let panel = NSOpenPanel()
            panel.title = "Locate “\(asset.originalURL.lastPathComponent)”"
            panel.message = "MovieCut can’t find this media file. Choose its new location."
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.movie, .video, .audio, .image]
            panel.nameFieldStringValue = asset.originalURL.lastPathComponent
            // Cancel ends the whole pass; the user opted out of re-linking.
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let linked = await relinkMedia(asset, to: url)
            if !linked {
                // relinkMedia already set lastErrorMessage with the cause.
                return
            }
        }
    }

    func addClipToTimeline() async {
        guard let selectedAsset else { return }
        await addClipToTimeline(selectedAsset)
    }

    func generateProxyForSelectedAsset() async {
        guard let selectedAssetId else {
            lastErrorMessage = "Select a video asset to generate a proxy."
            lastStatusMessage = nil
            return
        }

        await generateProxy(for: selectedAssetId)
    }

    func generateProxy(for assetId: UUID) async {
        let snapshot = await session.snapshot()
        guard var asset = snapshot.mediaLibrary.assets[assetId] else {
            lastErrorMessage = "Selected asset is no longer available."
            lastStatusMessage = nil
            return
        }

        guard asset.kind == .video else {
            lastErrorMessage = "Proxy generation is only available for video assets."
            lastStatusMessage = nil
            return
        }

        let directory = Self.proxyDirectory(for: snapshot.id)
        let resolution = snapshot.playbackSettings.proxyResolution
        guard let plan = ProxyGenerator.makeProxyPlan(
            for: asset,
            in: directory,
            proxyResolution: resolution
        ) else {
            lastErrorMessage = "Could not create a proxy generation plan."
            lastStatusMessage = nil
            return
        }

        lastErrorMessage = nil
        lastStatusMessage = "Generating \(resolution.shortLabel) proxy for \(asset.originalURL.lastPathComponent)..."

        do {
            // The encode pass is the expensive part — time it under a signpost
            // so Instruments can attribute proxy-generation cost separately
            // from import.
            let proxyInfo = try await AppLog.time(.importLog, "proxy.generate") {
                try await ProxyGenerator.generateProxy(
                    for: asset,
                    using: plan,
                    proxyResolution: resolution
                )
            }
            guard let proxyInfo else {
                lastErrorMessage = "Proxy generation failed. The source file may not support proxy export."
                lastStatusMessage = nil
                return
            }

            asset.proxy = proxyInfo
            try await session.dispatch(UpdateMediaAssetCommand(asset: asset))
            try await refreshFromSession()
            lastErrorMessage = nil
            lastStatusMessage = "Proxy ready for \(asset.originalURL.lastPathComponent)."
        } catch is CancellationError {
            // CA-22 2차: a cancelled generation is not a failure — the partial
            // file is already removed by the generator, so report and leave
            // the asset resumable.
            autoProxyCancelledCount += 1
            lastErrorMessage = nil
            lastStatusMessage = "Proxy generation cancelled for \(asset.originalURL.lastPathComponent)."
        } catch {
            lastErrorMessage = "Proxy generation failed: \(error.localizedDescription)"
            lastStatusMessage = nil
        }
    }

    func setDropStatus(_ message: String) {
        lastErrorMessage = nil
        lastStatusMessage = message
    }

    func setDropError(_ message: String) {
        lastStatusMessage = nil
        lastErrorMessage = message
    }
}
