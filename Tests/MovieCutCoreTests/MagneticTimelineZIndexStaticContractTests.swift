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

    @Test("Command support exposes magnetic compaction and track snapshot restore")
    func commandSupportExposesMagneticCompactionAndSnapshotRestore() throws {
        let source = try source("Sources/MovieCutCore/Commands/CommandSupport.swift")

        #expect(source.contains("compactClipsMagnetically"))
        #expect(source.contains("normalizeClipZIndexes"))
        #expect(source.contains("RestoreTrackClipsCommand"))
    }

    @Test("Delete command preserves gaps (no compaction) and normalizes clip zIndex")
    func deleteCommandPreservesGapsAndNormalizesClipZIndex() throws {
        // Step 2 of the core-editing repair handoff: normal Delete preserves
        // gaps — it no longer calls compactTrackMagnetically. Only zIndexes are
        // normalized. Ripple Delete is the separate gap-closing variant.
        let source = try source("Sources/MovieCutCore/Commands/DeleteClipCommand.swift")

        #expect(!source.contains("project.compactTrackMagnetically(removed.trackId)"))
        #expect(source.contains("project.normalizeClipZIndexes(in: removed.trackId)"))
        #expect(source.contains("RestoreTrackClipsCommand.snapshotKey(for: removed.trackId)"))
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

    @Test("Docs mark magnetic timeline and clip zIndex complete and advance next P1")
    func docsMarkMagneticTimelineAndClipZIndexCompleteAndAdvanceNextP1() throws {
        let backlog = try source("docs/CAPCUT_FEATURE_BACKLOG.md")
        let handoff = try source("docs/SESSION_HANDOFF.md")

        #expect(backlog.contains("- [x] ✅ 마그네틱 타임라인(자동 밀착) (P1)"))
        #expect(backlog.contains("Add/Move/Duplicate/Delete command path"))
        #expect(backlog.contains("Add/Move/Duplicate/Delete 후 same-track magnetic packing"))
        #expect(backlog.contains("same-track magnetic packing"))
        #expect(backlog.contains("- [x] ✅ 멀티트랙 레이어링 + 클립별 zIndex (P1)"))
        #expect(backlog.contains("persisted `Clip.zIndex`"))
        #expect(backlog.contains("TimelineView display ordering/layer actions"))
        #expect(backlog.contains("Caveat: 클립 그룹/링크는 P2 별도 항목으로 남긴다."))
        #expect(backlog.contains("다음 1순위는 F-01 실기기 검증"))

        #expect(handoff.contains("| 완료 | ✅ **F-06 임포트 메타데이터**"))
        #expect(handoff.contains("| 1 | **F-01 실기기 검증**"))
        #expect(handoff.contains("| 완료 | ✅ **마그네틱 타임라인 / 클립별 zIndex**"))
        #expect(!handoff.contains("| 1 | **마그네틱 타임라인 / 클립별 zIndex**"))
    }
}
