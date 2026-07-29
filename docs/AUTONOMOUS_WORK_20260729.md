# 무인 자율 작업 대기열 + 로그 (2026-07-29)

> **사용자 부재중 자율 작업.** 30분 간격 cron 발화 시 이 파일을 가장 먼저 읽고,
> 다음 PENDING 항목 1개를 수행한다.
> 작업 지시서(`docs/NEXT_SESSION_WORKORDER_20260729.md`) 공통 규칙 준수.

## 동작 규칙 (매 발화마다 반드시 준수)

1. **이 파일을 먼저 읽는다.** 가장 최근 LOG ENTRY에서 어디까지 했는지 확인.
2. **다음 PENDING 항목 1개**를 선택해 수행. (여러 개 한 번에 X)
3. **별도 브랜치**에서 작업. main을 **절대** 직접 건드리지 않는다.
4. **검증 게이트**: 각 항목 작업 후 반드시 실행 (PASSED 여부):
   ```
   scripts/verify_gate.sh
   ```
   (게이트 스크립트는 추적 파일 `scripts/verify_gate.sh`. 만약 없으면 `.build-check/verify_gate.sh` 또는 아래 백업 경로 확인. 로그는 `.build-check/last_gate.log`.)
   - `GATE_PASS` → 커밋, 해당 항목을 DONE으로 표시, LOG ENTRY 추가
   - `GATE_FAIL` → 즉시 `git checkout .` / `git clean -fd`로 revert, 해당 항목을 SKIPPED(사유 기재)로 표시, LOG ENTRY 추가. **거짓으로 DONE 표시 금지.**
5. **수용 기준** (게이트 판정과 별개로 필수 확인):
   - `swift test` **984개 유지 또는 증가**. 감소면 GATE_FAIL 처리 후 조사 기록.
   - 단 W2-1(산문 단언 제거)만 예외: 테스트 수 감소가 정상.
6. **iOS는 미검증**. iOS 타입/파일은 이 큐에 넣지 않음 (규칙 7).
7. 한 발화당 항목 1개가 원칙. 시간 남으면 다음 PENDING 1개 더 가능하되, 게이트 통과한 것만 DONE.

## 안전 정책 — 무인으로 건드리지 않는 것

- ❌ `public` API (`Sources/MovieCutCore/**`의 public 타입/메서드). 외부 소비자 가능성.
- ❌ 아키텍처/동작 변경, 공개 API 변경.
- ❌ iOS 관련 전부 (이 호스트 검증 불가).
- ❌ 판단이 들어가는 작업 (W2-2 부정단언 분류, W2-3 골든 픽셀, W3 린트 정책).
- ❌ main 직접 작업 / main 직접 병합. 브랜치 + 커밋만.

---

## 작업 대기열 (QUEUE)

> 상태: `PENDING` → 수행 중 `DOING` → `DONE`/`SKIPPED`. 진행 순서대로 처리.
> 각 항목은 사전 검증(grep 0~1회 참조) 완료 상태. 진행 전 **반드시 grep을 다시 돌려 재확인**.

### Track A — internal dead code 제거 (grep 1회 자기참조 확인됨)

- [ ] **A1** `App/MovieCutMac/Analysis/AutoAssistantView.swift` (157줄, `struct AutoAssistantView`, internal). `refactor/remove-dead-autoassistantview`. 게이트 통과 시 커밋 `refactor(moviecut): remove dead AutoAssistantView`.
- [ ] **A2** `App/MovieCutMac/Effects/MaskCompositor.swift` (9줄, internal). 커밋 `refactor(moviecut): remove dead MaskCompositor wrapper`.
- [x] **A3** `App/MovieCutMac/Effects/GlitchTransitionPlugin.swift` (99줄, internal). 커밋 `refactor(moviecut): remove dead GlitchTransitionPlugin`. ✅ DONE — GATE_PASS, swift test 984 유지.
- [ ] **A4** `App/MovieCutMac/Effects/ZoomTransitionPlugin.swift` (83줄, internal). 커밋 `refactor(moviecut): remove dead ZoomTransitionPlugin`.
- [ ] **A5** `App/MovieCutMac/Effects/BuiltinTransitionPlugins.swift` (76줄 전체 dead cluster: enum + 4 private plugin class + private protocol). `registerAll` 호출 0회. 커밋 `refactor(moviecut): remove dead BuiltinTransitionPlugins cluster`.
- [ ] **A6** `App/MovieCutiOS/Views/IOSTrimHandleView.swift` (121줄, `#if os(iOS)`). ⚠️ **iOS 빌드 검증 불가** — 게이트(macOS+Core test) 통과만 확인 가능. iOS 미검증임을 LOG에 명시. 커밋 `refactor(moviecut): remove dead IOSTrimHandleView`.

### Track B — unused import 제거 (HIGH 신뢰, 1개씩 컴파일 검증)

- [ ] **B1** `Tests/MovieCutCoreTests/CriticalHighCoreTests.swift` — `import XCTest` 제거 (Swift Testing만 사용). 커밋 `chore(moviecut): drop unused XCTest import`.
- [ ] **B2** `App/MovieCutMac/Inspector/InspectorShared.swift` — `import AppKit` 제거 (SwiftUI만 사용). 커밋 `chore(moviecut): drop unused AppKit import`.
- [ ] **B3** `Sources/MovieCutCore/Models/GestureTransform.swift` — `#if canImport(UIKit)` 블록의 `import UIKit` 제거. 커밋 `chore(moviecut): drop unused UIKit import in GestureTransform`.
- [ ] **B4** `Sources/MovieCutCore/Rendering/CubeLUTParser.swift:100` — `import CoreImage` 제거 (doc comment에만 언급). 커밋 `chore(moviecut): drop unused CoreImage import in CubeLUTParser`.

### Track C — 문서 stale 참조 정리 (코드 아님, 게이트는 swift build/test로 회귀만)

- [ ] **C1** `docs/PLATFORM_PARITY_MATRIX.md:223` — `IOSPlaybackEngine (dead code)` 항목 → ✅ 제거됨(7b5b2ad)으로 갱신. 커밋 `docs: mark IOSPlaybackEngine removal in parity matrix`.
- [ ] **C2** `docs/GAP_ANALYSIS_V2.md` — `ContentView.swift` → `iOSContentView.swift` 3곳(:14,:189,:208). 커밋 `docs: fix iOSContentView path in gap analysis`.
- [ ] **C3** `docs/GAP_ANALYSIS.md` + `docs/GAP_ANALYSIS_V2.md` — 허구 타입 `NoiseReductionProcessor` → `NoiseReductionService` 5곳. 커밋 `docs: fix NoiseReductionService name in gap analyses`.

### (귀환 후 검토 — 무인 처리 제외) Track X — public API dead code

> Package.swift가 MovieCutCore를 외부 library product로 정의. public API는 외부 소비자/의도적 유지 가능성. **사용자 결정 필요**. 이 문서 하단 "귀환 후 보고" 참조.

---

## 진행 로그 (LOG)

> 최신순(위에 추가). 각 ENTRY: 타임스탬프 / 항목ID / 상태 / 게이트 결과 / 커밋해시 / 비고.

### ENTRY 0 — 2026-07-29 10:41 — 세팅 완료
- **항목**: 인프라 세팅
- **상태**: DONE
- **내용**: 보수적 정책 확정(사용자 합의). 검증 게이트 스크립트 `scripts/verify_gate.sh` 작성. 대기열 A1-A6, B1-B4, C1-C3 확정. 각 후보 grep 독립 재검증 완료(전부 자기 선언 1건뿐).
- **기준선**: main `7b5b2ad`, swift test 984/162 suites 통과.
- **비고**: public API dead code(AutoReframeCommand 외 6개)는 무인 제외, 귀환 후 보고로 분리.

<!-- 새 ENTRY를 이 줄 위에 추가 -->

### ENTRY 3 — 2026-07-29 (cron 발화) — A3 ✅ DONE
- **항목**: A3 — `App/MovieCutMac/Effects/GlitchTransitionPlugin.swift` 제거
- **상태**: DONE
- **재검증**: grep `GlitchTransitionPlugin` → 자기 선언 1건뿐 (99줄, 단일 internal class, TransitionPlugin 준수하나 등록/인스턴스화 0회)
- **게이트 결과**: GATE_PASS — swift build OK / swift test **984/162 suites passed** / xcodebuild MovieCutMac OK
- **변경**: 파일 -99줄 + pbxproj 정리(net -5)
- **비고**: Mac internal 코드. iOS 빌드 미검증이나 Mac 게이트로 검증 완료.

### ENTRY 2 — 2026-07-29 (cron 발화) — A2 ✅ DONE (별도 브랜치, main 미병합)
- **항목**: A2 — `App/MovieCutMac/Effects/MaskCompositor.swift` 제거
- **상태**: DONE (브랜치 `refactor/remove-dead-maskcompositor`, 커밋 `5d8939b`)
- **게이트 결과**: GATE_PASS — swift test 984/162 passed.

### ENTRY 1 — 2026-07-29 (cron 발화) — A1 ✅ DONE (별도 브랜치, main 미병합)
- **항목**: A1 — `App/MovieCutMac/Analysis/AutoAssistantView.swift` 제거
- **상태**: DONE (브랜치 `refactor/remove-dead-autoassistantview`, 커밋 `673b931`)
- **게이트 결과**: GATE_PASS — swift test 984/162 passed.
