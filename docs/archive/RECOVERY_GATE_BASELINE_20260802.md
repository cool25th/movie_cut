# MovieCut 크래시 복구 회귀 게이트 (B-U7)

> 측정일: 2026-08-02 / 재현: `bash scripts/run_recovery_gate.sh` / 빌드: **Debug**
> 목적: B-U7(크래시 후 재실행 시 작업 복구 제안) 회귀 게이트. 종전엔 복구 *시맨틱*이 단위 테스트(`AutosaveRecoveryTests`, ProjectStore actor 수준)로만 검증됐고, 복구 *플로우*(`recoverableProject` → `adoptRecoveredProject`/`clearRecoveryAutosave`)는 자동 검증이 없었다.

## 배경 (조사로 확보한 구조적 장벽)

복구 alert는 `ContentView.swift`의 `presentRecoveryIfNeeded()` — 앱 시작 시 `.task`에서 한 번 실행. 세 가지 장벽이 자동 검증을 막았다:
1. **접근성 식별자 없음** — 복구 NSAlert와 "Recover"/"Discard" 버튼에 식별자가 없어 XCUITest가 못 찾음.
2. **`MOVIECUT_UITEST=1` 게이트가 alert 스킵** — harness 자동화가 alert를 우회하도록 의도됨.
3. **정상 종료가 recovery 파일 삭제** — `willTerminateNotification` 핸들러가 `clearRecoveryAutosave()`.

이 프로젝트는 모달 alert의 접근성 핸드셰이크가 XCUITest 하에서 불안정해(`UnsavedChangesGuardUITests.swift:73-77` 문서화) alert 직접 탭을 피한다. 대신 `confirmDiscardUnsavedChanges`(`EditorViewModel.swift:1010-1030`)의 **검증된 주입 패턴**(`MOVIECUT_UITEST_UNSAVED_RESPONSE`로 응답 주입 + 결과 파일로 단언)을 채택해 왔다.

## 접근법: 응답 주입 패턴 복제

B-U7은 이 주입 패턴을 충실히 복제한다:

- **`MOVIECUT_UITEST_RECOVERY=1`** — `presentRecoveryIfNeeded()`가 게이트를 우회하고 주입 경로로 진입. alert를 띄우지 않고, `MOVIECUT_UITEST_RECOVERY_RESPONSE=recover|discard`를 읽어 해당 동작을 직접 실행.
- **harness 시나리오 `runRecoveryUITestScenario`** — fixture import → 편집 → `flushAutosave()`로 recovery 파일 생성 → 세션 리셋 → recover/discard 실행 → 결과 보고.
- **`MOVIECUT_UITEST_SKIP_RECOVERY_CLEAR=1`** — 종료 시 recovery 파일 삭제를 스킵. 정상 종료 후에도 recovery 파일이 잔존하게 해, 미래 XCUITest 2-launch 경로(강제 kill 후 재시작)가 같은 파일을 재사용할 수 있게 함.

단일 프로세스 시뮬레이션: recovery 파일을 쓰고 같은 launch 안에서 다시 읽으므로 SIGKILL/relaunch 불필요. 핵심 로직(`recoverableProject` → `adoptRecoveredProject`)을 직접 검증한다.

## 결과

재현: `bash scripts/run_recovery_gate.sh`

```
=== recovery gate (B-U7) ===

recover    status=PASS recovered_clips=1
discard    status=PASS recovered_clips=0

=> PASS: recover + discard both behaved correctly
```

| 경로 | 기대 | 결과 |
|---|---|---|
| recover | recovered_clips≥1, status="Recovered unsaved work." | ✅ recovered_clips=1 |
| discard | recovered_clips=0, status="discarded" | ✅ recovered_clips=0 |

- **recover**: 편집→flush 로 만든 recovery 파일을 읽어 `adoptRecoveredProject`가 실행됐고, 복구된 프로젝트의 클립(1개)이 타임라인에 복원됨.
- **discard**: `clearRecoveryAutosave()`가 실행돼 recovery 파일이 삭제됐고, 복구된 클립 없이 fresh 세션 유지.

## 해석

- **B-U7 회귀 게이트 확립.** 복구 플로우의 두 분기(recover/discard)가 자동 검증된다. 단위 테스트(`AutosaveRecoveryTests`)가 ProjectStore actor 수준의 시맨틱을, 이 게이트가 EditorViewModel 수준의 플로우를 각각 커버.
- **검증된 패턴 재사용.** `confirmDiscardUnsavedChanges`의 주입 패턴을 복제했으므로, 모달 alert 불안정성에 영향받지 않는다. 접근성 식별자 추가는 이 방식에선 불필요(주입 경로가 alert를 건너뛰므로).
- **terminate-clear 게이트**(`MOVIECUT_UITEST_SKIP_RECOVERY_CLEAR`)는 `run_e2e_export.sh`의 sandbox 모드(`SANDBOX=1`) autosave 섹션(현재 SKIP)을 미래에 활성화할 수도 있는 인프라. 현재 게이트에선 단일 프로세스라 불필요하지만, 별도 비용 없이 추가됐다.

## 한계

1. **단일 프로세스 시뮬레이션.** recovery 파일을 쓰고 같은 launch에서 다시 읽는다. 실제 "프로세스 크래시 → 재시작 → 복구 제안" 흐름(별도 프로세스 경계)은 아니다. 핵심 로직은 동일하지만, "다음 launch에서 `presentRecoveryIfNeeded`가 파일을 발견해 alert를 띄운다"는 엔드투엔드는 별도 XCUITest 2-launch 경로가 필요.
2. **실제 SIGKILL 미사용.** terminate-clear 게이트로 정상 종료 후에도 파일이 잔존하게 했지만, 진짜 크래시(SIGKILL, segfault) 시나리오는 아니다. SIGKILL은 `willTerminateNotification`를 안 발생시키므로 terminate-clear 게이트 없이도 파일이 잔존하지만, 이 게이트는 정상 종료 경로에서 파일을 보존하는 다른 목적.
3. **접근성 식별자 미추가.** 주입 방식이므로 복구 alert에 식별자가 없어도 테스트가 동작한다. 실제 사용자용 접근성(VoiceOver 등) 개선이 필요하면 별도로 식별자를 추가할 수 있으나, B-U7 회귀 게이트 범위는 아니다.
4. **복구된 클립의 내용 검증은 클립 수만.** 클립의 텍스트/시간범위가 정확히 복원됐는지는 단위 테스트가 커버; 이 게이트는 "클립이 복원됐는지(수)"만 확인.

## 향후: 엔드투엔드 2-launch XCUITest

완전한 B-U7(강제 kill → 재시작 → 복구 alert 표시 → 탭 → 복원)을 원하면:
1. 첫 launch: `MOVIECUT_AUTOSAVE_DIR` 격리 + `MOVIECUT_UITEST_SKIP_RECOVERY_CLEAR=1`로 편집 후 종료 → recovery 파일 잔존.
2. 두 번째 launch: 게이트 없이(ungated) 시작 → `presentRecoveryIfNeeded`가 파일 발견 → alert 표시.
3. XCUITest가 alert를 탭(식별자 추가 필요)하고 `moviecut.status`가 "Recovered unsaved work."가 되는지 확인.

이 경로는 alert 직접 조작의 불안정성(위 배경 §1) 때문에 현재 주입 방식을 우선한다. 2-launch 경로는 후속 작업.
