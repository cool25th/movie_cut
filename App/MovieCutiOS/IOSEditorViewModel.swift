import Foundation
import AVFoundation
import MovieCutCore

@MainActor
@Observable
final class IOSEditorViewModel {
    var currentProject: Project
    var selectedClipId: UUID?
    var playheadTime: TimeInterval
    var isPlaying: Bool

    private let session: EditorSession

    init() {
        let project = Self.defaultProject()
        currentProject = project
        selectedClipId = nil
        playheadTime = 0
        isPlaying = false
        session = EditorSession(project: project)
    }

    var mediaAssets: [MediaAsset] {
        currentProject.mediaLibrary.assets.values.sorted {
            $0.originalURL.lastPathComponent.localizedStandardCompare($1.originalURL.lastPathComponent) == .orderedAscending
        }
    }

    var selectedClip: Clip? {
        guard let selectedClipId else { return nil }
        return currentProject.timeline.tracks
            .flatMap(\.clips)
            .first { $0.id == selectedClipId }
    }

    func importMedia(from url: URL, kind: MediaKind? = nil) async {
        var asset = MediaImporter.probe(url: url)
        if let kind {
            asset.kind = kind
        }
        asset.duration = await duration(for: url, kind: asset.kind)

        do {
            try await session.dispatch(ImportMediaCommand(asset: asset))
            await refreshFromSession()
        } catch {
            return
        }
    }

    func addClipToTimeline(asset: MediaAsset) async {
        do {
            var snapshot = await session.snapshot()
            if snapshot.mediaLibrary.assets[asset.id] == nil {
                try await session.dispatch(ImportMediaCommand(asset: asset))
                snapshot = await session.snapshot()
            }

            guard let track = snapshot.timeline.tracks.first(where: { $0.kind == trackKind(for: asset.kind) }) else {
                return
            }

            let duration = defaultDuration(for: asset)
            let start = snapshot.timeline.duration
            let clip = Clip(
                assetId: asset.id,
                kind: clipKind(for: asset.kind),
                sourceRange: TimeRange(start: 0, duration: duration),
                timelineRange: TimeRange(start: start, duration: duration)
            )

            try await session.dispatch(AddClipCommand(trackId: track.id, clip: clip))
            selectedClipId = clip.id
            playheadTime = clip.timelineRange.start
            await refreshFromSession()
        } catch {
            return
        }
    }

    func splitClip() async {
        guard
            let selectedClipId,
            let selectedClip,
            let trackId = selectedClipTrackId,
            selectedClip.timelineRange.contains(playheadTime)
        else { return }

        do {
            try await session.dispatch(SplitClipCommand(clipId: selectedClipId, trackId: trackId, splitTime: playheadTime))
            await refreshFromSession()
        } catch {
            return
        }
    }

    func deleteClip() async {
        guard let selectedClipId else { return }

        do {
            try await session.dispatch(DeleteClipCommand(clipId: selectedClipId))
            self.selectedClipId = nil
            await refreshFromSession()
        } catch {
            return
        }
    }

    func undo() async {
        do {
            try await session.undo()
            await refreshFromSession()
        } catch {
            return
        }
    }

    func redo() async {
        do {
            try await session.redo()
            await refreshFromSession()
        } catch {
            return
        }
    }

    func togglePlayPause() {
        isPlaying.toggle()
    }

    private var selectedClipTrackId: UUID? {
        guard let selectedClipId else { return nil }
        return currentProject.timeline.tracks.first { track in
            track.clips.contains { $0.id == selectedClipId }
        }?.id
    }

    private func refreshFromSession() async {
        currentProject = await session.snapshot()
        if selectedClipId != nil, selectedClip == nil {
            selectedClipId = nil
        }
        playheadTime = min(max(0, playheadTime), currentProject.timeline.duration)
        if currentProject.timeline.duration == 0 {
            isPlaying = false
        }
    }

    private func duration(for url: URL, kind: MediaKind) async -> TimeInterval? {
        guard kind != .image else { return nil }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.seconds.isFinite else {
            return nil
        }
        return duration.seconds > 0 ? duration.seconds : nil
    }

    private func defaultDuration(for asset: MediaAsset) -> TimeInterval {
        if let duration = asset.duration, duration > 0 {
            return duration
        }
        return 5
    }

    private func clipKind(for mediaKind: MediaKind) -> ClipKind {
        switch mediaKind {
        case .video: .video
        case .audio: .audio
        case .image: .image
        }
    }

    private func trackKind(for mediaKind: MediaKind) -> TrackKind {
        switch mediaKind {
        case .video, .image: .video
        case .audio: .audio
        }
    }

    private static func defaultProject() -> Project {
        let tracks = [
            Track(kind: .video, name: "Video", zIndex: 0),
            Track(kind: .audio, name: "Audio", zIndex: 1),
            Track(kind: .text, name: "Text", zIndex: 2)
        ]
        return Project(name: "Untitled Project", timeline: Timeline(tracks: tracks))
    }
}
