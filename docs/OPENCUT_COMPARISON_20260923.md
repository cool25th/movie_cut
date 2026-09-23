# OpenCut 비교 분석 (2026-09-23)

> 요청: 사용자 "opencut 최신버전 다운받은 것 확인·비교·개선포인트 도출".
> 조사 대상: 로컬 다운로드 사본 + 상류 GitHub(releases/classic) 실황 확인.

## 1. 다운로드 사본 확인

- 경로: `~/MyDev/automation/source/OpenCut` — clone of `github.com/OpenCut-app/OpenCut`
- 시점: **a5888e20 (2026-05-28)**, tag `pre-rewrite-7` — 다운로드 당시 main이 맞으나 **리라이트 본체의 초기 스캐폴드**: apps/web이 shadcn UI 프리미티브 62파일 + 라우터 골격뿐, **편집기/타임라인/출력 코드 전무**(packages·Rust 없음).
- 즉 "최신 버전"은 맞지만 내용은 껍데기 — 기능 비교의 실체는 아래 둘.

## 2. 상류 실황 (2026-09-23 확인)

- **리라이트 진행형**(opencut-app/OpenCut): v0.3.0(2026-04-15) — WebGL 렌더러 → **Rust/wgpu 컴포지터(WASM)** 교체, **시간 추적을 정수 틱(120,000/sec)으로 전환**, GPUI+Rust 데스크톱 스캐폴드. 로드맵 공식 선언: Editor API·**서드파티 플러그인(플러그인 퍼스트)**·Rust 단일 코어로 웹/데스크톱/모바일·**MCP 서버(AI 에이전트)**·**헤드리스 모드(자동화·배치 렌더)**·에디터 내 스크립팅 탭. 외부 기여는 아직 받지 않음.
- **실사용 버전 = opencut-classic**(archived 2026-05-17): Next.js 웹앱 + Rust GPU 컴포지터(이펙트·마스크·WASM 바인딩)·self-host Docker(DB·Redis·Wrangler 구성)·"영상은 기기에" 프라이버시 모티브·CapCut 페이월 대항 무료 오픈소스(MIT). 출력 경로는 아카이브 시점에도 "새 이진 렌더링 방식으로 리팩터링 중"이었음.

## 3. MovieCut 대비 비교

### MovieCut 우위 (실측 근거)
| 축 | MovieCut | OpenCut(classic/rewrite) |
|---|---|---|
| 파이프라인 | 네이티브 AVFoundation/CoreImage·프리뷰=출력 파리티 MAD≤2.0·A/V 0.000s·ProRes/10bit·LUFS 오디오 스위트 | 웹/WASM·출력 경로 재작성 이력·포맷 명세 미공개 |
| 오프라인 | 앱 자체 네트워크 0(차단망 실측·소켓 0) | "기기에" 표방하나 웹앱+self-host 인프라 구성 |
| 편집 깊이 | EQ/덕킹/NR DSP·스코프 4종·LUT 왕복·대사 검색 편집(N1)·roles/인덱스 | 타임라인·이펙트·마스크·텍스트/스티커(preview 수준) |
| 검증 | Core 1,503 테스트·골든·A/B 하니스·무결성 게이트 | 공개된 측정 하니스 없음 |
| 모바일 | iOS 앱(90 테스트) | 없음(로드맵) |

### OpenCut이 다르게 걸거나 앞선 축
- **멀티플랫폼 단일 코어**(Rust+GPUI→웹/데스크톱/모바일): Windows/Linux 도달 — MovieCut은 Apple 네이티브 한정.
- **플러그인 퍼스트 + Editor API**: 생태계 전략 — MovieCut 명시적 비목표.
- **MCP 서버·헤드리스·스크립팅 탭**: 에이전트/자동화 축의 제품화 선언(Palmier와 동일 축).
- **정수 틱 시간(120k/s)**: 부동소수 타임라인 결함 클래스의 근원 제거.
- **wgpu GPU 컴포지터**: 범용 GPU 경로(Apple 외 확장의 기반).

## 4. 개선포인트 (전략 정렬 순)

1. **시간 연산 정수 틱/합리수 검토(소형·고신뢰)** — MovieCut은 CODEX-01(타임코드 부동소수 하방 드리프프)로 동일 결함 클래스를 이미 실증 겪음. OpenCut v0.3이 택한 근본 처방(정수 틱)을 핫패스(트림·스냅·타임코드 표시·프레임 인덱스 유도)에 한정 도입 검토. CA-27 `TimecodeParser`가 이미 부분 Rational화 — 일반화 후보.
2. **'에이전트 편집' 축 표준화 압력 — P3 근거 강화** — Palmier(MCP 내장)에 이어 OpenCut(MCP 서버 로드맵)까지 같은 축 선언. 방향 자문 P3 'typed Action DSL agent-ready kernel'의 우선순위 상향 재검토 근거(단, 오프라인 원칙 내 형태 유지 — 원격 MCP 노출이 아니라 로컬 Action DSL 우선).
3. **헤드리스/배치 출력 제품화 후보(후순위 등록)** — MovieCut의 UITest 하니스가 사실상 헤드리스 엔진(실앱 무인 구동·출력). CLI 배치 출력은 자동화 니즈 + 오프라인 원칙 무관. OpenCut 헤드리스와 차별점은 '로컬 전용'.
4. **GPU 컴포지터 벤치마크 대상 확장** — 성능 대외 주장 보류 정책(§7) 유지하되, OpenCut rewrite 안정 시 CA-12 A/B 블라인드 대상에 오픈소스 3축(CapCut/OpenCut/Palmier) 포함 검토.
5. **따라가지 않을 것(판정 유지)** — 플러그인 생태계·웹 배포·Windows/Linux·self-host — MovieCut 포지셔닝(오프라인 네이티브 Apple 파리티)과 무관하고 OpenCut이 이미 점유. 경쟁 분석 문서의 브라우저 편집기 범위 밖 원칙은 유지하되 OpenCut은 '오픈소스 경쟁' 항목으로 추적.

## 5. 결론

다운로드 사본 자체는 리라이트 껍데기라 직접 비교 대상이 아니지만, 상류의 **방향**(Rust 단일 코어·정수 틱·MCP·헤드리스·플러그인)이 업계 트렌드를 그대로 보여준다. MovieCut은 **깊이(출력 정확성·오디오·검증)에서 우위**이고 **범위(플랫폼·생태계)** 에서는 의도적 집중. 취할 것은 1~4, 버릴 것은 5.
