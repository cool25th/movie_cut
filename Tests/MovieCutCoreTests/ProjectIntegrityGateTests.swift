import Foundation
import Testing
@testable import MovieCutCore

/// QAUTO-02 — 프로젝트 무결성 게이트.
///
/// 기존 `ProjectSchemaMigrationTests`가 커버하는 것(체인 도달·미래 버전
/// 거부·커밋 v1/v3 fixture 실디코드)과 상호 보완: 이 스위트는
/// ① 메인 프로젝트 파일 손상(truncate/empty)의 fail-closed,
/// ② 전 선행 버전의 실 파일 경로 save→reload round-trip,
/// ③ 마이그레이션 2회 idempotent 를 잠근다.
/// 손상 파일은 "일부 읽고 현행 스키마로 재저장"되어서는 안 되고, 그 자리에서
/// 구조화된 오류로 거부돼야 한다(요구사항: 부분 읽기 금지).
///
/// 이 스위트는 verify_gate 2단계(swift test 전체)에 편입되므로 별도
/// 드라이버 스크립트는 불필요하다.
@Suite("QAUTO-02 project integrity gate")
struct ProjectIntegrityGateTests {

    // MARK: - Helpers

    private func tempURL(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutIntegrityGateTests", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    /// v1 시절 최소 형태(JSON) — v1→v9까지 모든 필드 추가가 선택형
    /// (decodeIfPresent + 기본값)이므로, 이 형태는 모든 선행 버전의
    /// 유효한 표현이 된다. `schemaVersion`만 파라미터화한다.
    private func minimalProjectJSON(schemaVersion: Int) -> String {
        """
        {
          "id": "20000000-0000-4000-8000-000000000001",
          "name": "Integrity gate v\(schemaVersion)",
          "createdAt": "1970-01-01T00:00:00Z",
          "updatedAt": "1970-01-01T00:00:00Z",
          "appVersion": "0.1.0",
          "schemaVersion": \(schemaVersion),
          "mediaLibrary": { "assets": [] },
          "timeline": {
            "id": "20000000-0000-4000-8000-000000000002",
            "frameRate": { "numerator": 24, "denominator": 1 },
            "canvasSize": [1080, 1920],
            "aspectRatio": "portrait9x16",
            "tracks": [
              {
                "id": "20000000-0000-4000-8000-000000000003",
                "kind": "video",
                "name": "Main",
                "isMuted": false,
                "isLocked": false,
                "isHidden": false,
                "zIndex": 0,
                "clips": []
              }
            ],
            "markers": []
          },
          "markers": [],
          "canvas": { "aspectRatio": "portrait9x16", "frameRate": "fps24" },
          "exportSettings": {
            "resolution": "p1080",
            "frameRate": "fps24",
            "codec": "h264",
            "audioCodec": "aac",
            "containerFormat": "mp4",
            "quality": "high",
            "videoBitrateMbps": 10,
            "includeChapters": false,
            "includeBeatChapters": false
          }
        }
        """
    }

    // MARK: - ① 손상 fail-closed (메인 프로젝트 파일)

    @Test("A truncated project file is rejected with an error, not partially loaded")
    func truncatedFileRejected() async throws {
        let store = ProjectStore(autosaveDirectory: nil)
        let url = tempURL("truncated.moviecut")

        // 유효한 JSON의 절반만 기록 — decode는 반드시 실패해야 한다.
        let bytes = try minimalProjectJSON(schemaVersion: currentSchemaVersion).data(using: .utf8)!
        try bytes.prefix(bytes.count / 2).write(to: url, options: [.atomic])

        await #expect(throws: Error.self) {
            _ = try await store.load(from: url)
        }

        // fail-closed: 거부된 파일은 그 자리에 보존되며(재작성 없음) 내용 불변.
        let after = try Data(contentsOf: url)
        #expect(after == bytes.prefix(bytes.count / 2))
    }

    @Test("An empty project file is rejected, not treated as a fresh project")
    func emptyFileRejected() async throws {
        let store = ProjectStore(autosaveDirectory: nil)
        let url = tempURL("empty.moviecut")
        try Data().write(to: url, options: [.atomic])

        await #expect(throws: Error.self) {
            _ = try await store.load(from: url)
        }
    }

    // MARK: - ② 전 선행 버전 round-trip (실 파일 경로)

    @Test("Every prior schema version round-trips load→save→reload with equality")
    func everyPriorVersionRoundTrips() async throws {
        let store = ProjectStore(autosaveDirectory: nil)

        for version in 1..<max(1, currentSchemaVersion) {
            let url = tempURL("roundtrip_v\(version).moviecut")
            try minimalProjectJSON(schemaVersion: version).data(using: .utf8)!
                .write(to: url, options: [.atomic])

            // 로드 = 실 디코드 + 실 마이그레이션 체인
            let migrated = try await store.load(from: url)
            #expect(migrated.schemaVersion == currentSchemaVersion,
                    "v\(version) did not migrate to current")

            // 저장 후 재로드 — 같은 프로젝트가 그대로 돌아와야 한다.
            try await store.save(migrated, to: url)
            let reloaded = try await store.load(from: url)

            #expect(reloaded == migrated,
                    "v\(version) round-trip diverged after save→reload")
            #expect(reloaded.schemaVersion == currentSchemaVersion)
        }
    }

    @Test("A saved current project reloads byte-identically (stable canonical output)")
    func saveIsDeterministicAcrossReloads() async throws {
        let store = ProjectStore(autosaveDirectory: nil)
        let url = tempURL("canonical.moviecut")

        try minimalProjectJSON(schemaVersion: currentSchemaVersion).data(using: .utf8)!
            .write(to: url, options: [.atomic])
        let project = try await store.load(from: url)

        try await store.save(project, to: url)
        let first = try Data(contentsOf: url)
        try await store.save(project, to: url)
        let second = try Data(contentsOf: url)

        #expect(first == second,
                "saving the same project twice produced different bytes")
    }

    // MARK: - ③ 마이그레이션 2회 idempotent

    @Test("Migrating an already-migrated project is a no-op (idempotent)")
    func migrationIsIdempotent() async throws {
        let store = ProjectStore(autosaveDirectory: nil)
        let url = tempURL("idempotent.moviecut")
        try minimalProjectJSON(schemaVersion: 1).data(using: .utf8)!
            .write(to: url, options: [.atomic])

        var migrated = try await store.load(from: url)
        #expect(migrated.schemaVersion == currentSchemaVersion)

        // 이미 현행 버전인 프로젝트에 체인을 다시 돌려도 아무 것도 변하지 않는다.
        let before = migrated
        try ProjectMigrationRunner.migrate(&migrated)
        #expect(migrated == before,
                "second migration mutated an already-current project")
        #expect(migrated.schemaVersion == currentSchemaVersion)
    }
}
