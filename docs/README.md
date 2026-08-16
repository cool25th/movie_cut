# MovieCut 문서 인덱스 및 개발 가이드 (Documentation Map)

> **최종 갱신:** 2026-08-15  
> **기준 커밋:** `494f14f` (검증 게이트 `GATE_PASS`)  
> **목적:** MovieCut 프로젝트의 아키텍처, 요구사항, 검증기준, UI/UX 구조, 남은 작업을 한눈에 파악할 수 있는 단일 진입점 문서 지도입니다.

---

## 1. 5대 핵심 현역 문서 (Core Living Documents)

개발, 검증, 설계 시 가장 먼저 참조해야 하는 5개의 현역 문서입니다:

| 문서 | 설명 | 바로가기 |
|---|---|---|
| 🏛️ **전체 아키텍처 구조** | Core 모델, Command 패턴, 공유 PixelProcessor 합성 파이프라인, 스토리지/스키마 체인, 오디오 DSP, 플랫폼 구조 | [ARCHITECTURE.md](ARCHITECTURE.md) |
| 📋 **제품 요구사항 원천** | CapCut 동등 기능 및 Pro 능가 기능, 비기능 요구사항(샌드박스, 오프라인, 성능, 접근성) | [REQUIREMENTS.md](REQUIREMENTS.md) |
| 🎯 **검증 기준 & SLO 표준** | 렌더링 파리티 판정 기준(MAD ≤ 2.0, duration 일치), 골든 픽셀 원칙, 성능 SLO, 4단계 검증 게이트 | [VERIFICATION_STANDARD.md](VERIFICATION_STANDARD.md) |
| 🎨 **UI/UX 구조 & 디자인 규격** | Pro 다크 에디터 원칙, 정보 구조(IA), 디자인 토큰(`MovieCutTheme`), 키보드 단축키 및 제스처 맵 | [UIUX_DESIGN.md](UIUX_DESIGN.md) |
| 📌 **남은 작업 & 로드맵** | Track A(스토어 출시), Track B(iOS 파리티), Track C(컴파운드 Inc 2/고급 편집), Track D(테스트 부채) 잔여 원장 | [REMAINING_TASKS.md](REMAINING_TASKS.md) |

---

## 2. 배포, 릴리스 및 세부 참조 문서

| 문서 | 역할 및 내용 | 바로가기 |
|---|---|---|
| 🚀 **Mac App Store 출시 체크리스트** | Apple Developer Team ID, App Store Connect 등록, 아카이브, 심사 제출 순서 가이드 | [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) |
| 🧪 **TestFlight 베타 가이드** | 내부 테스터 6단계 시나리오 과제 및 정성 평가 시트 | [BETA_GUIDE.md](BETA_GUIDE.md) |
| 📊 **성능 SLO 세부 원천** | 실측 성능 베이스라인, 메모리/4K 인코딩 배수, OSLog Signpost 계측 항목 | [PERFORMANCE_SLO.md](PERFORMANCE_SLO.md) |
| 📱 **플랫폼 파리티 매트릭스** | macOS vs iOS 지원 현황 및 차이점 관리 매트릭스 | [PLATFORM_PARITY_MATRIX.md](PLATFORM_PARITY_MATRIX.md) |
| 📑 **기능 백로그 원장** | 전체 기능 목록 및 마일스톤 관리 | [CAPCUT_FEATURE_BACKLOG.md](CAPCUT_FEATURE_BACKLOG.md) |
| 🔍 **StaticContract 분류 현황** | 소스 문자열 검사 분류 및 동작 테스트 전환 대상 목록 | [STATIC_CONTRACT_TRIAGE_RESULT.md](STATIC_CONTRACT_TRIAGE_RESULT.md) |
| 📐 **기능 개발 세부 명세** | G-ID(기능) / U-ID(UI) 개발 단위 상세 명세 | [CAPCUT_SURPASS_SPEC_20260703.md](CAPCUT_SURPASS_SPEC_20260703.md) |

---

## 3. 과거 기록 보관소 (`docs/archive/`)

완료되었거나 최신 스펙/원장으로 통합 대체된 36개의 과거 작업지시서, 핸드오프, 감사 문서는 [docs/archive/](archive/) 디렉토리에 안전하게 보관되어 있습니다.
이전 작업 히스토리를 추적해야 할 때만 열람하시기 바랍니다.

---

## 4. 빌드 및 검증 명령 빠른 참조

```bash
# 1. 4단계 전체 검증 게이트 (Core 빌드 + 전체 테스트 + Mac 앱 + iOS 앱)
bash scripts/verify_gate.sh

# 2. Core 렌더링 파리티 12종 시나리오 실행
bash scripts/run_core_editing_parity.sh

# 3. Mac App Store 릴리스 빌드 & 아카이브 (Team ID 지정)
MOVIECUT_TEAM_ID=XXXXXXXXXX bash scripts/release.sh
```
