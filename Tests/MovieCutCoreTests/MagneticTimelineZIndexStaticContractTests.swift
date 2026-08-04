import Foundation
import Testing

/// The magnetic timeline and clip-level layer controls span Core commands and
/// the macOS timeline. These source-level checks keep that P1 contract visible
/// in SwiftPM's faster static loop.
@Suite("Magnetic Timeline ZIndex StaticContract")
struct MagneticTimelineZIndexStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("Timeline display uses clip zIndex ordering and layer actions")
    func timelineDisplayUsesClipZIndexOrderingAndLayerActions() throws {
        let source = try source("App/MovieCutMac/TimelineView.swift")

        #expect(source.contains("ForEach(clipsForDisplay(track))"))
        #expect(source.contains(".zIndex(Double(clip.zIndex)"))
        #expect(source.contains("layer %d"))
        #expect(source.contains("zIndex"))
        #expect(source.contains("Button(\"Bring to Front\")"))
        #expect(source.contains("Button(\"Send to Back\")"))
    }

    @Test("Command support exposes magnetic compaction and clip normalization")
    func commandSupportExposesMagneticCompactionAndClipNormalization() throws {
        let source = try source("Sources/MovieCutCore/Commands/CommandSupport.swift")

        #expect(source.contains("compactClipsMagnetically"))
        #expect(source.contains("normalizeClipZIndexes"))
    }

    @Test("Delete command preserves gaps (no compaction) and normalizes clip zIndex")
    func deleteCommandPreservesGapsAndNormalizesClipZIndex() throws {
        // Step 2 of the core-editing repair handoff: normal Delete preserves
        // gaps — it no longer calls compactTrackMagnetically. Only zIndexes are
        // normalized. Ripple Delete is the separate gap-closing variant.
        let source = try source("Sources/MovieCutCore/Commands/DeleteClipCommand.swift")

        #expect(!source.contains("project.compactTrackMagnetically(removed.trackId)"))
        #expect(source.contains("project.normalizeClipZIndexes(in: removed.trackId)"))
    }

    @Test("Magnetic compaction is scoped to the main video track via derived policy")
    func magneticCompactionScopedToMainVideoTrack() throws {
        // Step 2: Add/Move/Duplicate gate compaction on isMagneticTrack, and
        // the derived policy helper lives in CommandSupport.
        let commandSupport = try source("Sources/MovieCutCore/Commands/CommandSupport.swift")
        #expect(commandSupport.contains("func mainVideoTrackId() -> UUID?"))
        #expect(commandSupport.contains("func isMagneticTrack(_ trackId: UUID) -> Bool"))

        let addCommand = try source("Sources/MovieCutCore/Commands/AddClipCommand.swift")
        #expect(addCommand.contains("if project.isMagneticTrack(trackId)"))

        let moveCommand = try source("Sources/MovieCutCore/Commands/MoveClipCommand.swift")
        #expect(moveCommand.contains("if project.isMagneticTrack(currentTrackId)"))

        let duplicateCommand = try source("Sources/MovieCutCore/Commands/DuplicateClipCommand.swift")
        #expect(duplicateCommand.contains("if project.isMagneticTrack(trackId)"))
    }

    @Test("Clip coding defaults legacy zIndex and persists zIndex")
    func clipCodingDefaultsLegacyZIndexAndPersistsZIndex() throws {
        let source = try source("Sources/MovieCutCore/Models/Clip.swift")

        #expect(source.contains("zIndex = try container.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0"))
        #expect(source.contains("try container.encode(zIndex, forKey: .zIndex)"))
    }
}
