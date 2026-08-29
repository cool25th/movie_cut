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
| CA-01 | 오프라인 차단·DNS/HTTP 트래픽 캡처 테스트(iOS 포함) — 증거원장 MC-02 ②③ | P0 | **즉시 실행 가능** | 네트워크 차단망에서 대표 작업 전 통과 + 캡처 0 기록을 증거원장 MC-02에 갱신 |
| CA-02 | 파리티 허용 오차 등급 수치 확정(Exact/Tolerance/Perceptual) | P0 | **완료(2026-08-23)** — VERIFICATION_STANDARD §2 등급별 수치 확정(Exact=수치 동일·유닛테스트 담당 / Tolerance=MAD ≤ 2.0+1프레임·17 시나리오 게이트 / Perceptual=블라인드 비열등)+신규 시나리오 등급 명시·허용치 변경 승인제 기재 | 골든 재판정 기준 문서화 |
| CA-03 | 미디어 관리·프로젝트 생존성 감사(재연결·누락·손상·마이그레이션 실패 경로·디스크) | P0 | **완료(2026-08-24, e36f83a + 2차 실사 병합)** — `AUDIT_MEDIA_SURVIVABILITY_20260824.md`(경로 5종 판정 + §4 2차 병합). 등록: BUG-01(P0 오토토회복 침묵)·BUG-02(P0 임포트 무검증)·**BUG-04(P1 익스포트 사전 미디어 검사 부재 — 2차 신규)**·**BUG-05(P1 분류 오류 미분류 덮어씀 — 2차 신규)**. BUG-03(재연결 자동화 0)은 **폐기** — `MediaRelinkTests`가 이미 실경로 잠금(1차 탐색 누락). 수정은 BUG 증분으로(§1.7) | 감사 보고 + 발견 결함의 P0 버그 등록 (완료) |
| CA-04 | 입력 포맷 호환 매트릭스(VFR·10bit·Log·혼합 fps/sample rate·rotation) | P0 | **즉시 실행 가능(방향 문서 §3 v1.1 반영 완료 2026-08-24)** | 매트릭스 작성 + 최우선 회귀(혼합 미디어 sync·색 유지) 실측 |
| CA-05 | 실패·복구 UX 매트릭스(15 실패 시나리오 × 무손실/원인/재시도/이어하기/임시파일) | P0 | **완료(2026-08-24)** — `CA05_FAILURE_RECOVERY_UX_MATRIX_20260824.md`: 15 시나리오 × 5축 파일:라인 근거. 13/15 완전 충족(CA-03 감사·외부 리뷰 반영이 전제). 신규 등록: UX-REC-01(P2 iOS 부분출력 잔존)·UX-REC-02(P2 iOS 복구 무음 채택) — §1.9 | 매트릭스 + 결함 우선순위화 (완료) |
| CA-06 | 접근성 핵심 경로 매트릭스(임포트→편집→출력, VoiceOver 등) | P0 | **완료(2026-08-24)** — `CA06_ACCESSIBILITY_CORE_PATH_MATRIX_20260824.md`: Mac 핵심 경로 VoiceOver·키보드 전 충족(UX-08 계약+43 단축키). **iOS 차단 발견: A11Y-01(P1) 인스펙터 하위 뷰 5종 라벨 0건** + A11Y-02(P2)·A11Y-03(P3) — §1.10. 인스펙터 Picker 라벨 접힘은 이번에 수정 | 매트릭스 + 차단 결함 등록 (완료) |
| CA-07 | 가격·판매 단위 결정(모델 선택·Universal Purchase) | P0 | **모델 확정(Q2: 일회성+유료 메이저 업데이트) — 구체 가격은 사용자 전용 유지** | 결정 기록 → REQUIREMENTS §13 반영 |
| CA-08 | iOS 자막 스타일 6종·카라오케 이식 | P1 | **즉시(방향 문서 2단계 "카라오케 스타일 편집"과 일치)** | iOS 파리티 시나리오 + 실기기 검증 |
| CA-09/10 | N1-A 대사 검색 / N1-B 텍스트 기반 구간 선택 | P1 | 승인 대기(Q11 일괄 승인) | 검색 성공률·구간 이동 정확도 측정 |
| CA-11 | N2 제안형 오토스타일 MVP(제안→미리보기→적용→undo — 자동화 4원칙 전항) | P1 | 승인 대기(기존 'N2 등록' 대기와 동일 건) | COMPETITIVE_ANALYSIS §1.5 원칙 전항 + 동일 입력 재현성 |
| CA-12 | 경쟁사 A/B 벤치마크 하니스(조건 필드·12 fixture·PSNR/SSIM+블라인드) | P1 | **즉시 실행 가능(측정 인프라 — 방향 문서 4단계 게이트의 전진 구축)** | 하니스 + 기준 수치 최초 기록 |
| CA-13 | 폰트 패키징 정책(N5 — 라이선스 경고·프로젝트 포함·PostScript 충돌) | P1 | 승인 대기(라이선스 검토 선행) | 정책 문서 + 구현 |
| CA-14/15 | 비트 감지 iOS UI / 현지화·텍스트 품질 감사 | P1 | 즉시(소형 — G-09 Inc3 이후 슬롯) | 파리티/감사 보고 |
| CA-16 | [P2 묶음] N1-C/D·매치컬러·애니메이션 스티커·보이스 체인저·업로드 보조·iOS 프록시·배치 export·**Auditions 테이크 비교(2026-08-23 v4 보류 편입 — 중간 규모·FCP 고유 패러다임, 베타 반응 후)** — 벡터스코프 제거(2026-08-23: 이미 구현 `InspectorEffectsSection.swift:200`) | P2 | 베타 반응 후 | 각 항목 DoD |
| CA-17 | 자막 sidecar **검증**·iOS 진입 — VTT/SRT 구현·UI·테스트 이미 존재(737c036, `CA_REGISTRATION_PROPOSAL_20260823.md` v2). 잔여: 실제 플레이어 3종 로드 확인(D), iOS export 진입(없음 — G-09 Inc3 4순위와 세트) | 소형 | **즉시 실행 가능(2026-08-23 승인)** | 플레이어 3종 로드 기록(체크섬) + SRT↔VTT round-trip 골든 회귀 |
| CA-18 | 화자 분리(diarization) 자막 — 게이트형 연구. **임계값 사전 등록: 화자 혼동율 ≤10%(합성·실녹음 각각)·RTF ≤0.5·메모리 예산(스템 게이트와 동일 기준)** | 연구 | **측정 단계만 승인(2026-08-23)** — 구현 착수는 측정 보고 후 별도 승인 | 2인 fixture 측정 보고 → 임계값 전항 통과 시에만 UI 착수 승인 요청, 미통과 시 명시적 실패 기록 |
| CA-19 | 타임라인 **가이드라인**(드래그 기준선) + 눈자 밀도 감사 — 시간 눈자는 이미 존재(1/5/10초 밀도 적응, `TimelineView` timeRuler), 잔여는 가이드라인과 장편 분 단위 가독성 | 소형 | **즉시 실행 가능(2026-08-23 승인)** | 가이드라인 생성·이동·삭제·스냅 우선·undo 단일 골든 + 밀도 감사 보고 + VoiceOver 회귀 |
| CA-20 | roles + 타임라인 인덱스(W4 장편 관리 세트) — 클립 role 태그·롤별 레인 색·인덱스 검색→이동. FCP roles+Timeline Index 대응. role·키워드·스마트컬렉션 전무(`CA_REGISTRATION_PROPOSAL_20260823.md` v3 §2, 2026-08-23 코드 확인) | P2 | **등록 승인(2026-08-23) — 방향 문서 §3 반영 후 실행**(W4 직결, 2단계 배치 검토) | role 영속화+migration round-trip · 롤별 레인 골든(U) · 인덱스 검색→이동 30분 fixture p95 · VoiceOver 인덱스 탐색 · iOS defer 사유 기록 |
| CA-21 | Edit Detection(씬 자동 분할 제안) — Core `SceneChangeProvider` 존재, UI·명령 경로 없음. FCP 12.3 대응 | 연구(P2) | **측정 단계만 승인(2026-08-23)** — precision/recall 임계값은 측정 설계 시 사전 등록 후 고정 | 합성 fixture+실영상 2종 측정 보고 → 통과 시에만 UI 착수 승인 요청(§1.5 원칙 전항), 미통과 시 명시적 실패 기록 |
| CA-22 | 프록시 자동 생성 — 임포트 시 백그라운드 큐(현재 수동 전용 `EditorViewModel+Media.swift:63`). 인프라 완비(4단계+배지+thermal), 자동화만 부재(N8) | P2 | **즉시 실행 가능(2026-08-23 승인)** — G-27 이후 슬롯 | 백그라운드 생성 E2E(진행·취소·재개) · thermal 상호 정책 · 생성 중 편집 회귀 · 디스크 여유·실패 안내(CA-05 연결) |
| CA-23 | 프로젝트 스냅샷/버전 히스토리 — autosave와 별개 사용자 주도 안전망(현 기능 부재. 과거 `VersionHistory`는 archive V1/V2 이후 삭제 — 2026-08-23 전역 검색 0건, dead-code 재활용 근거 정정) | P2 | **등록 승인(2026-08-23) — 실행 시점은 별도 결정** | 스냅샷 생성·목록·복원 앱 E2E(undo 독립) · 용량 정책·오래된 정리 · autosave 역할 구분 문서화 · 복원 전 현재 상태 보호 확인 |
| CA-24 | 한국어 UI 커버리지 100% — xcstrings 파싱: Mac 316/422·iOS 303/409 키 ko 보유(각 106키 누락, 2026-08-23). Q1 페르소나 직결 | 소형(P1 하위) | **즉시 실행 가능(2026-08-23 승인)** — CA-15 묶음 처리 | 잔여 키 번역 완성(Mac+iOS) · 미번역 fallback 감지 게이트(CI 경고) · ko 실기기 스크린샷 골든 갱신 |
| CA-25 | 온보딩·샘플 프로젝트 — W1 미니 샘플 번들+첫실행 3단계 안내(임포트→자막→출력). 첫실행 경로 부재("Landscape Tutorial"은 템플릿 자산일 뿐, `BuiltinTemplates.swift:43`) | 소형 | **등록 승인(2026-08-23) — 방향 문서 §3 반영 후 실행**(Track A 베타 체감 직결) | 샘플 프로젝트 번들 내장(**오프라인 원칙 유지**) · 신규 사용자 첫 출력 ≤10분 목표 측정(SC-C1 스타일) · Quick Tools 발견률 최소 측정 |
| CA-26 | LUT export(.cube 저장) — 그레이딩→LUT 저장 경로 부재(2026-08-23 전역 확인: writeLUT/exportLUT 0건, import만 존재). W3/W4 색 워크플로 완결·표준 포맷이라 오프라인 원칙 무관 | 소형 | **완료(2026-08-23)** — Core `CubeLUTExporter`(serialize: %.6f red-fastest round-trip 무손실 + bake: 기본 보정을 생산 `ColorCorrectionPixelProcessor` 경유 그리드 렌더, v1 스코프=기본 보정 한정·3-way/HSL/마스크 제외 UI 명시)+테스트 3건(round-trip·identity bake·brightness bake)+Inspector "Export LUT…" 저장패널 진입점(외부 LUT 재내보냄 무손실/기본 보정 bake 분기, 상태 메시지로 스코프 고지) | 게이트 5단계 통과(1,354 테스트) |
| CA-27 | Timecode 직접 입력 — `PreviewPanel` 표시 전용이었음(2026-08-23 확인). 키보드 완결성·정밀 탐색(Q6 핵심 경로 정합) | 소형 | **완료(2026-08-23)** — Core `TimecodeParser`(SS·MM:SS·MM:SS:FF·HH:MM:SS:FF, 무효 입력 nil 명시적 실패)+유닛테스트 6건(Exact)+현재 시간 배지 편집 필드화(제출·포커스 상실 시 seek, 무효 입력 상태 메시지·원복)+VoiceOver 라벨+표시 fps를 프로젝트 프레임레이트로 정통화(기존 30 고정 오류)+StaticContract 2건 갱신·ko 문자열 3건 추가 | 게이트 5단계 통과(1,351 테스트) |
| CA-28 | RGB 파레이드 스코프 — `parade` 0건(2026-08-23 확인, 벡터스코프는 존재). `ScopeViews` 확장 소형 | 소형 | **완료(2026-08-24)** — Core `ScopeAnalyzer.rgbParade`(lumaWaveform과 동일 빈ning 계약의 R/G/B 채널별 파형)+골든 테스트 4건(채널 분리·x 램프 추적·혼합 픽셀 독립 빈ning·퇴화 가드, Exact)+Mac `RGBParadeView`(R/G/B 패널, WaveformView와 동일 렌더링 계약)+인스펙터 노출(그레이딩 패널 waveform/vectorscope 행 아래)+접근성 라벨/값(영어 키+en/ko). 기존 스코프(histogram·waveform·vectorscope) 무변경·회귀 없음 | 게이트 5단계 통과 |

**실행 규칙**: CA-01·02·03·04·05·06·08·12·14·15·17·19·22·24·26·27는 즉시 실행(03~06은 2026-08-24 방향 문서 §3 v1.1 반영으로 자격 확보), CA-28 완료, CA-18·21은 측정 단계만, CA-20·23·25는 등록 완료(실행 조건 도달 시), 나머지는 승인 대기. AI 음성(TTS 보이스 확장)은 **등록 보류(2026-08-23 승인 — 베타 반응 후 재상정)**. 루프 회차 보고에는 '승인 대기' 항목을 항상 나열한다.

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

### 참고 (UX-REC-03) — 세션 중 스코프 철회는 열기/익스포트 게이트에서만 감지

- 실시간 재탐지는 비용 대비 효과 낮음 — 현재 패턴 유지 결정(매트릭스 §2).

---

## 1.10 CA-06 매트릭스 파생 결함 — 접근성 (2026-08-24 등록)

> 원천: `CA06_ACCESSIBILITY_CORE_PATH_MATRIX_20260824.md`. Mac 핵심 경로는 차단 없음 — 아래는 iOS 중심.

### A11Y-01 (P1, iOS 차단급) — iOS 인스펙터 하위 뷰 VoiceOver — **수정 완료(2026-08-24)**

- 실사 정정: 텍스트 라벨 버튼/토글/ColorPicker는 기본 announced(0건 카운트는 과대) — 실제 갭은 bare `Slider`(효과 인스펙터 opacity/speed/inspectorSlider·크로마키 slider 헬퍼)와 필터 선택 상태. 수정 완료: 슬라이더 라벨+값·필터 선택 announce + `IOSInspectorAccessibilityContractTests` 4종(시뮬레이터 #filePath 경로 해석 포함).

### A11Y-02 (P2) — iOS 익스포트 진행 시트 — **해소(2026-08-24, 기존 구현 확인)**

- 실사 결과 이미 구현돼 있었음(라벨+값+힌트·취소 파괴적 롤+힌트) — 계약 테스트로 잠금.

### A11Y-03 (P3) — 빈 라이브러리 스켈리톤 카드 시각 신뢰감

- VO 숨김은 정상. 로딩/깨진 자산처럼 보이는 시각 문제 — 빈 상태 안내 카드로 교체(외부 리뷰 지적, 기능 아님).

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

**S1 G-02 Inc 1~3 커브/HSL 수학·렌더 체이닝 완료(2026-07-05)**: Inc 1에서 `CurvePoint`와 `CurveEvaluator` 순수 로직(256-entry LUT, endpoint 고정, duplicate-x deterministic, monotone cubic Hermite/Fritsch-Carlson tangents, clamp/no-overshoot)을 추가했고, Inc 2에서 `HSLBandCenter`/`HSLBand`/`HSLCubeBuilder` 순수 로직을 추가했다. Inc 3에서 `ColorGrade`에 optional `hslBands`/`curves`와 `ColorCurves`를 편입하고, `ColorGradePixelProcessor`가 CDL → HSL `CIColorCube` → channel/master curve cube 순서로 실제 렌더 체인을 소비한다. Mac/iOS preview/export는 shared processor 경로로 반영되고, E2E는 `MOVIECUT_UITEST_HSL_CURVES=1` 앱 export에서 baseline red-dominant `(5,1,0)` → neutral gray `(5,5,5)` 변화를 검증한다. Caveat: Mac/iOS HSL/Curve 편집 UI는 아직 미연결이며 G-02 Inc 5~7 범위다.

**S1 G-02 Inc 5 HSL 밴드 편집 UI 완료(2026-08-17)**: 위 Caveat의 Mac 측 해소 — `ColorHSLBandsView`(인스펙터 컬러 등급 섹션, 컬러휠·감마 슬라이더 인접 배치)로 8색상 밴드(적/주/황/녹/청/남/보/마젠타) 각 색조 시프트·채도·휘도 편집을 사용자가 만들 수 있다. 커밋은 드래그 종료 시 단일 커맨드(G-23 캔버스 패턴 — 제스처당 undo 1-step), 밴드 전부 identity면 `nil` 커밋으로 미그레이드 JSON 바이트 안정. 검증: 파리티 시나리오 16번 `hsl_curves` 신설(HSL_CURVES 게이트 — 레드 밴드 탈포화+마스터 커브, 프리뷰↔출력 동일), `ColorGradeGoldenTests` +JSON 라운드트립/identity 밴드 정규화, ui_regression 골든 갱신(의도 변경). 잔여: 커브 에디터 UI(Inc 6), iOS 동등 UI(2단계 파리티).

**S2 G-01 Inc 1 워드 타이밍 보존(2026-07-04)**: `WordTiming`, `TranscriptionSegment.words`, `TextClipContent.wordTimings`를 추가하고 Apple Speech `SFTranscriptionSegment` timestamp/duration/confidence를 보존하며, `SubtitleGenerator`가 세그먼트 절대 word 시각을 클립 상대 시각으로 변환한다. `StyledCaptionWordTimingTests` 6개로 legacy decode, Codable round-trip, relative transform, clamp, SRT omission을 검증했다. Caveat: caption style preset/active word renderer/preview-export burn-in/iOS 갤러리는 G-01 Inc 2+이다.

**V12 실사용 버그 재설정 및 G-15 AC1~AC3 상환(2026-07-12)**: 최신 분석 문서는 `docs/archive/GAP_ANALYSIS_V12_FUNC_UI_20260706.md`다. **사용자 보고 재현 확정**: 사진(이미지)은 import·타임라인 클립 생성까지만 되고 **preview 무표시 + export "Cannot Open" 실패**(헤드리스 실측 clips=1/export 미생성). 원인: 이미지 미디어 클립 파이프라인 미구현(`PlaybackEngine:494` video 트랙 전제 스킵, ExportEngine 이미지 분기 0건 — 이미지는 스티커 오버레이 경로만 존재). 전 E2E가 mp4/wav fixture라 미검출 → **A7 신설**(kind별 fixture 의무 + 실사용 스모크 상설). **G-15 Inc 1~3 부분 완료로 AC1~AC3는 역전**: `ImageVideoRenderService`가 image→H.264 segment를 만들고 Mac preview/export가 이를 기존 video source track으로 소비한다. E2E 실측: 단독 image export 성공(`duration=5.000000s`, middle frame `rgb=0,0,171`) + mixed image→video export 성공(timeline `video:image=0.000-5.000,video:video=5.000-7.000`, duration `7.000000s`, samples `image_rgb=0,0,171`, `video_rgb=5,0,0`) + image warm-grade export 평균색 이동(baseline `rgb=0,0,171` → graded `rgb=100,0,153`, `red_delta=+100`, `blue_delta=-18`). **남은 G-15**: AC4 실기기 preview/trim, AC5 EXIF fixture, AC6 iOS, AC7 대형 이미지 메모리 로그 [진행중]. 자동 선택 순서 **G-15 잔여 → U-08 잔여 → G-02 Inc 5~6 → G-01** (스펙 v1.6).

**V13 배선 격차 재설정(2026-07-29)**: 최신 분석 문서는 `docs/GAP_ANALYSIS_V13_FUNC_UI_20260729.md`(V12 대비 델타 62커밋)다. 기준선 실측: `swift build` ✅ / `swift test` **984 tests 162 suites 통과 18.6s** / Mac `xcodebuild` ✅ / **iOS `xcodebuild` ❌ 플랫폼(iOS 26.5) 미설치** / swiftlint 1,022건(error 414). **⚠️ 984 통과를 기능 증거로 읽지 말 것** — 테스트 파일 137개 중 85개(62%)가 StaticContract이고 부정 단언 248건이다.

① **격차 성격이 바뀌었다**: 주류가 "기능 부재"에서 **"배선 격차"**로 이동했다. `wordTiming`(Core 4파일 / App **0파일**), 프록시 소비(`PlaybackEngine`·`ExportEngine` 참조 **각 0회**), 현지화(`NSLocalizedString` 8파일이나 `.lproj`/`Localizable.strings`/`.xcstrings` **0개** → 실질 영어 전용) — 전부 만들어는 놨고 화면에 잇지 않았다.

② **미배선 Core 서브시스템 1,279줄 확정**(App 호출 0회): `Cloud/CollaborationService` 546, `AI/ClaudeEditingProvider` 265, `Analysis/StyleTransferProvider` 174, `Audio/VocalSeparationService` 121, `AI/AIEditingProvider` 103, `Cloud/VersionHistory` 70. `VocalSeparationService`는 V12 이전부터 dead code 전례로 지목됐고 **여전히 죽어 있다**(B-F5.2 격차와 직결). `Analysis/BackgroundRemovalProvider`도 App 0회지만 기능 자체는 `InspectorEffectsSection.swift:351` 토글 + `CustomVideoCompositor.swift:528 applyPersonSegmentation`로 동작하는 **위양성** — 프로바이더만 삭제 후보.

③ **부재 확정(각 0파일)**: 홈/프로젝트 목록(B-L2), 컴파운드 클립(B-F2.3), 프리뷰 품질 선택(B-I8), VTT/ASS export(B-F3.2), 속도 커브 프리셋(B-F2.4). 블렌딩 모드(B-F4.4)는 `blendMode` 매치 2건이 전부 `CISoftLightBlendMode`/`CIOverlayBlendMode` **내부 필터명**이라 사용자 노출 0. → **G-23 블렌딩 / G-24 컴파운드 신설**(스펙 v1.9).

④ **볼륨 실측**: 전환 12 / 이펙트 18 / 텍스트 템플릿 14 / 스티커 22 / SFX 12. CapCut은 각 수백~수천 — 전략상 큐레이션이나 격차는 격차로 기록한다.

⑤ **P0 부채 — 판정 재확인 필요**: 2026-07-28 핵심 편집 수리가 **메인 Preview가 프로젝트 합성 경로를 쓰지 않고 선택 원본을 직접 재생하고 있었음**(`b398563`)을 드러냈다. magnetic compaction 무차별 적용(`1fa836c`), 배속/ramp 시간 일관성 붕괴(`269d50a`·`dfde012`·`0115e6c`)도 함께 수리됐다. 즉 그 동안 V1~V12가 B-F2/B-F4에 부여한 `=` 판정은 preview+export 동시 증거 없이 내려진 것이다. **`=`는 재확인 전까지 잠정으로 읽는다** — 재확인 큐는 V13 §6.

⑥ **Track.isLocked dead-field 해소 확인**(v1.2 판정 정정): Core 3회 / App 2파일 배선됨.

**V11 기능+UI 재감사(2026-07-05, 기준 `6f76415`, 과거 기준)**: 분석 문서는 `docs/archive/GAP_ANALYSIS_V11_FUNC_UI_20260705.md`다. V10 권장 순서가 그대로 실행됨을 독립 검증 — G-12 #9(ffprobe chapter atom 실측)로 **10/14, 자동 상환 가능분 소진**, **G-02 Inc 1~3 완료**(HSL/커브 체이닝이 preview/export/iOS 실반영, 골든+E2E base_rgb 5,1,0→grade_rgb 5,5,5, build+353 tests PASS). 색 2차 보정 모순은 엔진 수준 해소 — **잔여는 편집기 UI(Inc 5~6)로, 현재 사용자가 HSL/커브 값을 만들 수단이 없다.** dead-value는 `wordTimings` 1건 잔존, dead code는 `VocalSeparationService`·`StyleTransferProvider`(폐기/G-07 흡수 결정 필요) 지속. **UI 트랙 4회 연속 착수 0건 — 다음 자동 선택은 U-08 → G-02 Inc 5~6(W5 완주) → G-01 Inc 2~4** (스펙 v1.5).

**SU U-08 Inc 1~2 UI 회귀/지표 인프라 착수/부분 완료(2026-07-06)**: `scripts/ui_capture.sh`가 Debug `MovieCutMac.app`을 populated harness(`MOVIECUT_UITEST_IMPORT` + Title 템플릿)로 실행해 실제 창을 `artifacts/ui/moviecut_populated_editor_raw.png`로 캡처하고, `scripts/ui_regression.sh`가 normalized PNG를 `Tests/UIEvidence/golden_populated_editor.png`와 dHash 비교한다. `artifacts/`는 `.gitignore`에 추가해 생성물과 committed evidence를 분리했고, `docs/UI_METRICS.md`에 사용법/정책을 기록했다. 검증: update-golden PASS, normal regression PASS(distance 0/threshold 4), 임시 golden negate 이빨 확인 FAIL(distance 56) 후 복원 PASS, build/test/xcodebuild/E2E PASS. Caveat: 현재 committed golden은 populated editor 1종이라 U-08 AC②의 4표면 골든과 AC③ 클릭수 metric은 [진행중].

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
