# CapCut 기능 백로그 & 작업 핸드오프

> 목적: 다른 세션(콜드 스타트)에서 이 문서만 읽고 바로 작업을 이어갈 수 있도록 정리한 핸드오프 문서.
> 작성일: 2026-06-09 / 기준 브랜치: `main`
> 관련 문서: `docs/archive/GAP_ANALYSIS_V6.md` (단, 아래 "현실 점검" 참고 — 자가보고 수치는 신뢰하지 말 것)
> **⚠️ 우선순위 상위 문서 (2026-08-15)**: `docs/DEVELOPMENT_DIRECTION_20260815.md` — 향후 12개월 순서·게이트·신규 G-23~G-29는 이 문서가 결정한다. 아래 역사적 판정(작성일 오래된 항목)은 근거 자료로만 참고할 것.

---

## 0. 한 줄 요약

기본 명령/배선(command, metadata)은 대부분 존재하지만, **사용자가 실제 결과를 보는 경로(드래그앤드롭, 픽셀/샘플 처리, 렌더링 UX 등)가 비어 있거나 부분 구현인 항목이 많다.** 2026-07-04 기준 EQ/NR/덕킹/플랫폼 프리셋/모션 트래킹은 실측 증거로 상환됐고, G-02 커브/HSL 수학과 G-01 워드 타이밍 저장은 착수됐다. 하지만 CapCut 대비 “완성도”는 아직 preview/export/iOS까지 닫힌 상태가 아니므로 과장 금지. **실동작 기준 체감 65~72%**로 보는 것이 안전하다. 완료 기준을 "코드 존재"가 아니라 "preview + export에서 결과 확인"으로 잡고 진행할 것.

> **(2026-08-22 갱신)** ① 1단계 P0 5종 전부 착수 이상 — G-23 크롭✅, G-02 Inc5–6 HSL/커브 UI✅, G-06 보간 UI✅, G-01 Inc2+ 카라오케·스타일 6종✅, G-03 조정 레이어✅(렌더 배선 b9d0e58). G-25(믹싱 골격)·G-26(프로세서)·G-24(안정화 v1)·G-28(브라우저) 완료. **1단계 게이트 잔여 1항 = G-27 실기기 3종(사용자 대기, `G27_DEVICE_VERIFICATION_GUIDE.md`)**. ② 완료 판정 표기는 E/U/P/X/D/S 6단계로 전환(`VERIFICATION_STANDARD.md` §1-4). ③ 경쟁 격차·신규 P0 후보(미디어 관리·입력 포맷·실패/복구·접근성·가격 결정)는 `COMPETITIVE_ANALYSIS_20260822.md`로 통합 — 방향 문서 §3 반영은 사용자 승인 대기.

---

## 0.5 개발 방향 확정 — 신규 ID 등록 (2026-08-15)

> 근거: 외부 검수 채택(`docs/DEVELOPMENT_DIRECTION_20260815.md` §2·§3). 포지셔닝은 "CapCut급 핵심 숏폼 제작 속도 + 선택된 워크플로에서 FCP급 렌더링·색·음향 일관성 + 완전 오프라인"으로 재정의. 90%는 기능 개수가 아니라 5개 대표 작업(W1 토킹헤드/W2 비트 몽타주/W3 합성/W4 5분 마스터/W5 카드뉴스)의 성공률·시간·품질로 판정한다.

**범위 경계 명문화(2026-08-26, 외부 리뷰 반영)**: "FCP급"은 **선택된 영역**(출력 정확성·색·음향 일관성·미디어 생존성)에만 적용된다 — FCP 전체 복제가 아니다. **명시적 비목표**(목표 전환 시 사용자 승인 필요): 멀티캠·자동 동기화·Auditions·전문 라이브러리 관리·서드파티 플러그인 생태계·FCPXML 상호운용. 핵심 숏폼 속도 경쟁력(터치 타임라인·자동 자막·비트 컷·검색 가능 자산·세로형 변형·빠른 공유)은 CapCut급 기준을 유지한다.

| ID | 항목 | 단계 | 완료 기준 요약 |
|---|---|---|---|
| **G-23** | 전용 크롭 도구 (모델+명령+인스펙터/캔버스 UI) | 1단계 | 크롭이 preview+export 동일 반영(골든/패리티 시나리오), undo 단일 트랜잭션 |
| **G-24** | 손떨림 보정 v1 (Vision 등록→경로 평활화→CI warp→confidence fallback) | 2단계 | 잔류 흔들림 중앙값 50%↓, 크롭 중앙값 ≤15%, 심각 워블 ≤3%, 장면 전환 오류 0건 |
| **G-25** | 오디오 믹싱 골격 (`AudioRenderGraphSpec`+팬+채널 매핑+트랙/마스터 미터+master bus+LUFS/true-peak) | 1단계 | 프리뷰↔출력 null test, 동일 PCM ±1 샘픐 정렬, 혼합 sample rate 60분 drift ≤1프레임 |
| **G-26** | 오디오 프로세서 기본선 (컴프레서·리미터·리버브·트랙 스트립·프리셋) — 구 G-05 후속 | 2단계 | LUFS ±0.2LU·true-peak ±0.2dB(기준 구현 대조), transfer curve 자동 검사, 블라인드 선호 60%+ |
| **G-27** | iOS 실기기 검증 인프라 (3단계 기기 러너 + 필수 시나리오) | 1단계 | 최소·중간·최신 실기기에서 프리뷰+출력+오디오 라우팅+발열·메모리+재오픈 통과 |
| **G-28** | 효과·템플릿 브라우저 + 선별 자산 (40→60→120개) — 구 G-07 재정의 | 2단계 | 검색·미리보기·적용 작업 성공률 90%+, 검색 성공률·재사용률 KPI(개수 KPI 폐지) |
| **G-29** | HDR-ready 색관리 파이프라인 (내부 전환, 공개는 후속) | 3단계 | SDR 골든 무회귀(차단 게이트), 10비트 램프 신규 banding 0, HLG 메타데이터 round-trip |

**기존 ID 재정의**: G-05(오디오 스위트)는 G-25(믹싱 골격)+G-26(프로세서)로 분해. G-07(이펙트 팩 20+)은 G-28로 흡수(수량 목표 폐지, 검색·재사용 KPI로 대체). G-13(자연 보정)·G-14(녹화 스위트, 구 C-2)는 보류 유지. G-02 Inc5–6(HSL/커브 UI)·G-06(보간 UI)·G-01 Inc2+(카라오케)·G-03(조정 레이어)는 1단계 P0로 승격(방향 문서 §3).

**G-29 전도부 이행(2026-08-17)**: 프리뷰↔출력 색공간 발산 결함 폐쇄 — AVPlayer 디코드 다리가 소스 BGRA에 ICC 태그(미태그 BT.601 SD → "Composite NTSC")를 붙이고 AVAssetExportSession 다리는 무태그라서, 컴포지터의 `CIImage(cvPixelBuffer:)`가 프리뷰에서만 sRGB 작업 공간으로 색 변환(순수 레드 (254,0,0)→(247,36,0), 파리티 MAD 10.25). `RenderColorConfiguration.sourceImage(from:)`로 양쪽 컴포지터(Mac·iOS)의 소스 해석을 작업 공간으로 고정해 폐쇄. 실증: 파리티 시나리오 `crop_rect_video` 신설(스크립트 15번) MAD 10.25→**0.50 PASS**, 전체 14/14 무회귀, `ColorSpaceParityTests` 2개 신규(디코더 ICC 태그 무관성). 잔여(후속 감사 범위): 무컴포지터(plain) 경로는 양 다리가 같은 회전값(255,23,0)으로 패리티는 일치하나 원본 의도 색상과는 미세 차이 — G-29 본 증분(3단계)에서 색 관리 전면 감사 시 다룬다.

---

### 0.5.1 경쟁 분석 파생 개선 큐 — CA (2026-08-22 등록)

> 등록 경위: 사용자 지시로 `docs/COMPETITIVE_ANALYSIS_20260822.md`(경쟁 분석 통합 문서)의 개선방향(Part 7 P0/P1/P2·Part 8 열린 결정 Q1~Q12)을 자율 루프 큐에 연결. **승인 상태 열이 실행 자격이다** — '즉시'는 방향 문서 §3와 무충돌, '승인 대기'는 해당 Q 답변 시 실행, '사용자 전용'은 루프가 결정하지 않는다.

| ID | 항목 | 단계 | 승인 상태 | 완료 기준 요약 |
|---|---|---|---|---|
| CA-01 | 오프라인 차단·DNS/HTTP 트래픽 캡처 테스트(iOS 포함) — 증거원장 MC-02 ②③ | P0 | **완료(2026-08-27)** — `run_ca01_offline_gate.sh` 실측: Mac은 sandbox-exec 네트워크 전면 거부(루프백 프로브로 프로파일 유효성 입증) 하에서 파리티 하니스(임포트→프리뷰→출력) 완주 + sandboxd 네트워크 위반 **0건**, iOS는 시뮬레이터 전체 하니스(임포트→프리뷰→출력→오디오→저장) 동안 lsof 소켓 캡처 **0개/36샘플** — MC-02 ②③ 갱신 | 네트워크 차단망에서 대표 작업 전 통과 + 캡처 0 기록 (완료) |
| CA-02 | 파리티 허용 오차 등급 수치 확정(Exact/Tolerance/Perceptual) | P0 | **완료(2026-08-23)** — VERIFICATION_STANDARD §2 등급별 수치 확정(Exact=수치 동일·유닛테스트 담당 / Tolerance=MAD ≤ 2.0+1프레임·17 시나리오 게이트 / Perceptual=블라인드 비열등)+신규 시나리오 등급 명시·허용치 변경 승인제 기재 | 골든 재판정 기준 문서화 |
| CA-03 | 미디어 관리·프로젝트 생존성 감사(재연결·누락·손상·마이그레이션 실패 경로·디스크) | P0 | **완료(2026-08-24, e36f83a + 2차 실사 병합)** — `AUDIT_MEDIA_SURVIVABILITY_20260824.md`(경로 5종 판정 + §4 2차 병합). 등록: BUG-01(P0 오토토회복 침묵)·BUG-02(P0 임포트 무검증)·**BUG-04(P1 익스포트 사전 미디어 검사 부재 — 2차 신규)**·**BUG-05(P1 분류 오류 미분류 덮어씀 — 2차 신규)**. BUG-03(재연결 자동화 0)은 **폐기** — `MediaRelinkTests`가 이미 실경로 잠금(1차 탐색 누락). 수정은 BUG 증분으로(§1.7) | 감사 보고 + 발견 결함의 P0 버그 등록 (완료) |
| CA-04 | 입력 포맷 호환 매트릭스(VFR·10bit·Log·혼합 fps/sample rate·rotation) | P0 | **완료(2026-08-25) — `AUDIT_INPUT_FORMATS_20260824.md` + `run_ca04_format_matrix.sh` 실측: VFR→CFR✅·혼합 fps A/V Δ0ms✅·BT.2020→bt709 재태그✅·10bit → BUG-06 해결(콘텐츠 영역 Δ0.9)·회전 → BUG-07 해결(비대칭 픽스처 방향 실측 + 어설션 승격)** | 매트릭스 작성 + 최우선 회귀(혼합 미디어 sync·색 유지) 실측 |
| CA-05 | 실패·복구 UX 매트릭스(15 실패 시나리오 × 무손실/원인/재시도/이어하기/임시파일) | P0 | **완료(2026-08-24)** — `CA05_FAILURE_RECOVERY_UX_MATRIX_20260824.md`: 15 시나리오 × 5축 파일:라인 근거. 13/15 완전 충족(CA-03 감사·외부 리뷰 반영이 전제). 신규 등록: UX-REC-01(P2 iOS 부분출력 잔존)·UX-REC-02(P2 iOS 복구 무음 채택) — §1.9 | 매트릭스 + 결함 우선순위화 (완료) |
| CA-06 | 접근성 핵심 경로 매트릭스(임포트→편집→출력, VoiceOver 등) | P0 | **완료(2026-08-24)** — `CA06_ACCESSIBILITY_CORE_PATH_MATRIX_20260824.md`: Mac 핵심 경로 VoiceOver·키보드 전 충족(UX-08 계약+43 단축키). **iOS 차단 발견: A11Y-01(P1) 인스펙터 하위 뷰 5종 라벨 0건** + A11Y-02(P2)·A11Y-03(P3) — §1.10. 인스펙터 Picker 라벨 접힘은 이번에 수정 | 매트릭스 + 차단 결함 등록 (완료) |
| CA-07 | 가격·판매 단위 결정(모델 선택·Universal Purchase) | P0 | **모델 확정(Q2: 일회성+유료 메이저 업데이트) — 구체 가격은 사용자 전용 유지** | 결정 기록 → REQUIREMENTS §13 반영 |
| CA-08 | iOS 자막 스타일 6종·카라오케 이식 | P1 | **완료(2026-08-26)** — `IOSEditorViewModel.applySubtitleStylePreset`(Mac 패리티·SetClipPropertyCommand) + 인스펙터 "Subtitle Style" 섹션: Core `SubtitleStylePresets.builtins` 6종(Clean White/Bold Box/Yellow Pop/Shadow Soft/Mint Outline/Classic Serif) 수평 칩 + 색상 미리보기 원형 + 원탭 적용(undo 1-step). 카라오케 렌더링은 Core TextOverlayPixelProcessor가 이미 처리 | iOS 파리티 + 실기기 검증 |
| CA-09/10 | N1-A 대사 검색 / N1-B 텍스트 기반 구간 선택 | P1 | 승인 대기(Q11 일괄 승인) | 검색 성공률·구간 이동 정확도 측정 |
| CA-11 | N2 제안형 오토스타일 MVP(제안→미리보기→적용→undo — 자동화 4원칙 전항) | P1 | 승인 대기(기존 'N2 등록' 대기와 동일 건) | COMPETITIVE_ANALYSIS §1.5 원칙 전항 + 동일 입력 재현성 |
| CA-12 | 경쟁사 A/B 벤치마크 하니스(조건 필드·12 fixture·PSNR/SSIM+블라인드) | P1 | **완료(2026-08-27)** — `ab_benchmark_metrics.py`(single/pair/blind/self-test 15종 — PSNR·SSIM·ΔE·banding·clipping·VFR·sync·loudness) + `make_ab_fixtures.sh`(12 fixture·SHA-256 핀=세트 버전 관리) + `run_ca12_ab_benchmark.sh`(§1.4 조건 필드·실앱 구동·RTF/RSS·baseline.json) + 하니스 게이트 CHROMA_KEY·export_wall_s. **첫 기준 수치 11/12 fixture 실측 기록**(`CA12_AB_BENCHMARK_20260827.md` — 30분 RTF 0.299·2시간 RTF 0.348·A/V Δ0.000s·peakRSS 5,054MB 등). 발견 등록: §1.13 BUG-CA12-01(파리티×덕킹 파킹)·BUG-CA12-02(HDR 파리티 위반) | 하니스 + 기준 수치 최초 기록 (완료 — B측 블라인드 평가는 경쟁사 출력 확보 시) |
| CA-13 | 폰트 패키징 정책(N5 — 라이선스 경고·프로젝트 포함·PostScript 충돌) | P1 | 승인 대기(라이선스 검토 선행) | 정책 문서 + 구현 |
| CA-14/15 | 비트 감지 iOS UI / 현지화·텍스트 품질 감사 | P1 | **완료(2026-08-28)** — CA-14: iOS `detectBeats`/`clearBeatMarkers`(Mac 패리티 — Core BeatDetectionProvider 공유·canonical 매핑·AddMarkersCommand 단일 undo) + 하단 툴바 "Beats" confirmationDialog(Detect/Clear) + 타임라인 비트 틱 오버레이 + **스냅 대상에 마커 포함**(Mac 파리티 갭 수습). 검증: `IOSBeatDetectionTests` 2/2(실제 클릭트랙 WAV→임포트→감지→마커≥6·클립 범위 내→정리·무선택 명시 오류). CA-15: `CA15_LOCALIZATION_TEXT_QUALITY_MATRIX_20260828.md` — 축 10종 중 7종 충족(4종 실측 프로브 `MultilingualTextRenderTests` — CJK·emoji/결합문자·RTL·줄바꿈 잉크 커버리지 4/4 PASS)·1종 범위 외(세로 텍스트)·2종 관찰(파일명 정규화·혼합방향). **신규 결함 0건** | 파리티/감사 보고 (완료) |
| CA-16 | [P2 묶음] N1-C/D·매치컬러·애니메이션 스티커·보이스 체인저·업로드 보조·iOS 프록시·배치 export·**Auditions 테이크 비교(2026-08-23 v4 보류 편입 — 중간 규모·FCP 고유 패러다임, 베타 반응 후)** — 벡터스코프 제거(2026-08-23: 이미 구현 `InspectorEffectsSection.swift:200`) | P2 | 베타 반응 후 | 각 항목 DoD |
| CA-17 | 자막 sidecar 검증·iOS 진입 | 소형 | **iOS export 진입 완료(2026-08-26)** — `IOSEditorViewModel.exportSubtitles(format:)`(SRT/VTT, Core `SubtitleDocument` 공유·Mac 바이트 동일) + 하단 툴바 "Subtitles" 버튼 → confirmationDialog 형식 선택 → 상단 ShareLink로 공유. 잔여: 실제 플레이어 3종 로드 확인(수동/D) | iOS export 진입 완료 + Core 파리티 |
| CA-18 | 화자 분리(diarization) 자막 — 게이트형 연구. **임계값 사전 등록: 화자 혼동율 ≤10%(합성·실녹음 각각)·RTF ≤0.5·메모리 예산(스템 게이트와 동일 기준)** | 연구 | **측정 단계만 승인(2026-08-23)** — 구현 착수는 측정 보고 후 별도 승인 | 2인 fixture 측정 보고 → 임계값 전항 통과 시에만 UI 착수 승인 요청, 미통과 시 명시적 실패 기록 |
| CA-19 | 타임라인 **가이드라인**(드래그 기준선) + 눈자 밀도 감사 | 소형 | **완전 종결(2026-08-28)** — 밀도 감사 보고(`CA19_RULER_DENSITY_AUDIT_20260828.md`): 충돌은 전 줌 범위(20~300px/s)에서 산술적으로 안전(최악 라벨 간격 200px·결함 0건), 장편 가독성 결함(초 고정 라벨 "3600s")은 `TimecodeParser.rulerLabel` 3단 적응(45s/12:05/2:02:05)으로 수정+표값 테스트 고착. 이전: iOS 스냅+가이드 완료(2026-08-26·Mac 패리티) | iOS 드래그 스냅+가이드 실측 + Mac 빌드 복구 + 밀도 감사 (완료) |
| CA-20 | roles + 타임라인 인덱스(W4 장편 관리 세트) — 클립 role 태그·롤별 레인 색·인덱스 검색→이동. FCP roles+Timeline Index 대응. role·키워드·스마트컬렉션 전무(`CA_REGISTRATION_PROPOSAL_20260823.md` v3 §2, 2026-08-23 코드 확인) | P2 | **등록 승인(2026-08-23) — 방향 문서 §3 반영 후 실행**(W4 직결, 2단계 배치 검토) | role 영속화+migration round-trip · 롤별 레인 골든(U) · 인덱스 검색→이동 30분 fixture p95 · VoiceOver 인덱스 탐색 · iOS defer 사유 기록 |
| CA-21 | Edit Detection(씬 자동 분할 제안) — Core `SceneChangeProvider` + VM `detectAndSplitScenes` + UI 배선 모두 존재(2026-08-25 정정, §H 참조). FCP 12.3 대응 | 연구(P2) | **측정 단계만 승인(2026-08-23)** — precision/recall 임계값은 측정 설계 시 사전 등록 후 고정 | 합성 fixture+실영상 2종 측정 보고 → 통과 시에만 UI 착수 승인 요청(§1.5 원칙 전항), 미통과 시 명시적 실패 기록 |
| CA-22 | 프록시 자동 생성 — 임포트 시 백그라운드 | P2 | **완료(2026-08-27, 2차)** — 2차: ①설정 UI 토글(인스펙터 Playback 섹션 "Auto-generate proxy on import") ②진행 취소(`cancelAutoProxyGeneration` — Core `ProxyGenerator`가 `withTaskCancellationHandler`+`cancelExport`로 인코딩 중 취소·부분 파일 정리) ③재개(`resumeMissingProxies` — 취소/thermal 스킵 분 모두 커버, 진행 중 태스크 완료 대기 후 스케줄) ④**1차 갭 수습: 타임라인 임포트 경로(주 경로)에도 자동 생성 연결**(미디어 라이브러리 경로에만 있었음) ⑤하니스 게이트 MODE/CANCEL/RESUME+정착 대기·기존 게이트 결정성 보호 옵트아웃. 검증: `run_ca22_proxy_gate.sh` **4 leg 12/12 PASS**(off 미스케줄·on 생성·인코딩 중 취소·취소→재개 완주) + Core 3종(취소 거부·레디 단축·설정 왕복) + 게이트 5/5(1,420)·파리티 스윕 13/13 | 백그라운드 생성 E2E·thermal 상호 정책 (완료) |
| CA-23 | 프로젝트 스냅샷/버전 히스토리 — autosave와 별개 사용자 주도 안전망(현 기능 부재. 과거 `VersionHistory`는 archive V1/V2 이후 삭제 — 2026-08-23 전역 검색 0건, dead-code 재활용 근거 정정) | P2 | **등록 승인(2026-08-23) — 실행 시점은 별도 결정** | 스냅샷 생성·목록·복원 앱 E2E(undo 독립) · 용량 정책·오래된 정리 · autosave 역할 구분 문서화 · 복원 전 현재 상태 보호 확인 |
| CA-24 | 한국어 UI 커버리지 100% — Q1 페르소나 직결 | 소형(P1 하위) | **완료(2026-08-25)** — 양 카탈로그 en+ko 전량(외부 리뷰가 iOS 106 미커밋 발견: fbf3149는 Mac만 반영돼 있었음 — 병렬 git 경합 유실, 재적용). CI 강화: 양 플랫폼 키+번역값(en·ko) 존재 검사 차단화. 잔여: `SNS 좋은 소리` 프리셋명은 로케일 불변 제품명(의도), ko 실기기 스크린샷 골든은 베타 시점 | 커버리지 100%·CI 이중 검사 (완료) |
| CA-25 | 온보딩·샘플 프로젝트 — W1 미니 샘플 번들+첫실행 3단계 안내(임포트→자막→출력). 첫실행 경로 부재("Landscape Tutorial"은 템플릿 자산일 뿐, `BuiltinTemplates.swift:43`) | 소형 | **등록 승인(2026-08-23) — 방향 문서 §3 반영 후 실행**(Track A 베타 체감 직결) | 샘플 프로젝트 번들 내장(**오프라인 원칙 유지**) · 신규 사용자 첫 출력 ≤10분 목표 측정(SC-C1 스타일) · Quick Tools 발견률 최소 측정 |
| CA-26 | LUT export(.cube 저장) — 그레이딩→LUT 저장 경로 부재(2026-08-23 전역 확인: writeLUT/exportLUT 0건, import만 존재). W3/W4 색 워크플로 완결·표준 포맷이라 오프라인 원칙 무관 | 소형 | **완료(2026-08-23)** — Core `CubeLUTExporter`(serialize: %.6f red-fastest round-trip 무손실 + bake: 기본 보정을 생산 `ColorCorrectionPixelProcessor` 경유 그리드 렌더, v1 스코프=기본 보정 한정·3-way/HSL/마스크 제외 UI 명시)+테스트 3건(round-trip·identity bake·brightness bake)+Inspector "Export LUT…" 저장패널 진입점(외부 LUT 재내보냄 무손실/기본 보정 bake 분기, 상태 메시지로 스코프 고지) | 게이트 5단계 통과(1,354 테스트) |
| CA-27 | Timecode 직접 입력 — `PreviewPanel` 표시 전용이었음(2026-08-23 확인). 키보드 완결성·정밀 탐색(Q6 핵심 경로 정합) | 소형 | **완료(2026-08-23)** — Core `TimecodeParser`(SS·MM:SS·MM:SS:FF·HH:MM:SS:FF, 무효 입력 nil 명시적 실패)+유닛테스트 6건(Exact)+현재 시간 배지 편집 필드화(제출·포커스 상실 시 seek, 무효 입력 상태 메시지·원복)+VoiceOver 라벨+표시 fps를 프로젝트 프레임레이트로 정통화(기존 30 고정 오류)+StaticContract 2건 갱신·ko 문자열 3건 추가 | 게이트 5단계 통과(1,351 테스트) |
| CA-28 | RGB 파레이드 스코프 — `parade` 0건(2026-08-23 확인, 벡터스코프는 존재). `ScopeViews` 확장 소형 | 소형 | **완료(2026-08-24)** — Core `ScopeAnalyzer.rgbParade`(lumaWaveform과 동일 빈ning 계약의 R/G/B 채널별 파형)+골든 테스트 4건(채널 분리·x 램프 추적·혼합 픽셀 독립 빈ning·퇴화 가드, Exact)+Mac `RGBParadeView`(R/G/B 패널, WaveformView와 동일 렌더링 계약)+인스펙터 노출(그레이딩 패널 waveform/vectorscope 행 아래)+접근성 라벨/값(영어 키+en/ko). 기존 스코프(histogram·waveform·vectorscope) 무변경·회귀 없음 | 게이트 5단계 통과 |

**실행 규칙**: CA-02·04·05·06·08·12·24·26·27·28 완료, CA-01 완료, CA-14·15·17·19·22 잔여 즉시 실행 가능, CA-18·21은 측정 단계만, CA-20·23·25는 등록 완료(실행 조건 도달 시), 나머지는 승인 대기. AI 음성(TTS 보이스 확장)은 **등록 보류(2026-08-23 승인 — 베타 반응 후 재상정)**. 루프 회차 보고에는 '승인 대기' 항목을 항상 나열한다.

---

## 1. P0 버그: 이미지/영상 드래그앤드롭이 실제로 안 됨

`docs/archive/GAP_ANALYSIS_V6.md`에는 "드래그앤드롭 미디어 임포트 ✅ 완료"로 적혀 있으나 **실제로는 타임라인에 드롭해도 클립이 생기지 않는다.**

### 근본 원인

1. **타임라인 드롭이 클립을 안 만든다.**
   - `App/MovieCutMac/TimelineView.swift:265` 의 `.onDrop` 핸들러가 `viewModel.importMedia([url])`만 호출.
   - `EditorViewModel.importMedia` (`App/MovieCutMac/EditorViewModel.swift:512`)는 `ImportMediaCommand`로 **미디어 라이브러리(mediaAssets)에만** 추가하고, 트랙에 `Clip`을 만들지 않음.
   - 클립 생성은 별도 메서드 `addClipToTimeline` (`App/MovieCutMac/EditorViewModel.swift:530`)이며, 현재는 라이브러리 패널의 "Add to Timeline" 버튼(`App/MovieCutMac/MediaLibraryPanel.swift:49`)으로만 호출됨.
   - 결과: 타임라인에 드롭 → 라이브러리에만 조용히 추가 → 타임라인엔 아무것도 안 나타남 → "안 된다"로 체감.

2. **라이브러리 → 타임라인 드래그가 불가능.**
   - `MediaLibraryPanel.swift`의 에셋 행(row)에 `.draggable` / `.onDrag`가 **없음**. 따라서 라이브러리에서 타임라인으로 끌어다 놓는 경로 자체가 존재하지 않음.

3. **실제 미디어 길이를 안 읽음.**
   - `Sources/MovieCutCore/Media/MediaImporter.swift:16` 의 `probe`가 확장자만 보고 `duration: nil` 반환 (AVFoundation 미사용).
   - 영상/오디오를 넣어도 실제 길이가 아니라 `defaultDuration` 기본값으로 클립이 생성됨. 해상도/fps도 모름.

### 현재 유일하게 동작하는 경로
라이브러리 영역에 드롭 → 에셋 선택 → "Add to Timeline" 버튼 클릭. (`MediaLibraryPanel.swift:71` 드롭 → `:49` 버튼)

### 수정 작업 (P0)

- [x] **타임라인 드롭 → 클립 생성**: `TimelineView`의 `DropDelegate`가 드롭 X좌표를 시간으로 환산(`x / pixelsPerSecond`)하고, `EditorViewModel.importMediaAndAddToTimeline`으로 import + clip 생성을 한 번에 수행한다. 검증은 build/static-contract 기준이며 UI 자동화는 아직 생성하지 않았다.
- [x] **라이브러리 아이템 `.draggable` 추가**: `MediaLibraryPanel` 에셋 row에 내부 asset UUID payload drag를 추가하고, 타임라인 drop이 내부 asset ID를 받아 기존 에셋으로 clip을 생성한다. 검증은 build/static-contract 기준이며 UI 자동화는 아직 생성하지 않았다.
- [x] **실제 import metadata probe**: Core `MediaImporter.probe`는 경량으로 유지하고, 앱 레이어(`EditorViewModel`)에서 `AVURLAsset`/ImageIO 기반 best-effort probe로 video/audio duration, 해상도/fps/codec, audio sample rate/channel count, image dimensions를 `MediaMetadata`에 채운다. 라이브러리 행/접근성 value가 compact metadata summary를 표시한다. 검증은 build/static-contract 기준이며 GUI visual verification은 아직 생성하지 않았다.
- [x] **드롭 성공/실패 사용자 피드백**: 타임라인 파일 드롭, 라이브러리 에셋→타임라인 드롭, 미디어 라이브러리 파일 드롭이 성공 시 `lastStatusMessage`, 실패/빈 payload 시 `lastErrorMessage`를 설정한다. `ContentView.statusBar`가 두 메시지를 표시하며, `DragDropFeedbackStaticContractTests`가 decoded-empty callback과 invalid payload feedback wiring을 검증한다.

### 검증 방법
실제 mp4/png 파일을 ① 타임라인에 직접 드롭 ② 라이브러리에서 타임라인으로 드래그 — 두 경로 모두 올바른 위치에 올바른 길이의 클립이 생기는지 확인. `swift build` + `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build`.

> 참고: 현재 sandbox 엔타이틀먼트 파일 없음(`.entitlements` 부재) → 파일 접근 권한 문제는 아님. 순수하게 클립 생성 로직 누락이 원인.

---

## 1.7 CA-03 감사 발견 결함 — 미디어 생존성 (2026-08-24 등록·병합)

> 원천: `AUDIT_MEDIA_SURVIVABILITY_20260824.md`(1차 감사 e36f83a + §4 2차 실사 병합). 2차 병합에서 BUG-04/05 신규 등록·BUG-03 폐기(`App/MovieCutMacTests/MediaRelinkTests.swift`가 이미 재연결·누락 감지 자동화를 실경로로 잠금).

### BUG-01 (P0) — 오토토회복 저장 실패 무음 — **수정 완료(2026-08-24, 9277d86)**

- 위치: `App/MovieCutMac/EditorViewModel.swift:215-218` — `scheduleAutosave`의 `try? await saveAutosave`.
- 디스크 풀/권한 상실 시 모든 autosave가 실패해도 신호 없음 → 크래시 시 옛 복구 파일 또는 부재 → 데이터 손실. 저장(saveProject)은 분류 메시지가 있으나 autosave는 부재.
- 수정 완료: `scheduleAutosave`/`flushAutosave` 실패 분류 → 비차단 상태바 경고(성공 시 해제). 검증: `AutosaveFailureSurfacingTests` 3종(읽기전용 디렉터리 경고·회복 시 해제·flush 경고). 재시도 백오프는 미구현(경고 표면화가 본질 — 잔여는 P2).

### BUG-02 (P0) — 임포트 무결성 검증 부재 — **수정 완료(2026-08-24, 11b2f20)**

- 위치: `Sources/MovieCutCore/Media/MediaImporter.swift:17-27,51-52` — 확장자 판별만, 미지원 확장자의 조용한 `.video` 디폴트.
- 수정 완료: Core `validatedProbe`(확장자 허용목록 + 512바이트 매직 스니프 + 종족 충돌 거부, mp3/aac 원시스트림 예외). 제품 경로 전환(맥 임포트·카드 이미지·재연결·보이스오버·슬라이드쇼·iOS 임포트). 검증: `MediaImporterValidationTests` 7종.

### BUG-04 (P1) — 익스포트/패키지 전 미디어 사전 검사 없음 — **수정 완료(2026-08-24, e00b3fe)**

- 위치: `exportProject(to:)`(`EditorViewModel.swift:1237`), `exportProjectPackage`(`EditorViewModel+Export.swift:20`) 등 전 익스포트 경로.
- 누락 감지·재연결은 프로젝트 열기 시에만 — 세션 중 디스크 분리 후 익스포트하면 렌더 도중(수분) 실패.
- 수정 완료: 5개 익스포트 진입점(무비·명시 비트레이트·ProRes×2·프로젝트 패키지) 전 `ensureAllMediaReachableForExport()` 가드. 검증: `ExportMediaPreflightTests` 3종.

### BUG-05 (P1) — VM 익스포트 catch가 분류 오류를 일반 문구로 덮어씀 — **수정 완료(2026-08-24, 5674250)**

- 위치: `EditorViewModel.swift:1256-1259` 등 — `lastErrorMessage = error.localizedDescription`. `FileOperationError`가 `LocalizedError` 미준수라 엔진이 분류해 throw한 디스크 풀 안내가 사라짐(계약 불이행).
- 수정 완료: `FileOperationError` `LocalizedError` 채택(errorDescription=userMessage) — throw·catch 양단에서 분류 문구 생존. 검증: `FileOperationErrorTests` 3건 추가.

---

## 1.8 외부 리뷰(2026-08-24) 검증 등록 — iOS 정확성·신뢰성 (같은 날 실사 확정)

> 원천: 사용자 제공 외부 리뷰. 코드 실사로 검증 후 등록 — 리뷰의 P0-2(iOS 속도·램프·프리즈·Reverse) 4건은 **현재 코드에서 이미 수정됨**(`IOSExportEngine`의 macOS 패리티 주석·`sourceTimeRange` 전체 소스 스팬·`renderReversedAsset` throw로 확인) → 등록 않음. 30fps 고정 주장도 부정확(동적 `exportSettings.frameRate`).

### BUG-IOS-01 (P0) — iOS 프로젝트 상태 이중화 — **수정 완료(2026-08-24)**

- 위치: `IOSEditorViewModel.swift:20` `currentProject` + 별도 `EditorSession`; 캔버스 변경(`:652` `currentProject.canvas = preset`)·템플릿 적용(`IOSTemplatePickerView.swift:138`)이 세션을 우회.
- 수정 완료: 캔버스는 기존 Core `SetProjectCanvasCommand`, 템플릿은 기존 `ReplaceProjectCommand`로 세션 경유(커맨드 신설 불필요). 직접 변경 지점 전수 스캔 제거 확인. 검증: `IOSSessionStateTests` 2종(캔버스 후속 커밋 생존·타임라인 재바인딩, 템플릿 후속 편집 시 프로젝트 유지).

### BUG-IOS-02 (P0) — iOS 프로젝트 저장·복구 부재 — **수정 완료(2026-08-24)**

- 수정 완료: `IOSEditorViewModel`이 Core `ProjectStore`로 커밋마다 autosave(실패 시 비차단 `autosaveFailureMessage`) + 런치 시 `restoreAutosaveIfAvailable()`(하니스 실행 제외). 테스트: `IOSPersistenceTests` 2종(재시작 복원·읽기전용 실패 표면화).

### BUG-IOS-03 (P1) — iOS 합성 누락 잔존 — **수정 완료(2026-08-24)**

- 수정 완료: 효과 객체 생성 2곳에 `blendMode: clip.blendMode` 전달 + 게이트에 transform(≠identity)·opacity(≠1) 트리거 추가.

### BUG-IOS-04 (P1) — 프로젝트 패키지 미디어 복사 실패 무시 — **수정 완료(2026-08-24)**

- 수정 완료: 복사 실패 전량 수집 → `mediaCopyFailed(fileNames:)` throw + 부분 패키지 제거 + `LocalizedError` 사용자 문구. 테스트 2건 갱신(누락 명시적 실패·북마크 스트립 실제 파일).

### BUG-IOS-05 (P1) — 보이스오버 버퍼 쓰기 실패 무시 — **수정 완료(2026-08-24)**

- 수정 완료: 탭 내 첫 쓰기 실패 래치(스레드 안전) → `stopRecording()`이 `writeFailed(underlying:)` throw — 불완전 테이크 폐기.

### BUG-IOS-06 (P1) — iOS 사진 임포트 전체 메모리 적재 + 실패 무음 — **수정 완료(2026-08-24, b0a5f03)**

- 수정 완료: 파일 URL 전송 + 1MiB 버퍼 스트림 복사 + 전달/복사 실패 오류 채널 표면화(실행 가능 문구).

### 참고 등록 (결함 아님)

- **Mac 앱 테스트 CI 비차단은 의도설계**: `ci.yml:59` `continue-on-error`는 기록된 호스트 플랫폼 플레이크 완화 + G-28 스위트 별도 차단. 전면 차단화는 플레이크 원인 해소 후(별도 결정).
- **ko 번역 누락 106개×2 카탈로그**: 빈 값이 아닌 ko 항목 자체가 없는 키(Mac/iOS 각 106). 현지화 완료 증분 필요(자동 검증기는 미싱 키만 잡음).
- **SwiftLint 전체 936건(error 94)**: high-signal 게이트는 유지, 전체 부채는 파일 분리(5,348행 `EditorViewModel`) 증분으로.
- **리뷰의 스크린샷 UI 지적(가짜 skeleton 카드·Inspector Picker 라벨 접힘)**: UX 부채로 CA-06 접근성 매트릭스와 함께 처리.

---

## 1.9 CA-05 매트릭스 파생 결함 — 실패·복구 UX (2026-08-24 등록)

> 원천: `CA05_FAILURE_RECOVERY_UX_MATRIX_20260824.md`.

### UX-REC-01 (P2) — iOS 익스포트 취소/실패 시 부분 출력 — **수정 완료(2026-08-24, 2ca5f38)**

- 수정 완료: 활성 출력 URL 추적 + 취소/실패 경로에서 제거(best-effort, 원 오류 보존).

### UX-REC-02 (P2) — iOS 크래시 복구 무음 자동 채택 — **수정 완료(2026-08-24, 9d277fd)**

- 수정 완료: 런치 복구 후 유지/버림 알림(영어 키+en/ko). 버림 → 신규 프로젝트 + 복구 파일 삭제.

### PARITY-TOL-01 (대기 결정 — VERIFICATION_STANDARD 허용치 변경 승인제) — 코어 파리티 2.0 허용치와 핏 스케일링

- BUG-06 수정으로 모든 소스가 캔버스에 aspect-fit됨(정확한 동작). 부수 효과: 서브-720p 픽스처(320×240)는 이제 양측 다리가 재표본(스케일) — 하드 엣지 픽스처(bars)에서 MAD 4~36로 2.0 허용치 초과. 수정 전 2.0 계약은 1:1 무스케일 시대 기준.
- **권장 (a)**: 파리티 픽스처를 캔버스 정합 ≥720p(예: 1440×1080 4:3)로 재생성 → 1:1 복원·2.0 계약 유지. (b): 비디오 시나리오 허용치 12로 재조정(전용 파리티 러너와 정합).
- **해결(2026-08-28 — 외부 리뷰 권고 (a) 실행 승인)**: 파리티 픽스처를 캔버스 정합 1440x1080(solid_red·bars(smptebars)·moving_subject)로 교체 — MAD ≤ 2.0 유지·허용치 무변경·**핵심 파리티 18/18 재검증 PASS**(ripple·normal 등 재실측). 파리티 스윕도 동일 픽스처+2.0으로 통일. 근거: 재표본 분산은 픽스처/캔버스 스케일 불일치 소생이며 계약 희석 없이 픽스처 교체로 해소.

### 참고 (UX-REC-03) — 세션 중 스코프 철회는 열기/익스포트 게이트에서만 감지

- 실시간 재탐지는 비용 대비 효과 낮음 — 현재 패턴 유지 결정(매트릭스 §2).

---

## 1.10 CA-06 매트릭스 파생 결함 — 접근성 (2026-08-24 등록)

> 원천: `CA06_ACCESSIBILITY_CORE_PATH_MATRIX_20260824.md`. Mac 핵심 경로는 차단 없음 — 아래는 iOS 중심.

### A11Y-01 (P1, iOS 차단급) — iOS 인스펙터 하위 뷰 VoiceOver — **수정 완료(2026-08-24)**

- 실사 정정: 텍스트 라벨 버튼/토글/ColorPicker는 기본 announced(0건 카운트는 과대) — 실제 갭은 bare `Slider`(효과 인스펙터 opacity/speed/inspectorSlider·크로마키 slider 헬퍼)와 필터 선택 상태. 수정 완료: 슬라이더 라벨+값·필터 선택 announce + `IOSInspectorAccessibilityContractTests` 4종(시뮬레이터 #filePath 경로 해석 포함).

### A11Y-02 (P2) — iOS 익스포트 진행 시트 — **해소(2026-08-24, 기존 구현 확인)**

- 실사 결과 이미 구현돼 있었음(라벨+값+힌트·취소 파괴적 롤+힌트) — 계약 테스트로 잠금.

### A11Y-03 (P3) — 빈 라이브러리 스켈리톤 카드 시각 신뢰감 — **수정 완료(2026-08-28)**

- VO 숨김은 정상이었으나 로딩/깨진 자산처럼 보이는 시각 문제(외부 리뷰 지적) — 스켈리톤 6장(`mediaEmptySkeletonCard`·`mediaEmptyGridRhythm`)을 **단일 빈 상태 안내 카드**로 교체: "Your library is empty" + 임포트 안내(en/ko 카탈로그 등록)·VoiceOver 가시(스켈리톤은 숨김이었음). 아이콘은 Phase 2-1 계약이 금지한 온보딩 아이콘 대신 `square.grid.2x2`. 계약 3종(Phase21·P0Browser·Phase24)을 새 구조로 갱신 + 스켈리톤 복귀 금지 부정 단언 추가. 게이트 5/5.

---

## 1.11 외부 리뷰(2026-08-25) 검증 등록 — iOS 프리뷰·렌더 통합 (실사 확정)

> 원천: 사용자 제공 리뷰. BUG-06·ko(iOS)는 본 세션에서 이미 수정(리뷰 작성 시점 기준). 아래는 검증된 신규 확정 항목.

### RENDER-01 (P0) — iOS 프리뷰와 익스포트가 다른 엔진 — **수정 완료(2026-08-25)**

- 수정 완료: `IOSExportEngine.makeRenderPlan(for:)`를 단일 렌더 원천으로 추출(컴포지션+videoComposition) — 익스포트와 **PreviewView가 동일 plan을 소비**(AVPlayerItem·AVAssetImageGenerator 모두 plan.videoComposition 부착, 단일 클립 후필터 파이프라인 `makeFilteredFrame` 전면 폐지). 속도 램프·리버스·프리즈·마스크·크로마·블렌드·다중 트랙·텍스트·스티커·캔버스 배경이 프리뷰=익스포트 구조적으로 동일.
- 부수: iOS 컴포지터에 Mac BUG-06 패리티 `fittedToCanvas` 적용(3지점+보조 레이어 — iOS에서도 종횡비 불일치가 코너 렌더됐음). 검증: `IOSRenderPlanParityTests` 4종(구조·2x 지속·**plan 프레임 vs 디코드 익스포트 luma 파리티**·다중 트랙 합성 기여) + StaticContract 2건 신형상 갱신. iOS 25/25·게이트 5/5·Mac 38/38.

### RENDER-02 (P2) — 익스포트 디코드 luma 드리프트 — **해결(2026-08-26, 88a7860)**

- 특성화(2026-08-25): 프리셋 익스포트 경로(AVAssetExportSession — 색상 태그 제어 불가)의 **안정적 디코드 관행** — 디코더가 기본 YUV 매트릭스/범위를 선택. 그레이드 포화 레드에서 ~21/255. Mac 라이터 경로는 Rec.709 태그 명시로 무드리프트.
- **해결(2026-08-26)**: iOS 익스포트를 `AVAssetWriter`(플래너 출력 설정 — SDR H.264에 Rec.709 명시 태그) + `AVAssetReader` 출력으로 전면 교체. **드리프트 21 → 3.09 실측 붕괴**; 파리티 밴드 26 → <8로 조임(태그 회귀 시 ~21로 돌아 즉시 실패).
- 과정에서 발견·수정된 실제 결함 2건+테스트 결함 1건(전부 실측 고착): ①**교착** — 오디오 writer input이 있는 상태에서 비디오 pump를 단독 선행하면 비디오 큐가 영구 정지(오디오 포함 컴포지션 전부 행업·뮤트는 정상·스택샘플로 전 파이프라인 유휴 확인) → 태스크그룹 **병렬 pump**로 해결. ②리더/라이터 오디오 포맷 정합(리더가 라이터의 48k 스테레오로 변환). ③**테스트 측정 버그** — 스테레오 interleaved 버퍼를 mDataByteSize/4로 읽어 타임라인 2배+L/R 교차(모노 44.1k 프리셋 시대엔 은폐, 48k 스테레오 라이터에서 발각) → 채널 스트라이드 추출로 수정, 페이드 테스트 실측 통과.
- 검증: iOS 전체 47/47(오디오 페이드·이미지·전환·회전이 전부 새 라이터 탑승) · verify_gate 5/5(Core 1,413).

### CANVAS-01 (P1) — 캔버스만 변경한 프로젝트의 출력 비율 무시 — **수정 완료(2026-08-25)**

- 수정 완료: `makeRenderPlan`이 **상시** videoComposition을 부착(RENDER-01 구조 위에서 자연 해결) — renderSize가 캔버스에서 오므로 클립 효과 없는 프로젝트도 캔버스 비율·배경이 출력·프리뷰에 보장됨. 검증: `IOSCanvasRatioGoldenTests` 4종(9:16→1080×1920·1:1→1080×1080 실측, plan renderSize, 파란 배경 레터박스 가시성+중앙 레드 콘텐츠). iOS 29/29·게이트 5/5·Mac 38/38.

### BUG-IOS-06 재개방 (P1) — MediaBrowserView 경로 잔여 — **수정 완료(2026-08-25)**

- 수정 완료: `IOSEditorViewModel.importFromPhotosPicker(_:)` 공유 임포터로 통합 — 파일 URL 전송 + 1MiB 버퍼 복사 + 검증 probe + 타임라인 배치 + 오류 표면화. 상단 피커·MediaBrowserView 모두 이 단일 경로 호출(뷰 로컬 복사 전면 폐지, Data 적재 재발 구조적 차단).

### AUTOSAVE-02 (P1) — iOS autosave 실패 미표시·비직렬 저장 — **수정 완료(2026-08-25)**

- 수정 완료: ① 직렬 coordinator — 편집마다 세대 번호 증가, 단일 worker Task가 150ms 디바운스 후 **최신 스냅샷만** 기록(이전 worker 취소, 완료/실패 상태 갱신은 해당 세대가 최신일 때만 적용 — 오래된 결과가 새 상태 덮어쓰기 차단) ② 실패 배너 — `autosaveFailureMessage` 상단 주황 캡슐+접근성 라벨(en/ko) ③ 손상 복구 파일 — `lastAutosaveLoadFailure` 소비, 제거 사실+원인 안내.

### MACUI-01 (P1, 인프라) — Mac UI 테스트 러너 부트스트랩 실패 — **진단 완료·사용자 조치 대기**

- 진단(2026-08-25): 최소 단일 테스트도 `MovieCutMacUITests-Runner (pid) encountered an error (The test runner hung before establishing connection.)`로 일관 실패. 재현 조건 전부 시도: ① stale 프로세스/러너 번들 제거 후 재시도 ② 부호화 무효화/기본 ad-hoc 양쪽 ③ 크래시 리포트 없음(러너 자체는 크래시하지 않고 XPC 연결 수립 전 교착). **제품 결함 아닌 머신 환경 문제로 판정** — macOS 26.5에서 xcodebuild/XCTest 러너의 TCC(접근성/개발자 도구) 권한 또는 러너 데몬 상태 의심.
- **사용자 조치**: 시스템 설정 → 개인정보 보호 및 보안 → 접근성·개발자 도구에 터미널/xcodebuild 추가(또는 재부팅 후 재시도). 복구 확인 후 CI 차단화(기존 결정 유지).

## 1.12 외부 리뷰(2026-08-26) 검증 등록 — 출력 정확성·생존성 (실사 확정)

> 원천: 사용자 제공 리뷰(최근 10커밋 점검). 8건 주장 전부 코드 대조로 확정(3개 탐색 패스 + 직접 열독). 반영계획 승인: Phase 0(게이트 복구) → 1(P0 출력 정확성) → 2(P1 생존성) → 3(게이트 강화·전략 문서).

### GATE-01 (P0 인프라) — swift test 교착 시 게이트 무기한 대기 — **수정 완료(2026-08-26)**

- 원인: `CriticalHighCommandTests.testInitSucceeds`의 `AudioComponentFindNext`(오디오 컴포넌트 레지스트리 동기 조회)가 전체 Core 스위트의 AVAudioEngine-heavy 병렬 스위트와 만나 교착(08-26 게이트 FAIL 직접 원인 — 로그에서 해당 테스트 시작 후 종료 없음). `AudioEqualizerService.init`는 AVAudioEngine+AVAudioUnitEQ 생성뿐이라 프로브가 보호하는 것 없음.
- 수정: 프로브 제거(init 자체만 단언) + `verify_gate.sh` step 2에 와치독 타임아웃(기본 900s, `SWIFT_TEST_TIMEOUT_S` 오버라이드)·tee 스트리밍(command substitution 버퍼링 폐지).

### BUG-08 (P0) — normal 멀티트랙 합성이 하위 트랙을 무시 (Mac·iOS 공통) — **수정 완료(2026-08-26)**

- 등록: Mac `CustomVideoCompositor.swift:457-462`(요구사항 4.3 pixel-identity 게이트)와 iOS `IOSCustomVideoCompositor.swift:423-428`(복제본) 모두: 활성 클립 전부 normal blend면 `layerActiveTracks`가 primary만 반환. 상단 클립 opacity<1·mask·crop 오버레이에서 하단 트랙이 사라지고 캔버스 배경이 보임. 기존 iOS 다중 트랙 테스트는 상·하단 같은 빨강 픽스처로 이 결함을 구분하지 못함.
- **실측으로 밝혀진 제2의 결함(iOS)**: `CustomCompositionClipEffect.init?`이 시각 편집 없는 항등 클립에서 nil을 반환 — iOS 엔진이 `includeIdentitySource`를 전달하지 않아 **편집 없는 기본(하단) 트랙의 효과가 아예 생성되지 않았음**. Mac은 code-review #7 시절부터 동 플래그를 전달(ExportEngine.swift:811). 게이트 제거만으로는 부족하고 이 플래그가 진짜 복구였음.
- 수정(2026-08-26): ①양 플랫폼 게이트 제거 — `guard !activeEffects.isEmpty`만 남겨 단일 트랙 byte-identity 보존 ②iOS 엔진 `includeIdentitySource: true` 전달. 검증: 이색 픽스처(solid_red/solid_blue)로 opacity 0.5 오버레이·ellipse 마스크 오버레이에서 하단 청색 기여 단언 — iOS `IOSRenderPlanParityTests`(플랜 프레임 실측) 2종 + Mac `MultitrackNormalBlendPixelTests`(실 컴포지터 구동) 2종 신설. iOS 31/31·Mac 44/44·게이트 5/5.

### BUG-IOS-08 (P0) — iOS 렌더 계획이 회전 메타데이터를 잃음 — **수정 완료(2026-08-26)**

- 등록: `IOSExportEngine.swift`의 `CustomCompositionClipEffect` 생성이 `sourcePreferredTransform` 미전달(Core 초기화자 identity 기본값) + iOS 컴포지터에 `orientedForDisplay` 부재(primary·보조 트랙·전환 3경로 모두 무회전 핏). Mac BUG-07 수정(3835f5a)의 iOS 대응 누락.
- 수정(2026-08-26): `makeVideoComposition`이 합성을 받아 트랙 pt를 효과에 전달 + 컴포지터 3경로에 `orientedForDisplay` 래핑(Mac 657-678 포팅). 검증: `ca04_rotated_asym` 비대칭 픽스처로 **플랜 프레임(프리뷰 경로) + 실제 출력 파일 디코드(autorotate 플레이어 관점) 양 다리**에서 상=적/하=청 upright 단언 — 이중 회전도 함께 차단. iOS 31/31.

### G-15 AC6 (P0) — iOS 이미지 클립이 렌더 입력에서 누락 — **수정 완료(2026-08-26, AC5 동시 완료)**

- 등록: `IOSExportEngine`이 `.kind == .video`만 필터링(228·268·414 3곳) — 타임라인은 `.image` 클립을 만들지만 사진 전용 프로젝트는 export 실패(`noExportableMedia`)·프리뷰 공백. Mac은 `mediaAsset.kind == .image` 기반 `ImageVideoRenderService` 사전 렌더로 처리(ExportEngine.swift:353-368).
- 수정: `ImageVideoRenderService`를 Core(`Sources/MovieCutCore/Rendering/`)로 이동해 양 플랫폼 공유 + `makeRenderPlan` 트랙 삽입에 이미지 사전 렌더 분기(캔버스 크기·Ken Burns 전달, Mac 패리티) + 임시 세그먼트 수명 관리(직전 플랜 세그먼트 정리). 검증: PNG(청)·HEIC(녹) 플랜 렌더, EXIF orientation 6 upright(상=적/하=청), **사진 전용 프로젝트 export E2E(AC6)** — `IOSImageClipPipelineTests` 4종. iOS 35/35.

### BUG-IOS-09 (P1) — iOS 전환이 렌더 instruction에 전달되지 않음 — **수정 완료(2026-08-26)**

- 등록: `clip.transition`은 프로젝트에 저장되나 `transitionEffects` 생성 경로 부재(항상 빈 배열 — `CustomCompositionInstruction` 기본값).
- 수정(2026-08-26): Mac `makeTransitionEffects`(ExportEngine 831-882) + overlap back-timing(397-404) 포팅. 구조: 전환 보유 트랙은 비디오·오디오 **2 슬롯 교차 배치**(컴포지터가 트랙별 소스 프레임을 읽으므로 2-소스 전환에 필수) + 수신 클립 백타이밍(전환 길이만큼 조기 시작, 음성 포함 — 슬롯이라 충돌 없음). 효과/경계는 조정된 시간을 따르고 합성 길이가 실제 길이(중첩 축소 반영)에서 옴. 전환 없는 트랙은 기존 단일 트랙 레이아웃 그대로(byte-identity 보존). 컴포지터의 2-소스 전환 브랜치(기존 비활성 코드)가 활성화 — 공유 `TransitionPixelProcessor`로 전 유형 렌더.
- 검증: `IOSTransitionPipelineTests` 3종 — 구조(2슬롯·3.4s 중첩 길이·전환 1건)·전환 없는 트랙 단일 유지·**플랜 프레임 실측(창 전 순수 적 → 중간 혼합 → 창 후 순수 청)**. iOS 38/38.

### BUG-IOS-10 (P1) — iOS 볼륨·페이드가 출력·프리뷰에 미반영 — **수정 완료(2026-08-26)**

- 등록: `AVMutableAudioMix`·volume ramp가 iOS 전무(UI만 존재, 프리뷰도 원본 오디오 그대로).
- 수정(2026-08-26): 렌더 계획에 `audioMix` 추가 — 삽입 시점에 실제 배치 구간(속도 스케일·백타이밍 반영)을 수집해 클립 볼륨+fade in/out 램프 구성(Mac `applyAudioVolumeAndFades` 패리티, 램프는 배치 구간에 클램프·겹치면 균분). 편집 없는 프로젝트는 mix nil(무변경). `AVPlayerItem.audioMix`(프리뷰)·`AVAssetExportSession.audioMix`(출력) 양쪽 부착.
- 검증: `IOSAudioMixPipelineTests` 3종 — 믹스 적용 리더 경로(플레이어/출력이 소비하는 동일 경로)에서 head/tail RMS < plateau 40% 실측, 편집 없으면 nil, **실제 출력 파일**에서 페이드 인/아웃 감쇠 실측. iOS 41/41.

### STICKER-01 (P1) — iOS 스티커 선택 콜백이 입력을 버림 — **수정 완료(2026-08-26)**

- `iOSContentView.swift:287` `onSelect: { _ in }` — 피커는 dismiss하지만 클립이 생성되지 않음. Mac `EditorViewModel.addSticker`(1951-1995) 패턴으로 `ensureTrack(.text)` + `AddClipCommand` + `TextClipContent(contentKind: .sticker)` 발행(emoji 우선).
- 수정(2026-08-26): `addSticker(_:)` 구현(Mac 패리티 — emoji 우선, 공유 `CanvasGeometry.defaultStickerPlacement` 배치, popIn 애니메이션) + 피커 콜백 연결. 커밋 f184401.

### SURV-01 (P1) — iOS 임포트 미디어가 임시 디렉터리에 저장 — **1차 완료(2026-08-26)**

- `IOSEditorViewModel.swift:481-489`가 PhotosPicker 파일을 `temporaryDirectory/MovieCutiOSImports`에 복사 후 절대경로 저장 — OS가 임시 파일 정리 시 복구 프로젝트만 남고 원본 소멸(CA-03 미디어 생존성 감사의 iOS 누락 영역). Application Support managed-imports 영역·상대 참조·missing-media preflight·relink 정책 필요. 부수: autosave background 진입 즉시 flush 부재(150ms 디바운스만) + 고정 sleep 기반 플래키 테스트(IOSPersistenceTests 200ms sleep) → 폴링 전환.
- 1차 수정(2026-08-26): Core `ProjectStore.defaultImportsDirectory()`(App Support/MovieCut/Imports) + 프로젝트별 하위 디렉터리 복사(`stagedImportDestination`) + 복구 시 결측 원본 표면화(relink UI는 후속). 부수 해소: scenePhase background 즉시 flush + 플래키 테스트 폴링 전환(f184401) + `IOSMediaSurvivabilityTests` 2종. 잔여: 상대 경로 참조·relink UI·정리 정책.
- **2차 완료(2026-08-26, 루프 회차 — 중단 인계 후 마무리)**: ①`MediaAsset.managedImportPath`(상대 참조 — Codable 하위호환) ②`ProjectStore.rebaseManagedImports`(복구 로드 시 죽은 절대경로를 상대 참조→레거시 접미사 매칭 순 재결합, 컨테이너 경로 변경 생존) ③relink UI(결측 배너+fileImporter → `relinkMedia` — 자산 UUID 유지해 클립 참조 보존, 교체본 관리 루트로 복사) ④`cleanupOrphanedImports`(미참조+7일 유예 정리 정책). 검증: `IOSMediaSurvivabilityTests` 6종(상대/레거시 재결합·relink E2E·정리 정책) + iOS 47/47 + 게이트 5/5.

### RACE-01 (P1) — iOS 프리뷰 재생성 stale-result 경합 + 중복 오버레이 — **수정 완료(2026-08-26)**

- `PreviewView.swift:111-142`: rebuild마다 추적 안 되는 Task 생성(취소·세대 검사 부족) — 느린 이전 빌드가 나중에 끝나면 stale AVPlayerItem 설치. + AVPlayer가 이미 videoComposition을 렌더하는데 최대 15fps `copyCGImage` 오버레이를 얹어 재생 프레임률·전력 손해(중복 렌더). Mac `PlaybackEngine` 세대 토큰 패턴(164-168·216-236) 이식 + 오버레이 경로 제거.
- 수정(2026-08-26): 세대 토큰+빌드 Task 추적·취소(Mac 패리티) + 15fps CPU 오버레이 전면 제거(플레이어가 플랜의 videoComposition을 직접 렌더 — 스크럽도 seek 타깃 프레임으로 해결). 커밋 f184401.

### L10N-01 (P1) — iOS 효과 인스펙터 한국어 하드코딩 31곳 — **수정 완료(2026-08-26)**

- `IOSEffectsInspectorView.swift` 57-354의 한글 리터럴 31곳이 카탈로그 키를 우회(source language en인데 영어 환경에서도 한국어 표시). 카탈로그에 이미 대응 키 다수 존재 — 영어 키 교체 + 부족 키 등록 + Swift 소스 Hangul 리터럴 차단 CI 검사. 함께: G-27 시뮬레이터 하니스가 공유 렌더 계획(`IOSExportEngine.makeRenderPlan`)이 아닌 레거시 `IOSPreviewCompositionBuilder` 사용(드리프트 위험) → 하니스 교체 후 레거시 빌더 삭제.
- 수정(2026-08-26): 31곳 영어 키 교체(verbatim 2건 포함) + 카탈로그 18키 등록 + `scripts/verify_no_hangul_literals.py` CI 차단 도입(4d881cb). G-27 하니스는 `makeRenderPlan` 구동으로 교체 + 레거시 빌더 삭제(012c10e).

---

## 1.13 CA-12 벤치마크 하니스 발견 결함 (2026-08-27 등록)

> 원천: CA-12 첫 기준 수치 실측 중 하니스가 포획(`docs/CA12_AB_BENCHMARK_20260827.md` §6). 둘 다 기존 도구 교차검증으로 확정.

### BUG-CA12-01 (P2 인프라) — 파리티 하니스×덕킹 조합의 태스크 파킹 — 미수정(조사 심화됨)

- 증상: 파리티 경로(`MOVIECUT_UITEST_PARITY=1`)에서 `MOVIECUT_UITEST_DUCKING_*` 게이트 적용 직후 태스크가 재개되지 않음 — 체크포인트 `scenarios_applied`에서 영구 정지(0% CPU·메인 스레드 런루프 유휴). **결정론 재현**: `WATCHDOG_S=180 bash scripts/run_ca12_ab_benchmark.sh ab09`.
- **조사 결과(2026-08-27 심화)**: ①파킹은 composition 재구성 이후 **첫 필수 서스펜션 지점마다 이동** — 순서 재배열(덕킹을 비억제 창에서 먼저 실행)로 composition_ready까지는 통과하지만 스냅샷 대기 루프에서 동일 파킹(→재배열은 폐기). ②`Task.sleep`·`Task.yield` 모두 재개 안 됨(시계 문제 아님). ③**`DispatchQueue.main.async` 블록도 전달 안 됨(GCD 레벨)** — 반면 앱 활성화 등 런루프 이벤트는 계속 처리됨(메인 런루프 모드 kCFRunLoopDefaultMode 정상·lldb 확인). ④전역 협력 풀은 생존(detached 하트비트 1틱 기록) — 이후 MainActor.run 홉에서 정지. ⑤덕킹 **램프 적용(APPLY)과 무관**(오디오 트랙 존재 자체가 트리거)·크로마키 게이트는 무관·일반 경로 덕킹 E2E는 통과. 종합: **메인 디스패치 큐의 전달이 영구 정지하는 OS/AVFoundation 계열 결함**(W4 ProRes 교찰의 "once-continuation 파킹(Apple측)"과 같은 부류로 추정) — 루프 내 도구로는 근본 원인 특정 불가.
- 부산물(유지): `snapshotFrame`의 seek completion 누수 방어 와치독(2s 경합·1회 재개 보장 — AVPlayer 공식 문서상 완전 핸들러 미보장 클래스). 파리티 스윕 13/13 무회귀 확인.
- **재현 경로 추가(2026-08-29, BUG-ACC-02에서 병합 — 메인 세션)**: W1 acceptance 실덕킹 경로에서 동일 파킹 — `autoDuckOtherAudio`(SilenceDetectionProvider 실분석) 호출 직후 60초 실발화(say 생성)에서 메인 런루프 유휴·워커 부재·첫 스텝조차 미기록(스택 샘플 2026-08-29 — 메인 스레드 mach_msg 대기만 존재). **1커맨드 재현: `bash scripts/run_w_acceptance.sh w1`**(STRICT — ducking 스텝 `path=analysis` 직후 무출력, 러너 900초 회수). 파리티×덕킹 '조합'이 아니라 덕킹 **분석 경로 자체**가 트리거일 가능성 — 에스컬레이션 조사 범위에 SilenceDetectionProvider.analyze의 continuation 포함 권장.
- 잔여: 재현은 1커맨드로 고정됨(ab09 + 위 acceptance w1 경로 2종). 근본 수정은 AVFoundation/OS 상호작용 추적 필요(별도 증분 — 상위 도구·에스컬레이션 후보). CA-12 fixture ⑨ 수치 공백 유지.

### BUG-CA12-02 (P1 후보) — HDR(BT.2020+PQ) 태그 소스의 preview↔export 픽셀 발산 — 미수정(메커니즘 확정·G-29 연계)

- 증상: `ca04_bt2020pq` 소스 패스스루에서 프리뷰 PNG 대비 출력 PSNR 15.1dB·ΔE mean 10.98. 기존 파리티 비교기 교차 FAIL(MAD 11.26 vs 허용 2.0) — CA-12 pair 메트릭 정합성 확인 완료.
- **메커니즘 확정(2026-08-27)**: 대부분 밴드는 일치(Δ≤2)하나 **고채도 시안 밴드만 프리뷰에서 핑크로 뒤집힘** — 프리뷰(plain 경로·플레이어 다리)는 AVFoundation이 HDR 태그 소스를 SDR 렌더 표면에 맞춰 변환하며 그 변환이 범위 밖 색을 뒤집는 것. 출력은 원시 재해석(bt2020 매트릭스 RGB 그대로 — CA-04가 검증한 v1 SDR 계약·소스 프레임과 MAD 2.49로 충실).
- **시도·부정된 수정 2건**: ①스냅샷 최종 변환의 작업공간 고정(`RenderColorConfiguration.sourceImage`) — 버퍼가 이미 변환돼 도착해 효과 없음(측정 MAD 11.13→11.07 노이즈). ②합성 색 삼중항 Rec.709 명시(player+reader 양 다리) — reader 다리는 삼중항을 색 변환에 소비하지 않아 효과 없음(11.07). 둘 다 폐기(측정 증거 없는 배선 금지 원칙). ①의 스냅샷 고정은 후속 HDR 파이프라인을 위한 원칙적 핀으로만 유지(주석에 행동 중립 명시).
- 본수정 방향: 양 다리가 동일 해석을 하도록 **HDR 인입 형식을 수용하는 컴포지터 + 공유 변환** 필요 — G-29(HDR-ready 파이프라인, 3단계)의 입력 요구사항으로 이관. 혼합(HDR+SDR) 소스 프로젝트의 처리 정책도 함께 설계 대상.

## 1.14 Codex 봇 리뷰(스택 PR) 파생 결함 (2026-08-29 등록)

> 원천: 스택 PR #19~#23(2026-08-29 push)에 `chatgpt-codex-connector[bot]` 자동 리뷰가 남긴 지적 — 전부 현재 HEAD 코드 대조로 판정(유효=등록, 이후 스택에서 이미 해결=회신만, 기존 등록과 중복=상호 참조). 본 PR들은 게이트 통과 스냅샷이므로 병합 블록으로 삼지 않고 후속 증분으로 처리. 스레드는 등록 회신 후 해결 완료.

### CODEX-01 (P2) — 타임코드 표시 프레임 양자화 하방 드리프트 — 미수정

- 증상: 프레임 정렬 시각에서 부동소수 오차로 곱이 정수보다 약간 작아 `Int` 절단이 이전 프레임으로 내려감 — 예: 30fps에서 `00:01:02` 입력은 `1 + 2/30`로 시크하나 표시 계산이 `1.9999999999999996`을 산출해 즉시 `00:01:01` 표시. 파서↔표시 왕복(CA-27 계약)이 다수 프레임값에서 깨짐. 위치: `App/MovieCutMac/PreviewPanel.swift` L850 부근.
- 수정 방향: 허용 오차 양자화(반올림) 또는 유리수/정수 시간 연산으로 프레임 인덱스 유도.

### CODEX-02 (P2) — LUT 재내보내기가 기존 대상 파일을 오류 보고 전에 삭제 — 미수정

- 증상: 기존 대상 경로 선택 + 관리 LUT 원본 결측 또는 후속 복사 실패 시, export 오류를 보고하기 전에 사용자의 기존 파일을 제거 — 실패한 export가 이전 LUT를 파괴(데이터 손실 인접). 위치: `App/MovieCutMac/EditorViewModel.swift` L5204 부근(CA-26 경로).
- 수정 방향: 임시 형제 파일에 기록/복사 후 새 파일 완성 뒤에만 원자적 치환 — ProjectStore ENOSPC fail-closed(2026-08-27)와 동일 패턴.

### CODEX-03 (P2·A류) — verify_doc_paths 백틱 경로 누수 — 미수정

- 증상: 추출 정규식이 슬래시 끝 매칭을 요구해 `` `docs/DOES_NOT_EXIST.md` `` 형태가 `docs/`로만 추출되고, 인식된 확장자 부재로 `check_backtick`이 무시 — 차단 CI 검사가 도입 취지인 백틱 파일 참조 검증을 놓침. 위치: `scripts/verify_doc_paths.sh` L78 부근.
- 수정 방향: 닫는 백틱까지 매칭. **A류(계측 스크립트 개선) — 루프 자율 실행 가능.**

### CODEX-04 (P1) — PhotosPicker URL transferable가 라이브러리 선택에서 nil 반환 가능 — 미수정 (PR #20)

- 증상: `importFromPhotosPicker`가 `item.loadTransferable(type: URL.self)` 사용 — PhotosPickerItem은 일반적으로 선택 미디어를 파일 표현으로 노출하므로, 라이브러리 선택이 URL 값 전송을 지원하지 않으면 nil 반환 → 모든 사진·영상 임포트가 transferFailed로 종료 가능. iOSContentView·MediaBrowserView 양 진입점이 동일 경로. 위치: `App/MovieCutiOS/IOSEditorViewModel.swift` L529.
- 수정 방향: `FileRepresentation` 기반 소형 `Transferable` 정의 후 수신 파일 URL 복사. **실기기 확인 필수(G-27 연계)** — 시뮬레이터 테스트는 파일 URL 경로라 이 결함을 못 잡음.

### CODEX-05 (P2) — 취소 export의 부분파일 정리가 공유 activeOutputURL에 결합 — 미수정 (PR #20)

- 증상: `cancelExport()`가 즉시 `isExporting=false`로 돌려 UI가 새 export를 시작할 수 있음. 새 export가 공유 `activeOutputURL`을 교체한 뒤 이전 취소 호출의 catch가 `removePartialOutput()`에 도달하면 **새 export의 출력 파일을 삭제**하고 엔진 상태를 초기화. 위치: `App/MovieCutiOS/Export/IOSExportEngine.swift` L335-364.
- 수정 방향: 실패한 호출의 국소 URL 또는 export 세대(generation) 번호로 정리 결합.

### CODEX-06 (P2·기능 회귀) — 정상 AIFF가 임포트 거부(BUG-02 경화 회귀) — 미수정 (PR #20)

- 증상: `.aif`/`.aiff`는 audioExtensions에 있으나 knownSignatures에 IFF `FORM` 시그니처 부재·weakMagic 예외(mp3/aac만)도 아님 → 유효한 AIFF도 `.unrecognizedContent`로 기각. 2026-08-24 BUG-02 스니핑 도입의 회귀(이전엔 임포트됨). 위치: `Sources/MovieCutCore/Media/MediaImporter.swift` L107-167(헤더 창 매칭 실패 = 무조건 throw 경로 실측 확인).
- 수정 방향: RIFF와 동일 패턴으로 `FORM` 시그니처 추가(종류는 확장자로 판정) + 실제 AIFF 픽스처 왕복 단위테스트. 기존 지원 포맷 회귀라 P2 상단 배치.

### CODEX-07 (P1) — relink 후 iOS 프리뷰가 재구축되지 않음 — 미수정 (PR #21)

- 증상: `relinkMedia`는 `currentProject.mediaLibrary`만 갱신하는데 `PreviewView`는 `.onChange(of: currentProject.timeline)`(L109)에서만 렌더 플랜을 재구축 — 원본 결측 상태에서 만든 플랜의 빈/부분 `AVPlayerItem`이 그대로 남아 relink된 클립이 무관한 타임라인 편집·뷰 재생성 전까지 재생 불가. 위치: `App/MovieCutiOS/Views/PreviewView.swift` L109·`IOSEditorViewModel.swift` L570.
- 수정 방향: mediaLibrary 변경(또는 relink 완료) 시 플랜 재구축 트리거 — SURV-01 왕복 테스트에 "relink 후 프리뷰 재생" 다리 추가로 고착.

### CODEX-08 (P1) — 혼합 회전 트랙에서 클립별 orientation이 트랙 단위로 덮어씌워짐 — 미수정 (PR #21)

- 증상: 클립 이펙트의 `sourcePreferredTransform` 소스가 composition **트랙의** `preferredTransform`(IOSExportEngine.swift L560-562)인데, 이 값은 `insertClip`이 **첫 비디오 소스** 삽입 시만 설정(L1032-1033) — 같은 트랙에 회전 메타데이터가 다른 클립이 뒤따르면 첫 클립의 방향을 상속해 옆으로 눕거나 잘못 회전. BUG-IOS-08 수정이 단일 회전 픽스처로만 검증돼 혼합 케이스가 빠짐. 위치: `App/MovieCutiOS/Export/IOSExportEngine.swift` L560·L1032.
- 수정 방향: 클립 소유의 `AVAssetTrack.preferredTransform`을 클립별로 로드해 이펙트에 전달(트랙 pt는 외부 플레이어 메타데이터로만 유지) + **혼합 회전(가로+세로) 트랙 픽스처**로 upright 실측.

### CODEX-09 (P1) — 전환 배치는 raw 지속시간·이펙트 창은 클램프 — 초과 시 클립 무음 드랍 — 미수정 (PR #21)

- 증상: 백타이밍 배치가 요청한 `transition.duration` 그대로 시작을 당김(L878-884)하나 이펙트 창은 인접 클립 길이로 클램프(L758-762) — 요청이 인접 클립보다 길면 배치가 실제 오버랩보다 앞서 커서가 역전하고, `insertClip`의 `timelineStart >= cursor` 가드(L1020)가 **셋째 클립을 조용히 반환(드랍)**. 짧은 3클립 + 긴 전환 조합에서 발생. 위치: `App/MovieCutiOS/Export/IOSExportEngine.swift` L758·L878·L1020.
- 수정 방향: 배치와 이펙트가 동일한 클램프된 지속시간을 사용(단일 계산 함수로) + 초과 전환 픽스처로 3클립 완주·드랍 0 단언.

### CODEX-10 (P1·A류) — 블라인드 투표 라벨이 구현화 파일과 불일치 — 약 반수에서 반대 편집기로 집계 — 미수정 (PR #22)

- 증상: `x_is_a=False` 시 `_X.mp4`=B측·`_Y.mp4`=A측으로 구현화는 정상인데 투표표의 X열이 `_Y.mp4`(=A측)를 안내 — 평가자의 X 선호가 mapping(X↔B)에 따라 **반대 편집기로 집계**. 블라인드 비교 결과를 왜곡. 위치: `scripts/ab_benchmark_metrics.py` L485-487.
- 수정 방향: 투표표는 항상 `<fixture>_X.mp4`를 X열에 고정(해독은 mapping 테이블이 담당) + 라벨/구현화 정합 셀프테스트. **A류(계측 스크립트) — 루프 자율 실행 가능.** B측 블라인드 평가 개시 전 필수.

### CODEX-11 (P1·A류) — REPS>1이 전부 실행되나 baseline은 rep1만 읽음 — 미수정 (PR #22)

- 증상: `REPS>1`이면 전 반복 실행·조건 필드에 반복 수 기록하나 `baseline.json`은 rep1만 집계(L283-284) — 중앙값/p95를 기록한다는 조건 노트(L133)와 달리 **단일 표본을 통계 집계처럼 보고**. 위치: `scripts/run_ca12_ab_benchmark.sh` L272-284·L321.
- 수정 방향: `rep_results` 전부 소비해 median/p95 산출 + 단일 rep 시 명시. **A류 — 루프 자율 실행 가능.**

### CODEX-12 (P2) — 레거시 AVFoundation 취소가 취소로 분류 안 됨 — 미수정 (PR #22)

- 증상: macOS 14 배포 대상의 레거시 브랜치에서 `cancelExport()` 후 `session.error`(AVFoundation 오류)가 throw되어 `catch is CancellationError`(`EditorViewModel+Media.swift` L124)를 우회 — 정상 취소가 "Proxy generation failed"로 보고되고 `autoProxyCancelledCount` 미증가. 현대 브랜치(개발기·CI macOS 15)만 게이트가 통과해 레거시 경로가 무검증.
- 수정 방향: Task 취소 상태 또는 AV 취소 오류도 취소로 분류 + 레거시 브랜치 재현 테스트.

### CODEX-13 (P2) — 수동 프록시 생성이 진행 중 가드를 우회 — 미수정 (PR #22)

- 증상: 자동 생성 활성 시 미디어 카드·컨텍스트 메뉴의 수동 `generateProxy(for:)`(`EditorViewModel+Media.swift` L63-73)가 `autoProxyGenerating` 집합을 안 거침 — 동일 자산에 두 export가 같은 URL에 동시 기입 가능, `proxyInfoIfReady`의 비어있지 않은 파일=준비 완료 판정이 첫 export의 부분파일을 부착할 수 있음.
- 수정 방향: 수동 진입도 동일 스케줄러/가드 경유 또는 추적 중 수동 비활성화.

### CODEX-14 (P2) — 비트 마커 삭제가 유효 선택 없이는 도달 불가 — 미수정 (PR #22)

- 증상: 소스 클립 삭제 후 마커 잔존·텍스트/이미지 클립 선택 시 `canDetectBeats=false`가 유일한 진입 버튼을 비활성화(`iOSContentView.swift` L844) — Detect/Clear 다이얼로그의 Clear가 의도(마커 존재 시 항상 가능 — L351-353 주석)와 모순되게 도달 불가. 위치: `App/MovieCutiOS/iOSContentView.swift` L844.
- 수정 방향: `canDetectBeats || hasBeatMarkers`일 때 툴바 활성, 다이얼로그 내 Detect만 선택 게이트 + 마커 잔존(소스 삭제 후) 정리 테스트.

### CODEX-15 (P2) — iOS 스냅 가이드가 드래그 중 렌더되지 않음 — 미수정 (PR #22)

- 증상: `snappedTime`이 `onEnded`에서만 호출(`IOSTimelineView.swift` L223-238)되고 같은 핸들러가 `draggedClipId`·`snapGuideTime`을 즉시 해제 — SwiftUI가 새 가이드를 렌더할 기회가 없음. Mac 구현은 onChanged에서 임시 위치·가이드 계산.
- 수정 방향: `onChanged`에서 임시 스냅 위치·가이드 계산(레이아웃 변경 없이 가이드만 표시 — 결정성 게이트 무영향 확인 후).

### CODEX-16 (P2) — 비트 틱이 HStack 셀 기준 오프셋으로 누적 드리프트 — 미수정 (PR #22)

- 증상: 각 틱의 오프셋이 순차 HStack 셀에서 측정(`IOSTimelineView.swift` L73-76) — 앞선 마커마다 2pt씩 표시 위치가 누적 이동(밀집 곡에서 큰 드리프프), 트랙 헤더 76pt·행 간격 미반영으로 전체가 좌측 편이. 장식용(비인터랙티브)이라 기능 영향은 없으나 시각적으로 마커 위치와 불일치.
- 수정 방향: 공통 ZStack/canvas 좌표계에 배치 + 헤더 원점 반영.

### CODEX-17 (P1) — iOS 플레이헤드 트림이 비정규 시간 매핑 사용 — 미수정 (PR #23)

- 증상: `trimSelectedClipStartToPlayhead`·`trimSelectedClipEndToPlayhead`(`IOSEditorViewModel.swift` L1329·L1350)가 `trimClip`(L1074)에 위임 — 타임라인 1초=소스 1초 가정이라 2x 속도 클립을 0.5초 트림하면 실제 1.0초가 남아야 하나 0.5초만 남겨 조기 절단·갭 발생, 리버스 시작 트림도 반대 소스 엣지 이동. **iOS 전체에 ClipTrimMath 사용 0건(Mac은 4경로 사용) 실측.**
- 수정 방향: 양 플레이헤드 동작을 `ClipTrimMath.compute` 경유로 전환(Mac 패리티) + 속도 램프·리버스 픽스처 트림 왕복 테스트.

### CODEX-18 (P2) — fps 프리셋 변경이 undo 2단위 — 미수정 (PR #23)

- 증상: 프리셋 선택이 `SetProjectCanvasCommand`(`IOSEditorViewModel.swift` L1145)와 `SetProjectExportSettingsCommand`(L1156)를 개별 dispatch — undo 1회가 exportSettings.frameRate만 복원해 캔버스·타임라인은 새 fps에 남아, 이 동기화가 막으려던 불일치가 undo로 재발.
- 수정 방향: 단일 커맨드 원자화(또는 세션 트랜잭션) + undo 1회 전체 왕복 테스트.

### CODEX-19 (P2) — 트랙 z-index가 tracks.count 배정 — 삭제 후 중복·레이어 순서 비결정론 — 미수정 (PR #23)

- 증상: `CreateTrackCommand.apply`가 caller가 준 z-index를 정규화 없이 append — iOS(`IOSEditorViewModel.swift` L418)·**Mac(`EditorViewModel.swift` L4510) 모두** `zIndex: tracks.count` 배정. 기본 0/1/2에서 z0 삭제 시 잔여 2트랙 상태로 다음 추가가 2로 중복 → 프리뷰·export가 zIndex 정렬만 하므로 겹침 레이어 순서가 비결정론화.
- 수정 방향: 삭제 시 전체 재정규화 또는 max+1 배정 + 중복 z-index 0 단언 테스트(양 플랫폼).

### CODEX-20 (P2) — RemoveTrackCommand가 트랙 잠금을 무시 — 미수정 (PR #23)

- 증상: `RemoveTrackCommand.apply`(`CreateTrackCommand.swift` 내 정의)가 index 제거만 하고 `ensureTrackIsEditable` 미호출 — 트랙 관리 시트의 스와이프 삭제가 잠긴 트랙과 클립 전체를 삭제(RippleDelete·SlideClip 등 다른 커맨드는 검사 사용). `Track.isLocked`의 보호 의도와 모순.
- 수정 방향: 제거 전 잠금 거부(또는 잠금 시 UI 삭제 비활성) + 잠금 트랙 삭제 거부 테스트.

## 1.15 W acceptance 게이트 발견 결함 (2026-08-29 등록)

> 원천: STAB-04 1차 — 실길이 대표 작업 게이트(`run_w_acceptance.sh`·W_STRICT 하니스 모드) 구축 직후 실측. 스모크(2~4초 픽스처)가 구조적으로 가리고 있던 결함들 — 외부 리뷰 #2 "게이트가 실제 작업보다 약하다" 지적의 실증.

### BUG-ACC-01 (P1) — ProRes·명시적 비트레이트 출력에서 겹치는 오디오의 길이가 합산됨 — **수정 완료(2026-08-29)**

- **원인 판명(실측 이분법)**: 그래프 빌더·렌더러·audibleSampleEnd는 전부 배치 정상 — 범인은 **조정 레이어가 오디오 스트립으로 편입**된 것. w4의 조정 클립(자산 ID 차용·G-03 그레이딩 컨테이너)이 자기 압축으로 가시 클립 뒤 [2,6]으로 밀린 뒤 carriesAudio 필터를 통과(자산=비디오) → audible 범위가 2s+4s=6s로 팽창. 비디오 스트림은 조정 클립이 export에서 필터돼 2s 유지 — 오디오만 6s인 실측과 완전 정합. (일반 콤마 임포트의 6s는 멀티 URL 루프의 의도적 순차 배치 — 드롭 UX, 결함 아님.)
- **수정**: `AudioGraphProjectBuilder`가 `isAdjustmentLayer` 클립을 오디오 스트립에서 제외(G-03 "콘텐츠 렌더 없음"의 오디오 대응). 검증: Core 유닛(조정 레이어 무편입·audible ≤4s 단언) + 스모크 w4 실측 **6.000s→4.000s(프리셋·ProRes 양 경로)** + 스모크 W 5/5·29/29 + acceptance w4의 duration/audio/av_sync 어설션 통과(export 성공 시). 게이트 5/5.

- 증상: 2초 영상 + 4초 BGM(오버레이) 타임라인의 ProRes 출력이 **6.000초**(2+4 합산) — 프리셋/프리뷰 경로는 정상 오버레이. 300초+300초 실측에서도 600초 재현. 코덱 자체는 정상(prores·1920x1080·aac). **W4 acceptance 게이트가 이 계약 위반으로 RED 유지 중**(`duration` 어설션).
- 추정 원인: writer 경로의 오디오 그래프 믹스다운(graphAudioURL 생성)이 타임라인 배치(병렬) 대신 클립 순차 이어붙임으로 렌더 — 그래프 빌더의 배치 해석 조사 필요.
- 수정 방향: 그래프 믹스다운이 타임라인 배치를 존중하도록 수정 + 2초+4초 오버레이 픽스처로 4초 단언(프리셋 경로 패리티).

### BUG-ACC-04 (P1) — 5분 마스터 출력이 간헐적으로 전면 실패(양 경로 0바이트·오류 무표면) — 등록(2026-08-29)

- 증상: acceptance w4(5분 마스터)에서 프리셋 export가 **4회 중 2회 bytes=0** — w4.mp4·w4-prores.mov 모두 미생성, dump.error=none(오류 무표면), **prores 스텝만 거짓 OK**(exportProResMaster가 조용히 조기 반환 — 오류 상태 전파 결함 의심). 성공 시 395MB·300.00s·A/V 0.000 정상. 실패 run elapsed ~170s(성공 ~211-242s) — 조기 사망.
- 조사 재료: acceptance 러너가 앱 stdout/stderr를 버려 원인 불명이었음 → 러너에 `app.log` 보존·실패 시 워크디렉터리 유지·ffprobe 탐침 재시도(인코직 직후 조기 공탐 — 보존 파일 재탐침 정상)를 이미 보강. 다음 재현의 app.log로 BUG-CA12-01(메인 디스패치 정지) 계열 여부 판정. STAB-04 2차 관련.
- **판정 완료(2026-08-29 22:4x, 메인 세션 — 3차 재현 1회차 적중, LbbKfC 보존)**: 프로젝트 원형 라인이 직접 판정. 통과 run `video:[0..300, 300..600adj]` vs 실패 run **`video:[0..300adj, 300..600]`** — **같은 비디오 트랙에서 조정 클립과 실제 영상 클립의 순서가 뒤집힘**(양 add는 await 순차지만 magnetic 압축/배치의 순서가 비결정 — 무순서 컬렉션 순회 의심). 뒤집힌 경우 실제 영상이 [300,600]으로 밀려 컴포지션·그래프 600s 팽창 + **t=0을 덮는 클립이 조정 레이어뿐(`sourceTrackIDs=[]`인 요청 — 22:47:25 진단 라인)** → firstSourceFrame nil → `-1` → 양 export 사망. **수정 방향 확정**: ①본수정 = 배치/압축 순서 결정화(무순서 순회 지점 색출 — 순서가 뒤집혀도 실제 영상은 항상 [0,300]) ②방어 = 컴포지터가 빈 소스 요청을 에러 대신 캔버스 프레임으로 완료(전면 사망→완주). ①만이 정확한 출력(현 결함은 완주해도 영상이 뒤쪽 절반에 재생됨)을 보장.
- **원에러 특정·루트 사이트 고정(2026-08-29 21:4x, 메인 세션)**: 계기 적용 직후 재현(5인스턴스차 — FfaJav 보존·하니스 전파 개선도 작동 확인 `prores (err=...)`) 후 raw 로그 확보: **`Error Domain=MovieCut Code=-1 "(null)"`** — 이 도메인의 유일한 생성처는 **커스텀 컴포지터의 실패 전달**(`CustomVideoCompositor.swift` L357·`ChromaKeyCompositor.swift` L22의 `request.finish(with: NSError(domain:"MovieCut", code:-1))`). L357의 트리거 조건: **`firstSourceFrame(in:instruction:)`이 nil** — 해당 구간에 소스 프레임이 없거나 준비되지 않은 요청. 즉 5분 마스터 렌더 중 컴포지터가 특정 구간에서 소스 프레임을 못 얻어 export 전체가 사망. **2차 조사(2026-08-29 22시 루프 회차 — 진단 로깅 실장·팽창원 실측)**: nil 경로 상태 로깅 + 패키지 형상 로깅(`pkg shape`·`pkg project clips`, `diagLogCompositionShape` 플래그 — 수정 후 제거)을 실장하고 재현 6회(실패 2·통과 4). **핵심 실측**: 실패 run은 `composition=600s graphAudio=600s tracks=[vide:0..600 soun:0..600]` — 그래프 믹스가 600s(300+300 순차 재래)로 렌더되고 비디오 트랙까지 600s로 팽창. 통과 run은 전부 300s·프로젝트 원형 결정적(`video:[0..300, 300..600adj] audio:[0..300]` — 조정 클립은 항상 자기 압축으로 [300,600]·BUG-ACC-01 가드로 무해). **잔여 판정**: 간헐 변수는 프로젝트/세션 수준에서 BGM이 [0,300] 오버레이 대신 [300,600] 순차로 놓이는 것(또는 동등한 audible-600 상태) — 하니스 배치 코드는 결정적으로 보이므로 **다음 실패 재현의 `pkg project clips` 라인이 배치 vs 그 외를 직접 판정**(로깅 이미 실장·재현 레시피: `bash scripts/run_w_acceptance.sh w4` 반복 + `/usr/bin/log show --last 10m --predicate 'processImagePath CONTAINS "MovieCutMac" AND eventMessage CONTAINS "pkg"' --info`). 평탄화(FlattenedTimeline)는 무죄 확인(단순 통과·w4엔 컴파운드 없음). 부수: 탐침 재시도 보강(rc 기반 6×1s — 통과 run에서도 prores_codec 공탐 지속 관찰).
- **진단 돌파(2026-08-29 21:3x, 메인 세션 — unified log 사후 추출 성공)**: 셸 builtin `log`와의 충돌로 `/usr/bin/log` 직접 호출 필요(이전 공탐의 진짜 원인). 18:00-19:00 창 40,661줄 회복 — **실패 8라인 전부 `[com.moviecut.mac:export] export failed: 작업을 완료할 수 없습니다.(MovieCut 오류 -1.)`**(18:21·18:23·18:26·18:28·18:35·18:37·18:45·18:46 — 4 PID × 2회 = **메인+ProRes 동시 실패 실증**, 루프 run + 메인 run 포함). 판정: ① 앱은 catch에서 로깅하고 있었음 — w.json `error=none`은 **하니스가 lastErrorMessage을 dump에 전파하지 않은 것**(개선 1: dump.error에 lastErrorMessage 포함) ② "MovieCut 오류 -1"은 FileOperationError.classify가 **원 에러를 삼킨 래핑** — ExportEngineError/GraphMixRenderer 어느 케이스인지 로그상 판별 불가(**개선 2: catch에서 classified와 함께 원 에러 로깅** — 1차 조치 후 재현 1회로 케이스 확정) ③ 양 경로 동시 실패 → 공통 선행 단계(`renderGraphAudio`) 또는 그 하류 세션 생성이 후보 ④ 디스크 가설 약화(현재 23Gi 여유 — 단 4연속 run × 3.3GB transients의 일시 고갈 가능성은 유지 관찰). STAB-04 2차에서 개선 1·2 적용 후 재현.
- **조사 상태(2026-08-29 밤, 메인 세션)**: 재현 누적 4인스턴스(루프 2/4 + idZ3QA + BUUQJL — 후자 2건 보존). **캡처 방법론 교정**: app.log(stdout)는 구조적으로 공탐 — AppLog는 OSLog로 발행되어 stdout에 안 나옴. 유효 캡처는 재현 직후 `log show --last 15m --predicate 'processImagePath CONTAINS "MovieCutMac"'` 사후 추출(병행 `log stream` 시도는 1줄만 확보 — 권한/버퍼 의심). 부수 성과: 통과 run(6ypaHX 보존분)에서 **BUG-ACC-01 수정이 300초 실스케일 확증**(w4-prores.mov·w4.mp4 모두 300.000000s·코덱 prores). 실패 run elapsed ~170s 패턴은 유지 관찰.

### BUG-ACC-02 (P1) — 실제 덕킹 분석 경로가 60초 실발화에서 continuation 파킹 — **BUG-CA12-01 병합 완료(2026-08-29)**

- 증상: W_STRICT의 w1에서 `autoDuckOtherAudio`(SilenceDetectionProvider 실분석) 호출 직후 앱 파킹 — 메인 런루프 유휴·워커 스레드 부재·w.json 미기록(첫 스텝도 디스크에 없음). 12분 관찰·스택 샘플로 확인. **BUG-CA12-01(메인 디스패치 전달 정지 계열)의 새 재현 경로** — 스모크의 하드코딩 범위 경로는 이 결함을 가림.
- 병합: 재현 경로·스택 증거가 §1.13 BUG-CA12-01 에스컬레이션 기록에 통합됨(아래 "재현 경로 추가" 불릿). 본 행은 동일 계열로 통합 관리 — 별도 수정 없이 근본 에스컬레이션(BUG-CA12-01) 해법을 따름. W1 acceptance는 이 계열 해소 전까지 RED 유지.

### BUG-ACC-03 (P2) — 비트 감지 마커 수율이 길이에 반비례 — 조사

- 증상: 4초 8클릭 픽스처는 마커 ≥6(기존 테스트)이나 **60초 120BPM(약 120 온셋)에서 마커 4개**(240BPM 드래프트에서는 6개). 스텝 자체는 통과(마커 존재)하나 대표 작업 관점에서 수율이 비정상적으로 낮음 — 분석 윈도우/최댓값/씬 정규화 의심.
- 수정 방향: BeatDetectionProvider의 긴 입력 처리 조사(윈도우 한계·얇기 규칙) + 60초 픽스처 기대치 문서화 후 게이트 강화.

---

## 2. 갭 분석 V6 현실 점검 (중요)

V6 문서의 판정은 "지정된 N개 파일 안에서 코드 경로가 보이는가"였고, **실제 동작/렌더 결과를 검증한 것이 아님.** 패턴:

- **메타데이터/명령 배선만 있고 실제 처리 없음** (🟡로 표기됨): 배경제거, EQ, 덕킹, 노이즈감소 → custom compositor로 값은 넘기지만 실제 픽셀/샘플 처리 알고리즘 미확인. 색보정 중 밝기/대비/채도는 shared `CIColorControls` pixel processor와 preview/export custom compositor static contract로 검증됨. Batch 13에서 procedural LUT/필터는 `VisualEffectPixelProcessor`로 preview/export 공통 경로에 연결됨(외부 `.cube` LUT import는 후속). Batch 14에서 크로마키는 shared `ChromaKeyPixelProcessor`와 Mac preview/export `CustomVideoCompositor` 경로에 연결되고 픽셀 알파/softness/spill suppression 테스트로 검증됨. Batch 15에서 마스크 합성은 shared `MaskPixelProcessor`로 rectangle/ellipse/triangle/diamond/linear/brush, feather/invert/rotation 경로를 Core renderer에 모으고 Mac/iOS custom compositor가 이를 호출하도록 정리됨. Batch 16에서 텍스트/자막 burn-in export는 shared `TextOverlayPixelProcessor`로 Mac/iOS custom compositor가 호출하는 공통 픽셀 경로에 연결됨.
- **UI 진입점만**: 자동자막, AI 어시스턴트, 클라우드 동기화, 템플릿 마켓 → 버튼/시트만.
- **실제 끝까지 동작**: trim/split/move/delete/ripple, 볼륨, 파형, 키프레임 렌더, 역재생, export 진행률/공유, 마커, 스티커 변형.

→ **완료 기준 재정의**: 새 작업은 "preview에서 보이고 export 결과물에도 반영됨"을 DoD(Definition of Done)로 삼는다.

---

## 2.5 증거 기반 검증 현황 리셋 (2026-06-23/24)

> Phase 0(기반 경화)에서 "🟡 자가보고"를 **실측 증거**로 교체했다. 상세·로드맵은 `docs/archive/MOVIECUT_PRO_ROADMAP_20260622.md`, 성능은 `docs/archive/PERF_BASELINE_20260622.md`.

**검증 인프라(신규)** — 이제 완료 증거는 static contract가 아니라 아래로 판정한다:
- **골든 픽셀 하니스** `Tests/.../Support/GoldenPixelHarness.swift` — `CIContext(useSoftwareRenderer:true)` 결정적·sandbox-safe, **silent-skip 제거**(망가진 렌더러는 소리내어 실패). 색보정·배경제거 골든이 이를 사용.
- **결정적 fixture** `Tests/Fixtures/` + `scripts/make_fixtures.sh` (실 AVFoundation 로드 검증).
- **앱 레벨 E2E** `scripts/run_e2e_export.sh` + DEBUG 하니스(`App/MovieCutMac/UITestHarness.swift`, env 게이트) — import→export·freeze·NR·autosave를 **실제 앱 런타임**으로 검증.

**티어1 스윕 판정(실측)**:

| 기능 | 기존 | 실측 판정 | 증거 |
|---|---|---|---|
| 색보정 밝기/대비/채도 | ✅ | ✅ | `ColorCorrectionGoldenTests` 골든 |
| 색보정 warmth/tint | ❌(no-op) | **✅ 구현 완료** | 골든(warm/magenta shift), 죽은 슬라이더 실수정 |
| 배경제거 F-08 | 🟡 | **✅**(실인물 E2E만 🟡) | `BackgroundRemovalGoldenTests`(alpha 255/0) |
| 정지프레임 | 🟡 미확인 | **✅ export 반영** | E2E duration 2.0→4.0s |
| 노이즈감소 | 🟡~❌ | **✅ 앱 런타임** | 헤드리스 크래시 없음·소스 swap |
| EQ | 🟡~❌ | **✅ 앱 export 실측** | `run_e2e_export.sh` EQ spectrum: bass_ratio 2.315524 vs treble_ratio 0.488654 |

**안정성(0.6)**: undo/redo 무결성(스냅샷 기반, `UndoIntegrityTests`)·크래시 복구 자동저장(`AutosaveRecoveryTests` + 앱 배선) ✅.

**성능(0.3)**: export +9%(0.49× realtime)·preview 5.5ms/frame(182fps) → CoreImage 합성 병목 아님 → **Metal 전면 재작성 보류**.

**미검증/주의**: 위 표와 아래 G-12 상환 기록 외 🟡 항목(비트감지·자동컷·리프레임·자막워크플로우·TTS·캔버스배경·클라우드)은 **아직 실측 미검증** — 자가보고 "구현됨"을 완료로 보지 말 것. 전체 `swift test`는 네트워크/Speech/마이크 통합 테스트로 헤드리스 완주 곤란(633/0 부분 통과).

**S0 iOS 빌드 복구(2026-07-03)**: G-09 Inc 1로 `MovieCutiOS` generic iOS 빌드를 `CODE_SIGNING_ALLOWED=NO` 조건에서 복구했다. 같은 세션에서 `swift build`, `swift test --filter 'StaticContract|Golden'`(341 tests), Mac `xcodebuild`, iOS generic `xcodebuild`, `scripts/run_e2e_export.sh`가 모두 PASS. CoreSimulator out-of-date는 simulator 지원 경고로 남아 있으나 generic device build에는 영향 없음.

**S0 iOS 파리티 매트릭스 재감사(2026-07-04)**: G-09 Inc 2로 `docs/PLATFORM_PARITY_MATRIX.md`를 기능 × Core/Mac UI/iOS UI/Mac preview-export/iOS preview-export 기준으로 갱신했다. Mac-only/iOS defer 15건(3-way advanced UI, LUT legacy path, chroma shared processor, two-source transition, background-removal shared compositor, freeze, speed ramp, reverse, ducking, EQ, NR apply, autosave/recovery, ProRes/GIF/still, platform presets, marker/quick tools)에 사유를 기록하고 `IOSParityMatrixStaticContractTests`로 문서/코드 신호를 잠갔다. Inc 3 시작점은 iOS freeze/speed/reverse 또는 shared compositor 통일.

**S0 G-12 #1 EQ 청감 상환(2026-07-03)**: `AudioEqualizerService`의 앱 export 크래시 경로를 AVAudioFile 버퍼 DSP로 교체하고, `eq_low_high_2s_mono.wav` fixture + `MOVIECUT_UITEST_EQ_PRESET` 하니스 + `run_e2e_export.sh` Goertzel 측정으로 bassBoost/trebleBoost 차이를 codify했다. 실측: bass_ratio 2.315524, treble_ratio 0.488654, bass_low 2.281896e+02, bass_high 9.854772e+01, treble_low 9.240646e+01, treble_high 1.891041e+02. 남은 G-12 오디오 부채는 NR 실잡음 효과와 덕킹 청감.

**S0 G-12 #2 NR 실잡음 효과 상환(2026-07-04)**: `NoiseReductionService`의 앱 export 경로를 deterministic AVAudioFile 버퍼 DSP로 고정하고, `noisy_voice_1k_hiss_8k_2s_mono.wav` fixture + `MOVIECUT_UITEST_DENOISE` 하니스 + `run_e2e_export.sh` Goertzel 측정으로 8kHz hiss/1kHz voice 비율 개선을 codify했다. 실측: base_ratio 0.248784 → denoised_ratio 0.075641, improvement_db 5.17dB, voice_retention 0.913, base_hiss 4.195051e+01 → denoised_hiss 1.164459e+01. 남은 G-12 오디오 부채는 덕킹 청감.

**S0 G-12 #3 덕킹 청감 상환(2026-07-04)**: `duck_bgm_220hz_4s_mono.wav` + `duck_voice_1000hz_1s_mono.wav` fixtures, DEBUG 앱 하니스 `MOVIECUT_UITEST_DUCKING_*`, `SetAudioDuckingCommand`, export ramp를 `run_e2e_export.sh` Goertzel 측정으로 codify했다. 실측: base_voice 3.098866e+01 → ducked_voice 1.935795e+00, reduction_db 12.04dB, quiet_delta_db 0.00dB, ducked_voice_quiet_ratio 0.062.

**S0 G-12 #4 모션 트래킹 실영상 상환(2026-07-04)**: `moving_subject_320x240_2s_30fps.mp4` fixture에서 실제 `MotionTrackingProvider.track(videoURL:initialRect:timeRange:frameRate:)`를 실행하고 timestamp별 expected box와 IoU를 측정했다. 실측: 15fps sampling 31 samples, meanIoU 0.7929, minIoU 0.7095(thresholds mean>=0.75, min>=0.65).

**S0 G-12 #8 플랫폼 프리셋 5종 상환(2026-07-04)**: `bars_320x240_3s_30fps.mp4` fixture, DEBUG 앱 하니스 `MOVIECUT_UITEST_PLATFORM_PRESET=<rawValue>`, 실제 `applyPlatformExportPreset` → `exportProject(to:)` 경로를 `run_e2e_export.sh` ffprobe 검증으로 codify했다. 실측: TikTok/Reels/Shorts 1080x1920 30/1 h264 `.mp4`, YouTube Standard 1920x1080 30/1 h264 `.mp4`, Instagram Post 1080x1080 30/1 h264 `.mp4` (`format_name=mov,mp4,m4a,3gp,3g2,mj2`).

**S1 G-02 Inc 1~3 커브/HSL 수학·렌더 체이닝 완료(2026-07-05)**: Inc 1에서 `CurvePoint`와 `CurveEvaluator` 순수 로직(256-entry LUT, endpoint 고정, duplicate-x deterministic, monotone cubic Hermite/Fritsch-Carlson tangents, clamp/no-overshoot)을 추가했고, Inc 2에서 `HSLBandCenter`/`HSLBand`/`HSLCubeBuilder` 순수 로직을 추가했다. Inc 3에서 `ColorGrade`에 optional `hslBands`/`curves`와 `ColorCurves`를 편입하고, `ColorGradePixelProcessor`가 CDL → HSL `CIColorCube` → channel/master curve cube 순서로 실제 렌더 체인을 소비한다. Mac/iOS preview/export는 shared processor 경로로 반영되고, E2E는 `MOVIECUT_UITEST_HSL_CURVES=1` 앱 export에서 baseline red-dominant `(5,1,0)` → neutral gray `(5,5,5)` 변화를 검증한다. Caveat(2026-08-26 갱신): Mac 편집 UI 완료 — Inc5 HSL 8밴드(c142c62)·Inc6 톤 커브 에디터 (채널 4종 드래그 캔버스·제스처당 undo 1-step·identity→nil, 파리티 #16 curves_only MAD 0.43 신설). iOS는 curves 값 통과만 존재(편집 UI 미연결 — 후속 관찰).

**S1 G-02 Inc 5 HSL 밴드 편집 UI 완료(2026-08-17)**: 위 Caveat의 Mac 측 해소 — `ColorHSLBandsView`(인스펙터 컬러 등급 섹션, 컬러휠·감마 슬라이더 인접 배치)로 8색상 밴드(적/주/황/녹/청/남/보/마젠타) 각 색조 시프트·채도·휘도 편집을 사용자가 만들 수 있다. 커밋은 드래그 종료 시 단일 커맨드(G-23 캔버스 패턴 — 제스처당 undo 1-step), 밴드 전부 identity면 `nil` 커밋으로 미그레이드 JSON 바이트 안정. 검증: 파리티 시나리오 16번 `hsl_curves` 신설(HSL_CURVES 게이트 — 레드 밴드 탈포화+마스터 커브, 프리뷰↔출력 동일), `ColorGradeGoldenTests` +JSON 라운드트립/identity 밴드 정규화, ui_regression 골든 갱신(의도 변경). 잔여: 커브 에디터 UI(Inc 6), iOS 동등 UI(2단계 파리티).

**S2 G-01 Inc 1 워드 타이밍 보존(2026-07-04)**: `WordTiming`, `TranscriptionSegment.words`, `TextClipContent.wordTimings`를 추가하고 Apple Speech `SFTranscriptionSegment` timestamp/duration/confidence를 보존하며, `SubtitleGenerator`가 세그먼트 절대 word 시각을 클립 상대 시각으로 변환한다. `StyledCaptionWordTimingTests` 6개로 legacy decode, Codable round-trip, relative transform, clamp, SRT omission을 검증했다. Caveat: caption style preset/active word renderer/preview-export burn-in/iOS 갤러리는 G-01 Inc 2+이다.

**V12 실사용 버그 재설정 및 G-15 AC1~AC3 상환(2026-07-12)**: 최신 분석 문서는 `docs/archive/GAP_ANALYSIS_V12_FUNC_UI_20260706.md`다. **사용자 보고 재현 확정**: 사진(이미지)은 import·타임라인 클립 생성까지만 되고 **preview 무표시 + export "Cannot Open" 실패**(헤드리스 실측 clips=1/export 미생성). 원인: 이미지 미디어 클립 파이프라인 미구현(`PlaybackEngine:494` video 트랙 전제 스킵, ExportEngine 이미지 분기 0건 — 이미지는 스티커 오버레이 경로만 존재). 전 E2E가 mp4/wav fixture라 미검출 → **A7 신설**(kind별 fixture 의무 + 실사용 스모크 상설). **G-15 Inc 1~3 부분 완료로 AC1~AC3는 역전**: `ImageVideoRenderService`가 image→H.264 segment를 만들고 Mac preview/export가 이를 기존 video source track으로 소비한다. E2E 실측: 단독 image export 성공(`duration=5.000000s`, middle frame `rgb=0,0,171`) + mixed image→video export 성공(timeline `video:image=0.000-5.000,video:video=5.000-7.000`, duration `7.000000s`, samples `image_rgb=0,0,171`, `video_rgb=5,0,0`) + image warm-grade export 평균색 이동(baseline `rgb=0,0,171` → graded `rgb=100,0,153`, `red_delta=+100`, `blue_delta=-18`). **남은 G-15**: ~~AC5 EXIF fixture~~·~~AC6 iOS~~ **완료(2026-08-26, 리뷰 반영 Phase 1-3)** — `ImageVideoRenderService` Core로 이동(Mac·iOS 공유), iOS 렌더 계획이 이미지 클립을 사전 렌더 세그먼트로 삽입(필터 3곳 `.video || .image`). 검증: PNG·HEIC 플랜 렌더 + EXIF orientation 6 upright(플랜 프레임) + 사진 전용 프로젝트 export E2E(`IOSImageClipPipelineTests` 4종). 픽스처 `exif_orient6_asym_320x240.jpg`·`swatch_green_64x64.heic` 신설. 잔여: AC4 실기기 preview/trim. ~~AC7 대형 이미지 메모리 로그~~ **완료(2026-08-26)** — `ImageVideoRenderScaleTests` 3종: 24MP(6000x4000) 소스가 1080p·4K 캔버스에서 캔버스 크기로 렌더 + Ken Burns 2x 줌에서도 캔버스 크기 유지(로드 상한 = max(캔버스장변, 캔버스장변×최대줌) — `kCGImageSourceThumbnailMaxPixelSize`가 6000px 원본을 상한으로 다운스케일). Core 1,416·게이트 5/5.. 자동 선택 순서 **G-15 잔여 → U-08 잔여 → G-02 Inc 5~6 → G-01** (스펙 v1.6).

**V13 배선 격차 재설정(2026-07-29)**: 최신 분석 문서는 `docs/GAP_ANALYSIS_V13_FUNC_UI_20260729.md`(V12 대비 델타 62커밋)다. 기준선 실측: `swift build` ✅ / `swift test` **984 tests 162 suites 통과 18.6s** / Mac `xcodebuild` ✅ / **iOS `xcodebuild` ❌ 플랫폼(iOS 26.5) 미설치** / swiftlint 1,022건(error 414). **⚠️ 984 통과를 기능 증거로 읽지 말 것** — 테스트 파일 137개 중 85개(62%)가 StaticContract이고 부정 단언 248건이다.

① **격차 성격이 바뀌었다**: 주류가 "기능 부재"에서 **"배선 격차"**로 이동했다. `wordTiming`(Core 4파일 / App **0파일**), 프록시 소비(`PlaybackEngine`·`ExportEngine` 참조 **각 0회**), 현지화(`NSLocalizedString` 8파일이나 `.lproj`/`Localizable.strings`/`.xcstrings` **0개** → 실질 영어 전용) — 전부 만들어는 놨고 화면에 잇지 않았다.

② **미배선 Core 서브시스템 1,279줄 확정**(App 호출 0회): `Cloud/CollaborationService` 546, `AI/ClaudeEditingProvider` 265, `Analysis/StyleTransferProvider` 174, `Audio/VocalSeparationService` 121, `AI/AIEditingProvider` 103, `Cloud/VersionHistory` 70. `VocalSeparationService`는 V12 이전부터 dead code 전례로 지목됐고 **여전히 죽어 있다**(B-F5.2 격차와 직결). `Analysis/BackgroundRemovalProvider`도 App 0회지만 기능 자체는 `InspectorEffectsSection.swift:351` 토글 + `CustomVideoCompositor.swift:528 applyPersonSegmentation`로 동작하는 **위양성** — 프로바이더만 삭제 후보.

③ **부재 확정(각 0파일)**: 홈/프로젝트 목록(B-L2), 컴파운드 클립(B-F2.3), 프리뷰 품질 선택(B-I8), VTT/ASS export(B-F3.2), 속도 커브 프리셋(B-F2.4). 블렌딩 모드(B-F4.4)는 `blendMode` 매치 2건이 전부 `CISoftLightBlendMode`/`CIOverlayBlendMode` **내부 필터명**이라 사용자 노출 0. → **G-23 블렌딩 / G-24 컴파운드 신설**(스펙 v1.9).

④ **볼륨 실측**: 전환 12 / 이펙트 18 / 텍스트 템플릿 14 / 스티커 22 / SFX 12. CapCut은 각 수백~수천 — 전략상 큐레이션이나 격차는 격차로 기록한다.

⑤ **P0 부채 — 판정 재확인 필요**: 2026-07-28 핵심 편집 수리가 **메인 Preview가 프로젝트 합성 경로를 쓰지 않고 선택 원본을 직접 재생하고 있었음**(`b398563`)을 드러냈다. magnetic compaction 무차별 적용(`1fa836c`), 배속/ramp 시간 일관성 붕괴(`269d50a`·`dfde012`·`0115e6c`)도 함께 수리됐다. 즉 그 동안 V1~V12가 B-F2/B-F4에 부여한 `=` 판정은 preview+export 동시 증거 없이 내려진 것이다. **`=`는 재확인 전까지 잠정으로 읽는다** — 재확인 큐는 V13 §6.

⑥ **Track.isLocked dead-field 해소 확인**(v1.2 판정 정정): Core 3회 / App 2파일 배선됨.

**V11 기능+UI 재감사(2026-07-05, 기준 `6f76415`, 과거 기준)**: 분석 문서는 `docs/archive/GAP_ANALYSIS_V11_FUNC_UI_20260705.md`다. V10 권장 순서가 그대로 실행됨을 독립 검증 — G-12 #9(ffprobe chapter atom 실측)로 **10/14, 자동 상환 가능분 소진**, **G-02 Inc 1~3 완료**(HSL/커브 체이닝이 preview/export/iOS 실반영, 골든+E2E base_rgb 5,1,0→grade_rgb 5,5,5, build+353 tests PASS). 색 2차 보정 모순은 엔진 수준 해소 — **잔여는 편집기 UI(Inc 5~6)로, 현재 사용자가 HSL/커브 값을 만들 수단이 없다.** dead-value는 `wordTimings` 1건 잔존, dead code는 `VocalSeparationService`·`StyleTransferProvider`(폐기/G-07 흡수 결정 필요) 지속. **UI 트랙 4회 연속 착수 0건 — 다음 자동 선택은 U-08 → G-02 Inc 5~6(W5 완주) → G-01 Inc 2~4** (스펙 v1.5).

**SU U-08 Inc 1~2 UI 회귀/지표 인프라 착수/부분 완료(2026-07-06)**: `scripts/ui_capture.sh`가 Debug `MovieCutMac.app`을 populated harness(`MOVIECUT_UITEST_IMPORT` + Title 템플릿)로 실행해 실제 창을 `artifacts/ui/moviecut_populated_editor_raw.png`로 캡처하고, `scripts/ui_regression.sh`가 normalized PNG를 `Tests/UIEvidence/golden_populated_editor.png`와 dHash 비교한다. `artifacts/`는 `.gitignore`에 추가해 생성물과 committed evidence를 분리했고, `docs/UI_METRICS.md`에 사용법/정책을 기록했다. 검증: update-golden PASS, normal regression PASS(distance 0/threshold 4), 임시 golden negate 이빨 확인 FAIL(distance 56) 후 복원 PASS, build/test/xcodebuild/E2E PASS. ~~Caveat~~ **해소(2026-08-26)**: AC② **4표면 골든 완료** — `Tests/UIEvidence/`에 `golden_import_only.png`·`golden_populated_editor.png`·`golden_with_color_grade.png`·`golden_with_mask.png` 4종 커밋(2026-08-17, `ui_capture.sh --state all` + `ui_regression.sh` 인프라). AC③ **클릭수 metric 완료** — `EditorSession.commandCount`(=`undoStack.count`) 공개 + `docs/UI_METRICS.md`에 대표 플로우별 측정치·CapCut 목표 대조표 기록. Core 1,416·게이트 5/5.

**V10 기능+UI 재감사(2026-07-05, 기준 `738f4ce`, 과거 기준)**: 분석 문서는 `docs/archive/GAP_ANALYSIS_V10_FUNC_UI_20260705.md`다. G-12 #7 상환을 독립 검증(E2E 스크립트/하니스 훅/실측치 실재 + `swift build`/361 tests PASS)해 **9/14 확정**했고, 이후 **G-12 #9 챕터/비트 마커 메타데이터**를 `MOVIECUT_UITEST_CHAPTER_MARKERS`/`MOVIECUT_UITEST_BEAT_CHAPTERS` 하니스 + AssetWriter timed metadata track + `.chapterList` association + ffprobe `-show_chapters` 실측으로 상환해 **10/14**가 됐다. 이어 **G-02 Inc 3**에서 `CurveEvaluator`·`HSLCubeBuilder`·`CurvePoint`/`HSLBand` dead-value를 renderer/app export 증거로 상환했다. 남은 dead-value는 `wordTimings`(렌더러 소비 0)이며 G-01 Inc 2~4에서 닫는다. **S0 게이트 완화(스펙 v1.4)**: #9까지 자동 상환 완료, #11/#12는 fixture 증분(#11a/b, #12a/b) 세분화, #13/#14는 수동 검증 대기 분리 — 이후 자동 선택은 **U-08 → G-01 Inc 2** 순.

**CapCut 대비 완성도 재평가(2026-07-05 loop-6, 기준 `fe9b062`, 과거 기준)**: 분석 문서는 `docs/archive/GAP_ANALYSIS_V9_FUNC_UI_20260705.md`다. 52주기식 자가보고 97%는 계속 폐기한다. G-12가 이후 10/14로 증가(#1 EQ, #2 NR, #3 덕킹, #4 모션 트래킹, #5 옵티컬 플로우, #6 텍스트 애니메이션, #7 타이틀 템플릿, #8 플랫폼 프리셋, #9 챕터/비트 마커 메타데이터, #10 오디오 추출)했고, G-02 Inc 3로 HSL/커브 저장+렌더 체인이 앱 export 증거까지 닫혔다. 체감 완성도는 70%대 초반으로 소폭 상향 가능하나, 아직 “능가” 선언은 금지다. 미완 핵심은 (1) G-02 HSL/커브 Mac/iOS 편집 UI와 W5 수동 완주, (2) G-01 caption style model+active-word renderer+preview/export+iOS, (3) G-12 잔여 자동 제외/fixture 대기 4개(#11/#12/#13/#14), (4) G-04 필름스트립, G-05 보컬분리/보이스FX, G-06 이징 UI, G-09 iOS 본대, (5) U-01/U-02/U-04/U-05/U-06/U-08/U-09 UI 표면이다.

**V8 기능+UI 재감사(2026-07-04, 기준 `8efa65e`, 과거 기준)**: 분석 문서는 `docs/archive/GAP_ANALYSIS_V8_FUNC_UI_20260704.md`다. 신규 G-ID/U-ID는 만들지 않았고, 상태만 재판정했다. 당시 G-12는 5/14 상환(#1 EQ, #2 NR, #3 덕킹, #4 모션 트래킹, #8 플랫폼 프리셋)이었으며, 이후 V9에서 8/14로 갱신됐다. G-09는 Inc 1~2 진행중이나 CI job/iOS W1/iOS E2E가 남았다. G-02는 `CurveEvaluator`/`HSLCubeBuilder` 순수 로직만 완료되어 App 호출 0회이고, `ColorGrade` 저장 필드와 renderer chain이 없다. G-01은 `wordTimings` 저장만 완료되어 active-word renderer와 caption style UI가 없다. UI는 U-03 `Track.isLocked` dead-field 판정을 취소(헤더 lock UI + command guard 존재)하고 U-07 browser grid/hover 일부 구현을 반영했지만, U-01/U-02/U-04/U-05/U-06/U-08/U-09는 여전히 열위다. Dead-code 후보는 `VocalSeparationService` 계열(App=0), `BackgroundRemovalProvider`(App=0), `StyleTransferProvider`(App=0)이며 `CurveEvaluator`/`HSLCubeBuilder`는 G-02 Inc 3 지연 시 dead-code risk로 본다.

**S0 G-12 #10 오디오 추출 상환(2026-07-04)**: `solid_red_tone_320x240_2s_30fps.mp4`(h264+aac, 2.0s) fixture, DEBUG 앱 하니스 `MOVIECUT_UITEST_EXTRACT_AUDIO=1`, audio-only export `MOVIECUT_UITEST_EXPORT_AUDIO`를 `run_e2e_export.sh`에 추가했다. 실제 `extractAudio(from:)` command-backed 앱 경로가 audio clip 1개를 생성하고, ffprobe/RMS 검증으로 export audio stream을 확인했다. 실측: clip_duration 2.000s, export_duration 2.066576s, codec aac, rms 0.087598. G-12는 6/14 상환(#1 EQ, #2 NR, #3 덕킹, #4 모션 트래킹, #8 플랫폼 프리셋, #10 오디오 추출)으로 진행중이다.

**S0 G-12 #5 옵티컬 플로우 실영상 상환(2026-07-04)**: 기존 `useOpticalFlow` export는 0.25×에서 duration/fps만 늘고 인접 중간 프레임 MAD가 0.0000인 duplicate 반복으로 드러났다. 이를 `MotionAwareSlowMotionRenderService` 임시 보간 asset 경로로 보강하고, `moving_subject_320x240_2s_30fps.mp4` fixture + DEBUG 하니스 `MOVIECUT_UITEST_PLAYBACK_RATE=0.25`, `MOVIECUT_UITEST_OPTICAL_FLOW=1`을 `run_e2e_export.sh`에서 검증한다. 실측: 8.000000s, 120/1fps, 960 frames, adjacent_mad 0.001519, mid_vs_blend 0.001845, anchor_mad 0.005642. G-12는 7/14 상환으로 진행중이다. Caveat: lightweight motion-aware interpolation이며 상용급 장면별 optical-flow 품질 평가는 후속 품질 작업이다.

**S0 G-12 #6 텍스트 애니메이션 13종 상환(2026-07-05)**: DEBUG 앱 하니스 `MOVIECUT_UITEST_TEXT_ANIMATION_PRESET=<rawValue>`가 실제 텍스트 클립을 추가하고, export path에서 텍스트 animation/keyframe이 화면 안 fixture 중앙(160,120)에 burn-in 되도록 고정했다. `run_e2e_export.sh`는 13종(none/fadeIn/fadeOut/fadeInOut/slideInLeft/slideInRight/slideInUp/slideInDown/typewriter/bounceIn/zoomIn/popIn/wave)을 none-baseline 대비 frame-diff로 검증한다. 실측: none overlay_mad 16.512326, non-none max_residual_temporal_mad min 2.870069(fadeOut) / max 6.594722(popIn), `E2E check OK`. G-12는 8/14 상환으로 진행중이다. Caveat: 하니스 검증은 320x240 synthetic fixture 기준이며 상용 템플릿 모션 디테일/GUI 녹화는 후속 품질 작업이다.

**S0 G-12 #7 타이틀 템플릿 14종 상환(2026-07-05)**: `TextTemplate.builtIn` 14종을 정확히 잠그고, DEBUG 앱 하니스 `MOVIECUT_UITEST_TEXT_TEMPLATE_NAME=<name>`가 실제 템플릿 클립을 추가해 export하는 경로를 추가했다. 일반 템플릿 경로는 320x240 E2E에서 화면 밖/no-visible overlay가 발생해, 하니스 전용 helper가 템플릿 content를 fixture 중앙 transform 중심으로 스케일 보정한다. `run_e2e_export.sh`는 no-template baseline export 대비 frame-diff를 14종 전체에 대해 측정한다. 실측 max_overlay_mad: Title 7.450278, Subtitle 7.109653, Lower Third 6.524444, Caption 6.459444, Credits 7.125347, News Banner 6.722222, Quote 6.725417, Callout 6.875694, Kinetic 6.848056, Handwritten 6.700069, Neon Glow 6.790208, Outline 6.636806, Typewriter 6.506250, Social Handle 6.885069. G-12는 9/14 상환으로 진행중이다. Caveat: synthetic fixture의 visible export proof이며 상용 1080p 템플릿 배치/GUI 녹화는 후속 품질 작업이다.

**S0 G-12 #9 챕터/비트 마커 메타데이터 상환(2026-07-05)**: DEBUG 앱 하니스 `MOVIECUT_UITEST_CHAPTER_MARKERS=1`가 표준 마커 Intro/Outro를, `MOVIECUT_UITEST_BEAT_CHAPTERS=1`가 beat marker `Beat 1`을 command path로 추가하고 export settings의 chapter/beat chapter 옵션을 켠다. ExportEngine은 chapter marker가 있을 때 AssetWriter 경로를 사용하고 timed metadata track을 비디오 input에 `.chapterList` association으로 연결해 실제 MP4 chapter atom을 기록한다. `run_e2e_export.sh` ffprobe 실측: `count=3 starts=0.25,0.75,1.25 ends=0.75,1.25,1.75`. G-12는 **10/14** 상환으로 진행중이다. Caveat: ffprobe title tag는 AVFoundation timed metadata 특성상 빈 문자열로 표시되어, E2E는 하니스 status로 marker names/count를 검증하고 ffprobe로 chapter atom timing/count를 검증한다.

---

## 3. CapCut 기능 백로그 (도메인별)

상태: ✅ 실제 동작 / 🟡 배선·UI만 존재(실처리 없음) / ❌ 없음
우선순위: P0(기본기 필수) > P1 > P2 > P3(차별화·후순위)

### A. 미디어 입출력
- [x] ✅ 타임라인 직접 드롭 → 클립 생성 **(P0, §1 참조; 2026-06-10 실기기 GUI 드래그 검증 완료 — DropDelegate가 실제 드래그를 거부하던 런타임 버그를 closure 기반 onDrop + Info.plist UTType 선언으로 수정)**
- [x] ✅ 라이브러리 → 타임라인 드래그 **(P0; 2026-06-10 실기기 GUI 드래그 검증 완료)**
- [x] ✅ 실제 import metadata probe (AVAsset/ImageIO, F-06) **(P0; video/audio duration, 해상도/fps/codec, audio sample rate/channel count, image dimensions를 앱 레이어에서 best-effort로 구현. GUI visual verification은 별도)**
- [x] ✅ 드롭 성공/실패 피드백 **(P0; status bar의 `lastStatusMessage`/`lastErrorMessage`, static-contract 검증)**
- [x] ✅ 썸네일/프록시 생성 (P1) — import path가 video/image `MediaAsset`에 `ThumbnailGenerator` PNG 썸네일을 opportunistic/non-fatal로 채우고, Media Library와 Timeline clip background가 `thumbnailData`를 실제 이미지로 렌더한다. video asset은 `ProxyGenerator.makeProxyPlan`의 deterministic target/resolution과 AVFoundation best-effort proxy export를 통해 실제 파일이 존재할 때만 `ProxyInfo(proxyURL:)`를 저장한다. Media Library row/context action에서 Generate Proxy를 실행하고 Proxy ready/No proxy 및 thumbnail 상태를 접근성 value에 노출한다. Caveat: proxy export는 `AVAssetExportSession`이 해당 source와 mp4 output을 지원하는 경우에만 성공하며, 실패 시 asset.proxy는 nil로 유지된다.
- [x] ✅ 포맷별 export(mp4/mov, 코덱/비트레이트 실제 반영) (P1) — format/codec/quality/container/estimated bitrate are persisted in `ExportSettings` and wired to macOS export. Custom bitrate now resolves only inside the documented 1~200 Mbps range (`nil` below minimum, clamp to 200 above maximum), and Inspector/toolbar export controls expose selected settings to VoiceOver. `AVAssetExportSession` still exposes preset selection plus `fileLengthLimit` rather than a direct `averageVideoBitRate` knob, so exact encoder bitrate control remains approximate.
- [ ] 🟡 비파일 드래그 소스(사진/브라우저, F-01) (P1) — Core `DragDropHandler.loadExternalMediaURLs`가 fileURL/movie/image 페이로드를 처리(`loadFileRepresentation`→data fallback→`MovieCutImports` 임시 디렉토리), 타임라인/라이브러리 onDrop에 `.movie`/`.image` 추가. `ExternalMediaDropTests` 6개가 실제 NSItemProvider 페이로드로 행동 검증. **2026-06-11 실기기 GUI 추가 검증: Safari data URL 이미지 드래그 → 라이브러리 import 성공(`Imported Media.png`, 320×180, thumbnail ready, `Imported 1 media file.`), Safari data URL 이미지 드래그 → Video 1 타임라인 클립 생성 성공.** Caveat: Photos 앱 또는 대체 네이티브 앱 비파일 소스는 Photos window 0/AppleScript import timeout 및 이후 screencapture black-frame 상태로 미검증 — DoD §1.3에 따라 F-01 전체 완료는 계속 ✅ 보류.
- [x] ✅ 플랫폼 프리셋(TikTok/Reels/Shorts/YouTube/Instagram Post) 실제 인코딩 (P2) — **2026-07-04 G-12 #8 상환**: `MOVIECUT_UITEST_PLATFORM_PRESET` 하니스가 실제 `applyPlatformExportPreset` 앱 호출부로 canvas/export settings를 바꾼 뒤 `exportProject(to:)`로 export한다. `run_e2e_export.sh` ffprobe 실측: TikTok/Reels/Shorts 1080x1920 30/1 h264 `.mp4`, YouTube Standard 1920x1080 30/1 h264 `.mp4`, Instagram Post 1080x1080 30/1 h264 `.mp4` (`format_name=mov,mp4,m4a,3gp,3g2,mj2`). Caveat: 현재 5종 프리셋 정의는 모두 30fps/H.264/AAC/MP4이며 직접 게시 API가 아니라 파일 export 검증이다.

### B. 타임라인 편집
- [ ] 🟡 **G-16 타임라인 스크럽(B-I2) (P0, 사용자 보고 2026-07-13)** — Inc 1~3 구현 완료. shared coordinate clamp tests 3/3, actual app E2E `requested/playhead/playback=1.250/1.250/1.250`, Mac build PASS. AC3 실기기 100ms 체감 및 AC4 재생 중 스크럽 확인 대기.
- [x] ✅ **G-17 클립 복사/잘라내기/붙여넣기(B-F2.1) (P0, 사용자 보고 2026-07-13)** — Core atomic clipboard commands + Mac Cmd+C/X/V/context menu + NSText native forwarding 완료. behavioral 6/6, Mac static 3/3, actual app `paste_starts=10.000,12.000 relative=2.000 paste_undo=1 cut_undo=1 new_ids=1`, ffprobe video `14.000000s` PASS. 실기기 메뉴 클릭은 UX 확인 항목으로 잔여.
- [x] ✅ **G-04 타임라인 필름스트립+호버 스크럽 (P1)** — 2026-07-18 AC1~AC5 자동 검증 완료. 실제 `TimelineView` request→cache/decode→publish→UI consumer에 production signpost를 연결했고, 20/40/80/160px/s 각각 zoom+real scroll 3회(총 required request 16개)에서 time-varying density `0.232/0.366/0.694/1.381 frame/s`, distinct identities, image/audio/text 표면 보존을 확인했다. 기존 1ms MainActor sleep proxy의 67ms 값은 scheduler/lifecycle artifact였으며, 대체 metric은 actual main-thread request/publish/consumer update/AppKit draw 전 구간을 필터·clamp 없이 정확히 16.6ms budget으로 집계한다. exact-final 격리 2회 모두 `n=66`(초기 request/publish도 삭제하지 않아 required 64보다 2개 많음), `p95/max=0.719/1.122ms`, `0.402/0.435ms`, `>16.6ms=0`; 스크립트는 초과 1건부터 실패한다. 10분 4K synthetic fixture도 두 run RSS delta `+0.0/+6.3MB`, decoded cache peak `8,816,640B/128MB`, height `41`이다. Caveat: 이 metric은 display presentation FPS가 아니며 실기기 스크롤/호버 체감은 사용자 확인 대기다. 별도 UB-V4 scrub/slider ≤100ms·playback start ≤300ms는 여전히 미측정이므로 UB-V4 완료는 선언하지 않는다.
- ✅ Trim / Split / Move / Delete / Ripple
- ✅ 스냅 / 줌 / 다중선택 / 컨텍스트 메뉴
- [x] ✅ 마그네틱 타임라인(자동 밀착) (P1) — Add/Move/Duplicate/Delete command path가 `RestoreTrackClipsCommand` track snapshot을 남기고, Add/Move/Duplicate/Delete 후 same-track magnetic packing으로 클립을 0초부터 end-to-start로 밀착한다. Undo는 이전 track snapshot/range를 복원한다.
- [x] ✅ 멀티트랙 레이어링 + 클립별 zIndex (P1) — persisted `Clip.zIndex`가 legacy JSON에서 기본값 0으로 decode되고 round-trip encode된다. `TimelineView`는 `clipsForDisplay(track)`와 `.zIndex(Double(clip.zIndex))` 기반 TimelineView display ordering/layer actions를 사용하며 Bring to Front / Send to Back context action으로 선택 클립 layer를 조정한다. Caveat: 클립 그룹/링크는 P2 별도 항목으로 남긴다.
- [x] ✅ 클립 그룹/링크(영상+오디오 묶음, F-04) (P2) — GUI 실기기 검증 완료(2026-06-11): 단일 클릭+Delete로 그룹 전체 삭제(연결 선택 입증), link 아이콘, Group/Ungroup 메뉴 가드. 상세는 스펙 F-04 검증 기록. 구현: `Clip.groupId` 영속화(legacy decode nil), `GroupClipsCommand`/undo, 연결 선택(그룹 클립 탭 → 그룹 전체 선택/해제), 컨텍스트 메뉴 Group/Ungroup, 타임라인 link 아이콘. `ClipGroupingTests` 7개 행동 검증. Caveat: 마그네틱 패킹 하에서 시간 오프셋 유지 이동은 미적용(연결 선택 방식 채택), GUI 실조작 확인 잔여 — DoD §1.3에 따라 ✅ 보류.
- [x] ✅ 키보드 단축키 맵 전체 (P2) — `MovieCutMacApp.commands` now owns the F-05 Playback/Timeline/Edit shortcut map: Space, Cmd+B, Q/W, Delete, Shift+Delete, Cmd+D, frame/1s arrows, clip-boundary Up/Down, +/- zoom, M, and Cmd+Z/Shift+Cmd+Z. Toolbar/background duplicate shortcut registrations were removed from `ContentView`, and Help exposes "MovieCut Keyboard Shortcuts." Caveat: text-entry-sensitive unmodified shortcuts use a centralized AppKit first-responder guard rather than a full SwiftUI FocusState router; GUI text-field regression remains host verification.

### C. 비디오 효과 (Visual)
- [x] ✅ 색보정(밝기/대비/채도) **실제 픽셀 처리** (P0) — `ColorCorrectionPixelProcessor`가 `CIColorControls`로 밝기/대비/채도를 적용하고, Mac `CustomVideoCompositor`가 preview/export 공통 경로에서 이를 사용한다. SwiftPM static contract가 `PlaybackEngine`/`ExportEngine`의 custom compositor 라우팅을 확인한다. 현재 sandbox에서는 `CIContext`가 non-black fixture도 transparent black으로 렌더해 pixel assertion은 guarded; 정상 CoreImage runner에서는 identity/brightness/saturation pixel sampling 테스트가 실행된다. **warmth/tint는 2026-06-23 구현 완료** — `CITemperatureAndTint` 단계를 shared processor에 추가(warmth+ = 따뜻함/red↑, tint+ = 마젠타). Mac/iOS Inspector 슬라이더가 이미 존재했으나 프로세서가 무시하던 **작동 안 하는 컨트롤**이었고 이제 preview/export 실반영. non-skippable 골든(`ColorCorrectionGoldenTests`: warmth+1→[166,148,121], tint+1→[191,124,185]).
- [x] ✅ 필터/LUT 실제 렌더 (P1) — `VisualEffectPixelProcessor`가 grayscale/sepia/blur/exposure/temperature/styleTransfer 및 cinematic/vintage/noir/vivid/cool procedural LUT preset을 Core Image로 적용한다. Mac `CustomVideoCompositor`가 clip `effects`를 preview/export 공통 custom compositor 경로에서 이 shared processor로 위임하고, `VisualEffectPixelProcessorTests`가 renderable contract, extent preservation, guarded pixel sampling, `PlaybackEngine`/`ExportEngine` 라우팅, Inspector preset 노출을 검증한다. 외부 `.cube` LUT import는 F-09에서 완료(`CubeLUTParser`+`.externalLUT`+Import LUT… UI, `CubeLUTTests` 10개, guarded 픽셀 검증). Caveat: 실기기 import GUI 확인 잔여.
- [x] ✅ 크로마키 keying 알고리즘 (P1) — `ChromaKeyPixelProcessor`가 `ChromaKeySettings`의 keyColor/tolerance/softness/spillSuppression을 Core Image `CIColorKernel`로 적용하고, keyed green 픽셀 alpha 제거, near-key partial alpha, foreground opacity 유지, invalid hex fallback, extent preservation을 SwiftPM 테스트로 검증한다. Mac `CustomVideoCompositor`와 `ChromaKeyCompositor`는 shared processor로 위임하며 `ExportEngine`/`PlaybackEngine` static contract가 chroma-key clip의 custom compositor 라우팅을 확인한다. eyedropper/매트 erode는 F-10에서 완료(`PixelSampler` 스포이드 + `edgeShrink`, `ChromaKeyEyedropperTests` 9개). Caveat: 실기기 스포이드 GUI 확인 잔여.
- [x] ✅ 마스킹(도형/그리기) 합성 (P1) — Batch 15에서 `MaskPixelProcessor`가 Core Image/CGContext 기반으로 rectangle/ellipse/triangle/diamond/linear/brush 마스크를 실제 알파 합성하고, Mac/iOS `CustomVideoCompositor`가 shared processor를 호출한다. SwiftPM 테스트가 rectangle/inverted/ellipse/brush 알파 샘플과 extent preservation, Mac export/playback 라우팅 static contract를 검증한다. Caveat: AI segmentation/refine edge 같은 고급 매트 보정은 이 배치 범위가 아니며 별도 후속 항목이다.
- [ ] 🟡 배경 제거(인물 세그멘테이션, F-08) (P2→preview 배선/품질분리/AC④ 완료) — `isBackgroundRemoved` Clip 속성 + `PersonSegmentationCompositor`(shared, guarded 픽셀 테스트) + preview `.fast`/export `.accurate` + 인물 미검출 시 무변경. `BackgroundRemovalTests` 9개. Caveat: 실인물 영상 GUI 확인 잔여 — DoD §1.3에 따라 ✅ 보류.
- [x] ✅ 전환효과 다양화 + Inspector 선택/Duration 노출 + two-source preview/export 배선 (P1) — Batch 17에서 `TransitionType`을 12개 built-in(none/crossDissolve/fadeThroughBlack/wipeRight/Left/Up/Down/slideLeft/Right/zoomIn/Out/glitch)으로 확장하고, Core 전용 `TransitionPixelProcessor`가 cross dissolve, fade-through-black, directional wipe, slide, zoom, deterministic glitch를 두 소스 `CIImage` 합성으로 처리한다. P1 transition pass에서 Mac export/playback이 `requiresTwoSourcePixelProcessing` 전환(wipeLeft/Up/Down, slide, zoom, glitch)에 대해 outgoing/incoming track metadata를 `CustomVideoCompositor`에 전달하고, transition overlap에서 별도 composition track source frame을 가져와 `TransitionPixelProcessor.apply(type:from:to:progress:)`로 합성하도록 배선했다. 2026-06-11 F-07 targeted pass에서 fade-through-black midpoint/boundary pixel fixture와 Inspector verification note/accessibility guard를 추가해 "targeted confidence only; export/device golden pending" 상태를 UI와 static contract로 잠갔다. Caveat: crossDissolve/fadeThroughBlack/wipeRight의 기존 layer-instruction ramp는 유지한다. 실제 exported visual fixture/e2e 검증은 후속으로 필요하며, release-ready/exported/device-verified라고 보고하면 안 된다.
- [x] ✅ 모션 트래킹 **실영상 provider.track + IoU 검증** (P3) — **2026-07-04 G-12 #4 상환**: `moving_subject_320x240_2s_30fps.mp4`(320×240, 2s, 30fps, 좌→우 이동 고대비 박스) fixture에서 `MotionTrackingProvider.track`를 실제 실행하고 timestamp별 expected rect와 비교했다. `MotionTrackingProviderTests.trackFollowsMovingSubjectFixtureByFrameIoU` 실측: 15fps sampling 31 samples, meanIoU 0.7929, minIoU 0.7095(thresholds mean>=0.75, min>=0.65). Caveat: 합성 고대비 피사체 기준이며 자연 실사/가림/스케일 변화는 후속 품질 검증.

### D. 텍스트/자막
- [x] ✅ 텍스트 오버레이 + 폰트/정렬/스타일 편집 UI (P1) — burn-in export는 Batch 16에서 완료됐고, Mac Inspector controls now cover font/size/color/background/alignment/presets for ordinary text clips. 편집은 `TextClipContent`를 `updateSelectedTextContent` → `SetClipPropertyCommand.textContent` 경로로 갱신하며, sticker clip은 기존 sticker metadata/transform 중심 UI를 유지한다. Caveat: advanced title template library remains separate P1/P2 work.
- [ ] 🟡 텍스트 템플릿/타이틀 프리셋 (Core만 존재) (P1)
- [x] ✅ 자동 자막(STT) 실제 생성 **(P0)** — Mac `AutoSubtitlesView` 경로가 `TranscriptionService.currentProvider`의 Apple Speech provider로 실제 STT를 실행하고, 선택된 audio/video 타임라인 클립이 있으면 `subtitleClips(from:alignedTo:)`로 `sourceRange`/`timelineRange`에 맞춰 pending subtitle clips를 만든 뒤 Apply에서 삽입한다. 타임라인 클립 없이 라이브러리 asset만 선택한 경우에는 00:00 기준 pending clips를 만들며 status text에 이를 명시한다. **2026-07-04 G-01 Inc 1**: `WordTiming`, `TranscriptionSegment.words`, `TextClipContent.wordTimings`를 추가하고 Apple Speech `SFTranscriptionSegment` timestamp/duration/confidence를 보존하며, `SubtitleGenerator`가 세그먼트 절대 word 시각을 클립 상대 시각으로 변환한다. `StyledCaptionWordTimingTests` 6개로 legacy decode, Codable round-trip, relative transform, clamp, SRT omission을 검증했다. Caveat: macOS Speech Recognition 권한과 recognizer availability가 필요하고, caption style preset/active word renderer/preview-export burn-in/iOS 갤러리는 G-01 Inc 2+이다.
- [x] ✅ 자막/text burn-in export (P1) — Batch 16에서 `TextOverlayPixelProcessor`가 CoreGraphics/CoreText 기반으로 텍스트/자막 클립을 투명 RGBA overlay에 렌더하고 Mac/iOS `CustomVideoCompositor`가 shared processor로 위임한다. 픽셀 테스트는 배경 박스/알파 변화, fadeIn, typewriter, extent preservation을 guarded `CIContext`로 검증하고 static contract가 Mac/iOS compositor delegation과 Mac export/playback 경로를 확인한다. Caveat: 이 완료 범위는 text/subtitle clip burn-in이며, 자막 스타일 프리셋과 고급 caption template 렌더링은 이미 별도 구현된 경우를 제외하면 후속 항목이다.
- [ ] 🟡 자막 편집 워크플로우 + SRT import/export (F-13) (P1→구현됨) — Core `SubtitleDocument` SRT 파서/시리얼라이저 + ViewModel 세그먼트 편집(수정/분할/병합/삭제, pending clip 재정렬 재사용) + `AutoSubtitlesView` 인라인 편집·SRT Import/Export. `SubtitleDocumentTests` 9개 검증. Caveat: W3 실기기 완주와 외부 플레이어 SRT 확인 잔여 — DoD §1.3에 따라 ✅ 보류.
- [ ] 🟡 텍스트 외곽선/그림자/굵기+사용자 프리셋 (F-12R) (P1→구현됨) — `TextClipContent` 데코 필드(A5) + shared 렌더러 stroke 2-pass/`setShadow`/폰트 트레이트 + `UserTextStylePreset` 저장소 + Inspector 컨트롤. `TextDecorationTests` 9개(RGBA 스캔 픽셀 검증 포함). Caveat: 실기기 확인 잔여 — DoD §1.3에 따라 ✅ 보류.
- [x] ✅ 텍스트 애니메이션 프리셋 13종 preview/export 검증 (P2) — **2026-07-05 G-12 #6 상환**: `TextAnimationPreset` 13종 renderState delta 테스트와 DEBUG 앱 하니스 `MOVIECUT_UITEST_TEXT_ANIMATION_PRESET`를 추가하고, `run_e2e_export.sh`가 none-baseline 대비 export frame-diff로 13종 burn-in을 검증한다. 실측: non-none max_residual_temporal_mad min 2.870069(fadeOut) / max 6.594722(popIn). Caveat: synthetic fixture 기준이며 상용 템플릿 모션 디테일은 후속 품질 작업.

### E. 스티커/오버레이
- ✅ 이모지/이미지 스티커 + 캔버스 변형
- ✅ 온캔버스 드래그/리사이즈/회전 핸들(단일 선택)
- [ ] ❌ 다운로드형 스티커 스토어/팩 (P3)

### F. 오디오
- ✅ 볼륨 / 페이드 / 파형 표시
- [x] ✅ 페이드 duration 편집 UI (P1) — Mac Inspector `Fade Duration` 그룹에서 Fade In/Fade Out 현재값을 초 단위로 표시하고 Slider + Seconds `TextField` + 0.05s Stepper로 0...min(10s, clip duration) 범위 정밀 편집을 제공한다. Reset Fades/None/Soft/Long preset은 모두 `updateSelectedAudioFade` → `AudioFadeCommand` 경로로 적용되어 undo/redo path를 유지한다.
- [x] ✅ 자동 덕킹 **실제 preview/export ramp + 앱 export RMS 검증** (P2) — **2026-07-04 G-12 #3 상환**: `AudioDuckingPlanner` + `Clip.duckingRanges/duckingLevel` + `SetAudioDuckingCommand`(단일 undo) + Mac preview/export 동일 ramp(attack 0.12s/release 0.25s, fade 회피) + Inspector Duck/Clear. `AudioDuckingTests` 14개에 더해 `run_e2e_export.sh`가 `duck_bgm_220hz_4s_mono.wav`/`duck_voice_1000hz_1s_mono.wav`를 앱 하니스로 두 트랙 export 후 220Hz BGM 성분을 Goertzel 측정한다. 실측: voice-window BGM 3.098866e+01→1.935795e+00, reduction 12.04dB, quiet_delta 0.00dB, voice/quiet 0.062. Caveat: 실제 상용 BGM+사람 음성 GUI 녹화는 후속 품질 작업.
- [x] ✅ EQ **실제 DSP + 앱 export 스펙트럼 검증** (P2) — **2026-07-03 G-12 #1 상환**: 과거 판정(`AudioEqualizerService` dead/crash + 평균게인 볼륨근사)은 현재 해소. `AudioEqualizerService`는 AVAudioFile 버퍼 DSP로 bass/mid/treble 대역을 분리 적용하고, Mac 하니스 `MOVIECUT_UITEST_EQ_PRESET`이 command-backed `applyEQPreset` 경로로 선택 클립에 적용한다. `run_e2e_export.sh`가 `eq_low_high_2s_mono.wav`를 bassBoost/trebleBoost로 각각 앱 export 후 Goertzel 측정: bass_ratio 2.315524 vs treble_ratio 0.488654, treble_high 1.891041e+02 > bass_high 9.854772e+01. Caveat: UI 슬라이더 실조작 녹화와 세밀한 5밴드 청감 튜닝은 후속 품질 작업으로 남는다.
- [x] ✅ 노이즈감소 **실제 DSP + 앱 export SNR 검증** (P2) — **2026-07-04 G-12 #2 상환**: `NoiseReductionService`가 deterministic AVAudioFile 버퍼 DSP로 sub-voice rumble 제거 + high-frequency residual attenuation을 적용하고 `applyNoiseReduction(for:)` destructive apply로 클립 소스를 denoise 파일로 교체한다. 앱 컨텍스트 `MOVIECUT_UITEST_DENOISE` + `noisy_voice_1k_hiss_8k_2s_mono.wav` E2E에서 8kHz hiss/1kHz voice 비율이 0.248784→0.075641로 감소(improvement 5.17dB, voice_retention 0.913). Caveat: 실제 사람 음성/생활소음 청감 GUI 녹화는 후속 품질 작업으로 남는다.
- [ ] 🟡 비트 감지(음악 동기 편집, F-15) (P2→구현됨) — `BeatDetectionProvider`(에너지 플럭스 onset, 합성 클릭 트랙으로 <50ms 간격 검증) + `Marker.kind(.beat)` + 배치 마커 명령(단일 undo) + 룰러 틱 렌더/스냅 포함 + Quick Tools Detect/Clear Beats. `BeatDetectionTests` 13개. Caveat: 실음원 GUI 확인 잔여 — DoD §1.3에 따라 ✅ 보류.
- [x] ✅ 보이스오버 실제 마이크 녹음 (P1) — Mac `VoiceoverRecordingView`가 macOS `AVCaptureDevice` microphone 권한을 확인/요청하고, shared `VoiceoverRecorder`의 `AVAudioEngine` input tap 경로로 temp CAF에 실제 녹음한다. 녹음 UI는 timer/input level/saving progress/accessibility label·hint를 제공하고, stop 시 recorder elapsed time을 `fallbackDuration`으로 `EditorViewModel.addVoiceoverAudio(from:fallbackDuration:)`에 넘긴다. EditorViewModel은 `audioDuration(for:)`로 readable audio duration을 먼저 쓰고, recorder fallback duration, 0.1s minimum 순서로 duration을 확정해 playhead 위치에 audio clip을 추가/선택한다. `MediaImporter`는 voiceover CAF를 audio asset으로 분류한다. Caveat: 실제 마이크 접근은 `NSMicrophoneUsageDescription`, macOS Microphone 권한, 선택된 입력 하드웨어에 의존하므로 호스트에서 실제 녹음 검증이 필요하다.
- [x] ✅ 오디오 추출 **실제 앱 경로 + audio-only export 검증** (P2) — **2026-07-04 G-12 #10 상환**: `solid_red_tone_320x240_2s_30fps.mp4` fixture와 `MOVIECUT_UITEST_EXTRACT_AUDIO` 하니스가 실제 `extractAudio(from:)` 경로로 video asset에서 audio clip을 생성하고, `MOVIECUT_UITEST_EXPORT_AUDIO`가 audio-only export를 작성한다. `run_e2e_export.sh` ffprobe/RMS 실측: clips=1, clip_duration 2.000s, export_duration 2.066576s, codec aac, rms 0.087598. Caveat: GUI 실조작 녹화는 후속 품질 작업.
- [ ] 🟡 TTS(텍스트→음성, F-17) (P3→구현됨) — shared `TextToSpeechSynthesizer`(AVSpeechSynthesizer.write→CAF) + value-type voice 목록 + ViewModel 텍스트클립 정렬 오디오 클립 생성 + Inspector Voice 피커/Generate Voice. `TextToSpeechTests` 7개(실합성 통합 테스트가 실제 오디오 생성). Caveat: 실기기 GUI 확인 잔여 — DoD §1.3에 따라 ✅ 보류.

### G. 속도/시간
- [x] ✅ 속도 조절 / speed ramp preview+export (P1) — Mac `PlaybackEngine` preview와 `ExportEngine` export가 `SpeedRampCurve(points: clip.speedRampPoints)`로 source segment를 나누고 `scaleTimeRange`로 composition time range를 조정한다. 비디오 클립의 audio preview path와 `.audio` track preview path도 같은 segment/scale 경로를 사용한다. 고급 옵티컬 플로우 기반 부드러운 슬로우모션은 아래 P3 항목에서 G-12 #5로 별도 상환했다.
- ✅ 역재생
- [x] ✅ 정지프레임 (P2) — **2026-06-23 export 반영 확정**: `ExportEngine`(`isFreezeFrame` 감지 → 1프레임 source range → `scaleTimeRange`)·`PlaybackEngine` 양쪽 표준 기법. **헤드리스 E2E 측정**: 2s 클립에 2s freeze → export 2.0s→**4.0s**(delta 정확히 freeze duration). `run_e2e_export.sh`.
- [x] ✅ 옵티컬 플로우 보간(부드러운 슬로우모션) (P3) — **2026-07-04 G-12 #5 상환**: 0.25× slow-motion export가 단순 duration/fps stretch만 하던 문제(adjacent MAD 0.0000)를 `MotionAwareSlowMotionRenderService`의 motion-aware temporary render asset 경로로 보강했다. `run_e2e_export.sh`가 `moving_subject_320x240_2s_30fps.mp4`를 `MOVIECUT_UITEST_PLAYBACK_RATE=0.25` + `MOVIECUT_UITEST_OPTICAL_FLOW=1`로 export 후 ffprobe/frame-diff 검증한다. 실측: 8.000000s, 120/1fps, 960 frames, adjacent_mad 0.001519, mid_vs_blend 0.001845, anchor_mad 0.005642. Caveat: deterministic motion-aware 보간 기준이며, 실사/가림/복잡 모션 품질은 CapCut 대비 후속 품질 튜닝 필요.

### H. AI 기능 (CapCut 차별화)
- [ ] 🟡 자동 컷(무음 제거, F-18) (P1→preview/파라미터/단일undo 구현됨) — `AutoCutPlanner`(패딩으로 발화 보존) + `AutoCutCommand`(단일 undo) + ViewModel preview/apply/cancel + threshold/min/padding 슬라이더 + 타임라인 빨간 하이라이트. `AutoCutPlannerTests` 13개. Caveat: 실인터뷰 fixture 청취 확인 잔여 — DoD §1.3에 따라 ✅ 보류.
- [ ] 🟡 씬 변경 감지 자동 분할 (P2) — **2026-08-24 정정**: Core `SceneChangeProvider` + ViewModel `detectAndSplitScenes` 명령 경로 + UI 배선(분석 섹션·suggestCuts) 모두 존재. 잔여는 CA-21 측정 게이트(precision/recall 사전등록)뿐.
- [ ] 🟡 자동 리프레임(피사체 추적 crop, F-19) (P2→스무딩/미리보기 구현됨) — `ReframeSmoothing`(moving average + clamp, AC③ 떨림 감소 테스트) + ViewModel preview/apply/cancel + PreviewPanel crop-path 오버레이 + Inspector 섹션. `ReframeSmoothingTests` 8개. Caveat: 실영상 추적 정확도(AC②) 확인 잔여 — DoD §1.3에 따라 ✅ 보류.
- [ ] 🟡 AI 어시스턴트(자연어 편집 명령, F-21) (P3→규칙기반 1단계 구현됨) — `AssistantCommandParser`(동의어 target×action + 숫자 파싱) + ViewModel 실행기(기존 명령 매핑) + Inspector AssistantSection. `AssistantCommandParserTests` 8개(20 intent 시나리오 포함). Caveat: 외부 LLM 연동 별도 합의 — DoD §1.3에 따라 ✅ 보류.
- [ ] 🟡 자동 하이라이트(롱폼→숏폼, F-20) (P3→구현됨) — `HighlightScorer`(silence/scene/beat 출력 조합, 비중첩 top-N) + ViewModel detect/createSequence(새 프로젝트 스왑) + Inspector HighlightsSection. `HighlightScorerTests` 8개. Caveat: 실영상 후보 적합성 확인 잔여 — DoD §1.3에 따라 ✅ 보류.

### I. 캔버스/프로젝트
- ✅ 비율 프리셋(16:9 / 9:16 / 1:1 / 4:5 / 21:9)
- [ ] 🟡 캔버스 배경(블러/컬러/이미지, F-11) (P2→구현됨) — shared `CanvasBackgroundPixelProcessor` + Mac/iOS compositor 합성 + Canvas 팝오버 UI + `CanvasBackgroundTests` 14개. Caveat: 실기기 preview 확인과 export visual fixture 잔여 — DoD §1.3에 따라 ✅ 보류. 상세는 스펙 F-11 검증 기록.
- ✅ 마커(추가/이름/삭제/점프)
- [x] ✅ 챕터/비트 마커 export 메타데이터 (P3) — **2026-07-05 G-12 #9 상환**: `MOVIECUT_UITEST_CHAPTER_MARKERS=1`/`MOVIECUT_UITEST_BEAT_CHAPTERS=1` 하니스가 표준/비트 마커를 command path로 추가하고, ExportEngine이 AssetWriter timed metadata track + `.chapterList` association으로 MP4 chapter atom을 기록한다. `run_e2e_export.sh` ffprobe 실측: `count=3 starts=0.25,0.75,1.25 ends=0.75,1.25,1.75`. Caveat: ffprobe title tag는 빈 문자열로 표시되어 하니스 status로 marker name/count를 함께 검증한다.

### J. 협업/배포
- [ ] 🔴 클라우드 동기화(F-22) (P3, 미구현) — **2026-08-24 정정**: 과거 기록이 `CloudSyncService`·`CloudConflictTests`의 존재를 주장했으나 현재 저장소에 소스 0건(아카이브/DerivedData 잔재만 존재). 구현 시 신규 착수로 취급.
- [ ] 🟡 템플릿 마켓플레이스 — picker만 (P3)
- [ ] 🟡 템플릿 패키지(F-23) (P3→구현됨) — `ProjectPackage` .mctemplate export/import + Package 메뉴, `ProjectPackageTests` 7개. Caveat: 실기기 GUI 잔여.
- [x] ✅ 플랫폼 게시(F-24) — OS 공유 시트(ShareLink)로 충족. 직접 API 게시는 스펙 권고대로 범위 외.

### K. 카드뉴스 사용성 (UB-C / 2026-07-14 등록)
- [x] ✅ **G-18 카드 문서 모델+편집기 (P0)** — **Inc 1~4 완료**: persisted normalized card model/atomic commands, command-backed Mac card mode, real normalized canvas(move/resize/인라인 텍스트/atomic 이미지 교체), actual-app save/reload E2E(`MOVIECUT_UITEST_CARD_EDITOR=1` dump `complete=true/error=none/finalPageCount=5/maxNormalizedFrameError=0/saveReloadEqual=true`, 전체 `run_e2e_export.sh` `E2E check OK`). `CardDocumentCommand|CardLayout` 26/26 PASS. UB-C1(add/duplicate/delete/reorder 각 ≤2)/UB-C3(3규격, error 0≤0.001)/UB-C4(inline 1회 진입+undo 복원) 자동화 충족. SC-C1(≤10분/막힘 0)은 `[사용자 확인 대기]` 유지(admin UI Automation 권한으로 XCUITest 초기화 차단).
- [x] ✅ **G-19 카드 템플릿+마스터 스타일 (P0)** — 고유 시각 fingerprint의 내장 세트 10종, 5장/all roles/empty slot 0, 선택→적용 2클릭, 8장 effective master 전파와 page override 보존/폰트·색·로고 위치 적용 2클릭, template/master 각각 single-step undo를 actual-app dump와 전체 `E2E check OK`로 검증했다. SC-C1은 `[사용자 확인 대기]`; 다음 자동 마일스톤은 G-20 브랜드 킷.
- [ ] ❌ **G-20 브랜드 킷 (P1)** — 로고·색·폰트 묶음의 프로젝트 간 영속 저장/적용 0건. 목표: 새 프로젝트 적용 ≤2클릭, SC-C2(8장+일괄 스타일+export) ≤5분.
- [ ] ❌ **G-21 카드 export (P0)** — 페이지 세트 renderer/PNG·JPG 순번 일괄 writer/카드→9:16 video planner 0건. 목표: 전 카드 `card_01...` PNG/JPG(1080×1080/1080×1350/1080×1920) 및 기본 duration+전환+BGM 슬롯 영상화, SC-C3 조작 ≤1분(렌더 제외).
- [ ] ❌ **G-22 대본 자동 분배 (P2)** — 문단 parser/distributor/온디바이스 요약 seam 0건. 목표: 문단 매핑 누락·중복 0, 문안 창작 제외, SC-C4 ≤5분.
- [ ] ❌ **U-10 카드뉴스 진입점 (P1)** — 앱이 영상 에디터로 직행하며 New Project 카드 분기 0건. 목표: 카드 갤러리까지 2클릭 이하, SC-C1 ≤10분·막힘 0/P-반복 ≤5분.

---

## 4. 권장 작업 순서

V12/v1.6 Works-First 기준 우선순위: 사용자 보고로 사진 클립 preview/export P0 회귀가 확인되어 **G-15 이미지 클립 파이프라인이 모든 큐 최우선**이다. **G-15 AC1~AC3**(blue png 앱 export + 사진→비디오 mixed export duration/색 샘플 + image warm-grade 평균색 이동)는 상환했지만, 실기기 preview+trim/EXIF/iOS/대형 이미지 메모리는 [진행중]이므로 다음 자동 선택은 **G-15 AC4 실기기 확인**이다. 그 다음은 G-15 AC5~AC7, **U-08 잔여(4표면/클릭수)**, **G-02 Inc 5~6(W5 완주)**, G-01 Inc 2~4 순서다. #11/#12는 fixture 제작 증분으로 분리해 병행 슬롯에서 다루고, #13/#14는 수동 검증 대기로 자동 선택에서 제외한다. 레거시 P1 정적 계약 기준의 다음 1순위는 F-01 실기기 검증이며, V12 신규 루프와 병행한다.

1. **P0 묶음 완료 확인** — 라이브러리→타임라인 드래그앤드롭은 2026-06-10 실기기 GUI 검증까지 완료됐고, 드롭 성공/실패 피드백(A), 색보정 밝기/대비/채도 실픽셀 처리(C), 자동자막 STT(D)도 닫혔다. 단, 이것이 CapCut 95% 도달을 뜻하지는 않는다.
2. **P1 high-ROI 실제 렌더링/UX 항목 계속 진행** — 썸네일/프록시(A), speed ramp preview+export(G), 텍스트 스타일 편집 UI(D), 보이스오버 실녹음(F), 페이드 duration 편집 UI(F), 마그네틱 타임라인 / 클립별 zIndex(B), 키보드 단축키 맵(F-05), 임포트 메타데이터(F-06)는 닫혔다. F-01 비파일 드래그 소스(Photos/브라우저 이미지 드래그)는 `.image`/`.movie` payload materialization과 NSItemProvider behavioral test까지 통과했고, 2026-06-11 Safari data URL 이미지의 라이브러리 import 및 Video 1 타임라인 클립 생성은 실제 GUI 드래그로 확인했다. 단 Photos 앱 또는 대체 네이티브 앱 비파일 소스는 Photos window 0/AppleScript import timeout 및 screencapture black-frame 상태로 미검증이라 전체 완료 처리는 보류한다. 이 잔여는 V8 기준 G-12 #14로 유지한다. export format/codec controls(A)는 custom bitrate 1~200 Mbps clamp와 export/mask accessibility 배치까지 닫혔고, 자막/text burn-in export(D)는 Batch 16 범위에서 닫혔고, 전환효과 Inspector picker/duration 노출은 Batch 17 범위에서, two-source custom compositor preview/export 배선은 P1 transition pass에서 닫혔으므로 남은 P1 UI 목록에서 제외한다.
3. **"🟡 배선만" → 실제 알고리즘 채우기** — 명령/메타데이터 경로가 이미 있으므로, compositor에 CIFilter/Vision/AVAudioUnit 처리만 붙이면 됨. 신규 배선보다 ROI 높음.
4. **갭 문서 재작성** — "코드 존재"가 아니라 "preview+export 결과 확인"을 완료 기준으로.

---

## 5. 빌드/검증 메모

- `swift build` 는 Core에서 통과.
- `swift test --filter '...'` 으로 부분 테스트 가능.
- macOS 앱 빌드: `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build`.
- 과거 일부 환경에서 `xcodebuild`가 SwiftPM 패키지 resolution 단계에서 `~/.cache/clang/ModuleCache`, `~/Library/Caches/org.swift.swiftpm` 쓰기 때문에 막힌 기록 있음(샌드박스 한정). 대안: `swift build --disable-sandbox`, `swiftc -typecheck -disable-sandbox`.

## 6. 핵심 파일 위치
- 타임라인/드롭: `App/MovieCutMac/TimelineView.swift`
- 라이브러리/드롭/Add to Timeline: `App/MovieCutMac/MediaLibraryPanel.swift`
- 임포트/클립 생성 로직: `App/MovieCutMac/EditorViewModel.swift` (`importMedia` :512, `addClipToTimeline` :530)
- probe: `Sources/MovieCutCore/Media/MediaImporter.swift`
- export compositor: `App/MovieCutMac/Export/CustomVideoCompositor.swift`, `Export/ExportEngine.swift`
- preview 렌더: `App/MovieCutMac/Playback/PlaybackEngine.swift`, `PreviewPanel.swift`
- iOS 대응: `App/MovieCutiOS/` (Mac과 구조 유사, 변경 시 동기화 필요)
