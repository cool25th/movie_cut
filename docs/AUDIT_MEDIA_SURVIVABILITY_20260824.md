# CA-03 미디어 관리·프로젝트 생존성 감사 보고 (2026-08-24)

> **등록**: 백로그 §0.5.1 CA-03 (P0-D 신뢰성 스트림 첫 항목 — 방향 문서 §3 v1.1 반영 후 실행).
> **범위**: 재연결 · 누락 · 손상(미디어/프로젝트 JSON/출력) · 마이그레이션 실패 · 디스크 — 코드 경로 조사 + 기존 측정 증거 목록 + 갭 등록.
> **방법**: 코드 감사(`file:line` 근거) + 기존 테스트/게이트 재조사. 본 감사는 결함 **등록**까지만 (수정은 별도 증분 — 등록 BUG-01~03).

## 1. 경로별 판정

### 1.1 재연결 (relink) — 강점, 자동화 증거 없음
| 항목 | 내용 | 근거 |
|---|---|---|
| UUID 보존 재연결 | 새 위치 재프로브(메타데이터·북마크) 후 `UpdateMediaAssetCommand`로 **원 자산 UUID 그대로 갱신** — 클립 참조 생존, undo 가능 | `EditorViewModel.swift:864-897` |
| 배치 재연결 UI | `missingMediaAssets` 목록 순회 NSOpenPanel — 개별 취소/전체 취소 모두 남은 항목 유지 | `presentRelinkMissingMedia` (`EditorViewModel+Media.swift:34`) |
| 재평가 루프 | 재연결 성공마다 `reportMediaNeedingRelocation` 재실행, 전부 복구 시 "All media files are linked." | `EditorViewModel.swift:892-895` |

**갭 → BUG-03**: 재연결·누락 탐지 흐름의 자동화 증거 0 (유닛·하니스 시나리오 전무 — `Tests/`에서 `relinkMedia`/`missingMediaAssets` 참조 0건). 코드 동작은 문서화돼 있으나 회귀 잠금 없음.

### 1.2 누락 (open 시점 파일 부재) — 강점
- 북마크 재해석 실패 자산 → `missingMediaAssets` 노출 + 상태 메시지("N media file(s) can't be found…") — 침묵 스킵 없음 (`EditorViewModel.swift:825,840-850`, S2).
- 북마크 마이그레이션(v1→v2) 테스트 존재 (`SecurityScopedBookmarkMigrationTests`) — 북마크 복원 경로는 자동화됨.
- **판정: 양호** (탐지+안내 경로 완비, 마이그레이션 자동화 있음).

### 1.3 손상 — 프로젝트 JSON/출력은 견고, **미디어 파일 무검증**
| 하위 경로 | 상태 | 근거 |
|---|---|---|
| 손상된 오토토회복 파일 | **견고** — 분류·기록(`lastAutosaveLoadFailure`)·손상 파일 제거(매 실행 반부활 방지) | `ProjectStore.swift:41-62` + `AutosaveRecoveryTests` 5종(라운드트립·크래시 잔존·클린 종료·손상 보고+제거·실패 기록 해제) |
| 손상된 프로젝트 파일 열기 | **양호** — `openProject` catch → `lastErrorMessage` 표면화 | `EditorViewModel.swift:829-833` |
| 손상된 출력물 | **견고** — 실패/취소 시 부분 출력 파일 제거 + 분류된 메시지(4개 classify 지점) | `ExportEngine.swift:128-141` 외 3곳 + `FileOperationErrorTests` 9종 |
| **미디어 파일 무결성(임포트 시점)** | **갭 → BUG-02** | 아래 |
| 재생 중 디코드 실패 | 양호 — `lastCompositionError` 표면화, 스냅샷 가드 | `PlaybackEngine.swift:266,322` |

**BUG-02 상세**: `MediaImporter.probe`는 **확장자 기반 판별만** 하고 내용 검증이 없음 (`MediaImporter.swift:17-27`). ① 손상된 mp4(가비지 바이트)가 정상 임포트되어 프리뷰/출력에서야 실패 — 사용자는 임포트 성공을 믿고 편집 후 출력 단계에 폭탄. ② **알 수 없는 확장자가 조용히 `.video`로 디폴트** (`MediaImporter.swift:51-52` `return .video`) — .txt 드래그도 "비디오" 자산이 됨. 미지원 형식의 명시적 실패 금지 원칙(마스터 프롬프트) 위반 소지.

### 1.4 마이그레이션 실패 경로 — 견고
- 실패 시 `ProjectMigrationError.migrationFailed(from:to:message)` 구조화 → 열기 오류로 표면화 (`ProjectStore` 로드 → `openProject` catch).
- 미래 버전 파일 거부 `newerThanCurrent` — 업데이트 안내 메시지 + **테스트 존재** (`ProjectSchemaMigrationTests` "rejected with a structured error, not a crash").
- 체인 불완전 즉시 실패(부분 마이그레이션 로드 금지) — `ProjectMigrationRunner` + 주입 체인 테스트.
- **판정: 양호** (v1→v8 체인 + 주입 체인 + 미래 버전 거부 전부 자동화됨).

### 1.5 디스크 — 저장은 원자적, **오토토회복이 침묵**
| 하위 경로 | 상태 | 근거 |
|---|---|---|
| 프로젝트 저장 | **견고** — 임시파일 → `replaceItemAt`(원자적 교체) → 실패 시 임시파리 정리 | `ProjectStore.swift:95-105` |
| 오류 분류 | **견고** — `diskFull`·`permissionDenied`·`volumeReadOnly` 등 NSFileWriteErrorCode 매핑 | `FileOperationError.swift:16-71` + 테스트 9종 |
| 출력 부분파일 | 견고 (1.3 표) | 상동 |
| **오토토회복 저장 실패** | **갭 → BUG-01** | 아래 |

**BUG-01 상세**: 오토토회복 호출부가 **`try?`로 오류를 전부 삼킴** (`EditorViewModel.swift:217` `Task { try? await projectStore.saveAutosave(...) }`, `:223` `flushAutosave` 동일). 디스크 만료 상태에서 ① 오토토회복이 조용히 중단되고 ② 사용자는 크래시 복구가 존재한다고 믿으며 편집. 최종 저장에서야 diskFull 오류를 보지만, 직전 오토토회복 실패분(최대 수십 분 편집)은 크래시 시 **복구 불능**이다. 분류 인프라(`FileOperationError.diskFull`)가 이미 있음에도 표면화되지 않는 것은 "미지원 케이스의 조용한 품질 강등 금지" 위반.

## 2. 갭 등록 (P0 결함 — 별도 증분에서 수정)

| ID | 결함 | 심각도 | 제안 수정 |
|---|---|---|---|
| **BUG-01** | 오토토회복 저장 실패(디스크 만료 등)가 `try?`로 침묵 — 크래시 시 복구 불능 구간 발생 | P0 | `saveAutosave` 실패 분류 → 상태 표면화(경고 배너) + 재시도 백오프. 저장 자체는 비차단 유지 |
| **BUG-02** | 임포트 무결성 검증 부재 — 손상 미디어가 출력 단계에 폭발 + 알 수 없는 확장자의 조용한 `.video` 디폴트 | P0 | probe에 경량 헤더 스니프(파일 매직) 추가 + 미지원 확장자 명시적 거부. 전체 디코드 검증은 프리뷰 첫 로딩에 위임 |
| **BUG-03** | 재연결·누락 탐지 흐름 자동화 증거 0 (회귀 잠금 없음) | P0(측정) | 하니스 시나리오(누락 자산 포함 프로젝트 → 재연결 → 전체 복구 단언) + Core 단위(누락 판정 로직) |

## 3. 증거 인덱스 (기존 — 본 감사가 재확인)

- `Tests/MovieCutCoreTests/AutosaveRecoveryTests.swift` — 5종 (크래시/클린/손상 복구 파일)
- `Tests/MovieCutCoreTests/FileOperationErrorTests.swift` — 9종 (분류 매핑)
- `Tests/MovieCutCoreTests/ProjectSchemaMigrationTests.swift` — v1→v8 체인·주입 체인·미래 버전 거부
- `Tests/MovieCutCoreTests/SecurityScopedBookmarkMigrationTests.swift` — 북마크 복원
- `scripts/run_recovery_gate.sh` — 크래시 복구 E2E 게이트 (B-U7)
- `verify_gate` 5/5·1,405 테스트 @ a9103e9 (감사 시점 HEAD)
