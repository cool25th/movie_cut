import Foundation

/// Imports multiple media files and places matching clips on the main video track.
public struct ImportMultipleCommand: EditorCommand, Sendable, Codable {
    /// The command identifier.
    public let id: UUID

    /// File URLs to import.
    public var urls: [URL]

    /// Creates a multi-import command.
    public init(id: UUID = UUID(), urls: [URL]) {
        self.id = id
        self.urls = urls
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        var undoValues: [String: CommandResultValue] = [:]
        var importedClipIds = Set<UUID>()
        var trackIndex = try Self.mainVideoTrackIndex(in: &project, undoValues: &undoValues)
        try project.ensureTrackIsEditable(at: trackIndex)

        var timelineStart = project.timeline.tracks[trackIndex].clips
            .map(\.timelineRange.end)
            .max() ?? 0

        for (index, url) in urls.enumerated() {
            let asset = MediaImporter.importToLibrary(url, library: &project.mediaLibrary)
            let duration = Self.clipDuration(for: asset)
            let range = TimeRange(start: timelineStart, duration: duration)
            let clip = Clip(
                assetId: asset.id,
                kind: Self.clipKind(for: asset.kind),
                sourceRange: TimeRange(start: 0, duration: duration),
                timelineRange: range
            )

            project.timeline.tracks[trackIndex].clips.append(clip)
            importedClipIds.insert(clip.id)
            undoValues[Self.assetUndoKey(for: index)] = .uuid(asset.id)
            undoValues[Self.clipUndoKey(for: index)] = .clip(clip)

            timelineStart = range.end
            trackIndex = try project.trackIndex(for: project.timeline.tracks[trackIndex].id)
        }

        project.normalizeTrackZIndexes()

        return CommandResult(
            affectedClipIds: importedClipIds,
            description: "Imported \(urls.count) media file(s)",
            undoValues: undoValues
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        var assetIds: [UUID] = []
        var clipIds: [UUID] = []

        for index in urls.indices {
            if case .uuid(let assetId)? = result.undoValues[Self.assetUndoKey(for: index)] {
                assetIds.append(assetId)
            }
            if case .clip(let clip)? = result.undoValues[Self.clipUndoKey(for: index)] {
                clipIds.append(clip.id)
            }
        }

        let createdTrackId: UUID?
        if case .uuid(let trackId)? = result.undoValues[Self.createdTrackUndoKey] {
            createdTrackId = trackId
        } else {
            createdTrackId = nil
        }

        if assetIds.isEmpty, clipIds.isEmpty {
            return NoOpCommand(description: "Missing imported media snapshots for inverse")
        }

        return RemoveImportedMediaCommand(
            assetIds: assetIds,
            clipIds: clipIds,
            createdTrackId: createdTrackId
        )
    }

    private static let defaultImportedClipDuration: TimeInterval = 5
    private static let createdTrackUndoKey = "createdTrackId"

    private static func assetUndoKey(for index: Int) -> String {
        "assetId:\(index)"
    }

    private static func clipUndoKey(for index: Int) -> String {
        "clip:\(index)"
    }

    private static func mainVideoTrackIndex(
        in project: inout Project,
        undoValues: inout [String: CommandResultValue]
    ) throws -> Int {
        if let index = project.timeline.tracks.firstIndex(where: { $0.kind == .video }) {
            return index
        }

        let track = Track(
            kind: .video,
            name: "Video 1",
            zIndex: project.timeline.tracks.count
        )
        project.timeline.tracks.append(track)
        undoValues[createdTrackUndoKey] = .uuid(track.id)
        return project.timeline.tracks.index(before: project.timeline.tracks.endIndex)
    }

    private static func clipDuration(for asset: MediaAsset) -> TimeInterval {
        asset.duration ?? defaultImportedClipDuration
    }

    private static func clipKind(for mediaKind: MediaKind) -> ClipKind {
        switch mediaKind {
        case .video:
            return .video
        case .audio:
            return .audio
        case .image:
            return .image
        }
    }
}

private struct RemoveImportedMediaCommand: EditorCommand, Sendable, Codable {
    let id: UUID
    var assetIds: [UUID]
    var clipIds: [UUID]
    var createdTrackId: UUID?

    init(
        id: UUID = UUID(),
        assetIds: [UUID],
        clipIds: [UUID],
        createdTrackId: UUID?
    ) {
        self.id = id
        self.assetIds = assetIds
        self.clipIds = clipIds
        self.createdTrackId = createdTrackId
    }

    func apply(to project: inout Project) throws -> CommandResult {
        var removedClipIds = Set<UUID>()

        for clipId in clipIds {
            let removed = try project.removeClip(id: clipId)
            removedClipIds.insert(removed.clip.id)
        }

        for assetId in assetIds {
            guard project.mediaLibrary.assets.removeValue(forKey: assetId) != nil else {
                throw EditorCommandError.assetNotFound(assetId)
            }
        }

        if let createdTrackId,
           let index = project.timeline.tracks.firstIndex(where: { $0.id == createdTrackId }),
           project.timeline.tracks[index].clips.isEmpty {
            try project.ensureTrackIsEditable(at: index)
            project.timeline.tracks.remove(at: index)
        }

        project.normalizeTrackZIndexes()

        return CommandResult(
            affectedClipIds: removedClipIds,
            description: "Removed \(assetIds.count) imported media file(s)"
        )
    }

    func invert(from result: CommandResult) throws -> any EditorCommand {
        NoOpCommand(description: "Missing imported media snapshots for inverse")
    }
}
