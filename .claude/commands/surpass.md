---
description: CapCut 능가 스펙(G-ID 기능 / U-ID UI) 작업 착수 — 인자 없으면 다음 우선순위 자동 선택
argument-hint: "[G-ID | U-ID | debt | status] 예: /surpass G-02, /surpass U-08, /surpass debt"
---

# CapCut 능가 작업 세션

MovieCut의 CapCut 능가 계획을 G-ID(기능)/U-ID(UI) 단위로 실행한다. **스펙이 사실의 원천이다** — 아래 순서를 반드시 따른다.

인자: `$ARGUMENTS`

## 0. 컨텍스트 로드 (필수, 순서대로)

1. `docs/archive/CAPCUT_SURPASS_SPEC_20260703.md` — **작업 명세(데이터 모델·구현 증분·AC·검증 계획)**. §3 G-ID(기능)와 §5 U-ID(UI)가 작업 단위다.
1-b. `docs/CAPCUT_BENCHMARK_STANDARD.md` — 작업할 G/U-ID가 대응하는 **B-ID 기준 문장**을 확인. 완료 선언 = 해당 B-ID **= 이상** 도달(증거 포함)이어야 한다.
2. 최신 `docs/GAP_ANALYSIS_V*`(버전 번호 최고) — 기능+UI 통합 재감사 (권장 실행 순서 포함).
3. `docs/archive/CAPCUT_GAP_IMPROVEMENT_PLAN_20260703.md` — 기능 격차 배경.
4. `docs/CAPCUT_FEATURE_BACKLOG.md` §2.5 — 증거 기반 검증 현황 (자가보고 수치 신뢰 금지).
5. U-ID 작업 시 추가: `docs/UI_DESIGN_PRINCIPLES.md`(디자인 원칙·토큰), `docs/MOVIECUT_CAPCUT_DESIGN_GAP_AUDIT_20260619.md`(IA 계약 배경).

## 1. 인자 처리

- **`G-XX`** (예: `G-02`): 해당 기능 항목 착수. 스펙의 선행 의존(마일스톤 순서 원칙)이 미충족이면 먼저 보고하고 사용자 확인.
- **`U-XX`** (예: `U-08`): 해당 UI 항목 착수 — 스펙 §5의 UI 공통 DoD(IA 계약·토큰·U-08 캡처 증거) 적용. U-02는 G-04와, U-07은 G-07/G-08과 묶음 실행 권장(스펙 참조).
- **`debt`**: G-12 검증 부채 원장에서 미상환 항목 상위 1~2개를 골라 상환.
- **`status`**: 작업 없이 현황만 보고 — 스펙 AC의 검증 기록 줄과 git log를 대조해 G-ID/U-ID별 진행 상태 표 출력 후 종료.
- **(없음)**: **스펙 변경 이력의 최신 게이트 규칙을 우선 적용**(v1.6 기준: **G-15 이미지 파이프라인(실사용 P0) → U-08 → G-02 Inc 5~6(W5 완주 포함) → G-01 Inc 2~4** 순. #13/#14는 수동 검증 대기 — 자동 선택 금지)하고, 최신 `GAP_ANALYSIS_V*`의 권장 실행 순서로 완료 기록이 없는 첫 항목을 선택. 선택 근거를 한 줄로 보고 후 진행.

## 2. 콜드 스타트 체크 (작업 전 필수 — 실패 시 수리부터)

```bash
git status --short && git log --oneline -5
swift build && swift test --filter 'StaticContract|Golden'
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build
scripts/run_e2e_export.sh
```

작업 트리가 더러우면 먼저 diff를 읽고 의도 있는 변경인지 확인. E2E FAIL이면 신규 작업 금지, 회귀 수리가 우선.

## 3. 작업 규율 (스펙 §1.2 DoD + §1.3 A1~A6 요약)

- **DoD 4+1단계**: Core 테스트 → preview/export/iOS 양쪽 배선 → 실기기/E2E 확인 → 결과물 검증 → **A6: Core 서비스 신설 시 앱 호출부+E2E 훅을 같은 커밋에** (dead code 금지 — EQ·VocalSeparation 재발 방지).
- 모든 편집은 `EditorSession.dispatch(Command)` 경유. 시각 효과는 `Sources/MovieCutCore/Rendering/` shared processor + Mac/iOS compositor 위임.
- 모델 필드 추가는 Codable 하위호환(optional) + 디코딩 테스트 의무.
- static contract는 회귀 잠금 전용 — **완료 증거로 불인정**. 완료 증거는 골든/E2E 해시/ffprobe/GUI 녹화.
- 픽셀 테스트는 `GoldenPixelHarness`(software renderer, silent-skip 금지).
- `swift test` 전체 실행 금지(헤드리스 완주 곤란) — 필터 스위트 사용.
- `project.yml`에 `info:` 블록 추가 금지 (xcodegen이 hand-maintained Info.plist를 덮어씀).
- AVAudioEngine offline render 검증은 앱 컨텍스트 E2E로 (테스트 프로세스 SIGABRT 이력).

## 4. 구현 진행

선택한 G-ID의 **구현 증분(Inc) 순서대로** 진행한다. 증분 하나가 끝날 때마다:
1. 해당 증분의 테스트/검증 실행 (스펙의 "검증 계획" 참조).
2. 기능 단위 커밋 — conventional commits (`feat(moviecut): …` / `test:` / `docs:`), attribution 없음.

큰 항목(규모 L)은 한 세션에 다 못 끝내도 된다 — 증분 경계에서 멈추고 §5 마무리를 수행하면 다음 세션이 이어받는다.

## 5. 마무리 (매 세션 필수)

1. **스펙 갱신**: `archive/CAPCUT_SURPASS_SPEC_20260703.md` 해당 G-ID의 AC에 검증 결과 1줄 추가 (통과한 AC 번호 + 증거). AC를 바꿔야 했으면 스펙 수정을 먼저 커밋.
2. **백로그 갱신**: `CAPCUT_FEATURE_BACKLOG.md` 해당 항목에 ✅/🟡 + caveat 1줄.
3. 미완 증분이 있으면 스펙 해당 항목에 `[진행중] 다음 증분: Inc N, 시작점: <파일:라인>` 기록.
4. 최종 검증(빌드+필터 테스트+E2E) 재실행 후 커밋·보고. **검증 없이 완료 선언 금지.**
