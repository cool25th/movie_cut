import Foundation
import Testing

/// The macOS app target is built by xcodebuild. These checks keep the P0
/// import/drop wiring visible in SwiftPM's faster core test loop.
@Suite("Media Drag Drop Static Contract")
struct MediaDragDropStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("timeline file drops import media and add clips at the drop position")
    func timelineFileDropCreatesClips() throws {
        let source = try source("App/MovieCutMac/TimelineView.swift")

        #expect(source.contains(".fileURL"))
        #expect(source.contains("handleTrackDrop"))
        #expect(source.contains("onDrop(of: [.fileURL, .movieCutMediaAssetID], isTargeted: nil)"))
        #expect(source.contains("location.x"))
        #expect(source.contains("pixelsPerSecond"))
        #expect(source.contains("importMediaAndAddToTimeline"))
        #expect(source.contains("preferredTrackId: trackId"))
        #expect(source.contains("startTime: startTime"))
    }

    @Test("timeline accepts internal library asset ID drops")
    func timelineAcceptsLibraryAssetDrops() throws {
        let source = try source("App/MovieCutMac/TimelineView.swift")

        #expect(source.contains("movieCutMediaAssetID"))
        #expect(source.contains("loadAssetIDs"))
        #expect(source.contains("UUID(uuidString:"))
        #expect(source.contains("addImportedAssetsToTimeline"))
    }

    @Test("media library asset rows are draggable with UUID payloads")
    func mediaLibraryRowsAreDraggable() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")

        #expect(source.contains(".onDrag"))
        #expect(source.contains("asset.id.uuidString"))
        #expect(source.contains("UTType.movieCutMediaAssetID.identifier"))
        #expect(source.contains("Drag it to the timeline to create a clip"))
        #expect(source.contains("draggable to timeline"))
    }

    @Test("mac view model probes AVAsset duration before import and supports drop insertion")
    func viewModelProbesDurationAndInsertsDroppedMedia() throws {
        let source = try source("App/MovieCutMac/EditorViewModel.swift")

        #expect(source.contains("func importMediaAndAddToTimeline"))
        #expect(source.contains("MediaImporter.probe(url: url)"))
        #expect(source.contains("AVURLAsset(url: url)"))
        #expect(source.contains("try await asset.load(.duration)"))
        #expect(source.contains("ImportMediaCommand(asset: asset)"))
        #expect(source.contains("AddClipCommand(trackId: track.id, clip: clip)"))
        #expect(source.contains("sourceRange: TimeRange(start: 0, duration: duration)"))
        #expect(source.contains("timelineRange: TimeRange(start: max(0, startTime), duration: duration)"))
        #expect(source.contains("preferredTrack.kind == destinationKind"))
    }
}
