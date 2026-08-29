import Foundation
import Testing

/// P0 polish keeps the left browser and populated timeline presentation-first:
/// compact Media import affordances, browser-card rhythm, and clip-first timeline
/// visuals without moving commands back to top chrome or touching model behavior.
@Suite("P0 Browser Timeline Polish StaticContract")
struct P0BrowserTimelinePolishStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw P0BrowserTimelinePolishStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw P0BrowserTimelinePolishStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Media empty state has compact source row drop tile and grid rhythm")
    func mediaEmptyStateHasCompactSourceRowDropTileAndGridRhythm() throws {
        let media = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let empty = try section(
            in: media,
            from: "private var mediaImportCTAEmptyState: some View",
            to: "    private func assetGridCard"
        )
        let shared = try source("App/MovieCutMac/Inspector/InspectorShared.swift")

        for marker in [
            "mediaCompactImportSourceRow",
            "mediaCompactDropTile",
            "mediaEmptyGuidanceCard",
            #"Text(NSLocalizedString("Your library is empty", comment: ""))"#,
            #"Label(NSLocalizedString("Local media", comment: ""), systemImage: "folder")"#,
            #"Label(NSLocalizedString("Import", comment: ""), systemImage: "square.and.arrow.down")"#,
            #"Text(NSLocalizedString("Drop files to import", comment: ""))"#,
            ".movieCutLibraryBrowserCard("
        ] {
            #expect(empty.contains(marker))
        }
        #expect(!empty.contains("mediaEmptySkeletonCard"))

        #expect(shared.contains("func movieCutLibraryBrowserCard("))
        #expect(shared.contains("static let librarySourceRowBackground"))
        #expect(shared.contains("static let librarySkeletonFill"))
        #expect(!empty.contains(".frame(maxWidth: .infinity, minHeight: 220)"))
        #expect(!empty.contains(".controlSize(.large)"))
    }

    @Test("Timeline populated state emphasizes clip surfaces over grid")
    func timelinePopulatedStateEmphasizesClipSurfacesOverGrid() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let clip = try section(
            in: timeline,
            from: "private func clipView(_ clip: Clip, trackKind: TrackKind) -> some View",
            to: "    @ViewBuilder\n    private func clipMediaBackground"
        )
        let mediaBackground = try section(
            in: timeline,
            from: "private func clipMediaBackground(for clip: Clip, trackKind: TrackKind, selected: Bool) -> some View",
            to: "    private func thumbnailImage"
        )
        let grid = try section(
            in: timeline,
            from: "private func timelineGridLines(height: CGFloat) -> some View",
            to: "    private var mainVideoTrackBadge"
        )
        let lane = try section(
            in: timeline,
            from: "private func trackLane(_ track: Track) -> some View",
            to: "    private func trackHeaderControls(for track: Track) -> some View"
        )

        for marker in [
            "MovieCutTheme.timelineSelectedClipFill",
            "clipMediaTypeStripe(accent: clipAccent, selected: isSelected)",
            "clipTrimHandle(selected: isSelected)",
            ".strokeBorder(clipAccent.opacity(0.98), lineWidth: 1.6)",
            ".shadow(color: isSelected ? clipAccent.opacity(0.26) : Color.clear",
        ] {
            #expect(clip.contains(marker))
        }

        for marker in [
            "thumbnailStrip(image)",
            "waveformCanvas(for: clip, selected: selected)",
            "textClipRhythmStrip(for: clip, selected: selected)",
            "clipPlaceholderRhythm(accent: accentForClip(clip: clip, trackKind: trackKind), selected: selected)",
            "fallbackWaveformLevel(index: index)"
        ] {
            #expect(mediaBackground.contains(marker) || timeline.contains(marker))
        }

        #expect(grid.contains("MovieCutTheme.timelineGrid.opacity(0.44)"))
        #expect(grid.contains("MovieCutTheme.timelineGrid.opacity(0.24)"))
        #expect(lane.contains(".background(MovieCutTheme.trackHeaderBackground.opacity(0.74))"))
        #expect(lane.contains("trackHeaderControls(for: track)"))
        #expect(lane.contains("timelineGridLines(height: trackHeight)"))
        #expect(lane.contains("clipView(clip, trackKind: track.kind)"))
    }
}

private enum P0BrowserTimelinePolishStaticContractError: Error {
    case missingMarker(String)
}
