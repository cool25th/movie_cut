# CA-05 실패·복구 UX 매트릭스 (2026-08-24)

> 방향 문서 §3 v1.1 **P0-D** 세 번째 항목. 대상: 실패 시 사용자 경로 — 데이터 무손실 / 원인 표시 /
> 재시도 / 이어하기 / 임시파일 정리의 5축. 방법: 코드 실사(파일:라인 근거). 대부분의 기반은
> CA-03 감사(`AUDIT_MEDIA_SURVIVABILITY_20260824.md`)·외부 리뷰 반영(§1.8, BUG-01/02/04/05·
> BUG-IOS-01~05 수정)에서 이미 검증·보강됨 — 본 매트릭스는 그 결과를 **사용자 관점 시나리오**로
> 재편성하고 잔여 결함을 등록한다.

## 1. 매트릭스 (15 시나리오 × 5축)

범례: ✅ 충족 · ⚠️ 부분 충족(근거에 결함 등록) · — 해당 없음

| # | 시나리오 | 무손실 | 원인 표시 | 재시도 | 이어하기 | 임시파일 정리 | 근거 |
|---|---|---|---|---|---|---|---|
| 1 | 프로젝트 열기 — 파일 손상 | ✅ 원본 미변경 | ✅ | ✅ 다른 파일 | — | — | `openProject` catch → `lastErrorMessage`(`EditorViewModel.swift:829-833`) |
| 2 | 프로젝트 열기 — 미래 스키마 | ✅ | ✅ 업데이트 안내 | ✅ 앱 업데이트 후 | — | — | `ProjectMigrationError.newerThanCurrent`(`ProjectStore.swift` 로드 경로) + `ProjectSchemaMigrationTests` |
| 3 | 프로젝트 저장 — 디스크 풀/권한 | ✅ 원본 유지 | ✅ 실행 가능 문구 | ✅ | ✅ 편집 계속 | ✅ 임시파일 제거 | `saveProject` → `FileOperationError.classify`(`EditorViewModel.swift:920`), `ProjectStore.save` temp+replace(`ProjectStore.swift:85-108`) |
| 4 | 크래시 복구 파일 — 손상 (런치) | ✅ 손상 파일 제거 후 부팅 | ✅ `lastAutosaveLoadFailure` 고지 | — | — (복구 불가) | ✅ 손상 파일 제거 | `ProjectStore.loadAutosaveIfAvailable`(`ProjectStore.swift:52-68`) + `AutosaveRecoveryTests` |
| 5 | 크래시 복구 파일 — 정상 (런치, Mac) | ✅ | ✅ | — | ✅ 복구/버림 선택 | — | `recoverableProject` → recover/discard 게이트(`scripts/run_recovery_gate.sh`) |
| 6 | 오토회복 저장 — 디스크 풀 (편집 중) | ✅ 프로젝트 상태 무사 | ✅ 비차단 경고(BUG-01 수정) | ✅ 다음 커밋 시 자동 재시도 | ✅ 편집 계속 | — | `scheduleAutosave` 경고(`EditorViewModel.swift`, `AutosaveFailureSurfacingTests`). 재시도 백오프는 P2 잔여 |
| 7 | 미디어 임포트 — 손상/미지원 파일 | ✅ 라이브러리 오염 없음 | ✅ 파일별 사유(BUG-02 수정) | ✅ | — | — | `MediaImporter.validatedProbe` + `MediaImporterValidationTests` |
| 8 | 미디어 누락 — 프로젝트 열기 시점 | ✅ | ✅ 개수+재연결 안내 | ✅ | ✅ 나머지 편집 계속 | — | `reportMediaNeedingRelocation`(`EditorViewModel.swift:825,840`) |
| 9 | 미디어 누락 — 세션 중 분리 후 익스포트 | ✅ | ✅ 렌더 전 거부(BUG-04 수정) | ✅ 재연결 후 재시도 | ✅ | — | `ensureAllMediaReachableForExport`(5 진입점) + `ExportMediaPreflightTests` |
| 10 | 재연결 — 사용자 취소/실패 | ✅ 취소 시 남은 항목 유지 | ✅ | ✅ 재실행 | ✅ | — | `presentRelinkMissingMedia`(취소=전체 종료, 개별 실패=사유) + `MediaRelinkTests` |
| 11 | 익스포트 — 디스크 풀/쓰기 실패 (Mac) | ✅ | ✅ 분류 문구(BUG-05 수정) | ✅ | ✅ | ✅ 부분 출력 제거 | `ExportEngine` 4개 catch → `removePartialOutput`(`ExportEngine.swift:125-141` 등) |
| 12 | 익스포트 — 사용자 취소 (Mac) | ✅ | — (사용자 의도) | ✅ | ✅ | ✅ | 취소 → 세션 오류 → catch 경로 동일 정리 |
| 13 | 보이스오버 녹음 — 쓰기 실패 | ✅ 불완전 파일 폐기 | ✅ `writeFailed`(BUG-IOS-05 수정) | ✅ 재녹음 | — | ✅ | `VoiceoverRecorder.stopRecording` throw |
| 14 | 분석(전사·씬·하이라이트) — 실패 | ✅ 프로젝트 무사 | ✅ `lastErrorMessage`(suggestCuts는 실패 도구 목록 보고 — 이번 수정) | ✅ 버튼 재실행 | ✅ | — | `runAnalysis`(`EditorViewModel.swift:4854`), `suggestCuts` |
| 15 | 프로젝트 패키지 — 임포트/익스포트 실패 | ✅ 원본 무사·부분 패키지 제거(BUG-IOS-04 수정) | ✅ 누락 파일 목록 | ✅ | — | ✅ 부분 패키지 제거 | `ProjectPackage.PackageError.mediaCopyFailed` + 테스트 2건 |

## 2. 잔여 결함 (신규 등록)

### UX-REC-01 (P2) — iOS 익스포트 취소/실패 시 부분 출력 파일 잔존

- 위치: `IOSExportEngine.cancelExport`(`IOSExportEngine.swift:66-74`)·catch 경로 — Mac의 `removePartialOutput`(4개 지점)에 해당하는 정리가 없음. 취소/실패 시 `MovieCutiOSExports` 임시 디렉터리에 잘린 .mov 잔존.
- 완화 사실: 목적지가 임시 디렉터리(사용자 지정 경로 아님)라 심각도 P2. 수정: 취소/실패 경로에 Mac 패리티 정리 추가.

### UX-REC-02 (P2) — iOS 크래시 복구가 무음 자동 채택 (복구/버림 선택 없음)

- 위치: `IOSEditorViewModel.restoreAutosaveIfAvailable`(BUG-IOS-02 수정 때 도입) — Mac의 recover/discard 프롬프트와 달리 조용히 채택. 복구 파일이 오래된 상태면 사용자가 버릴 수단이 없음(프롬프트에서 "버림" 선택지 필요).
- 완화 사실: iOS는 매 실행 빈 프로젝트에서 시작하므로 되돌릴 "현재 작업"과 충돌하지 않음. 수정: 런치 시 복구 알림 + 버림 선택지.

### UX-REC-03 (참고) — 세션 중 보안 스코프 철회의 탐지 시점

- 스코프 상실(시스템 권한 철회)은 프로젝트 열기·익스포트 사전검사에서만 감지(재생은 오류 표면화). 실시간 재탐지는 비용 대비 효과 낮음 — 현재 패턴(열기/익스포트 게이트) 유지 결정, 재검토 사유 발생 시 등록.

## 3. 결론

- **15 시나리오 중 13개 완전 충족** — 이번 주 CA-03 감사·외부 리뷰 반영으로 무손실/원인/재시도 축이 정비됨(BUG-01/02/04/05·BUG-IOS-01~05·suggestCuts 표면화가 본 매트릭스의 전제).
- 신규 등록: UX-REC-01(P2)·UX-REC-02(P2) + 참고 1건. iOS 출력 golden 테스트(속도별 길이·프레임 해시)는 여전히 별도 잔여(§1.8 참고).
- 본 매트릭스의 재검증 시점: UX-REC-01/02 수정 시 해당 행 갱신.
