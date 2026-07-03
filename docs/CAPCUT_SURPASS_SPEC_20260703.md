# MovieCut → CapCut 능가 개발 명세서 (Surpass Specification)

> 버전: 1.1 / 작성일: 2026-07-03 (v1.1: UI 명세 §5 U-01~U-09 신설, 기준 커밋 `5cd5155`) / 브랜치: `feat/core-backend-expansion`
> 상위 분석: `CAPCUT_GAP_IMPROVEMENT_PLAN_20260703.md`(기능 격차·우선순위), `GAP_ANALYSIS_V7_FUNC_UI_20260703.md`(기능+UI 통합 격차) — 이 문서는 그 G-ID/U-ID들의 **개발 착수 가능한 상세 명세**다.
> 형식·운영 규칙은 `CAPCUT_PARITY_SPEC.md`를 계승한다: 작업은 G-ID 단위로 진행하고, 완료 시 해당 AC에 검증 결과를 1줄 추가한다. AC를 바꿔야 하면 이 문서를 먼저 수정·커밋한다(스펙이 사실의 원천).
> 모든 명세는 2026-07-03 코드 실사 기준으로 실제 타입/파일에 앵커되어 있다.

---

## 1. 목표·범위·완료 기준

### 1.1 목표 워크플로우 (기존 W1~W4에 추가)

| 워크플로우 | 정의 | 관련 G-ID |
|---|---|---|
| W5. Pro 그레이딩 | 임포트 → 스코프 보며 1차(휠) → 2차(HSL/커브) → 조정 레이어로 전체 룩 → ProRes/HDR export | G-02, G-03 |
| W6. 워드 자막 숏폼 | 임포트 → STT → 워드 스타일 자막(karaoke) → 9:16 플랫폼 프리셋 export | G-01 |
| W7. 음악 편집 | BGM 임포트 → 보컬 분리 → 비트 마커 → 컷 동기화 → export | G-05 |
| W8. NLE 연계 | MovieCut 컷 편집 → FCPXML export → Final Cut에서 열기 | G-10 |

### 1.2 완료 기준 (DoD) — 전 기능 공통, `CAPCUT_PARITY_SPEC.md` §1.3 계승 + 강화

1. **Core 로직**: SwiftPM 테스트 (픽셀 처리는 골든/guarded pixel sampling).
2. **배선 검증**: preview(`PlaybackEngine`)와 export(`ExportEngine`) 양쪽 + **iOS compositor 동시**.
3. **실기기 확인**: 빌드된 앱에서 실조작 1회 이상 (가능하면 `run_e2e_export.sh` 훅으로 codify).
4. **결과물 검증**: export 파일에서 효과 확인 (대표 기능은 E2E 해시/픽셀/ffprobe).
5. **[신규] dead-code 금지 규칙**: Core에 서비스/프로세서를 신설하는 커밋은 **앱 호출부 + E2E 훅(또는 골든 테스트)을 같은 커밋에 포함**해야 한다. 위반 사례 2건(EQ `AudioEqualizerService`, 보컬 분리 `VocalSeparationService`)의 재발 방지.

### 1.3 아키텍처 불변 원칙 (A1~A5 계승, `CAPCUT_PARITY_SPEC.md` §2.3)

- A1. 모든 편집 변형은 `EditorSession.dispatch(Command)` 경유.
- A2. 시각 효과는 `Sources/MovieCutCore/Rendering/` shared processor(CIImage→CIImage), Mac/iOS compositor는 위임만.
- A3. preview와 export는 동일 effect metadata를 소비.
- A4. Core는 미디어 프레임워크 의존 최소화, 미디어 I/O는 앱 레이어.
- A5. 모델 필드 추가는 Codable 하위호환(optional 디코딩) + 디코딩 테스트 의무.
- **A6.(신규)** Core 신설 서비스는 앱 호출부+검증 훅 동반 (§1.2-5).

### 1.4 범위 제외 (Non-Goals, 변경 없음)

클라우드 마켓플레이스 상용 백엔드 / SNS 직접 게시 API / AI 아바타·script-to-video / FCP·Resolve 전면 추격 / 픽셀 단위 CapCut 룩앤필 복제.

---

## 2. 마일스톤

> 캘린더 추정 없음(로드맵 관례) — 순서·의존성·완료 판정으로 관리.

| 마일스톤 | 테마 | 포함 | 완료 판정 |
|---|---|---|---|
| **S0. 지반** | 검증 부채 상환 + iOS 빌드 복구 | G-12, G-09(빌드만) | E2E 전 체크 PASS + iOS 빌드 CI 통과 + 부채 목록 ✅/❌ 판정 완료 |
| **S1. Pro 색 완성** | 2차 보정 + 구간 룩 | G-02 → G-03 | W5 완주 + 골든/E2E |
| **S2. 자막 능가** | 워드 스타일 자막 | G-01 | W6 완주 + 골든/E2E |
| **S3. 체감·오디오** | 편집 체감 + 오디오 스위트 | G-04, G-05, G-06, G-09(본대) | W7 완주 + 필름스트립 성능 측정 |
| **S4. 확장·상호운용** | 이펙트/에셋/NLE 연계 | G-07, G-08, G-10, G-11 | W8 완주 |
| **S5. 합의 필요** | 범위 판단 후 착수 | G-13, G-14 | 별도 합의 |
| **SU. UI 트랙 (병행)** | 제품 표면·체감 완성 | U-01~U-09 (§5) | 슬롯 순서: U-08 → U-02(+G-04) → U-01 → U-04/U-03/U-05 → U-06 → U-07/U-09 (`GAP_ANALYSIS_V7_FUNC_UI_20260703.md` §6) |

순서 원칙: S0는 선행 필수(이후 모든 검증의 지반). S1↔S2는 교차 가능. S3의 G-04/G-06은 S1/S2와 병행 가능. **UI 트랙은 전 단계 병행하되 U-08(회귀 인프라)을 선행**하고, U-02는 G-04와, U-07은 G-07/G-08과 같은 세션 묶음을 권장. 각 마일스톤 종료 시 해당 워크플로우 1회 수동 완주 + `CAPCUT_FEATURE_BACKLOG.md` 갱신.

---

## 3. 기능 명세 (G-ID)

---

### G-01. 워드 단위 스타일 자막 (Styled Captions) — P0 / S2 / 규모 L

#### 요구사항
1. STT 실행 시 워드별 타임스탬프가 자막 세그먼트에 저장된다.
2. 사용자는 자막 클립(들)에 캡션 스타일 프리셋을 선택할 수 있고, 재생 시각에 해당하는 워드만 다른 스타일(하이라이트)로 렌더된다.
3. preview와 export(burn-in)가 프레임 단위로 동일하다.
4. SRT export는 문장 단위 호환을 유지한다(워드 정보는 SRT 표준 밖 — 유실 허용, 프로젝트 파일에는 보존).

#### 현재 상태 (실사)
- `TranscriptionSegment`(`Sources/MovieCutCore/Transcription/TranscriptionTypes.swift:4`)는 `text/startTime/endTime/confidence`만 보유 — **워드 타이밍 없음**.
- `SpeechTranscriptionProvider`가 `SFSpeechRecognizer`를 사용 — `SFTranscriptionSegment`는 워드별 `timestamp`/`duration`을 이미 제공하나 버려지고 있음.
- `TextClipContent`는 stroke/shadow/bold 등 데코 필드 완비(F-12R) — 워드 개념 없음.
- 렌더는 `TextOverlayPixelProcessor`(CoreText attributed string) — Mac/iOS compositor 위임 구조(A2) 재사용 가능.

#### 데이터 모델 (A5 준수 — 전부 optional 추가)

```swift
// TranscriptionTypes.swift
public struct WordTiming: Codable, Sendable, Equatable {
    public var text: String
    public var startTime: TimeInterval   // 오디오 소스 기준 절대 시각
    public var endTime: TimeInterval
    public var confidence: Double
}
// TranscriptionSegment에 추가:
public var words: [WordTiming]?          // nil = 구버전/워드 미지원 provider

// 신규 Models/CaptionStyle.swift
public struct CaptionStyle: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var base: TextStyleAttributes          // 색/스트로크/그림자/배경 (TextClipContent 데코 필드 미러)
    public var activeWord: ActiveWordStyle        // 하이라이트 방식
    public struct ActiveWordStyle: Codable, Sendable, Equatable {
        public var mode: HighlightMode            // .color / .backgroundPill / .scale / .underline
        public var color: String?                 // hex
        public var backgroundColor: String?
        public var scale: Double?                 // 1.0 = 변화 없음
        public var transition: TimeInterval       // 워드 전환 크로스페이드 (0 = 하드 스위치)
    }
}

// TextClipContent에 추가:
public var wordTimings: [WordTiming]?    // 클립 sourceRange 기준 상대 시각으로 변환 저장
public var captionStyleID: UUID?         // 내장/사용자 스타일 참조 (스타일 자체는 프로젝트에 복사 저장)
public var captionStyle: CaptionStyle?   // 참조 깨짐 방지용 인라인 사본 (source of truth)
```

#### 구현 증분

| Inc | 내용 | 파일 |
|---|---|---|
| 1 | **워드 추출**: `SpeechTranscriptionProvider`에서 `SFTranscriptionSegment` → `WordTiming` 매핑. `SubtitleGenerator`가 세그먼트→자막 클립 변환 시 워드 시각을 클립 상대로 변환해 `TextClipContent.wordTimings`에 기록 | `SpeechTranscriptionProvider.swift`, `SubtitleGenerator.swift` |
| 2 | **스타일 모델+내장 프리셋 8종**: Karaoke Fill(색 채움), Background Pill(배경 캡슐), Pop Scale(1.15× 확대), Underline Sweep, Bold Switch, Color Pulse, Dim Others(비활성 워드 50% 투명), Classic(하이라이트 없음). `BuiltinCaptionStyles.swift` + Codable round-trip 테스트 | `Sources/MovieCutCore/Models/CaptionStyle.swift`, `Templates/BuiltinCaptionStyles.swift` |
| 3 | **렌더러**: `TextOverlayPixelProcessor.render(content:at:)`에 프레임 시각 파라미터가 이미 있는지 확인(애니메이션 렌더에 사용 중) → active word 판정(`wordTimings` 이진 탐색) → 워드별 attributed run 분리 적용. `transition > 0`이면 인접 워드와 스타일 보간 | `Rendering/TextOverlayPixelProcessor.swift` |
| 4 | **compositor 배선**: Mac/iOS `CustomVideoCompositor`의 텍스트 burn-in 경로에 wordTimings/captionStyle 전달(기존 `CustomCompositionClipEffect` 확장). preview `PlaybackEngine` 텍스트 레이어 경로도 동일 metadata 소비(A3) — CoreAnimation 레이어로는 워드 하이라이트 근사가 어려우면 **텍스트 클립을 custom compositor 라우팅으로 승격**(grade-only 클립 라우팅 전례 있음) | Mac/iOS `CustomVideoCompositor.swift`, `PlaybackEngine.swift`, `ExportEngine.swift` |
| 5 | **UI**: `AutoSubtitlesView`에 스타일 갤러리(프리셋 카드 + 미니 프리뷰 애니메이션). Inspector에 선택 자막 클립의 스타일 편집(하이라이트 색/모드/전환). "Apply style to all subtitle clips" 일괄 적용(단일 undo — batch `SetClipPropertyCommand`) | `App/MovieCutMac/Transcription/AutoSubtitlesView.swift`, `Inspector/InspectorBasicSection.swift` |
| 6 | **iOS**: 갤러리/편집 시트 배선 (`IOSInspectorSheet` 패턴) | `App/MovieCutiOS/` |

#### AC
1. 실음성 fixture(한국어+영어 각 1개, `scripts/make_fixtures.sh` 확장) STT 결과의 모든 세그먼트에 `words`가 채워지고, 워드 시각이 세그먼트 범위 안에 단조 증가.
2. Karaoke Fill 스타일, 3워드 자막 "hello brave world"에서 t=워드2 중앙 프레임 렌더 시 **워드2만 하이라이트 색**(골든 픽셀: 워드1/3 영역과 워드2 영역 색 상이).
3. preview와 export의 동일 프레임 렌더 결과 일치(E2E export 중간 프레임 샘플 vs 골든).
4. SRT export가 기존 `SubtitleDocumentTests` 라운드트립 통과 유지(워드 필드 무시).
5. 구버전 프로젝트 decode 정상(`wordTimings == nil` → 기존 렌더 경로).
6. 60프레임 자막 렌더 성능: 워드 판정+run 분리 오버헤드가 프레임당 1ms 이하(측정 로그).

#### 검증 계획
- `WordTimingTests`(추출·클립 상대 변환·이진 탐색), `CaptionStyleGoldenTests`(AC②·스타일별 1골든), `run_e2e_export.sh`에 `MOVIECUT_UITEST_CAPTION` 훅(자막 스타일 적용 → export → 프레임 픽셀 검사).
- 실기기: STT→스타일→export 완주 GUI 녹화 (W6).

#### 리스크
- `SFSpeechRecognizer` 워드 타임스탬프 정밀도는 locale·on-device 여부에 따라 편차 — confidence 낮은 워드는 세그먼트 내 균등 분배 폴백을 둘 것.
- preview의 CoreAnimation 텍스트 레이어로는 워드 단위 스타일이 불가능할 수 있음 → Inc 4의 custom compositor 승격이 사실상 필수 경로(성능은 0.3 베이스라인상 여유: 5.5ms/frame).

---

### G-02. HSL 2차 보정 + RGB/루마 커브 — P0 / S1 / 규모 L ⭐

#### 요구사항
1. 그레이딩 패널에서 8밴드 HSL(밴드별 hue shift / saturation / luminance)을 조절할 수 있다.
2. master/R/G/B 4개 커브를 컨트롤 포인트 드래그로 편집할 수 있다.
3. 기존 lift/gamma/gain·스코프와 한 패널에서 동작하고, preview/export/iOS 동일 렌더.
4. 구버전 프로젝트 호환(A5).

#### 현재 상태 (실사)
- `ColorGrade`(`Models/ColorGrade.swift:13`): `lift: RGB` / `gamma: Double`(master) / `gain: RGB`, init에서 클램핑, `isIdentity` 게이트. **HSL·커브 없음**(grep 0건).
- 렌더는 `ColorGradePixelProcessor`(CIColorMatrix slope+offset → CIGammaAdjust). 골든 6종 보유.
- 스코프 3종(`ScopeAnalyzer`) + 휠(`ColorGradeWheel`) + `refreshScopes` 파이프라인 완비 — 커브/HSL 추가 시 즉시 연동 가능.

#### 데이터 모델

```swift
// ColorGrade에 추가 (전부 optional/기본 identity — init 시그니처 하위호환 유지):
public var hslBands: [HSLBand]?          // nil 또는 8개; identity 밴드는 저장 생략 가능
public var curves: ColorCurves?

public struct HSLBand: Codable, Sendable, Equatable {
    public var center: HSLBandCenter     // .red .orange .yellow .green .aqua .blue .purple .magenta
    public var hueShift: Double          // -60...60 (deg)
    public var saturation: Double        // -1...1 (0 = identity)
    public var luminance: Double         // -1...1
}

public struct ColorCurves: Codable, Sendable, Equatable {
    public var master: [CurvePoint]      // 정렬된 control points, 기본 [(0,0),(1,1)]
    public var red: [CurvePoint]
    public var green: [CurvePoint]
    public var blue: [CurvePoint]
    public var isIdentity: Bool { ... }  // 전 채널 2포인트 대각선
}
public struct CurvePoint: Codable, Sendable, Equatable { public var x: Double; public var y: Double } // 0...1
```

#### 구현 증분

| Inc | 내용 | 파일 |
|---|---|---|
| 1 | **커브 수학 (순수 로직)**: `CurveEvaluator` — 단조 Catmull-Rom(또는 monotone cubic Hermite; 오버슈트 금지) 보간, `[CurvePoint]` → 256-entry LUT. 유닛 테스트: identity=대각선, midtone raise 단조성, 끝점 클램프, 포인트 정렬 | 신규 `Sources/MovieCutCore/Rendering/CurveEvaluator.swift` |
| 2 | **HSL 수학 (순수 로직)**: `HSLCubeBuilder` — 8밴드 조정 → 64³ RGB cube data. hue 거리 가중치(cosine falloff, 밴드폭 45°)로 인접 밴드 부드럽게 보간. 유닛 테스트: red 밴드 sat -1 → 순빨강 무채색·순파랑 불변, hue shift 방향성, identity 밴드 = passthrough cube | 신규 `Rendering/HSLCubeBuilder.swift` |
| 3 | **렌더 체이닝**: `ColorGradePixelProcessor.apply`를 CDL → HSL(`CIColorCube`, cube 캐시: hslBands 해시 키) → Curves(`CIColorCurves` 또는 채널별 cube 합성) 순서로 확장. `isIdentity` 단락 유지 | `Rendering/ColorGradePixelProcessor.swift` |
| 4 | **명령/undo**: 기존 `updateSelectedColorGrade` 경로 재사용(그레이드는 스냅샷 undo — 추가 명령 불필요). Codable 하위호환 + 디코딩 테스트 | `EditorViewModel.swift`, 모델 테스트 |
| 5 | **커브 에디터 UI**: 그레이딩 패널 "Curves" 탭 — Canvas 기반: 배경에 히스토그램(기존 `HistogramView` 데이터 재사용), 채널 선택(M/R/G/B 세그먼트), 클릭=포인트 추가·드래그=이동·더블클릭=삭제·우클릭=리셋. 드래그 중 실시간 preview(기존 grade 슬라이더와 동일 스로틀) | `App/MovieCutMac/Inspector/`(그레이딩 패널), 신규 `CurveEditorView.swift` |
| 6 | **HSL UI**: "HSL" 탭 — 8밴드 색상 칩(가로) + 선택 밴드 hue/sat/lum 슬라이더 3개 + 밴드별 리셋. (2단계 후보: 벡터스코프 클릭→해당 밴드 자동 선택) | 동일 패널, 신규 `HSLPanelView.swift` |
| 7 | **iOS**: shared processor라 렌더는 자동. 조절 UI는 그레이드 시트에 커브(간이: 프리셋 S-curve 3종 + 포인트 편집) + HSL 슬라이더 | `App/MovieCutiOS/` |

#### AC
1. red 밴드 saturation -1 적용 시 순빨강 픽셀 무채색화, 순파랑 픽셀 ΔE < 1 (골든).
2. master 커브 midtone raise((0.5, 0.65) 포인트) → 중간 luma 픽셀 상승, (0,0)/(1,1) 불변 (골든).
3. R 커브만 조정 시 G/B 채널 불변 (골든).
4. 커브+HSL+CDL 동시 적용 순서 결정성: 동일 입력 → 동일 출력 해시 (E2E).
5. preview=export=iOS (E2E 평균색 + iOS static contract).
6. 구버전 프로젝트 decode → `hslBands == nil`, `curves == nil`, 렌더 결과 기존과 비트 동일 (기존 골든 6종 무회귀).
7. 커브 드래그 중 preview 갱신 지연 100ms 이하 (스로틀 측정 로그).

#### 검증 계획
- `CurveEvaluatorTests` / `HSLCubeBuilderTests` (순수 로직) + `ColorGradeGoldenTests` 확장(AC①~③) + `run_e2e_export.sh` grade 체크 확장(AC④⑤).
- 실기기: W5 완주 녹화(스코프 보며 HSL/커브 조작 → HDR export).

#### 리스크
- `CIColorCube` 64³은 미세 밴딩 가능 → 스코프로 확인, 필요시 `CIColorCubeWithColorSpace`+linear 작업 공간.
- 커브 UI의 드래그 성능: LUT 재계산은 밀리초 수준이나 cube 재생성은 스로틀(예: 30Hz) 필수.

---

### G-03. 조정 레이어 (Adjustment Layer) — P1 / S1 / 규모 L

#### 요구사항
1. "조정 클립"을 임의 트랙에 추가하면, 그 시간 구간 동안 **아래(zIndex 하위) 모든 비디오 합성 결과**에 조정 클립의 colorGrade/colorCorrection/effects가 적용된다.
2. trim/move/duplicate/delete/undo 전부 일반 클립과 동일.
3. preview/export/iOS 동일.

#### 현재 상태 (실사)
- `Clip`에 role 개념 없음, adjustment grep 0건. compositor는 클립별 독립 처리(각 클립 소스 프레임 → 효과 → 합성).
- 참조 가능한 전례: two-source transition(overlap 구간에서 별도 트랙 소스 frame을 가져와 합성) — "다른 소스의 프레임을 참조하는" 인프라가 이미 있음.

#### 데이터 모델

```swift
// Clip에 추가 (A5):
public var role: ClipRole            // .media(기본, decode 폴백) / .adjustment
public enum ClipRole: String, Codable, Sendable { case media, adjustment }
```
- adjustment 클립은 `assetId` 없음(또는 무시), `sourceRange`는 `timelineRange`와 동일 길이의 더미.
- 적용 대상 효과 필드는 기존 것 재사용: `colorGrade`, `colorCorrection`, `effects` (마스크/크로마키 등은 1차 범위 제외 — 명시적 non-goal).

#### 구현 증분

| Inc | 내용 | 파일 |
|---|---|---|
| 1 | 모델+명령: `ClipRole` 추가(decode 폴백 `.media`), `AddAdjustmentLayerCommand`(현 playhead에 기본 5s, 최상위 트랙 또는 신규 트랙). 일반 클립 명령(trim/move/…)은 무수정 동작 확인 | `Models/Clip.swift`, `Commands/` |
| 2 | **compositor 적용**: 프레임 합성 마지막 단계에서 "현재 시각에 활성인 adjustment 클립(zIndex 내림차순)"의 grade/correction/effects를 합성 결과 CIImage에 순차 적용. Mac export → Mac preview → iOS 순. instruction 빌드 시 adjustment 클립 목록을 `CustomCompositionInstruction`에 별도 배열로 전달(소스 프레임 불필요 — 메타데이터만) | Mac/iOS `CustomVideoCompositor.swift`, `ExportEngine.swift`, `PlaybackEngine.swift` |
| 3 | **compositor 활성 조건**: adjustment 클립이 존재하는 구간은 반드시 custom compositor 경로로 라우팅(grade-only 클립 라우팅 전례 재사용) | `ExportEngine.swift:284` 인근, `PlaybackEngine` 대응부 |
| 4 | 타임라인 렌더: adjustment 클립 전용 시각(반투명 보라 + 아이콘, 파형/썸네일 없음) + 컨텍스트 메뉴 "Add Adjustment Layer" + Quick Tools 버튼 | `TimelineView.swift`, `ContentView.swift` |
| 5 | Inspector: adjustment 클립 선택 시 그레이딩/이펙트 섹션만 노출(오디오/텍스트 섹션 숨김) | `InspectorPanel.swift` |

#### AC
1. 서로 다른 색의 2클립 위에 warm grade adjustment → export에서 **두 클립 모두** R↑/B↓ (E2E 평균색, 구간 밖 프레임 불변).
2. adjustment를 trim해 클립1만 커버 → 클립2 불변 (E2E).
3. adjustment 2개 중첩 시 zIndex 순서대로 적용(순서 바꾸면 결과 상이 — 골든).
4. undo/redo 왕복 무결성(`UndoIntegrityTests` 시퀀스에 adjustment 명령 추가).
5. 구버전 프로젝트 decode 정상(role 폴백).
6. preview=export=iOS.

#### 리스크
- **구조 변경점**: 현 compositor의 "클립별 처리 후 합성" 순서에 "합성 후 후처리" 단계가 추가된다. `sourceTrackIDs`/instruction 구성이 adjustment 구간에서 달라지므로, transition overlap과 겹치는 경우(전환 중 + adjustment 활성)의 조합 테스트 필수.
- preview의 AVVideoComposition instruction 재빌드 비용 — adjustment 추가/이동 시 전체 재빌드 허용(기존 grade 변경과 동일 수준).

---

### G-04. 타임라인 필름스트립 + 호버 스크럽 — P1 / S3 / 규모 M

#### 요구사항
1. 비디오 클립 배경에 시간축을 따라 연속 프레임 스트립이 표시된다(줌 레벨 연동).
2. 클립 위 마우스 호버 시 해당 시각 프레임 팝오버 프리뷰(선택: 옵션 토글).
3. 스크롤/줌 60fps 유지, 메모리 상한.

#### 현재 상태 (실사)
- `TimelineView.swift:909` — `viewModel.thumbnailData(for: clip)` 단일 PNG를 클립 배경으로. `ThumbnailGenerator`는 단일 프레임 생성.

#### 구현 증분

| Inc | 내용 | 파일 |
|---|---|---|
| 1 | `FilmstripGenerator`(앱 레이어, A4): `AVAssetImageGenerator`로 클립당 프레임 배열 생성. API: `frames(for: assetURL, sourceRange:, targetCount:, maxHeight: 60) async -> [CGImage]`. `requestedTimeToleranceBefore/After = .init(seconds: 0.2)` (키프레임 근처 스냅 허용 → 고속) | 신규 `App/MovieCutMac/Media/FilmstripGenerator.swift` |
| 2 | 캐시: `FilmstripCache` actor — 키 `(assetID, zoomBucket)`, zoomBucket = pixelsPerSecond를 2배 단위 버킷화(4단계). NSCache 기반, totalCostLimit 128MB, 클립 삭제 시 무효화 | 동일 파일 |
| 3 | `TimelineView` 클립 배경을 HStack 타일 → 폴백 체인: 스트립 준비 전 단일 썸네일 → 그마저 없으면 현행 색상. 생성은 클립 가시 영역 기준 lazy(스크롤 밖 클립 skip), Task 취소 처리 | `TimelineView.swift` |
| 4 | 호버 스크럽: `onContinuousHover`로 X→시각 환산 → 캐시에서 최근접 프레임 팝오버(120×68) + 시각 라벨. 캐시 미스 시 표시 안 함(블로킹 생성 금지) | `TimelineView.swift` |
| 5 | 성능 계측: `os_signpost`로 스트립 생성 시간/스크롤 프레임 시간 기록, `docs/PERF_BASELINE_20260622.md`에 수치 추가 | `scripts/perf_baseline.sh` 확장 |

#### AC
1. 3분 1080p 클립 + 줌 4단계 전환에서 스트립 갱신이 UI를 블로킹하지 않음(메인 스레드 프레임 16.6ms 초과 0건 — signpost 측정).
2. 메모리 피크 증가 +150MB 이내(4K 10분 프로젝트 기준, 측정 로그).
3. 줌 인 → 프레임 밀도 증가, 줌 아웃 → 감소(버킷 전환 확인).
4. 호버 프리뷰 시각과 클립 소스 시각 일치(±0.3s).
5. 스트립 미지원 소스(이미지/오디오)는 현행 렌더 유지.

#### 검증
- `FilmstripGeneratorTests`(fixture 영상으로 프레임 수/시각 정확도), 성능은 perf 스크립트 실측. 실기기 스크롤 체감 GUI 녹화.

---

### G-05. 오디오 스위트 — 보컬 분리 배선 + 보이스 FX + 청감 검증 — P1 / S3 / 규모 M

#### 요구사항
1. 오디오/비디오 클립에서 "Remove Vocals"(karaoke) / "Isolate Vocals" 원클릭 적용.
2. 보이스 FX 프리셋 6종(Deep/Chipmunk/Echo/Radio/Megaphone/Robot)을 클립에 적용.
3. EQ/NR/덕킹의 청감 검증 부채를 실오디오 fixture로 상환.

#### 현재 상태 (실사)
- `VocalSeparationService`(`Sources/MovieCutCore/Audio/VocalSeparationService.swift`): `CenterChannelVocalSeparator`(mid/side DSP, `removeVocals`/`isolateCenter`, amount 0~1, ML seam 프로토콜 `AudioStemSeparator`) — **알고리즘은 실재하나 앱 호출 0회 dead code** (A6 위반 사례 2호).
- 배선 전례: `NoiseReductionService` — offline render → denoise 파일 생성 → 클립 소스 destructive 교체, `MOVIECUT_UITEST_DENOISE` E2E 훅. 이 패턴 그대로 복제 가능.
- EQ는 `c7e9d23`에서 실 5밴드 DSP 배선 커밋됨 — 청감 검증 잔여.

#### 구현 증분

| Inc | 내용 | 파일 |
|---|---|---|
| 1 | **분리 render 경로**: `VocalSeparationRenderer`(앱 레이어) — `AVAudioFile` 읽기 → `StereoFrames` 블록 처리(`CenterChannelVocalSeparator.process`) → CAF 기록. 모노 입력은 에러("stereo required") | 신규 `App/MovieCutMac/Audio/VocalSeparationRenderer.swift` |
| 2 | **ViewModel + UI**: `applyVocalSeparation(mode:amount:)` — NR 패턴(파일 생성→`SetClipPropertyCommand`로 소스 교체, 단일 undo). Inspector Audio 섹션에 "Vocals" 그룹: Remove/Isolate 버튼 + amount 슬라이더 + 되돌리기는 undo 안내. **옵션 B(2차)**: "Split to 2 clips"(vocal+instrumental 클립 2개 생성, 같은 구간 2트랙) | `EditorViewModel.swift`, `InspectorBasicSection.swift` |
| 3 | **E2E 훅**: `MOVIECUT_UITEST_VOCALSEP` — 스테레오 음악 fixture(보컬 대체물: 센터 팬 사인 톤 + 사이드 팬 노이즈) import → removeVocals → **센터 성분 RMS가 원본 대비 -20dB 이상 감소, 사이드 성분 -3dB 이내 유지** 측정 | `UITestHarness.swift`, `scripts/run_e2e_export.sh`, `scripts/make_fixtures.sh`(스테레오 fixture 추가) |
| 4 | **보이스 FX**: `VoiceEffectPreset` 모델(pitch cents / reverb wet / distortion preset / EQ 조합) + `VoiceEffectRenderer`(AVAudioEngine offline: `AVAudioUnitTimePitch`+`AVAudioUnitReverb`+`AVAudioUnitDistortion` 체인, NR offline 패턴) + destructive apply + Inspector 피커 + E2E 훅(`pitch shift → 스펙트럼 피크 이동 측정`) | 신규 `Sources/MovieCutCore/Audio/VoiceEffectPreset.swift`, `App/MovieCutMac/Audio/VoiceEffectRenderer.swift` |
| 5 | **청감 부채 상환**: 실오디오 fixture 3종(음성+배경소음 / 음악 bass·treble 구분용 스윕 / 인터뷰 무음 포함) 제작 → EQ bass vs treble E2E 스펙트럼 구분, NR 전후 SNR 측정, 덕킹 ramp 전후 RMS 측정 — 전부 `run_e2e_export.sh` codify | `scripts/` |

#### AC
1. AC-분리: E2E 측정치(센터 -20dB↓, 사이드 유지) 통과 + 실음악 청감 확인 1회(GUI).
2. AC-FX: Deep 프리셋 적용 후 스펙트럼 기본 주파수 하향 이동(E2E 측정) + preview 재생과 export 결과 동일 소스(destructive라 자동 일치).
3. AC-부채: EQ bassBoost vs trebleBoost export 파일의 저역/고역 에너지 비가 서로 반대(측정) — `AudioEqualizerGapTests`의 "구분 못 함" 잠금 해제·역전.
4. 모든 신규 render 경로가 앱 컨텍스트 E2E 훅 보유(A6).
5. undo로 원본 소스 복원.

#### 리스크
- DSP 분리는 센터 팬 보컬 한정(서비스 주석 자인) — UI에 "works best on center-panned vocals" 안내 문구. ML(Demucs류) 격상은 `AudioStemSeparator` seam 뒤로 별도 합의(모델 동봉 크기 이슈).
- AVAudioEngine offline render는 과거 SIGABRT 이력(테스트 프로세스 한정) — 검증은 반드시 앱 컨텍스트 E2E로(NR 전례).

---

### G-06. 키프레임 이징 UI + 커스텀 베지어 — P1 / S3 / 규모 S~M

#### 요구사항
1. 키프레임별 이징(linear/easeIn/easeOut/easeInOut/hold)을 UI에서 선택할 수 있다.
2. 커스텀 큐빅 베지어 커브를 두 키프레임 사이에 설정할 수 있다(핸들 드래그).

#### 현재 상태 (실사) — ⚠️ 스펙 축소 근거
- `InterpolationMode` 5종이 **모델에 이미 존재**하고(`Models/Keyframe.swift:15`), Mac(`CustomVideoCompositor.swift:209`)·iOS(`:195`) compositor 모두 `startKeyframe.interpolation`으로 **이미 적용 중**.
- **그러나 UI에서 interpolation을 설정하는 코드가 0건** — 사용자는 영원히 `.linear`만 쓴다. 즉 이 기능의 절반은 "이미 있는 엔진에 피커 하나 붙이는 일"이다.

#### 데이터 모델

```swift
// InterpolationMode에 case 추가:
case custom                              // customCurve 필드 참조
// Keyframe에 추가 (A5):
public var customCurve: CubicBezierControl?   // interpolation == .custom일 때만 사용
public struct CubicBezierControl: Codable, Sendable, Equatable {
    public var p1: CGPoint   // (0...1, 임의) — CSS cubic-bezier 관례
    public var p2: CGPoint
}
```

#### 구현 증분

| Inc | 내용 | 파일 |
|---|---|---|
| 1 | **이징 피커 UI**: `KeyframeListView`/`KeyframeEditorView`(Inspector Animation disclosure)에 선택 키프레임의 interpolation 세그먼트 피커. 변경은 기존 `updateSelectedKeyframes` 경로(undo 호환) | `App/MovieCutMac/Inspector/`(keyframe 뷰), `EditorViewModel.swift` |
| 2 | `.custom` + 베지어 평가: `Keyframe.interpolate`에 `.custom` 분기(뉴턴법 or 사전 샘플 LUT로 y(t) 평가 — 순수 로직 유닛 테스트). 구버전 decode 테스트 | `Models/Keyframe.swift` |
| 3 | **베지어 핸들 UI**: 키프레임 에디터에서 구간 선택 시 미니 커브 뷰(핸들 2개 드래그) + 프리셋(Snappy/Smooth/Anticipate/Overshoot — overshoot는 값 클램프 없는 속성만 허용, opacity는 0~1 클램프) | keyframe 뷰 |
| 4 | iOS: 피커만 우선(핸들 에디터는 후속) | `App/MovieCutiOS/` |

#### AC
1. easeInOut 선택 후 export에서 t=0.25 위치가 linear 대비 지연(골든: 두 export의 동일 프레임 위치 차이).
2. custom(0.34,1.56,0.64,1) overshoot가 position에 적용 → 목표값 초과 후 복귀(유닛 + 골든).
3. 피커 변경이 undo 1회로 복원.
4. 구버전 프로젝트 decode 정상, `.custom` 없는 프로젝트는 기존 렌더 비트 동일.

---

### G-07. 이펙트 팩 20종 + 브라우저 + 플러그인화 — P2 / S4 / 규모 M

#### 요구사항
1. 숏폼 수요 상위 이펙트 20종을 추가하고, 각 이펙트는 1~3개 파라미터를 노출한다.
2. 이펙트 브라우저(썸네일 그리드/카테고리/검색/라이브 프리뷰)로 탐색·적용한다.
3. 내장 이펙트 전부를 `PluginRegistry` 경유로 등록해 플러그인 SDK 1단계를 dogfooding한다.

#### 목록 (카테고리별)
- **Retro**: VHS(트래킹 노이즈+색 번짐), Film Grain, Light Leak, Halation, CRT Scanlines
- **Glitch**: RGB Split, Digital Glitch(블록 시프트), Datamosh-lite, Pixelate, Bad Signal
- **Look**: Duotone, Bleach Bypass, Teal&Orange, Cross Process, Day-for-Night
- **Motion/Lens**: Zoom Blur, Radial Blur, Chromatic Aberration, Fisheye, Vignette+(중심 이동 가능)

#### 구현 증분
| Inc | 내용 | 파일 |
|---|---|---|
| 1 | `VisualEffectPixelProcessor`에 20종 구현(CIKernel/기존 CIFilter 체인). `EffectType` case 추가 + `Effect.parameters: [String: Double]` 확인/확장(A5) | `Rendering/VisualEffectPixelProcessor.swift`, `Models/Effect.swift` |
| 2 | 종별 골든 1개(기본 파라미터, 결정적 시드 — glitch류는 프레임 시각 기반 deterministic) | `VisualEffectPixelProcessorTests` |
| 3 | **브라우저 UI**: 시트 — 카테고리 사이드바 + 썸네일 그리드(fixture 프레임에 이펙트 적용한 정적 썸네일, 최초 1회 생성 캐시) + 검색 + 호버 시 선택 클립 프레임으로 라이브 프리뷰 + 더블클릭 적용 | 신규 `App/MovieCutMac/Effects/EffectBrowserView.swift` |
| 4 | **플러그인화**: `EffectPlugin` 프로토콜(id/name/category/parameters 스키마/`apply(CIImage, params) -> CIImage`) 정의 → 내장 20종+기존 프리셋을 전부 플러그인으로 등록, compositor는 registry 조회로 위임. 외부 로딩(번들/디렉토리)은 범위 외 명시 | `Sources/MovieCutCore/Plugins/`, `PluginRegistry` 확장 |

#### AC
1. 20종 각각 골든 통과 + extent 보존 + preview=export 라우팅.
2. 브라우저에서 검색→적용→Inspector 파라미터 조절→export 완주(E2E 1종 대표).
3. registry 미등록 이펙트 id를 만난 compositor는 원본 통과 + 경고 로그(크래시 금지).
4. glitch류 재현성: 동일 프로젝트 2회 export 해시 동일.

---

### G-08. 로컬 에셋 라이브러리 (음악/SFX/스티커) — P2 / S4 / 규모 M

#### 요구사항
1. 라이선스 명시된 스타터 팩(음악 10+ / SFX 30+)이 번들되어 미리듣기→드래그→타임라인이 즉시 된다.
2. 사용자 지정 폴더를 라이브러리 소스로 등록하면 자동 카탈로그化된다.
3. `.mcstickers` 로컬 스티커 팩을 import할 수 있다.

#### 현재 상태 (실사)
- `MusicLibrary.placeholder()`(`Models/MusicLibrary.swift`) + `MusicLibraryView` 존재, `SFXLibrary`(`Audio/SFXLibrary.swift`) 골격, `AssetCatalog`/`AssetCatalogProvider`(`Catalog/`) 추상화 존재 — **채울 그릇은 이미 있음**.

#### 구현 증분
| Inc | 내용 | 파일 |
|---|---|---|
| 1 | 스타터 팩 자산 확보(CC0/자체 제작 — 출처·라이선스는 `Resources/Audio/LICENSES.md`에 파일 단위 기재) + SwiftPM resources 번들 + `MusicLibrary.builtIn()`으로 placeholder 대체 | `Sources/MovieCutCore/Resources/`, `Models/MusicLibrary.swift` |
| 2 | 미리듣기: `MusicLibraryView`에 재생/정지(AVAudioPlayer, 단일 인스턴스) + duration/BPM 표시(BPM은 `BeatDetectionProvider` 재사용 — 최초 1회 계산 캐시) | `App/MovieCutMac/Music/MusicLibraryView.swift` |
| 3 | 사용자 폴더: 설정에 폴더 선택(NSOpenPanel, security-scoped bookmark 저장) → 열거+메타데이터 probe(기존 `mediaAssetWithAppProbe` 재사용) → 카탈로그 섹션 표시. 폴더 감시는 1차 범위 외(수동 Refresh 버튼) | `EditorViewModel.swift`, `MusicLibraryView.swift` |
| 4 | `.mcstickers`: zip(manifest.json + PNG들) — `ProjectPackage`(.mctemplate) 코드 재사용. Import 메뉴 + `StickerLibrary`에 사용자 팩 섹션 | `Templates/`, `StickerPickerView.swift` |

#### AC
1. 클린 설치 상태에서 BGM 브라우저에 실제 곡 10+ 표시, 미리듣기 재생, 드래그→타임라인→export 완주(E2E).
2. 사용자 폴더의 mp3/wav가 Refresh 후 카탈로그에 나타나고 메타데이터(duration) 표시.
3. 라이선스 문서가 앱 About/도움말에서 접근 가능.
4. `.mcstickers` import → 스티커 브라우저 사용자 섹션 → 캔버스 배치 → export 반영.

---

### G-09. iOS 파리티 스프린트 — P1 / S0(빌드)+S3(본대) / 규모 L

#### 요구사항
1. **(S0)** `MovieCutiOS`가 이 머신(또는 CI)에서 빌드 통과 상태로 복구·유지된다.
2. `PLATFORM_PARITY_MATRIX.md` 재감사로 "Mac만 있는 UI" 목록을 확정하고 전부 해소하거나 명시적 defer 처리한다.
3. 신규 G 기능은 iOS 배선을 AC에 포함한다(재발 방지).

#### 구현 증분
| Inc | 내용 |
|---|---|
| 1 | iOS 플랫폼/시뮬레이터 런타임 설치 확인 → `xcodebuild -scheme MovieCutiOS -destination 'generic/platform=iOS Simulator' build` 통과 → `.github/workflows/ci.yml`에 iOS 빌드 job 추가 |
| 2 | 파리티 매트릭스 재감사(기능 × {Core, Mac UI, iOS UI, Mac compositor, iOS compositor} 표 갱신) — 알려진 갭: 그레이딩 조절 UI(읽기전용 이력), 스코프 뷰, 이펙트 파라미터 시트, 마커 관리, export 커스텀 설정, Quick Tools 상당수 |
| 3 | 갭 해소 순서: 그레이딩 시트(휠 간이형+슬라이더) → 자막 워크플로우(STT+스타일) → export 옵션 시트 → 마커 → Quick Tools. 각 항목 `IOSInspectorSheet` 패턴, 터치 타깃 ≥44pt |
| 4 | iOS E2E: 시뮬레이터 headless export 스크립트(`run_e2e_export.sh`의 iOS 버전 — `xcrun simctl` 기반) 1개 확립 |

#### AC
1. CI에서 Mac+iOS 빌드 동시 통과(회귀 시 즉시 검출).
2. 매트릭스의 "Mac만" 셀 0건 또는 각각 defer 사유 1줄.
3. iOS 시뮬레이터에서 W1(숏폼) 완주 녹화.
4. iOS export E2E 1체크 codify.

검증 기록:
- 2026-07-03 G-09 Inc 1: `swift build`, `swift test --filter 'StaticContract|Golden'`(341 tests), Mac `xcodebuild ... MovieCutMac`, iOS generic `xcodebuild ... MovieCutiOS CODE_SIGNING_ALLOWED=NO`, `scripts/run_e2e_export.sh` 모두 PASS. CoreSimulator out-of-date는 simulator device support 경고로 기록.
- 2026-07-04 G-09 Inc 2: `PLATFORM_PARITY_MATRIX.md`를 기능 × Core/Mac UI/iOS UI/Mac preview-export/iOS preview-export로 재감사하고 Mac-only/iOS defer 15건에 사유 1줄씩 기록. `IOSParityMatrixStaticContractTests`로 문서/코드 신호를 잠그고 `swift build`, `swift test --filter 'StaticContract|Golden|iOS|Parity'`, iOS generic `xcodebuild ... MovieCutiOS CODE_SIGNING_ALLOWED=NO`, Mac `xcodebuild ... MovieCutMac` PASS.

---

### G-10. FCPXML export — P2 / S4 / 규모 M

#### 요구사항
1. File > Export FCPXML… 로 현재 프로젝트를 FCPXML 1.10 문서로 저장한다.
2. 표현 범위: 클립 배치/trim, 트랙→lane 매핑, 볼륨, 기본 transform(position/scale/rotation), 텍스트 클립(제목+본문), 마커. 속도는 고정 배속만(ramp는 skip 리포트).
3. 미표현 기능은 export 후 리포트 시트에 항목별 표시(조용한 유실 금지).

#### 구현 증분
| Inc | 내용 | 파일 |
|---|---|---|
| 1 | `FCPXMLExporter`(Core, XML 문자열 빌더 — 외부 의존 없음): `resources`(format/asset) + `sequence/spine`(primary storyline = zIndex 최하 비디오 트랙, 나머지는 connected clip lane). 프레임 정밀 유리수 시간(`64bit/timescale`) 변환 유닛 테스트 | 신규 `Sources/MovieCutCore/Export/FCPXMLExporter.swift` |
| 2 | skip 리포트: 순회 중 미표현 속성(effects/chromaKey/mask/speedRamp/…) 수집 → `FCPXMLExportReport` 반환 | 동일 |
| 3 | 메뉴+저장 패널+리포트 시트 | `MovieCutMacApp.swift`, `ContentView.swift` |

#### AC
1. fixture 프로젝트(비디오 2 + 오디오 1 + 타이틀 1 + 마커 2, trim/이동 포함) export → **실제 Final Cut Pro에서 오류 없이 import**되고 클립 경계 프레임 일치(실기기 검증 — DoD §1.2-3).
2. 유리수 시간 변환 왕복 오차 0 (유닛: 23.976/29.97/60fps).
3. speedRamp 있는 프로젝트 → 리포트에 "Speed ramp → constant rate로 대체" 명시.
4. DTD 검증: 산출 XML이 FCPXML DTD로 `xmllint` 통과(스크립트 codify).

---

### G-11. 프리뷰/Export 폴리시 — P2 / S4 / 규모 M

#### 요구사항
1. preview 해상도 Full/Half/Quarter 셀렉터(무거운 합성·4K 대응).
2. proxy 보유 asset은 preview에서 proxy 소스를 사용(export는 원본) — 현재 proxy는 생성만 되고 소비 경로 미확인이므로 감사 후 배선.
3. export 백그라운드 큐: export 중 편집 지속 + 다중 잡(플랫폼 프리셋 3종 일괄 export).

#### 구현 증분
| Inc | 내용 |
|---|---|
| 1 | preview 품질: `PlaybackEngine`에 `renderScale`(1.0/0.5/0.25) — AVVideoComposition `renderSize` 축소 + custom compositor 소스 다운스케일. 툴바 셀렉터 + "Auto"(프레임 시간 16.6ms 초과 감지 시 자동 강등, 0.3 재검토 트리거 구현을 겸함) |
| 2 | proxy 소비 감사: `ProxyInfo.proxyURL` 사용처 추적 → `PlaybackEngine` composition 빌드에서 proxy 우선 사용(있으면) + Preview 패널 "Proxy" 뱃지 + 토글. export는 항상 원본(테스트로 잠금) |
| 3 | export 큐: `ExportQueue`(직렬 실행, 잡 모델: preset/출력URL/진행률/상태) + 큐 패널 UI(진행/취소/완료 알림) + "Export for All Platforms"(TikTok/Shorts/Reels 3잡 일괄 등록) |

#### AC
1. Half 모드에서 4K+grade+transition 프로젝트 preview 프레임 시간이 Full 대비 50%± 감소(signpost 측정).
2. proxy 사용 중 export 산출물이 원본 해상도(ffprobe) — proxy 파일 핸들이 export 프로세스에서 미열람.
3. 잡 2개 등록 → 순차 완료 → 두 파일 모두 유효(E2E ffprobe), 진행 중 타임라인 편집 가능(메인 스레드 블로킹 0).

---

### G-12. 검증 부채 일괄 상환 — P0 / S0 / 규모 M (상시 규율)

> 신규 기능이 아니라 **기존 🟡의 실측 판정**. 각 항목 산출물: `{증거(E2E 로그/녹화/측정치), 판정 ✅/❌, 백로그 갱신 1줄}`.

| # | 부채 | 검증 방법 | 예상 산출물 |
|---|---|---|---|
| 1 | EQ 청감 (bassBoost vs trebleBoost) | G-05 Inc 5와 병합 — 스윕 fixture 스펙트럼 측정 | E2E 측정치 |
| 2 | NR 실잡음 효과 | 노이즈+음성 fixture 전후 SNR | E2E 측정치 |
| 3 | 덕킹 청감 | BGM+음성 fixture, duck 구간 RMS 차 | E2E 측정치 |
| 4 | 모션 트래킹(`c242632`) 실영상 | 이동 피사체 fixture → 트래킹 박스 좌표가 피사체 따라감(프레임별 IoU) | 유닛+E2E |
| 5 | 옵티컬 플로우(`d23a924`) 실영상 | 0.25× export 프레임 수 = 원본×4 근사 + 보간 프레임이 인접 블렌드가 아님(차분 측정) | E2E |
| 6 | 텍스트 애니메이션 13종(`a13fe17`) | 종별 t=0.5 렌더 골든 또는 대표 3종 E2E 프레임 | 골든 |
| 7 | 타이틀 템플릿 14종(`e0443d7`) | 템플릿 적용→export 프레임에 텍스트 존재(E2E 1종 대표 + GUI 스윕) | E2E+녹화 |
| 8 | 플랫폼 프리셋 5종(`4581f67`) | 각 프리셋 export → ffprobe(해상도/fps/코덱) 일치 | `run_e2e_export.sh` 확장 |
| 9 | 챕터/비트 마커 메타데이터(`377a3d7`) | export 파일 chapter atom을 ffprobe/AVAsset으로 확인 | E2E |
| 10 | 오디오 추출(`438f284`) | 추출 파일 duration/스트림 검사 | E2E |
| 11 | 배경제거 실인물 | 실인물 fixture(직접 촬영 1클립) → E2E alpha 측정 | E2E |
| 12 | 자동 리프레임 실영상 추적 | 이동 피사체 fixture → crop 키프레임이 피사체 중심 추종 | E2E |
| 13 | iCloud 2기기 충돌 | 실기기 2대 수동(별도 세션, 절차 문서화) | 녹화 |
| 14 | F-01 Photos 앱 드래그 | 실기기 수동 1회 | 녹화 |

**신규 fixture 필요분** (`scripts/make_fixtures.sh` 확장): 스테레오 음악형(센터 톤+사이드 노이즈), 스윕 톤, 노이즈+음성, 무음 포함 인터뷰형, 이동 피사체(합성: 움직이는 도형 or 실촬영), 실인물 1클립.

**AC**: 표의 1~12가 E2E/골든으로 codify되어 `run_e2e_export.sh`(또는 테스트 스위트) PASS. 13~14는 녹화 증거. 백로그 전 항목 ✅/❌ 재판정 완료.

검증 기록:
- 2026-07-03 G-12 #1 EQ 청감: `eq_low_high_2s_mono.wav` fixture + `MOVIECUT_UITEST_EQ_PRESET` 앱 하니스 + `scripts/run_e2e_export.sh` Goertzel 측정 PASS. bassBoost/trebleBoost 스펙트럼: bass_ratio=2.315524, treble_ratio=0.488654, bass_low=2.281896e+02, bass_high=9.854772e+01, treble_low=9.240646e+01, treble_high=1.891041e+02.
- 2026-07-04 G-12 #2 NR 실잡음 효과: `noisy_voice_1k_hiss_8k_2s_mono.wav` fixture + `MOVIECUT_UITEST_DENOISE` 앱 하니스 + `scripts/run_e2e_export.sh` Goertzel 측정 PASS. base_ratio=0.248784, denoised_ratio=0.075641, improvement_db=5.17, voice_retention=0.913, base_hiss=4.195051e+01, denoised_hiss=1.164459e+01.
- 2026-07-04 G-12 #3 덕킹 청감: `duck_bgm_220hz_4s_mono.wav` + `duck_voice_1000hz_1s_mono.wav` fixtures, `MOVIECUT_UITEST_DUCKING_*` 앱 하니스, `SetAudioDuckingCommand` export ramp, `scripts/run_e2e_export.sh` Goertzel 측정 PASS. base_voice=3.098866e+01, ducked_voice=1.935795e+00, reduction_db=12.04, quiet_delta_db=0.00, ducked_voice_quiet_ratio=0.062.
- 2026-07-04 G-12 #8 플랫폼 프리셋 5종: `bars_320x240_3s_30fps.mp4` fixture + `MOVIECUT_UITEST_PLATFORM_PRESET` 앱 하니스 + `scripts/run_e2e_export.sh` ffprobe 측정 PASS. TikTok/Reels/Shorts=1080x1920 30/1 h264 mp4, YouTube Standard=1920x1080 30/1 h264 mp4, Instagram Post=1080x1080 30/1 h264 mp4.

---

### G-13. 내추럴 리터치 — P3 / S5 / 규모 M ⚠️ 착수 전 합의 필요

**권장 최소 범위**: Vision 얼굴 관찰(`VNDetectFaceRectanglesRequest`+landmarks) → 피부 영역 소프트 마스크 → 마스크 한정 주파수 분리 근사(고주파 보존 + 중주파 스무딩 블렌드) — "Natural Retouch" 슬라이더 1개(0~1). 과장 보정(눈 확대/윤곽 변형)은 만들지 않는다(브랜드 결정).
**AC(합의 후 확정)**: 피부 영역 노이즈 감소가 골든으로 측정되고 눈/입/모발 선명도 유지(엣지 에너지 측정), 얼굴 미검출 시 무변경.

### G-14. Mac 녹화 스위트 — P3 / S5 / 규모 L ⚠️ 착수 전 합의 필요

**권장 범위**: ① ScreenCaptureKit 화면+시스템 오디오 → 라이브러리 자동 import ② AVCaptureSession 웹캠 PiP 클립 ③ 텔레프롬프터 오버레이(텍스트 클립 원고 스크롤). 보이스오버 녹음 UI/권한 패턴 재사용. 상세 스펙은 합의 후 본 문서에 증분 추가.

---

## 5. UI 명세 (U-ID) — v1.1 신설 (2026-07-03)

> 근거 분석: `GAP_ANALYSIS_V7_FUNC_UI_20260703.md` §3. UI 트랙은 기능 S-마일스톤과 **병행 슬롯**으로 실행한다(V7 §6).
> **UI 공통 DoD** (G-ID DoD에 추가로):
> - `UI_DESIGN_PRINCIPLES.md` 원칙(반응성·밀도·발견성·접근성) 및 디자인 토큰(`MovieCutTheme`) 준수 — 새 색/간격 하드코딩 금지.
> - IA 계약 유지: `IAMenuPositionStaticContractTests` 통과 (Split/Delete/Add Marker의 상단 툴바 재유입 금지, transport 하단 도킹 유지).
> - 레이아웃/카피 변경은 static contract로 잠금(회귀 방지 전용) + **U-08 캡처 증거**(populated 스크린샷)를 완료 증거로.
> - 모든 신규 컨트롤에 접근성 label/hint + 키보드 도달성.
> - 프레젠테이션 레이어 변경 원칙: 명령/세션/렌더 아키텍처(A1~A3)를 건드리지 않는다. 모델 필드가 필요하면 A5 준수.

---

### U-01. 홈/프로젝트 매니저 화면 — P0 / 규모 M

#### 요구사항
1. 앱 실행 시 홈 화면이 뜬다: 최근 프로젝트 카드 그리드(썸네일·이름·수정일·길이) + "New Project" + "Open…" + 템플릿(.mctemplate) 섹션.
2. 카드 더블클릭/Enter로 에디터 진입, 에디터에서 ⌘W 또는 "Back to Home"으로 복귀(저장 확인).
3. 크래시 복구 제안(기존 recovery.moviecut 감지)은 홈에서 배너로 표시.
4. 설정으로 "마지막 프로젝트 바로 열기" 선택 가능(U-05 연계).

#### 현재 상태 (실사)
- 홈/프로젝트 브라우저 **없음** — `WindowGroup`이 곧바로 `ContentView`(에디터). File>Open/New 메뉴만 존재(F-04 부수 수리로 배선됨). 최근 프로젝트 저장소 없음(grep: RecentProjects 0건).
- 재료: `ProjectStore`(load/save/autosave), `ThumbnailGenerator`, `.mctemplate`(`ProjectPackage`), 크래시 복구 NSAlert(런치 시) 기존재.

#### 구현 증분
| Inc | 내용 | 파일 |
|---|---|---|
| 1 | `RecentProjectsStore`(앱 레이어): 항목 `{URL(security-scoped bookmark), name, modifiedAt, duration, thumbnailPath}` — App Support JSON. 프로젝트 open/save 시 upsert, 존재하지 않는 파일은 표시 시 회색 처리+제거 액션 | 신규 `App/MovieCutMac/Home/RecentProjectsStore.swift` |
| 2 | `HomeView`: 카드 그리드(LazyVGrid, 카드=썸네일+이름+메타), New/Open 액션, 템플릿 행(내장+import된 .mctemplate), 복구 배너. 디자인은 Pro 다크 토큰, 온보딩 CTA는 여기로 일원화(프리뷰 empty CTA와 중복 제거 — 감사 R3 잔여 해소) | 신규 `App/MovieCutMac/Home/HomeView.swift` |
| 3 | 앱 상태 전환: `AppStage` enum(.home/.editor(projectURL?)) — `MovieCutMacApp`에서 분기. 에디터 종료 시 dirty면 저장 시트. 홈 표시 정책은 UserDefaults(기본 on, 헤드리스/UITest 하니스는 기존처럼 에디터 직행 게이트 유지 — E2E 무회귀) | `MovieCutMacApp.swift`, `ContentView.swift` |
| 4 | 프로젝트 썸네일: 저장 시 첫 비디오 클립 프레임(또는 캔버스 렌더) 1장을 캐시에 기록 | `EditorViewModel.swift`(save 경로) |

#### AC
1. 클린 실행 → 홈 표시, New Project → 빈 에디터, 편집·저장 후 재실행 → 최근 카드에 썸네일과 함께 표시 → 더블클릭 → 그 프로젝트 열림.
2. recovery 파일 존재 상태로 실행 → 홈 배너에서 복구/폐기 선택 가능(기존 NSAlert 동작 대체, `AutosaveRecoveryTests` 시맨틱 유지).
3. `run_e2e_export.sh` 전 체크 무회귀(하니스는 홈 우회).
4. 없는 파일 카드 → 클릭 시 에러 토스트(U-04) + 목록 정리 액션.

#### 검증
- `RecentProjectsStoreTests`(upsert/정렬/누락 파일), 홈 표면 static contract, U-08 스크린샷(홈 populated). 실기기: 홈→열기→편집→홈 왕복 녹화.

---

### U-02. 타임라인 클립 표면 리치니스 (전환 pill·뱃지) — P0 / 규모 M

> **G-04(필름스트립)와 같은 코드 영역(`TimelineView` 클립 렌더) — 같은 세션 묶음 권장.**

#### 요구사항
1. 전환이 설정된 클립 경계에 전환 아이콘 pill이 표시되고, 클릭하면 인스펙터 전환 섹션으로 포커스(선택+스크롤).
2. 클립 우상단에 적용 상태 뱃지: FX(effects 비었지 않음)/그레이드(colorGrade non-identity)/속도(≠1.0x — "2x"·"0.5x" 라벨)/자막 스타일/그룹(기존 link 아이콘 유지).
3. 뱃지는 줌 아웃으로 클립이 좁아지면(예: <48px) 자동 숨김 — 클립 가독성 우선.

#### 현재 상태 (실사)
- `TimelineView.swift`에 transition 시각 표시 **0건**(grep). 뱃지 없음(link 아이콘·Sticker 라벨만). 전환 설정은 인스펙터를 열어야만 확인 가능.

#### 구현 증분
| Inc | 내용 | 파일 |
|---|---|---|
| 1 | 클립 뱃지 스트립: 클립 뷰 우상단 HStack(아이콘 12pt, 최대 4개+overflow "…"), 조건 계산은 `Clip` 순수 함수(`clipBadges(for:)` — Core 또는 ViewModel, 유닛 테스트) | `TimelineView.swift`, `EditorViewModel.swift` |
| 2 | 전환 pill: 인접 클립 경계(transition.type ≠ .none인 클립 끝)에 겹침 원형 pill(전환 타입 아이콘). 탭 → 해당 클립 선택 + `inspectorFocusSection = .transition` 발행 → InspectorPanel이 스크롤/하이라이트 | `TimelineView.swift`, `InspectorPanel.swift`(포커스 수신) |
| 3 | 줌 반응: 클립 폭 기반 뱃지/pill 표시 임계값, 접근성 label에는 항상 상태 포함(시각 숨김과 무관) | `TimelineView.swift` |

#### AC
1. crossDissolve 설정 클립 경계에 pill 표시, 클릭 → 인스펙터 전환 섹션 가시화(스크롤 위치 검증은 실기기).
2. 속도 1.0 클립엔 속도 뱃지 없음, 2x 설정 시 "2x" 라벨(뱃지 조건 유닛 테스트 전 케이스).
3. 줌 아웃 극단에서 뱃지 숨김·클립 렌더 무손상, 60fps 유지(G-04 측정과 병행).
4. VoiceOver가 클립에서 "transition: cross dissolve, speed 2x" 형태로 읽음.

#### 검증
- `ClipBadgeLogicTests`(순수 조건), static contract(pill/뱃지 존재), U-08 populated 캡처. 실기기 클릭 동선 녹화.

---

### U-03. 트랙 헤더 완성 (lock 배선 + 높이) — P1 / 규모 S

#### 요구사항
1. 트랙 lock 토글 — 잠긴 트랙의 클립은 선택/드래그/드롭/삭제가 거부되고 시각적으로 표시(빗금 오버레이 또는 감광).
2. 트랙 높이 프리셋 S/M/L(오디오 트랙 파형 상세 확인용) — 프로젝트에 저장.

#### 현재 상태 (실사)
- `Track.isMuted`/`isHidden`은 UI 배선됨(`TimelineView.swift:656-672`). **`Track.isLocked`는 모델만 존재, UI grep 0건 — dead model field**(A6 취지 위반 상태).
- 트랙 높이는 고정.

#### 구현 증분
| Inc | 내용 | 파일 |
|---|---|---|
| 1 | lock 토글 버튼(자물쇠 아이콘, mute/hide 옆) — `SetTrackPropertyCommand` 기존 경로(zIndex 전례). 편집 가드: `EditorViewModel`의 클립 선택/이동/드롭/삭제 진입점에서 잠긴 트랙 거부 + 토스트(U-04)/상태 메시지 | `TimelineView.swift`, `EditorViewModel.swift` |
| 2 | 잠긴 트랙 시각: 클립에 감광(opacity 0.55)+자물쇠 워터마크, drop 타깃 제외 | `TimelineView.swift` |
| 3 | 트랙 높이: `Track.laneHeight`(enum S/M/L, A5 optional decode) + 헤더 컨텍스트 메뉴로 전환, 파형/필름스트립 렌더가 높이 반영 | `Models/Track.swift`, `TimelineView.swift` |

#### AC
1. 잠긴 트랙 클립 드래그 시도 → 이동 없음 + 피드백. 삭제/split도 거부. undo 스택에 잔여 명령 없음.
2. 잠금 상태 프로젝트 저장/로드 왕복.
3. 오디오 트랙 L 높이에서 파형 세로 해상도 증가 확인(캡처).
4. 구버전 프로젝트 decode(laneHeight nil → M).

---

### U-04. 토스트 피드백 시스템 — P1 / 규모 S

#### 요구사항
1. 성공/정보/에러 3종 토스트가 우하단에 큐로 표시(자동 소멸 3s, 에러는 5s+닫기 버튼), 최근 이력은 상태바 클릭으로 팝오버 확인.
2. 기존 `lastStatusMessage`/`lastErrorMessage` 발행 지점을 전부 토스트 경유로 승격(발행 API는 유지 — 호출부 대량 수정 없이 어댑터).

#### 현재 상태 (실사)
- 상태바 정적 텍스트 1줄(`ContentView.statusBar`) — 드롭 피드백 등 40+ 발행 지점이 이미 존재하므로 표시 계층만 교체하면 됨.

#### 구현 증분
| Inc | 내용 | 파일 |
|---|---|---|
| 1 | `ToastCenter`(@Observable, 앱 레이어): `post(kind:message:)` 큐(최대 3 동시)+이력(최근 20). `EditorViewModel.lastStatusMessage/lastErrorMessage` didSet에서 자동 post(어댑터 — 호출부 무수정) | 신규 `App/MovieCutMac/UIKitCommon/ToastCenter.swift`, `EditorViewModel.swift` |
| 2 | `ToastOverlayView`: ZStack 최상위 오버레이(우하단), 토큰 준수(에러=시스템 red 톤, 성공=액센트 아님 — 액센트 남용 금지 원칙), reduce-motion 대응 | `ContentView.swift` |
| 3 | 상태바 정리: 텍스트 1줄 유지하되 이력 팝오버 버튼 추가. export 완료/실패·E2E 하니스 메시지도 경유 | `ContentView.swift` |

#### AC
1. 파일 드롭 성공 → 토스트 표시 후 자동 소멸, 이력 팝오버에 잔존.
2. 연속 5개 발행 → 큐 3개 표시+순차 처리(유닛: ToastCenter 큐 로직).
3. VoiceOver announcement 발행(`AXAnnouncement`).
4. 기존 `DragDropFeedbackStaticContractTests` 무회귀.

---

### U-05. 환경설정 창 — P1 / 규모 S

#### 요구사항
`Settings` scene(⌘,)에 3탭: **General**(홈 표시 정책, 언어 안내, 최근 프로젝트 개수), **Editing**(autosave 주기, 스냅 기본값, 매그네틱 기본값, 트랙 높이 기본), **Export**(기본 프리셋, 기본 저장 폴더, 프록시 preview 정책 — G-11 연계).

#### 현재 상태 (실사)
- `Settings` scene **없음**(`MovieCutMacApp.swift` grep). autosave 주기 등은 하드코딩.

#### 구현 증분
| Inc | 내용 | 파일 |
|---|---|---|
| 1 | `AppPreferences`(@Observable + UserDefaults 백킹, 키 상수화) — 소비처(autosave 스케줄러/스냅 초기값/export 기본)에 주입 | 신규 `App/MovieCutMac/Settings/AppPreferences.swift` |
| 2 | `Settings { SettingsView() }` 3탭 폼(macOS 표준 `Form`+`TabView`) | `MovieCutMacApp.swift`, 신규 `SettingsView.swift` |

#### AC
1. autosave 주기 변경 → 스케줄러 반영(로그/테스트 훅으로 확인).
2. 설정 값 재실행 후 유지.
3. 각 설정에 접근성 label + 기본값 복원 버튼.

---

### U-06. 현지화 (ko + en) — P1 / 규모 M

#### 요구사항
1. String Catalog(`Localizable.xcstrings`) 도입, 한국어 번역 1차 완료 — 시스템 한국어에서 주요 표면(브라우저 탭/타임라인 도구/인스펙터 섹션/메뉴/export/토스트)이 한국어로 표시.
2. 신규 UI 문자열은 카탈로그 등록을 규율로(하드코딩 리터럴 static contract 스윕은 표면 단위로 점진).

#### 현재 상태 (실사)
- `NSLocalizedString` 산발 사용(EditorViewModel 등), **.lproj/xcstrings 없음** → 번역 리소스 자체가 부재. `project.yml` 리소스 배선 필요(xcodegen — `info:` 블록 함정과 무관하나 재생성 검증 필수).

#### 구현 증분
| Inc | 내용 | 파일 |
|---|---|---|
| 1 | `Localizable.xcstrings` 추가 + `project.yml` 리소스 등록 + xcodegen 재생성 검증(plist 보존 확인 — 함정 회피 체크 포함) | `App/MovieCutMac/`, `project.yml` |
| 2 | 표면 스윕 1차(메뉴/툴바/브라우저 탭/타임라인 헤더): `Text("...")` 리터럴 → `String(localized:)`. 접근성 label/hint 포함 | `ContentView.swift`, `TimelineView.swift`, `MediaLibraryPanel.swift`, `MovieCutMacApp.swift` |
| 3 | 표면 스윕 2차(인스펙터/export/시트) + ko 번역 채움 | `Inspector/`, 각 시트 |
| 4 | iOS 동일 카탈로그 공유(타깃 리소스 공유 또는 복제 정책 결정 — 파리티 매트릭스에 기록) | `App/MovieCutiOS/`, `project.yml` |

#### AC
1. `defaults write -g AppleLanguages '(ko)'` 실행 상태에서 주요 표면 한국어 표시(스크린샷 증거 — U-08).
2. 영어 폴백 정상(미번역 키 영어 표시, 빈 문자열 0건 — 카탈로그 lint).
3. xcodegen 재생성 후에도 리소스/Info.plist 배선 보존(기존 함정 테스트).

---

### U-07. 브라우저 콘텐츠 그리드 리듬 — P2 / 규모 M

> **G-07(이펙트 브라우저)·G-08(에셋 라이브러리)과 병합 실행** — 이 항목은 "탭 간 공통 시각 언어" 스코프.

#### 요구사항
1. Effects/Transitions/Filters/Text/Stickers 탭이 동일한 카드 컴포넌트(썸네일+이름+호버 상태)의 그리드로 통일 — 감사 R2 잔여("one visual language") 해소.
2. 전환/필터 카드는 호버 시 선택 클립 프레임(또는 fixture 프레임)으로 미니 프리뷰.
3. Captions/Adjust 탭 신설 여부 결정: **Captions 탭 신설**(G-01 스타일 갤러리 진입점), Adjust는 인스펙터 소관으로 비신설(결정 기록).

#### 구현 증분
| Inc | 내용 | 파일 |
|---|---|---|
| 1 | `BrowserCard` 공통 컴포넌트(토큰 기반: 카드 크기 2종, 호버/선택 상태, 라벨 1줄) + 각 탭 그리드 이관 | 신규 `App/MovieCutMac/Library/BrowserCard.swift`, `MediaLibraryPanel.swift` |
| 2 | 전환/필터 썸네일: fixture 프레임에 적용한 정적 PNG 캐시(G-07 Inc 3 썸네일 파이프라인 공유) | G-07과 공유 |
| 3 | Captions 탭(G-01 완료 후): 캡션 스타일 카드 → 선택 자막 클립(들) 적용 | `MediaLibraryPanel.swift` |

#### AC
1. 5개 탭 카드가 동일 컴포넌트 사용(코드 검증) + 시각 일관(U-08 캡처).
2. 카드 호버 프리뷰가 UI 블로킹 없음.
3. 키보드 탐색(화살표+Enter 적용) 동작.

---

### U-08. UI 회귀/지표 인프라 — P0(상시) / 규모 M

> **UI 트랙의 G-12** — 이후 모든 U-ID의 "완료 증거" 생산 수단. 최우선 선행.

#### 요구사항
1. **populated 상태 캡처 자동화**: 부트스트랩 프로젝트(비디오+오디오+텍스트+선택 상태)를 하니스로 구성 → 창 스크린샷 저장. 감사 문서의 "matching populated side-by-side 재캡처" 부채 상환.
2. **골든 스크린샷 회귀**: 핵심 표면 4종(브라우저/프리뷰+인스펙터/타임라인 populated/그레이딩 패널)의 perceptual hash 비교(허용 오차 임계값) — 의도 변경 시 골든 갱신 절차 문서화.
3. **발견성 지표**: 대표 플로우(클립 추가→전환 적용→export 시작)의 클릭 수를 XCUITest(또는 하니스 로그)로 기록 — `UI_DESIGN_PRINCIPLES.md` 목표(핵심 편집 ≤2클릭) 대조.

#### 현재 상태 (실사)
- `MOVIECUT_BOOTSTRAP_PROJECT` env 게이트 스크린샷 부트스트랩(사용자 커밋 `eb63f1d`)과 UITest 하니스(env 훅) 기존재 — 재료는 있음. 골든 스크린샷/클릭수 자동화 없음. 과거 캡처는 `/tmp` 휘발 — **증거는 리포지토리 내 `Tests/UIEvidence/`(골든) + 산출은 `artifacts/`(gitignore)로 이원화**.

#### 구현 증분
| Inc | 내용 | 파일 |
|---|---|---|
| 1 | `scripts/ui_capture.sh`: 부트스트랩 populated 상태 → `screencapture -l`(창 ID) → `artifacts/ui/` 저장. 상태 변형 env(선택 클립 타입) 지원 | 신규 스크립트, `UITestHarness.swift` 확장 |
| 2 | 골든 비교: `scripts/ui_regression.sh` — 캡처 vs `Tests/UIEvidence/golden_*.png` perceptual hash(dHash 등, Swift 소도구 또는 Python) 비교, 임계 초과 시 FAIL+diff 이미지. 골든 갱신은 `--update-golden` 명시 플래그 | 신규 스크립트 + 골든 4종 커밋 |
| 3 | 클릭수 로거: 하니스에 액션 카운터 훅 or XCUITest 플로우 1개(클립 추가→전환→export)로 클릭 수 산출 → `docs/UI_METRICS.md`에 기록 | `App/MovieCutMacUITests/` |

#### AC
1. `scripts/ui_regression.sh`가 클린 상태에서 PASS, 의도적 색 변경(토큰 1개 수정) 시 FAIL을 증명(이빨 확인) 후 revert.
2. 골든 4종이 리포지토리에 커밋되고 갱신 절차가 문서화됨.
3. 대표 플로우 클릭수 측정치가 기록되고 원칙 목표와 대조표 존재.

---

### U-09. 커맨드 팔레트 (⌘K) — P2 / 규모 M (Pro 능가 표면)

#### 요구사항
1. ⌘K로 오버레이 팔레트: 명령(split/duplicate/marker/auto-cut/export 등 기존 액션 전부)·이펙트·전환·텍스트 템플릿·캡션 스타일을 fuzzy 검색 → Enter 실행(적용 대상은 현재 선택 규칙 그대로).
2. 각 결과 행에 카테고리·단축키 병기. 최근 사용 상단 정렬.

#### 구현 증분
| Inc | 내용 | 파일 |
|---|---|---|
| 1 | `CommandRegistry`(앱 레이어): 항목 `{id, title, category, shortcut?, isEnabled(selection), perform()}` — 기존 메뉴/QuickTools/브라우저 적용 액션을 등록(신규 로직 금지, 재노출만). 유닛: fuzzy 매칭·enabled 규칙 | 신규 `App/MovieCutMac/Palette/CommandRegistry.swift` |
| 2 | `CommandPaletteView`: 오버레이(⌘K 토글, Esc 닫기, ↑↓ 탐색), 검색은 subsequence fuzzy + 최근 가중치 | 신규 `CommandPaletteView.swift`, `MovieCutMacApp.swift`(키 등록) |
| 3 | G-07/G-08 완료 후 이펙트/에셋 항목 자동 등록(registry 소스 확장) | registry |

#### AC
1. ⌘K → "split" 입력 → Enter가 메뉴 Split과 동일 동작(선택/플레이헤드 가드 포함).
2. 비활성 명령(선택 없음 등)은 회색+실행 불가.
3. 텍스트 필드 포커스 중 ⌘K 충돌 없음(기존 `MovieCutShortcutGuard` 경유).
4. 팔레트 open→실행까지 키보드만으로 완주(접근성).

---

## 6. 실행 체크리스트 (콜드 스타트)

```bash
git status --short && git log --oneline -5        # c242632 기준
swift build && swift test --filter 'StaticContract|Golden'
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build
scripts/run_e2e_export.sh                          # 기존 E2E 전부 PASS 확인 후 착수
```

**공통 주의사항**
- `project.yml`에 `info:` 블록 금지(xcodegen이 hand-maintained `Info.plist`를 덮어씀 — `INFOPLIST_FILE` 참조만).
- static contract는 회귀 잠금 전용 — 완료 증거 불인정.
- `swift test` 전체는 헤드리스 완주 곤란(네트워크/Speech/마이크) — 필터 스위트 사용.
- AVAudioEngine offline render 검증은 앱 컨텍스트 E2E로(테스트 프로세스 SIGABRT 이력).
- 픽셀 테스트는 `GoldenPixelHarness`(`CIContext(useSoftwareRenderer:true)`, silent-skip 금지) 사용.
- 작업 완료 시: 이 문서 해당 AC에 검증 결과 1줄 + `CAPCUT_FEATURE_BACKLOG.md` 갱신 + 커밋.
