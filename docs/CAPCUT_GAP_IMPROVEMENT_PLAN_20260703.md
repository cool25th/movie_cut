# CapCut 대비 격차 분석 & 상세 개선안 — 2026-07-03

> 작성일: 2026-07-03 / 브랜치: `feat/core-backend-expansion` (기준 커밋: `c242632`)
> **이 문서는 다른 세션(콜드 스타트)에서 바로 개발에 착수할 수 있는 핸드오프 문서다.**
> **개발 착수용 상세 스펙(데이터 모델·구현 증분·AC·검증 계획)은 `CAPCUT_SURPASS_SPEC_20260703.md` — 실제 작업은 그 문서의 G-ID 단위로 진행한다.**
> 전략 배경: `MOVIECUT_PRO_ROADMAP_20260622.md` / 기능 백로그: `CAPCUT_FEATURE_BACKLOG.md` / 이전 갭 분석: `GAP_ANALYSIS_V6.md`(자가보고 수치 신뢰 금지)
> 판정 근거: 2026-07-03 코드 grep·문서·git log 실사. "코드 존재"가 아니라 **"preview에 보이고 export에 반영 + 증거"** 를 완료 기준으로 유지한다.
> 2026-07-04 loop-9 재평가 기준 커밋: `84b696c feat(moviecut): preserve subtitle word timings`.

---

## 0. 한 줄 요약

Phase 2A(색 그레이딩·ProRes/HDR)와 2026-07-04 실측 스프린트(EQ/NR/덕킹/플랫폼 프리셋/모션 트래킹)로 **검증 지반은 크게 개선됐다.** 또한 S1 G-02는 커브/HSL 순수 수학(Inc 1~2)까지, S2 G-01은 워드 타이밍 보존(Inc 1)까지 착수했다. 그러나 CapCut 대비 완성도는 아직 “능가”가 아니라 **중간 증분 상태**다: ① **숏폼 필수 기능의 깊이**는 워드 timing 저장은 됐지만 스타일 프리셋/active-word 렌더/UI/export가 남았고, ② **Pro 색**은 커브/HSL 수학만 있고 렌더 체이닝/저장/UI/iOS가 남았으며, ③ **체감 품질**은 필름스트립/iOS 파리티/잔여 실기기 검증 부채가 여전히 격차다. 다음 보강은 G-02 Inc 3~5와 G-01 Inc 2~4를 완료 증거(preview/export/iOS)까지 닫는 순서가 최우선이다.

---

## 1. 현재 위치 — 3분류 요약

### 1-A. 이미 CapCut을 능가하는 영역 (증거 있음 — 지키고 홍보할 것)

| 영역 | MovieCut | CapCut | 증거 |
|---|---|---|---|
| Pro 출력 | ProRes 422 master, HEVC Main10 + Rec.2020 + HLG **10-bit HDR** | h.264/HEVC 소비자 출력, HDR export 없음 | `run_e2e_export.sh` E2E(pix_fmt/color_transfer 실측) |
| 색 그레이딩 컨트롤 | 3-way lift/gamma/gain + **컬러 휠** + **스코프 3종**(히스토그램/웨이브폼/벡터스코프) | 밝기/대비/HSL 수준, 스코프 없음 | `ColorGradeGoldenTests`, E2E scope 샘플 |
| 온디바이스 AI 컬러 | Auto WB/Levels/Enhance (gray-world/히스토그램, 클라우드 0) | 클라우드 AI (로그인·업로드 필요) | E2E gain 수치 codify |
| 프라이버시/오프라인 | 완전 오프라인, 로그인 불필요, 워터마크 없음 | 강제 로그인·클라우드 의존·페이월 | 구조적 |
| 안정성 | 자동저장+크래시 복구, 스냅샷 기반 undo 무결성 검증 | 크래시 복구는 있으나 undo 무결성 비공개 | `UndoIntegrityTests`, `AutosaveRecoveryTests`, E2E |
| 슬로모 품질 | 옵티컬 플로우 보간 (`d23a924`) | 프레임 블렌딩(데스크톱 일부 유료) | 커밋 — ⚠️ 실영상 검증 잔여 |
| 모션 트래킹 | Vision `VNTrackObjectRequest` 온디바이스 + 합성 실영상 IoU 검증 | 클라우드/모바일 한정 | `07ab764`, meanIoU 0.7929 / minIoU 0.7095 |

### 1-B. 파리티 도달했으나 검증 부채가 남은 영역 (🟡 — 완료 선언 금지)

- 덕킹(청감), 자동컷(실인터뷰 청취), 배경제거(실인물 E2E), 비트감지(실음원), 자동 리프레임(실영상 추적 정확도), TTS·자막 워크플로우(실기기 GUI), 캔버스 배경(export visual fixture), 클라우드 충돌(실 iCloud 2기기), F-01 비파일 드래그(Photos 앱), **최근 5커밋 전부**(EQ DSP 청감, 옵티컬플로우/모션트래킹 실영상, 텍스트 애니메이션/템플릿 GUI, 플랫폼 프리셋 인코딩 확인).
- iOS는 렌더 파리티(shared processor)는 있으나 **조절 UI 상당수 미배선 + 이 머신에서 빌드 자체 미검증**.

### 1-C. CapCut이 여전히 앞서는 영역 (실질 격차 — 이 문서의 본론)

| # | 격차 | CapCut | MovieCut 현재 | 심각도 |
|---|---|---|---|---|
| 1 | **워드 단위 스타일 자막** | 워드별 하이라이트(karaoke), 자막 템플릿 수십 종, 자동 강조 | **Inc 1 완료**: Apple Speech word timestamp 보존 + `TextClipContent.wordTimings` 상대 저장. 아직 스타일 프리셋/active word 렌더/UI/export/iOS 미완 | **최상** — 숏폼 제작 필수, 다음은 Inc 2~4 |
| 2 | **색 2차 보정 (HSL/커브)** | HSL 6채널 + RGB 커브 (데스크톱) | **Inc 1~2 완료**: `CurveEvaluator` + `HSLCubeBuilder` 순수 수학. 아직 `ColorGradePixelProcessor` 렌더 체이닝/ColorCurves 저장/Mac+iOS UI 미완 | **최상** — Pro 정체성, 다음은 Inc 3~5 |
| 3 | **이펙트 볼륨** | 수백 종 트렌드 이펙트(글리치/블링/레트로/파티클), 매주 갱신 | 프로시저럴 ~10종 + .cube LUT import | 상 |
| 4 | **에셋 라이브러리** | 상용 음악/SFX/스티커/폰트 클라우드 카탈로그 | `MusicLibrary.placeholder()`, SFXLibrary 골격, 이모지/뱃지 스티커 | 상 |
| 5 | **조정 레이어** | 조정 레이어(구간 일괄 효과) 지원 | 없음 (grep 0건) — 클립별 개별 적용만 | 상 |
| 6 | **키프레임 이징** | 프리셋 이징(ease in/out 등) | 선형 보간만. 커브 에디터 없음 (Phase 4 예정) | 중 |
| 7 | **타임라인 필름스트립** | 클립 위 연속 프레임 스트립 + 호버 스크럽 | 단일 썸네일 배경 (`TimelineView.swift:909`) | 중 — 체감 완성도 격차 큼 |
| 8 | **오디오 고급 도구** | 보컬 분리, 보이스 체인저, 음성 강화 | `VocalSeparationService`가 **dead code**(앱 호출 0회 — 과거 EQ와 동일 함정), 보이스 FX 없음 | 중 |
| 9 | **뷰티/리터치** | 얼굴 보정·바디 이펙트 (모바일 강점) | 없음 | 중하 — Pro 포지셔닝상 범위 판단 필요 |
| 10 | **템플릿 생태계** | 커뮤니티 템플릿 수백만, 원탭 제작 | `.mctemplate` 로컬 패키지 + 내장 템플릿 | 중하 — 마켓플레이스는 비목표 유지, 로컬 축만 |
| 11 | **화면 녹화/웹캠/텔레프롬프터** | 데스크톱 내장 | 없음 (보이스오버 녹음만) | 하 |
| 12 | **모바일 UX** | 모바일이 홈그라운드 | iOS 미완(읽기전용 인스펙터·빌드 미검증) | 상 (플랫폼 전략상) |

---

## 2. 개선 방향성 — 4개 축

전략(`MOVIECUT_PRO_ROADMAP_20260622.md`)은 유지한다: **CapCut의 UX/속도는 계승, 화질·출력·제어는 Pro급, 클라우드 약점은 온디바이스로 공략.** 이번 계획은 그 위에 다음 4개 축으로 정렬한다.

1. **축 A — Pro 정체성 완성**: HSL/커브, 조정 레이어, 키프레임 이징, FCPXML 상호운용. "Pro라면서 CapCut보다 색 도구가 얕다"는 모순을 제거하고, CapCut이 구조적으로 못 따라오는 항목(FCPXML, 스코프 연동 2차 보정)으로 격차를 벌린다.
2. **축 B — 숏폼 필수 기능의 깊이**: 워드 단위 스타일 자막이 단일 최대 격차. Apple Speech의 워드 타임스탬프(온디바이스)로 CapCut의 클라우드 자막보다 빠르고 프라이버시 우위인 구현이 가능하다.
3. **축 C — 체감 완성도**: 필름스트립·호버 스크럽·프리뷰 품질 선택 등 "열어본 순간의 인상"을 결정하는 항목. 기능 수가 아니라 밀도·반응성 지표(UI 트랙)로 관리.
4. **축 D — 부채 상환 규율**: 신규 기능 N개당 검증 부채 M개 상환(권장 1:1)을 세션 규칙으로. 특히 **dead code 재발 방지**(VocalSeparationService가 이미 두 번째 사례) — "Core 서비스 추가 시 앱 호출부 + E2E 훅까지가 한 단위"를 DoD에 명문화.

**비목표(변경 없음)**: 클라우드 마켓플레이스, 직접 SNS 게시 API, AI 아바타/script-to-video, FCP/Resolve 전면 추격.

---

## 3. 상세 개선안 (G-ID 단위)

> 각 항목: 배경 → 구현 방안 → 대상 파일 → 수용 기준(AC) → 검증. 기존 규율 적용: shared pixel processor 패턴, command 기반 편집, Mac/iOS 동시 갱신, 증거 기반 DoD.

### G-01. 워드 단위 스타일 자막 (Styled Captions) — P0, 축 B ⭐

**배경**: CapCut 사용자 체감 1순위 기능. 현재 MovieCut STT는 문장(segment) 단위로만 클립을 만들고, `SFTranscriptionSegment`가 무료로 제공하는 **워드별 타임스탬프를 버리고 있다.**

**구현 방안** (증분 4개):
1. **워드 타이밍 모델 — 완료(2026-07-04, `84b696c`)**: `WordTiming`, `TranscriptionSegment.words`, `TextClipContent.wordTimings`. Apple Speech `SFTranscriptionSegment` timestamp/duration/confidence 보존. `SubtitleGenerator`는 세그먼트 절대 시각을 클립 상대 시각으로 변환/clamp.
2. **캡션 스타일 프리셋 모델**: `CaptionStyle` (기본 스타일 + `activeWordStyle`: 색/배경필/스케일/볼드) + 내장 프리셋 6~10종 (karaoke fill, background pill, bounce, underline sweep 등 — CapCut 인기 스타일 참조하되 자체 네이밍).
3. **렌더러**: `TextOverlayPixelProcessor` 확장 — 프레임 시각 기준 active word 판정 → 워드별 attributed run 스타일 적용. 기존 CoreText 경로 재사용, 픽셀 골든으로 "같은 프레임에서 active/inactive 워드 색 다름" 검증.
4. **UI/preview-export/iOS**: `AutoSubtitlesView`에 스타일 피커(썸네일 프리뷰) + Inspector에서 세부 조절. Mac/iOS custom compositor와 preview 경로가 동일 metadata를 소비해야 완료.

**대상 파일**: `Sources/MovieCutCore/Transcription/`, `Sources/MovieCutCore/Rendering/TextOverlayPixelProcessor.swift`, `App/MovieCutMac/Transcription/`, `App/MovieCutiOS/Export/IOSCustomVideoCompositor.swift`

**AC**: ① STT 결과에 워드 타임스탬프 존재(실오디오 fixture) ② karaoke 스타일에서 t 시점 active 워드만 하이라이트(골든 픽셀) ③ preview+export 동일 결과(E2E export 프레임 샘플) ④ SRT export 시 문장 호환 유지.

**검증**: 골든 픽셀 + `run_e2e_export.sh` 신규 체크 + 실영상 GUI 녹화.

---

### G-02. HSL 2차 보정 + RGB 커브 — P0, 축 A ⭐

**배경**: 로드맵 Phase 2A 명세에 "커브, HSL"이 있었으나 **미구현**(grep 0건). 스코프 3종을 이미 보유했으므로 커브/HSL이 붙는 순간 "스코프 보면서 2차 보정"이라는 CapCut 불가능 워크플로우가 완성된다.

**구현 방안**:
1. **HSL 퀄리파이어 수학 — 완료(2026-07-04, `d7c8399`)**: `HSLBandCenter`/`HSLBand`/`HSLCubeBuilder`, 8밴드 hue center, 45° cosine falloff, hue wrap-around, RGB↔HSL 변환, RGBA cube data(`size^3*4`). 남은 일은 `ColorGrade` 저장 필드와 `ColorGradePixelProcessor` 체이닝.
2. **RGB/루마 커브 수학 — 완료(2026-07-04, `07b666b`)**: `CurvePoint`/`CurveEvaluator`, 256-entry LUT, endpoint 고정, duplicate-x deterministic, monotone cubic Hermite/Fritsch-Carlson tangents, clamp/no-overflow. 남은 일은 `ColorCurves` 모델 저장과 CI 렌더 적용.
3. **렌더 체이닝**: HSL cube + curve LUT를 기존 lift/gamma/gain/CDL 뒤에 연결하고, preview/export/iOS compositor가 같은 processor를 쓰게 한다.
4. **UI**: 그레이딩 패널에 Curves 탭(드래그 가능한 커브 에디터 — 포인트 추가/삭제/드래그) + HSL 탭(밴드 선택 + 3슬라이더). 스코프와 같은 화면에 배치.
5. **Auto 연계**: `AutoColorAnalyzer`에 히스토그램 기반 auto-curve(S자 대비) 후보 추가(선택).

**대상 파일**: `Sources/MovieCutCore/Models/ColorGrade.swift`, `Sources/MovieCutCore/Rendering/ColorGradePixelProcessor.swift`, `App/MovieCutMac/Inspector/`(그레이딩 패널), iOS compositor.

**AC**: ① red 밴드 sat -100 → 빨간 픽셀만 무채색(골든) ② 커브 raise midtone → 중간톤 luma 상승·하이라이트/섀도 클램프 유지(골든) ③ undo/redo 왕복 무결성 ④ preview=export 동일(E2E 평균색).

**검증**: `ColorGradeGoldenTests` 확장 + E2E codify. Codable 하위호환(구 프로젝트 decode) 테스트 필수.

---

### G-03. 조정 레이어 (Adjustment Layer) — P1, 축 A

**배경**: CapCut도 보유한 기능인데 MovieCut에 없음. 구간 전체에 그레이드/이펙트를 한 번에 걸 수 없어 클립마다 반복 적용해야 한다. Pro 워크플로우 필수.

**구현 방안**: 새 클립 타입 대신 **`Clip.role = .adjustment`** (미디어 없는 클립, 지속시간만 보유). Compositor에서 해당 시각에 활성인 adjustment 클립의 `colorGrade`/`colorCorrection`/`effects`를 **하위 트랙 합성 결과에 후처리**로 적용(zIndex 상위부터). 타임라인에서 반투명 보라색 등 전용 렌더. "Add Adjustment Layer" 메뉴 + 컨텍스트.

**대상 파일**: `Sources/MovieCutCore/Models/Clip.swift`, Mac/iOS `CustomVideoCompositor`, `ExportEngine`/`PlaybackEngine`(합성 순서), `TimelineView`.

**AC**: ① adjustment 클립 구간의 모든 하위 비디오에 grade 적용(golden: 2클립 위 adjustment → 두 클립 모두 색 이동) ② 구간 밖 미적용 ③ trim/move/undo 정상 ④ preview=export.

**주의**: 현 compositor는 클립별 독립 처리 구조라 "하위 합성 결과에 후처리"가 구조 변경점. two-source transition 배선(overlap 시 별도 트랙 소스)과 같은 패턴으로 adjustment 활성 구간에 합성 순서를 재정의할 것.

---

### G-04. 타임라인 필름스트립 + 호버 스크럽 — P1, 축 C

**배경**: CapCut 타임라인은 클립 위에 연속 프레임이 보여 "어디를 자를지"가 즉시 보인다. MovieCut은 단일 썸네일 반복이라 체감 격차가 크다 (`TimelineView.swift:909`).

**구현 방안**:
1. `ThumbnailGenerator`를 **스트립 모드**로 확장: 클립당 N프레임(줌 레벨 따라 0.5~2s 간격) `AVAssetImageGenerator` 배치 생성, 클립ID+줌 버킷 키 캐시(메모리 상한 + LRU).
2. `TimelineView` 클립 배경을 가로 타일 필름스트립으로. 생성 전엔 기존 단일 썸네일 폴백. 스크롤/줌 변경 시 비동기 갱신(취소 가능 Task).
3. **호버 스크럽**: 클립 위 마우스 X → 해당 시각 프레임을 소형 팝오버 프리뷰(프레임은 같은 캐시 재사용).
4. 성능 가드: 생성은 background QoS, 프레임당 최대 크기 160px, `os_signpost`로 스크롤 fps 회귀 측정(0.3 베이스라인 연계).

**AC**: ① 3분 4K 클립에서 스크롤 60fps 유지(측정) ② 줌 인/아웃 시 스트립 밀도 갱신 ③ 메모리 피크 +100MB 이내.

---

### G-05. 오디오 스위트 완성 — 보컬 분리 배선 + 보이스 FX — P1, 축 B/D

**배경**: `VocalSeparationService`가 **앱 호출 0회 dead code** — EQ 사례(❌ dead+볼륨근사)와 동일한 함정 재발. CapCut의 보컬 분리/보이스 이펙트 대비 격차.

**구현 방안**:
1. **보컬 분리 배선**: 서비스 실체 확인(알고리즘이 진짜인지 먼저 감사 — DSP 근사면 정직하게 ❌ 판정 후 재구현 결정). 배선은 NR과 동일한 destructive-apply 패턴(분리 파일 생성 → 클립 소스 교체 or 별도 클립 2개 생성: vocal/instrumental). `MOVIECUT_UITEST_*` 훅 + `run_e2e_export.sh` 체크 추가.
2. **보이스 FX**: `AVAudioUnitTimePitch`(pitch shift)/`AVAudioUnitReverb`/`AVAudioUnitDistortion` 기반 프리셋(Deep/Chipmunk/Echo/Radio 등 6종). NR과 같은 offline render 패턴 재사용. 프리셋 모델 + Inspector 피커.
3. **잔여 청감 검증 일괄**: EQ(bassBoost vs trebleBoost 실청감 구분), NR 실잡음, 덕킹 — 실오디오 fixture 1세트로 한 세션에 몰아서 처리.

**AC**: ① 보컬 분리 E2E — 보컬 트랙 RMS가 원본 대비 유의미하게 상이(스펙트럼 측정) ② 보이스 FX preview=export ③ dead code 0건(Core Audio 서비스 전수 호출부 감사 스크립트).

---

### G-06. 키프레임 이징 + 커브 에디터 — P1, 축 A

**배경(2026-07-03 실사로 정정)**: `InterpolationMode` 5종(linear/easeIn/easeOut/easeInOut/hold)이 **모델에 이미 존재하고 Mac/iOS compositor가 이미 적용 중**(`CustomVideoCompositor.swift:209`, iOS `:195`). 그러나 **UI에서 설정하는 코드가 0건** — 사용자는 사실상 linear만 쓸 수 있다. 즉 절반은 "있는 엔진에 피커 붙이기"다.

**구현 방안**:
1. UI 1단: 키프레임 리스트/에디터에 이징 프리셋 피커(기존 `updateSelectedKeyframes` undo 경로).
2. `.custom` case + `Keyframe.customCurve: CubicBezierControl?`(A5) — 큐빅 베지어 평가는 Core 순수 로직.
3. UI 2단: 두 키프레임 사이 베지어 핸들 드래그 미니 커브 뷰 + 프리셋(Snappy/Smooth/Anticipate/Overshoot).

**AC**: ① easeInOut export가 linear 대비 t=0.25 위치 상이(골든) ② custom overshoot가 목표값 초과 후 복귀(유닛+골든) ③ 구 프로젝트 decode 시 기존 렌더 비트 동일.

---

### G-07. 이펙트 팩 확장 + 플러그인 SDK 공개 준비 — P2, 축 A/B

**배경**: 이펙트 수백 종을 클라우드로 따라가는 건 비목표. 대신 **고품질 큐레이션 팩 + 확장 가능 구조**로 대응.

**구현 방안**:
1. **1차 팩 20종**: 숏폼 수요 상위(VHS/glitch 변형, chromatic aberration, film grain, halation, zoom blur, RGB split, duotone, pixelate, vignette+, light leak 등) — 전부 `VisualEffectPixelProcessor`에 CIKernel/체인 프로시저럴로. 각각 파라미터 1~3개 노출.
2. **이펙트 브라우저 UI**: 현 preset 리스트를 썸네일 그리드 + 카테고리 + 검색 + 호버 라이브 프리뷰로 (스티커 브라우저 패턴 재사용).
3. **플러그인 SDK 1단계**: 기존 `PluginRegistry` 위에 이펙트 플러그인 프로토콜(파라미터 스키마 + CIImage in/out) 문서화. 외부 배포는 별도 합의, 이번 범위는 "내장 이펙트 20종을 전부 플러그인 형태로 등록"까지 (dogfooding).

**AC**: 각 이펙트 골든 1개(파라미터 기본값) + extent 보존 + preview=export 라우팅 static contract.

---

### G-08. 로컬 에셋 라이브러리 (음악/SFX/스티커/폰트) — P2, 축 B

**배경**: `MusicLibrary.placeholder()` 수준. 클라우드 카탈로그는 비목표지만, **번들 스타터 팩 + 사용자 폴더 연동**으로 "빈 라이브러리" 문제는 해소해야 한다.

**구현 방안**:
1. **스타터 팩**: CC0/자체 제작 음악 10~20곡 + SFX 30~50개 번들(라이선스 명시 파일 필수). `MusicLibrary`/`SFXLibrary`를 placeholder → 실카탈로그로.
2. **사용자 라이브러리 폴더**: 지정 폴더(예: `~/Music/MovieCut`) 워치 → 자동 카탈로그 등록(메타데이터 probe 재사용). 브라우저에 미리듣기(재생 버튼) + 파형 미니뷰 + 드래그 투 타임라인.
3. **스티커 팩 포맷**: `.mcstickers`(zip: manifest + PNG/GIF) 로컬 import — `.mctemplate` 패턴 재사용. 폰트는 시스템 폰트 패널 연동 확인 + 최근 사용 폰트.

**AC**: ① 스타터 팩 곡이 미리듣기→드래그→타임라인→export까지 완주(E2E) ② 사용자 폴더에 파일 추가 시 카탈로그 자동 반영 ③ 라이선스 고지 화면.

---

### G-09. iOS 파리티 스프린트 — P1, 축 C ⭐

**배경**: "Mac+iOS 동시 파리티"가 전략인데 iOS는 조절 UI 다수 미배선(색보정 파리티 static contract만, 그레이드 인스펙터 읽기전용 이력), **빌드 자체가 이 머신에서 미검증**. CapCut의 홈그라운드가 모바일이라 이 격차는 전략적으로 위험.

**구현 방안**:
1. **빌드 복구 최우선**: iOS 플랫폼/시뮬레이터 설치 확인 → `xcodebuild MovieCutiOS build`를 CI/로컬에서 상시 통과 상태로. (이게 안 되면 iOS 커밋 전부 미검증 상태로 누적된다.)
2. `PLATFORM_PARITY_MATRIX.md` 재감사 → 미배선 UI 목록화(그레이드 휠/스코프, 이펙트 파라미터, 캡션 스타일, 마커, export 프리셋 등).
3. 우선순위: 그레이딩 조절 UI(읽기전용 해소) → 자막 워크플로우 → export 옵션 → 나머지. 터치 UX는 Mac 이식이 아니라 시트/제스처 중심 재설계(기존 `IOSInspectorSheet` 패턴).
4. 신규 기능(G-01/02/03/06)은 **iOS 배선을 AC에 포함**해 격차 재발 방지.

**AC**: ① iOS 빌드 CI 통과 ② 파리티 매트릭스에서 "Mac만" 항목 0건(또는 명시적 defer 사유) ③ iOS 시뮬레이터에서 W1 숏폼 워크플로우 완주 녹화.

---

### G-10. FCPXML/상호운용 export — P2, 축 A (능가 항목)

**배경**: CapCut에 없는 Pro 차별화. "MovieCut에서 컷 편집 → Final Cut/Resolve로 피니싱" 워크플로우가 열리면 프로슈머 신뢰가 급상승한다.

**구현 방안**: `FCPXMLExporter`(Core) — 타임라인 클립 배치/trim/속도/볼륨/기본 transform을 FCPXML 1.10+로 직렬화. 미표현 기능(자체 이펙트 등)은 명시적 skip 목록 + 경고 리포트. File 메뉴 "Export FCPXML…". (import는 후속 별도.)

**AC**: ① 3클립+오디오+타이틀 프로젝트 FCPXML이 Final Cut Pro에서 오류 없이 열림(실기기 검증) ② 클립 경계 프레임 정확(±0) ③ skip 리포트 표시.

---

### G-11. 프리뷰/성능 폴리시 — P2, 축 C

**배경**: 0.3 베이스라인상 병목은 아니나, CapCut 대비 "체감 반응성" 항목이 남아 있다.

**구현 방안**:
1. **프리뷰 품질 셀렉터**: Full/Half/Quarter 해상도 토글(무거운 합성·4K 대비). 재검토 트리거(프레임 16.6ms 초과) 계측과 연동.
2. **프록시 자동 전환**: proxy 있는 asset은 preview에서 proxy 사용 + "Proxy" 뱃지, export는 원본. (현재 proxy는 생성만 되고 preview 소비 경로 확인 필요 — 감사 후 배선.)
3. **백그라운드 export 큐**: export 중 편집 계속 + 다중 export 큐(플랫폼 프리셋별 일괄 export — TikTok+Shorts+Reels 3종 동시 큐가 CapCut 없는 킬러 유스케이스).

**AC**: ① half 품질에서 무거운 합성 프로젝트 preview fps 측정 개선 ② proxy 사용 시 원본 미접근(파일 핸들 검증) ③ 2개 export 동시 큐 완주 E2E.

---

### G-12. 검증 부채 일괄 상환 세션 — P0(상시), 축 D

**배경**: 1-B 목록 + 최근 5커밋이 전부 미검증. 부채가 쌓이면 "97% 자가보고" 사태 재발.

**작업 목록** (한 세션 1묶음):
1. **오디오 묶음**: EQ 청감(bass vs treble 실구분), NR 실잡음, 덕킹, 보컬분리(G-05와 병합) — 실오디오 fixture 세트 제작 포함.
2. **AI/분석 묶음**: 모션트래킹·옵티컬플로우·자동리프레임·배경제거 — 실인물/실모션 fixture 영상 1개로 4종 일괄 E2E.
3. **텍스트 묶음**: 텍스트 애니메이션 13종·타이틀 템플릿 14종 GUI 확인 + export 프레임 샘플.
4. **플랫폼 묶음**: 플랫폼 프리셋 5종 실인코딩 ffprobe 검증(해상도/fps/코덱) — `run_e2e_export.sh` 확장.
5. **iOS 빌드**(G-09와 병합), **iCloud 2기기**, **F-01 Photos 드래그**.

**규율 제안**: 이후 모든 세션은 "신규 기능 1 + 부채 상환 1" 페어링. Core 서비스 신설 시 **앱 호출부+E2E 훅 없으면 커밋 금지**(dead code 3호 방지).

---

### G-13. 뷰티/리터치 — P3, 축 B (범위 판단 필요 ⚠️)

**배경**: CapCut 모바일 강점이나 Pro 포지셔닝과 긴장 관계. 전면 추격(바디 이펙트 등)은 비추천.

**권장 범위(최소)**: Vision 얼굴 랜드마크 + 은은한 skin smoothing(주파수 분리 근사: 피부 영역 마스크 + noise reduction 블렌드) 단일 슬라이더. "Natural Retouch" 1개로 한정 — 과장 필터는 만들지 않는 것이 브랜드에 맞다. **착수 전 사용자 합의 필요.**

---

### G-14. Mac 녹화 스위트 (화면/웹캠/텔레프롬프터) — P3, 축 C

**배경**: CapCut 데스크톱 보유. Mac은 `ScreenCaptureKit`으로 더 잘 만들 수 있는 영역(튜토리얼/리액션 제작자 유입 포인트).

**구현 방안(요약)**: ScreenCaptureKit 화면+시스템 오디오 캡처 → 라이브러리 자동 import / AVCaptureSession 웹캠 PiP 클립 / 텍스트 클립 원고 스크롤 텔레프롬프터 오버레이. 보이스오버 녹음 UI 패턴 재사용. 별도 합의 후 착수.

---

## 4. CapCut 능가 스코어카드 (목표 상태)

| 카테고리 | 현재 | G-플랜 완료 후 |
|---|---|---|
| 색/그레이딩 | ProRes/HDR·휠·스코프는 우위, HSL/커브는 수학 Inc 1~2만 완료 | **전면 능가** (G-02 Inc 3~5: 저장+렌더+UI+iOS, 스코프+커브+HSL 통합 워크플로우) |
| 자막 | STT+word timing 보존은 착수, 스타일/active-word 렌더는 열위 | **동급+프라이버시 우위** (G-01 Inc 2~4: 스타일 모델+렌더+preview/export+iOS) |
| 오디오 | EQ/NR 보유, 분리·FX 열위 | 동급 (G-05) |
| 편집 UX | 코어 파리티, 체감 열위 | 동급 (G-03/04/06/11) |
| 이펙트/에셋 | 열위 | 열위 축소+확장 구조 (G-07/08) — 볼륨 추격은 비목표 |
| Pro 워크플로우 | ProRes/HDR 우위 | **압도** (G-10 FCPXML, G-11 export 큐) |
| 모바일 | 열위 | 파리티 (G-09) |
| 신뢰성 | 우위 | 우위 유지 (G-12 규율) |

---

## 5. 권장 착수 순서

> 병렬 가능하지만 단일 세션 흐름 기준 순서. 각 항목은 백로그 관례대로 완료 시 `CAPCUT_FEATURE_BACKLOG.md`에 ✅/caveat 갱신.

| 순서 | 항목 | 이유 |
|---|---|---|
| 1 | **G-02 Inc 3~5 HSL/커브 완성** | 이미 수학은 있으나 렌더/저장/UI/iOS가 없어 사용자가 결과를 볼 수 없다. Pro 정체성 최우선 |
| 2 | **G-01 Inc 2~4 워드 스타일 자막 완성** | word timing 저장은 됐지만 CapCut 체감 격차는 active-word 스타일 렌더와 UI에서 결정된다 |
| 3 | **G-05 오디오 스위트** (보컬분리 배선+FX) | dead code 상환 + CapCut 격차 동시 해소 |
| 4 | **G-04 필름스트립** + **G-06 이징** | 체감 완성도 점프 |
| 5 | **G-03 조정 레이어** | compositor 구조 변경 — G-02 렌더 체이닝 완료 후가 안전 |
| 6 | **G-09 iOS 파리티 본대** | 신규 기능 iOS 배선과 병행하되, simulator out-of-date 환경성 경고를 별도 관리 |
| 7 | **G-12 잔여 부채**: 옵티컬플로우 실영상, 배경제거 실인물, 자동리프레임 실영상, 비트감지 실음원, 캔버스 배경 export visual, TTS/자막 GUI, iCloud 2기기, F-01 Photos 드래그 | 신규 기능 완료 선언 전에 증거 부채 축소 |
| 8 | **G-07 이펙트 팩** → **G-08 에셋 팩** → **G-10 FCPXML** → **G-11 프리뷰 폴리시** | P2 묶음 |
| 9 | G-13 뷰티(합의 후) / G-14 녹화(합의 후) | P3 |

---

## 6. 착수 전 확인 명령 (콜드 스타트 체크리스트)

```bash
git status --short && git log --oneline -5   # 84b696c 기준 확인
swift build && swift test --filter 'StaticContract|Golden'
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build
scripts/run_e2e_export.sh                     # 기존 E2E 체크 전부 PASS 확인 후 시작
```

주의사항 (기존 합의):
- `project.yml`에 `info:` 블록 금지 — hand-maintained `Info.plist`를 `INFOPLIST_FILE`로만 참조 (xcodegen 함정).
- static contract는 회귀 잠금 전용 — 완료 증거 아님.
- 모든 편집은 `EditorSession.dispatch(Command)` 경유, 시각 효과는 shared pixel processor + Mac/iOS compositor 위임.
- `swift test` 전체는 헤드리스 완주 곤란 — 필터 스위트 사용.
