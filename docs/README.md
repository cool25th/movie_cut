# MovieCut 문서 인덱스 및 개발 가이드 (Documentation Map)

> **최종 갱신:** 2026-08-22 (문서 체계 정리 — 경쟁 분석 통합·구문서 9종 archive)  
> **목적:** MovieCut 프로젝트의 아키텍처, 요구사항, 검증기준, 방향, 경쟁 분석을 한눈에 파악할 수 있는 단일 진입점 문서 지도입니다.

---

## 1. 핵심 현역 문서 (Core Living Documents)

개발, 검증, 설계 시 가장 먼저 참조해야 하는 문서입니다:

| 문서 | 설명 | 바로가기 |
|---|---|---|
| 🧭 **개발 방향 (최종 결정)** | 12개월 고정 순서·게이트·G-23~G-29·의사결정 로그. **우선순위 분쟁 시 이 문서가 이긴다** | [DEVELOPMENT_DIRECTION_20260815.md](DEVELOPMENT_DIRECTION_20260815.md) |
| 🏛️ **아키텍처 구조** | Core 모델, Command 패턴, 공유 PixelProcessor 합성 파이프라인, 오디오 렌더 그래프(G-25/26), 스토리지/스키마 체인, 플랫폼 구조 | [ARCHITECTURE.md](ARCHITECTURE.md) |
| 📋 **요구사항 원천** | 제품 요구사항 + §13 전략 전환 이력(변경 이력표로 최신 관리) | [REQUIREMENTS.md](REQUIREMENTS.md) |
| 🎯 **검증 기준 & SLO 표준** | 완료 판정 E/U/P/X/D/S, 파리티 3등급·16 시나리오, 골든 픽셀 원칙, 성능 수치 정의(RTF·seek 분해), 5단계 게이트, 경쟁 주장 수위 사다리 | [VERIFICATION_STANDARD.md](VERIFICATION_STANDARD.md) |
| 🌐 **경쟁 분석·제품 방향 (통합)** | YT Create(모바일)·CapCut·FCP 12.3(맥 설치판) 격차 분석 + 증거 원장(Part 9) + 역량 매트릭스(Part 10) + P0/P1/P2 | [COMPETITIVE_ANALYSIS_20260822.md](COMPETITIVE_ANALYSIS_20260822.md) |
| 📑 **기능 백로그 원장** | 작업 핸드오프. §0.5에 G-23~G-29 등록 상태 | [CAPCUT_FEATURE_BACKLOG.md](CAPCUT_FEATURE_BACKLOG.md) |
| 📱 **플랫폼 파리티 매트릭스** | macOS vs iOS 배선 현황 및 defer 사유 | [PLATFORM_PARITY_MATRIX.md](PLATFORM_PARITY_MATRIX.md) |

## 2. 루프 운영 문서 (세션 상태 — 자동 갱신 대상, 수동 편집 주의)

| 문서 | 설명 | 바로가기 |
|---|---|---|
| 🔁 **루프 상태** | 현재 증분·게이트 상태·대기 결정 사항(단일 진실원) | [LOOP_STATE.md](LOOP_STATE.md) |
| 🤝 **세션 핸드오프** | 콜드 스타트 세션이 읽는 상세 인계 (983줄) | [SESSION_HANDOFF_CURRENT.md](SESSION_HANDOFF_CURRENT.md) |
| 📱 **G-27 실기기 검증 가이드** | 3종 기기 러너 실행 절차(사용자 대기 중인 마지막 1단계 게이트) | [G27_DEVICE_VERIFICATION_GUIDE.md](G27_DEVICE_VERIFICATION_GUIDE.md) |
| 🤖 **에이전트 프롬프트** | 마스터/루프 프롬프트(수동 운영 도구) | [AGENT_MASTER_PROMPT_20260815.md](AGENT_MASTER_PROMPT_20260815.md) · [AGENT_LOOP_PROMPT_20260816.md](AGENT_LOOP_PROMPT_20260816.md) |

## 3. 배포·세부 참조 문서

| 문서 | 역할 및 내용 | 바로가기 |
|---|---|---|
| 🎨 **UI/UX 구조 & 디자인 규격** | Pro 다크 에디터 원칙, IA, 디자인 토큰, 단축키·제스처 맵 | [UIUX_DESIGN.md](UIUX_DESIGN.md) |
| 📊 **성능 SLO 세부 원천** | 실측 기준선·게이트 + 측정 정의(RTF·seek 분해·fixture 조건) | [PERFORMANCE_SLO.md](PERFORMANCE_SLO.md) |
| 🔊 **오디오 렌더 그래프 사양** | G-25/26 구현 사양(이행 완료 — 확장 시에만 갱신) | [AUDIO_RENDER_GRAPH_SPEC_20260817.md](AUDIO_RENDER_GRAPH_SPEC_20260817.md) |
| 🚀 **Mac App Store 출시 체크리스트** | Team ID·App Store Connect·아카이브·심사 순서 | [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) |
| 🧪 **TestFlight 베타 가이드** | 내부 테스터 시나리오 과제·정성 평가 시트 | [BETA_GUIDE.md](BETA_GUIDE.md) |

## 4. 과거 기록 보관소 (`docs/archive/`)

완료·대체된 45개 문서(구 격차 분석 V1~V13, SURPASS 스펙, 실행 계획, 검수 리뷰, 진단 프롬프트, REMAINING_TASKS 등)는 [docs/archive/](archive/)에 보관됩니다. 역사 추적 시에만 열람하세요. 2026-08-22 이전 인덱스가 가리키던 다음 문서들은 모두 archive로 이동했습니다: `REMAINING_TASKS.md`, `CAPCUT_SURPASS_SPEC_20260703.md`, `EXECUTION_PLAN_20260816.md`, `EXECUTION_PLAN_PHASE2_20260819.md`, `STATIC_CONTRACT_TRIAGE_RESULT.md`, `COMPETITIVE_GAP_ANALYSIS_20260816.md`, `MovieCut_Compositor_Validation_Prompt.md`, `UI_CAPTURE_DIAGNOSIS_PROMPT_20260817.md`, `EXTERNAL_RESEARCH_PLAN_REVIEW_20260815.md`.

## 5. 빌드 및 검증 명령 빠른 참조

```bash
# 1. 5단계 전체 검증 게이트 (Core 빌드 + 전체 테스트 + Mac 빌드 + iOS 빌드 + iOS generic)
bash scripts/verify_gate.sh

# 2. Core 렌더링 파리티 시나리오 실행 (17종, MAD ≤ 2.0 & duration 1프레임)
bash scripts/run_core_editing_parity.sh

# 3. 지연 기준선 (seek·프로젝트 열기 — 위반 차단 강제)
bash scripts/run_latency_baseline.sh

# 4. G-27 iOS 실기기 검증 러너 (가이드 참조)
bash scripts/run_g27_simulator_e2e.sh  # 시뮬레이터 E2E

# 5. Mac App Store 릴리스 빌드 & 아카이브 (Team ID 지정)
MOVIECUT_TEAM_ID=XXXXXXXXXX bash scripts/release.sh
```
