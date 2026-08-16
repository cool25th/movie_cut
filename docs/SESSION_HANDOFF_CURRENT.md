# 세션 핸드오프 — 현재 (2026-08-16)

> 마스터 프롬프트(`AGENT_MASTER_PROMPT_20260815.md`) 프로토콜 6번의 세션 종료 산출물.
> 최신 세션이 이 파일의 최상단에 기록한다. 실행 순서의 근거는 `DEVELOPMENT_DIRECTION_20260815.md` §3·§9.

## 2026-08-16 세션 (프로토콜 0 + 증분 2개)

**게이트**: 전 증분 `verify_gate.sh` 4단계 PASS (swift build / swift test **1,143 tests / 168 suites** / xcodebuild Mac / xcodebuild iOS). 커밋 `ab35763`→`6a3845f`까지 6건, main 로컬 (미푸시).

### 완료
1. **프로토콜 0a — WIP 커밋**: `ab35763` docs 재편, `5bec84d` 컴파운드 Phase 2 + 프로 도구 V/C/Y/U, `a66dd6b` iOS 컴포지터 패리티 + 문자열 카탈로그, `eb61487` 방향 문서 채택.
2. **프로토콜 0b — §8 문서 반영**: 백로그 §0.5에 G-23~G-29 등록(G-05/G-07 재정의 포함), VERIFICATION_STANDARD §6(검증 업그레이드 6항), PERFORMANCE_SLO(Metal 트리거 7개 표, 스트레스 타임라인 T1/T2/T3, EffectCostProfile), REQUIREMENTS §13.14 + 체인지로그 + 아카이브 링크 수정.
3. **증분 1 — G-23 크롭 Inc 1** (`0c37215`):
   - `CropPixelProcessor`(Core 공유): 정규화 top-left rect → y-플립 → 픽셀 crop → 캔버스 aspect-fill 중앙 정렬. 전체 프레임은 무변경 게이트.
   - `Clip.cropRect: NormalizedRect?` (레거시 디코드 nil, 미설정 JSON 바이트 동일) + `ClipProperty.cropRect` 케이스(단일 undo).
   - 배선: `CustomCompositionClipEffect.cropRect` → Mac/iOS 컴포지터 `applyClipEffects` 크롭-퍼스트 + 양쪽 엔진 트리거에 `cropRect != nil` 추가(프리뷰=출력 동일 픽셀 경로 구조 보장).
   - UI: 인스펙터 Basic/visual 크롭 섹션 — 비율 프리셋 6종(Original/1:1/4:3/3:4/16:9/9:16), 소스 실제 픽셀 aspect 기반 중앙 크롭 계산.
   - 테스트 9개: 골든 픽셀 4(y-플립 고정, fill+센터링, no-op), 프리셋 수학 3, 명령/Codable 2.
   - **수반 수정(사전 존재 드리프트)**: 프리뷰 커스텀 컴포지터 경로가 transform/opacity/keyframes 미전달(출력만 적용) → `PlaybackClipInstructionMetadata`에 `clipTransform`/`keyframes` 추가해 폐쇄.
4. **증분 2 — 지연 측정 기반** (`6a3845f`): 하니스 `MOVIECUT_UITEST_LATENCY_BASELINE=<n>` + `scripts/run_latency_baseline.sh`(수집 게이트, `--enforce` 전환 가능). **첫 실측**: seek request p50 0.11ms / p95 0.17ms, scrub apply p50 0.07ms / p95 0.10ms, 소형 fixture 프로젝트 열기 121.6ms — PERFORMANCE_SLO.md 기록 완료.

### 발견한 함정(다음 세션 참고)
- `writeHarnessStatus`는 **truncate-write** — 하니스 결과는 마지막 한 줄만 살아남는다. 진행 체크포인트는 디버깅용이고, 최종 판정 라인이 반드시 마지막 write여야 한다.
- 하니스 시나리오는 `ContentView.task`에서 시작(홈 스테이지 아니어야 함 — 기존 게이트와 동일하게 `MOVIECUT_UITEST=1`이면 에디터로 라우팅됨). 시나리오 종료 시 `MOVIECUT_UITEST_QUIT=1` 처리를 직접 호출해야 앱이 종료된다.

### 다음 세션 인계 (우선순위 순)
1. **G-23 Inc 2**: 프리뷰 캔버스 크롭 핸들(마스크 캔버스 패턴 참조) + 파리티 시나리오 #13 `crop_rect`(하니스 `MOVIECUT_UITEST_CROP` + `run_core_editing_parity.sh` 추가) + iOS 크롭 UI 진입점.
2. **G-02 Inc5 HSL 편집 UI** 착수(1단계 최대 체감; 컬러휠/스코프 옆 8밴드 + 커브 에디터).
3. **T1/T2/T3 스트레스 타임라인 fixture** 확정 + `PERFORMANCE_SLO.md`에 p50/p95 기록.
4. lint 신규 error 0 CI 반영 + `EditorViewModel` 분해 1호 경계(timeline editing).
5. 장형(≥10분) fixture 제작 후 `run_latency_baseline.sh` 재측 — SLO "10분 프로젝트 열기 3초"의 원 의미 실측.

### 사용자 결정 대기 사항
- 없음(§7 열린 결정은 기본 채택값으로 진행 중). Track A(A-1 아이콘/A-2 App Store Connect)는 사용자 작업으로 계속 대기.
