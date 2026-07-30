# MovieCut 문서 지도 — 현역 / 보관 / 열린 작업

> 작성일: 2026-07-30 / 기준 커밋: `7e0c466` / 브랜치: `docs/inventory-and-requirements`
> 목적: `docs/`에 42개까지 쌓인 문서를 **현역 23 / 보관 19**로 갈라, "지금 열려 있는 작업이 무엇인가"를 한 화면에 고정한다.
> **이 문서의 성격 — 문서 상태 인덱스다.** 기능 완료 판정을 새로 내리지 않는다. 기능 판정은 §6의 원천 문서와 `gap-audit` 세션의 몫이다.
> 여기 적힌 수치는 전부 **이 문서를 쓰면서 직접 실행한 명령의 출력**이다. 다른 문서의 자가보고 수치를 옮겨 적지 않았다.

---

## 0. 이 세션에서 직접 측정한 기준선

| 검증 | 명령 | 결과 |
|------|------|------|
| Core 빌드 | `swift build` | ✅ 성공 |
| 전체 테스트 | `swift test` | ✅ **1031 tests / 167 suites 통과** |
| Mac 앱 빌드 | `xcodebuild -scheme MovieCutMac -destination 'platform=macOS'` | ✅ **BUILD SUCCEEDED** |
| iOS 앱 빌드 | `xcodebuild -scheme MovieCutiOS -destination 'generic/platform=iOS'` | ❌ **불가** — 아래 주의 |
| 린트 | `swiftlint lint --quiet` | ⚠️ 1,016건 (CI 비블로킹) |
| StaticContract 부채 | `grep -rl StaticContract Tests` | ⚠️ **85 / 143 파일**(59%), 부정 단언 224건, `docs/` 산문을 단언하는 파일 38개 |

위 세 빌드/테스트는 `scripts/verify_gate.sh`의 3단계와 동일하며, 이 문서 작성 브랜치에서 전부 통과했다. **문서 38개가 테스트에 산문으로 묶여 있으므로, 이번 문서 재배치가 테스트를 깨지 않았음을 이 실행으로 확인했다.**

### iOS 빌드 차단의 정확한 성격 (2026-07-30 재확인 — 기존 문서보다 정밀함)

기존 문서들은 "iOS 26.5 미설치"라고만 적었으나, 실제로는 **SDK는 있고 플랫폼 컴포넌트가 없다**:

```
$ xcodebuild -showsdks
iOS SDKs:  iOS 26.5  -sdk iphoneos26.5          ← SDK는 존재
$ xcrun simctl list runtimes
== Runtimes ==                                   ← 런타임 0개
$ xcodebuild -scheme MovieCutiOS -destination 'generic/platform=iOS' build
error: Unable to find a destination matching the provided destination specifier
  Ineligible: { platform:iOS, name:Any iOS Device,
                error:iOS 26.5 is not installed. Please download and install
                the platform from Xcode > Settings > Components. }
```

→ **사용자 조치 필요**: Xcode > Settings > Components에서 iOS 26.5 플랫폼 설치. 이것이 아래 W4~W7과 R4를 막고 있는 단일 차단점이다.

---

## 1. 역할별 시작점 (콜드 스타트 3줄)

| 하려는 일 | 먼저 읽을 문서 |
|---|---|
| 기능·UI 개발 (G-ID / U-ID) | [CAPCUT_SURPASS_SPEC_20260703.md](CAPCUT_SURPASS_SPEC_20260703.md) — 사실의 원천 → 판정 기준은 [CAPCUT_BENCHMARK_STANDARD.md](CAPCUT_BENCHMARK_STANDARD.md) (B-ID) |
| App Store 출시 준비 | [PRO_SPEC_GAP_WORKORDER_20260730.md](PRO_SPEC_GAP_WORKORDER_20260730.md) Track R (S1→S2→S3 순서 고정) |
| 요구사항 확인·변경 | [REQUIREMENTS.md](REQUIREMENTS.md) — §13에 출시·품질·사용성 요구사항 추가됨 |
| 격차 재감사 | [GAP_ANALYSIS_V13_FUNC_UI_20260729.md](GAP_ANALYSIS_V13_FUNC_UI_20260729.md) (최신) + `/gap-audit` |
| 사용성 판정 | [USABILITY_BENCHMARK_STANDARD.md](USABILITY_BENCHMARK_STANDARD.md) (UB/SC-ID) + [UB_AUDIT_V1_20260714.md](UB_AUDIT_V1_20260714.md) |

---

## 2. 미완료 통합 원장 — 지금 열려 있는 것 전부

각 행의 상태는 이 세션의 grep/빌드로 확인했다. "코드 0건"은 해당 심볼이 `Sources`·`App`에 없다는 뜻이다.

### 2-A. Track R — App Store 출시 차단 (순서 의존, 반드시 이 순서)

| ID | 항목 | 상태 | 확인 근거 |
|----|------|------|----------|
| S1 | 프로젝트 스키마 마이그레이션 경로 | ✅ **완료** | `970f9f4` — `ProjectSchemaVersioning.swift`. `currentSchemaVersion = 2`, 체인에 `AddSecurityScopedBookmarkMigration` 등록됨 |
| S2 | Security-Scoped Bookmark 저장/복원 | ✅ **완료** | `a0f0807` — `App/MovieCutMac/Media/SecurityScopedAccess.swift` + `MacTests/SecurityScopedAccessTests.swift`, `MediaAsset.originalBookmark` |
| S3 | App Sandbox + entitlements | ✅ **완료** | `7e0c466` — `MovieCutMac.entitlements` / `MovieCutiOS.entitlements`. `app-sandbox` + `files.user-selected.read-write` + `files.bookmarks.app-scope` + `device.microphone`. camera·network는 의도적 제외(미사용 권한은 심사 리스크) |
| S4 | 앱 아이콘 · 번들 메타데이터 | ❌ 미착수 | `AppIcon*` / `*.appiconset` 0건 |
| S5 | 서명 · 공증 · 배포 파이프라인 | ❌ 미착수 | `.github/workflows/`에 `codesign`/`notarytool` 0건. **배포 경로 결정이 선행**(§2-B S11 표 아래) |

> **S1→S2→S3 순서 의존은 지켜졌다.** `currentSchemaVersion`이 2로 오르면서 v1→v2 마이그레이터가 같은 흐름에서 등록됐다. 순서를 어겼을 때 무슨 일이 벌어지는지 이번에 실측됐다 — 마이그레이터 없이 버전만 2로 올라간 중간 상태에서 `ProjectSchemaMigrationTests` / `AutosaveRecoveryTests` / `CoreFeatureTests` **4건이 실패**했다. 앞으로 스키마 버전을 올리는 변경은 마이그레이터를 **같은 커밋에** 넣을 것.
>
> **Track R 남은 것은 S4·S5뿐이다.** 출시 차단 요소의 대부분(순서 의존 3종)이 닫혔다.

### 2-B. Track T / P / U / O / D — 병렬 가능

| ID | 항목 | 상태 | 확인 근거 |
|----|------|------|----------|
| S8 | STT 온디바이스 강제 + 폴백 고지 | ✅ **완료** | `7dffc43` — `SpeechTranscriptionProvider`가 `requiresOnDeviceRecognition` 요구 |
| S6 | 4K · 열 · 메모리 실측 | 🔵 **진행 중 (다른 세션)** | 2026-07-30 공유 작업트리에 미커밋 `scripts/perf_4k.sh` + `UITestHarness.swift` 변경 존재. **착수 전 충돌 확인 필수.** Metal 재검토 결정의 입력 |
| S7 | thermalState 기반 프록시 자동 강등 | ❌ 미착수 | `thermalState` 코드 0건 |
| S9 | J/K/L · 툴 모드 · slip/slide · Cmd+스크롤 줌 | ❌ 미착수 | `toolMode`/`slipClip`/`slideClip` 코드 0건 |
| S10 | OSLog · MetricKit 최소 도입 | ❌ 미착수 | `import OSLog`/`import MetricKit` 0건 |
| S11 | 캡처 입력 (카메라/화면녹화/Continuity) | ⚪ **결정 대기** | `AVCaptureSession`/`ScreenCaptureKit` 0건. 착수 전 사용자 결정 필요 |

### 2-C. Track 1 — 지금 착수 가능 (iOS 무관)

| ID | 항목 | 상태 | 확인 근거 |
|----|------|------|----------|
| W2 | StaticContract 부채 정리 | ❌ 미착수 | 85/143 파일, 부정 단언 224건. 방침은 [STATIC_CONTRACT_TRIAGE_20260728.md](STATIC_CONTRACT_TRIAGE_20260728.md) |
| W3 | SwiftLint 베이스라인 확립 | ❌ 미착수 | 1,016건, CI 비블로킹 |

### 2-D. Track 2 — iOS 플랫폼 설치 후 (전부 §0 차단점에 막힘)

| ID | 항목 | 상태 |
|----|------|------|
| W4 | iOS 테스트 인프라 구축 (W5~W7 선행 조건) | 🚫 차단 |
| W5 | chroma / background-removal shared processor 전환 | 🚫 차단 |
| W6 | two-source transition iOS 배선 | 🚫 차단 |
| W7 | harness 완주 시나리오 + parity 전체 실행 | 🚫 차단 (일부는 iOS 무관 — 아래) |
| R4 | iOS 현지화 카탈로그 부재 | 🚫 차단 — `App/MovieCutiOS/*.xcstrings` 0건 (Mac만 존재) |

**W7 중 iOS와 무관한 부분은 지금 가능하다**: harness 훅이 없는 5종 — `sticker at 5s`, `trim`, `undo`(parity 경로), `play`, `preview vs export duration 비교`.

### 2-E. V13이 확정한 격차 (기능)

| 항목 | 상태 | 비고 |
|------|------|------|
| G-23 클립 블렌딩 모드 | ❌ 미착수 | 확정 격차, 규모 S |
| G-24 컴파운드 클립 (중첩 시퀀스) | ❌ 미착수 | 확정 격차, 규모 L |
| 미배선 Core 서브시스템 | ❌ 미배선 | App 호출 0회. 예: `CollaborationService` — `grep -rl CollaborationService App` → 0개 파일 |
| `=` 판정 재확인 부채 | ⚠️ 열림 | 7/28에 "메인 Preview가 프로젝트 합성을 쓰지 않고 있었다"가 드러남 → `=` 판정 B-ID는 preview+export 동시 증거로 재확인 필요 |

**G-01~G-22 / U-01~U-10의 개별 완료 여부는 이 문서가 판정하지 않는다.** 스펙의 AC 밑 검증 기록 줄과 `git log`를 대조하는 것이 규약이며, 표기가 항목마다 일관되지 않아 신뢰할 수 있는 롤업을 만들 수 없었다. 필요하면 `/gap-audit`를 돌릴 것.

---

## 3. 완료된 것 (보관 근거)

| 작업 묶음 | 근거 |
|---|---|
| 핵심 편집 경로 수리 Step 1~7 | `4088ee2` 병합. 메인 Preview가 프로젝트 합성 경로를 쓰도록 복구 |
| 신뢰성 수리 Task A~G | 전부 커밋. `swift test` 행(hang) + 3건 실패 해소 |
| 무인 자율 큐 Track A/B/C | 13/13 소진 (QUEUE EMPTY) |
| Track X — public API dead code | `3c438aa` — 6종 삭제, Core 816줄 감소 |
| W1 — IOSPlaybackEngine dead code 제거 | `7b5b2ad` |
| R1 카라오케 공백 유실 / R2 검증 공백 | `6cdcee6` — 픽셀 동일성 회귀 테스트 2건 추가로 R2도 함께 닫힘 |
| R3 영어 로케일 접근성 레이블 | `75b6421` |
| R5 프록시 배지 + 해상도 선택 (B-I7 완결) | `f64fb45`, `d8bfc8c` |
| 역재생 클립 분할/트림 + parity 게이트 | `d8fac5e`, `0d188c0` |
| UI IA 재배치 + P0/P1/P2 폴리시 | `060b0e5`, `05ca9a5`, `a2b86a0` |
| **Track R 순서 의존 3종** — S1 스키마 마이그레이션 → S2 bookmark → S3 App Sandbox | `970f9f4` → `a0f0807` → `7e0c466` |
| S8 온디바이스 STT 강제 | `7dffc43` |

---

## 4. 현역 문서 (23개)

### 4-A. 사실의 원천 · 기준서 (상시 유지)

| 문서 | 역할 |
|---|---|
| [REQUIREMENTS.md](REQUIREMENTS.md) | 제품 요구사항. 범위·품질·출시 기준의 원천 |
| [CAPCUT_SURPASS_SPEC_20260703.md](CAPCUT_SURPASS_SPEC_20260703.md) | 개발 단위 명세 (G-ID 기능 / U-ID UI). **작업은 이 문서 단위로** |
| [CAPCUT_BENCHMARK_STANDARD.md](CAPCUT_BENCHMARK_STANDARD.md) | CapCut 대비 판정 기준 (B-ID). 완료 선언 = `=` 이상 + 증거 |
| [USABILITY_BENCHMARK_STANDARD.md](USABILITY_BENCHMARK_STANDARD.md) | 사용성 판정 기준 (UB/SC-ID). 2축: 영상편집(CapCut) + 카드뉴스(미리캔버스) |
| [UI_DESIGN_PRINCIPLES.md](UI_DESIGN_PRINCIPLES.md) | 디자인 원칙·토큰. "CapCut 유사도" 지표 폐기 근거 |
| [PERF_BASELINE_20260622.md](PERF_BASELINE_20260622.md) | 성능 베이스라인. 조건부 Metal 결정의 측정 근거 |
| [MOVIECUT_PRO_ROADMAP_20260622.md](MOVIECUT_PRO_ROADMAP_20260622.md) | 전략 전환 기록 (파리티 → Pro 능가) |
| [PLATFORM_PARITY_MATRIX.md](PLATFORM_PARITY_MATRIX.md) | Mac ↔ iOS 파리티 원장 + defer 사유 |
| [CAPCUT_FEATURE_BACKLOG.md](CAPCUT_FEATURE_BACKLOG.md) | 기능 원장 + §2.5 증거 기반 검증 현황 |
| [UI_METRICS.md](UI_METRICS.md) | UI 회귀 증거 인프라 (골든 캡처/회귀 스크립트) |
| [MOVIECUT_CAPCUT_DESIGN_GAP_AUDIT_20260619.md](MOVIECUT_CAPCUT_DESIGN_GAP_AUDIT_20260619.md) | IA 계약 배경. U-ID 작업 시 참조 |

### 4-B. 현역 작업지시서 (열린 항목 있음 → §2)

| 문서 | 열린 항목 |
|---|---|
| [PRO_SPEC_GAP_WORKORDER_20260730.md](PRO_SPEC_GAP_WORKORDER_20260730.md) | S2~S7, S9~S11 (S1·S8 완료) |
| [NEXT_SESSION_WORKORDER_20260729.md](NEXT_SESSION_WORKORDER_20260729.md) | W2~W7 (W1 완료) |
| [REVIEW_FINDINGS_WORKORDER_20260729.md](REVIEW_FINDINGS_WORKORDER_20260729.md) | R4만 남음 (R1·R2·R3·R5 완료) |
| [STATIC_CONTRACT_TRIAGE_20260728.md](STATIC_CONTRACT_TRIAGE_20260728.md) | W2 실행 방침 (미착수) |
| [GAP_ANALYSIS_V13_FUNC_UI_20260729.md](GAP_ANALYSIS_V13_FUNC_UI_20260729.md) | 최신 격차 분석 — G-23/G-24, 배선 격차 |
| [UB_AUDIT_V1_20260714.md](UB_AUDIT_V1_20260714.md) | 사용성 감사 베이스라인 (후속 감사 없음) |

### 4-C. 완료·대체됐지만 이동하지 않은 문서 (6개)

StaticContract 테스트가 이 경로들을 `source("docs/…")`로 직접 읽는다. 경로를 바꾸면 테스트가 깨지므로 제자리에 두고 **상단에 상태 배너**를 붙였다. W2에서 해당 테스트를 정리한 뒤 `archive/`로 옮길 것.

| 문서 | 상태 | 테스트 참조 |
|---|---|---|
| [CAPCUT_UI_SHOWCASE_HANDOFF.md](CAPCUT_UI_SHOWCASE_HANDOFF.md) | 완료 (IA + P0~P2) | 21회 |
| [CAPCUT_UI_PARITY_REQUIREMENTS.md](CAPCUT_UI_PARITY_REQUIREMENTS.md) | 대체됨 (유사도 지표 폐기) | 19회 |
| [CAPCUT_CORE_EDITING_REPAIR_HANDOFF_20260727.md](CAPCUT_CORE_EDITING_REPAIR_HANDOFF_20260727.md) | 완료 (Step 1~7) | 7회 |
| [SESSION_HANDOFF.md](SESSION_HANDOFF.md) | 대체됨 (2026-06-11) | 5회 |
| [UIUX_HANDOFF.md](UIUX_HANDOFF.md) | 완료 (IA/폴리시) | 4회 |
| [CAPCUT_PARITY_SPEC.md](CAPCUT_PARITY_SPEC.md) | 대체됨 (SURPASS_SPEC이 계승) | 2회 |

---

## 5. 보관 문서 (19개) — `docs/archive/`

현역이 아니며 갱신되지 않는다. 각 파일 상단에 보관 사유 배너가 있다.

| 문서 | 보관 사유 |
|---|---|
| `archive/GAP_ANALYSIS.md` | **⚠️ 88/88 100% 완료로 적혀 있으나 사실이 아니다.** 파일 존재만으로 판정 |
| `archive/GAP_ANALYSIS_V2.md` | **⚠️ 72/72 100% 완료로 적혀 있으나 사실이 아니다** |
| `archive/GAP_ANALYSIS_V3.md` ~ `V6.md` | 지정 3~10개 파일만 읽은 제한 범위 감사 |
| `archive/GAP_ANALYSIS_V7~V12` | V13이 대체한 기능+UI 재감사 6종 |
| `archive/CAPCUT_GAP_IMPROVEMENT_PLAN_20260703.md` | V13이 판정을 정정 |
| `archive/AGENT_HANDOFF_PROMPT.md` | `.claude/commands/{surpass,gap-audit}.md`가 현행본 |
| `archive/CORE_REPAIR_FOLLOWUP_WORKORDER_20260728.md` | Task A/C/D/E가 W4~W7로 이관 |
| `archive/RELIABILITY_REPAIR_WORKORDER_20260728.md` | Task A~G 완료 |
| `archive/AUTONOMOUS_WORK_20260729.md` | 큐 13/13 소진. **단 §안전 정책은 계속 유효** |
| `archive/AUTONOMOUS_PUBLIC_API_DEADCODE_20260729.md` | `3c438aa`로 삭제 완료 |
| `archive/REVERSE_EDITING_PARITY_FIX_20260729.md` | 완료 기록 |

---

## 6. 판정 규율 (모든 세션 공통)

이 규율은 반복된 실패에서 나왔다. 어기면 문서가 다시 못 믿을 것이 된다.

1. **코드 존재는 완료 증거가 아니다.** 완료 = preview + export에 반영 + 증거(E2E 로그·골든 해시·ffprobe·캡처).
2. **StaticContract(소스 문자열 존재 검사)로 DoD를 대체 금지.** 현재 테스트의 59%가 이 종류이며 동작 신호가 없다.
3. **자가보고 수치 금지.** 보고에 쓰는 모든 숫자는 그 세션에서 직접 실행한 명령의 출력이어야 한다.
4. **게이트 통과 ≠ 정확성.** R1은 `GATE_PASS` 상태에서 사용자에게 깨진 화면을 보여주고 있었다.
5. `=` 판정이 붙은 B-ID는 preview+export 동시 증거로 재확인해야 한다 (7/28 발견 근거).
6. 별도 브랜치에서 작업하고, 항목 완료 후 `scripts/verify_gate.sh`를 실행한다.

---

## 7. 주의 — 같은 작업트리에서 세션이 동시에 돌 수 있다

2026-07-30 이 문서를 쓰는 동안 **다른 Claude 세션이 같은 작업트리에서 S2·S3·S6을 구현하고 있었다.** 그 때문에 실제로 겪은 일:

- 같은 트리에서 `swift test`를 돌리면 **상대의 미완성 중간 상태를 측정한다.** 이 문서 작성 중 4건 실패를 관측했는데, 원인은 상대가 `currentSchemaVersion`을 2로 올린 직후 마이그레이터 등록 전이었던 것이다 — 내 변경과 무관했다.
- `git checkout -b` / `git stash`는 **HEAD와 미커밋 변경을 공유한다.** 상대의 작업을 쓸어갈 수 있다.

**규칙.** 문서 작업이나 긴 실험은 `git worktree`로 분리한다. 이 문서는 그렇게 만들었다:

```bash
git worktree add ../movie_cut-docs -b <branch> <base>
```

측정 수치를 기록하기 전에 `git status`로 **내가 만들지 않은 변경이 트리에 있는지** 확인할 것.

---

## 8. 이 문서의 유지 규칙

- 작업지시서의 항목이 닫히면 §2에서 §3으로 옮기고 근거 커밋을 적는다.
- 지시서의 모든 항목이 닫히면 그 문서를 `archive/`로 옮기고 상단에 배너를 붙인다.
- 새 격차 분석(V14…)이 나오면 이전 버전을 `archive/`로 옮긴다. **현역 격차 분석은 항상 1개다.**
- `archive/`의 문서는 수정하지 않는다. 틀린 내용을 발견하면 배너에 한 줄 추가한다.
