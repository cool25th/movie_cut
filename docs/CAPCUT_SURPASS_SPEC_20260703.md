# MovieCut → CapCut 능가 개발 명세서 (Surpass Specification)

> 버전: 1.8 / 작성일: 2026-07-03 (v1.8: 카드뉴스 사용성 G-18~G-22/U-10 등재) / 브랜치: `feat/core-backend-expansion`
> 상위 분석: `CAPCUT_GAP_IMPROVEMENT_PLAN_20260703.md`(기능 격차·우선순위), `GAP_ANALYSIS_V8_FUNC_UI_20260704.md`(기능+UI 통합 재감사) — 이 문서는 그 G-ID/U-ID들의 **개발 착수 가능한 상세 명세**다.
> 형식·운영 규칙은 `CAPCUT_PARITY_SPEC.md`를 계승한다: 작업은 G-ID 단위로 진행하고, 완료 시 해당 AC에 검증 결과를 1줄 추가한다. AC를 바꿔야 하면 이 문서를 먼저 수정·커밋한다(스펙이 사실의 원천).
> 모든 명세는 2026-07-04 V8 코드 실사 기준으로 실제 타입/파일에 앵커되어 있다.

변경 이력:
- 2026-07-14 v1.8: `USABILITY_BENCHMARK_STANDARD.md` v1.0의 카드뉴스 경로를 개발 단위로 등록. **G-18 카드 문서 모델+편집기 / G-19 카드 템플릿+마스터 스타일 / G-20 브랜드 킷 / G-21 카드 PNG·JPG 세트 export+원클릭 영상화 / G-22 대본 자동 분배 / U-10 카드뉴스 진입점**을 신설하고 UB-C/SC-C의 클릭 수·시간·출력 규격을 AC에 그대로 고정했다.
- 2026-07-13 v1.7: 사용자 보고 편집 체감 P0를 코드 실사 후 정식 등재. **G-16 타임라인 스크럽(B-I2)**과 **G-17 클립 복사/잘라내기/붙여넣기(B-F2.1)**를 신설하고, 구현 순서를 G-16→G-17→G-04로 고정했다.
- 2026-07-06 v1.6: **사용자 실사용 버그 재현**(사진 import→타임라인은 되나 preview 무표시 + export "Cannot Open" 실패, `GAP_ANALYSIS_V12_FUNC_UI_20260706.md`). ① **G-15 이미지(사진) 클립 파이프라인 신설 — 모든 큐에 최우선**(자동 선택: G-15 → U-08 → G-02 Inc 5~6 → G-01 Inc 2~4). ② **A7 신설**: 미디어 kind(video/audio/image)를 새로 소비하는 기능은 해당 kind fixture E2E 1건 의무(이번 버그가 못 잡힌 원인 = 전 E2E가 mp4/wav 전용). ③ **Works-First 규율**: `run_e2e_export.sh` 최상단에 실사용 스모크(사진+비디오+텍스트 혼합 → export) 상설, G-15 완료 시 사용자 실기기 확인 1회를 DoD에 포함. ④ 과거 "이미지 드래그앤드롭 ✅" 판정은 "라이브러리 진입까지만"으로 강등.
- 2026-07-05 v1.5: V11 재감사(`GAP_ANALYSIS_V11_FUNC_UI_20260705.md`) 반영. G-12 #9 상환(10/14, 자동 상환 가능분 소진)과 **G-02 Inc 3 완료(HSL/커브 체이닝 + 골든 + E2E)를 독립 검증** — dead-value 4계열 중 3계열 상환, `wordTimings`만 잔존. v1.4 게이트에 따라 **다음 자동 선택은 U-08**(UI 트랙 4회 연속 미착수), 그다음 G-02 Inc 5~6(커브/HSL 편집기 UI → W5 완주), G-01 Inc 2 순. `StyleTransferProvider`는 폐기/G-07 흡수 결정 필요로 승격.
- 2026-07-05 v1.4: V10 재감사(`GAP_ANALYSIS_V10_FUNC_UI_20260705.md`) 반영. ① **S0 게이트 완화**: G-12 #9 상환 후 자동 선택은 S1(G-02 Inc 3)→SU(U-08)→S2(G-01 Inc 2)로 진행. #11/#12는 fixture 제작 증분으로 세분화(병행 슬롯), #13/#14는 수동 검증 대기로 분리(자동 선택 제외). ② **A6 보강**: 순수 로직/모델 타입도 도입 후 다음 마일스톤 전환 시점까지 소비처 미연결이면 G-12 원장 자동 등재(현재 해당: CurveEvaluator·HSLCubeBuilder·CurvePoint/HSLBand·wordTimings). ③ 버전 헤더 정리(G-12 10/14; #9 chapter metadata 상환 후 다음 자동 항목 G-02 Inc 3).
- 2026-07-04 v1.3: G-12 #10 오디오 추출 app/E2E 상환. G-12 진행 상태를 6/14로 갱신.
- 2026-07-04 v1.2: V8 재감사 반영. G-12 5/14 상환, G-09 Inc 2 진행, G-02 Inc 1~2 순수 로직, G-01 Inc 1 워드 타이밍, U-03 `Track.isLocked` dead-field 판정 정정, U-07 부분 구현 상태를 기록.

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
- **A6.(신규)** Core 신설 서비스는 앱 호출부+검증 훅 동반 (§1.2-5). **(v1.4 보강)** 순수 로직·모델 타입(평가기/빌더/저장 필드)도 도입 후 다음 마일스톤 전환 시점까지 소비처(렌더 체인 또는 UI)에 연결되지 않으면 dead-value로 간주해 G-12 원장에 자동 등재한다.
- **A7.(v1.6 신설, Works-First)** 미디어 kind(video/audio/image)를 새로 소비하는 기능은 **해당 kind의 fixture로 E2E 1건**을 의무화한다. 또한 `run_e2e_export.sh`의 실사용 스모크(사진+비디오+텍스트 혼합 export)가 FAIL이면 모든 자동 세션은 신규 작업 금지·수리 우선이다. 근거: 전 E2E가 mp4/wav 전용이어서 이미지 클립 파이프라인 부재(G-15)를 한 번도 잡지 못했다.

V8 dead-code 감사 메모: `VocalSeparationService` 계열은 G-05의 명시 부채다. 추가 후보로 `BackgroundRemovalProvider`(App=0, tests-only; 실제 렌더는 `PersonSegmentationCompositor`/iOS inline path)와 `StyleTransferProvider`(App=0, tests-only; 실제 효과는 `VisualEffectPixelProcessor` 계열)가 식별됐다. `CurveEvaluator`/`HSLCubeBuilder`도 App=0이지만 G-02 Inc 1~2 진행 산출물이므로 Inc 3에서 렌더 체이닝으로 해소해야 한다.

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
| **SU. UI 트랙 (병행)** | 제품 표면·체감 완성 | U-01~U-09 (§5) | 슬롯 순서: U-08 → U-02(+G-04) → U-01 → U-04/U-03/U-05 → U-06 → U-07/U-09 (`GAP_ANALYSIS_V8_FUNC_UI_20260704.md` §9) |

순서 원칙: S0는 선행 필수(이후 모든 검증의 지반). S1↔S2는 교차 가능. S3의 G-04/G-06은 S1/S2와 병행 가능. **UI 트랙은 전 단계 병행하되 U-08(회귀 인프라)을 선행**하고, U-02는 G-04와, U-07은 G-07/G-08과 같은 세션 묶음을 권장. 각 마일스톤 종료 시 해당 워크플로우 1회 수동 완주 + `CAPCUT_FEATURE_BACKLOG.md` 갱신.

V8 재감사 상태(2026-07-04): S0는 아직 완료가 아니다. G-12는 14개 중 6개(#1 EQ, #2 NR, #3 ducking, #4 motion tracking, #8 platform presets, #10 audio extraction)가 상환됐고, G-09는 iOS generic build와 파리티 매트릭스 재감사까지 진행됐으나 CI job, iOS W1 녹화, iOS E2E가 남아 있다. G-02/G-01 착수분은 S1/S2 진행중 증거로만 본다.

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
- 2026-07-04 Inc 1: `TranscriptionSegment.words`와 `TextClipContent.wordTimings` optional 필드가 추가됐고, `SpeechTranscriptionProvider`가 `SFTranscriptionSegment`의 word timestamp/duration/confidence를 보존한다. `SubtitleGenerator`는 세그먼트 절대 word 시각을 클립 상대 시각으로 변환해 저장한다.
- `TextClipContent`는 stroke/shadow/bold 등 데코 필드 완비(F-12R) + word timing 저장 필드 보유. 아직 caption style 참조/active word 렌더는 미구현.
- 렌더는 `TextOverlayPixelProcessor`(CoreText attributed string) — Mac/iOS compositor 위임 구조(A2) 재사용 가능하나, 워드 단위 하이라이트 적용은 Inc 3+ 범위.
- V8 grep: `TextClipContent.wordTimings`는 저장/테스트에는 존재하지만 `TextOverlayPixelProcessor`와 Mac/iOS compositor가 active word를 읽지 않는다. `CaptionStyle` 타입/프리셋도 아직 없다. 따라서 G-01은 **진행중(Inc 1 완료)**이며 사용자-visible styled caption 완료가 아니다.

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
- 2026-07-04 G-01 Inc 1: `WordTiming`, `TranscriptionSegment.words`, `TextClipContent.wordTimings`, Apple Speech segment 보존, `SubtitleGenerator` 상대시각 변환을 추가했다. `StyledCaptionWordTimingTests`가 legacy decode nil, word timing Codable round-trip/confidence clamp, TextClipContent legacy decode, segment absolute→clip relative 변환, segment 밖 word clamp, SRT sentence compatibility/word timing omission을 검증한다. 검증: `swift build` PASS, `swift test --filter StyledCaptionWordTiming` PASS(6 tests). Caveat: caption style model/active-word renderer/compositor/UI/iOS는 Inc 2+.
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
- `ColorGrade`(`Models/ColorGrade.swift`): `lift: RGB` / `gamma: Double`(master) / `gain: RGB`, init에서 클램핑, `isIdentity` 게이트. V8 기준 `hslBands`/`curves` 저장 필드는 아직 없다.
- 2026-07-04 Inc 1~2: `CurvePoint`, `HSLBandCenter`, `HSLBand`, `CurveEvaluator`, `HSLCubeBuilder` 순수 로직과 유닛 테스트가 추가됐다. 그러나 App 호출은 0회이며 `ColorGradePixelProcessor`가 아직 이 로직을 소비하지 않는다.
- 렌더는 여전히 `ColorGradePixelProcessor`(CIColorMatrix slope+offset → CIGammaAdjust) 기반 3-way only다. HSL(`CIColorCube`)·커브 LUT 체이닝, cache, preview/export/iOS 검증은 Inc 3+.
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

검증 기록:
- 2026-07-04 G-02 Inc 1: `CurvePoint` + `CurveEvaluator` 순수 로직 추가. Monotone cubic Hermite/Fritsch-Carlson tangents, endpoints fixed `(0,0)/(1,1)`, duplicate-x last-write deterministic, 256-entry LUT clamp/no-overshoot. `swift test --filter CurveEvaluator` PASS (6 tests: identity diagonal, sanitized sort/endpoints, duplicate x, midtone raise, monotone nondecreasing, arbitrary no-overshoot). 렌더 체이닝/UI/iOS는 미연결이며 Inc 3+ 대상.
- 2026-07-04 G-02 Inc 2: `HSLBandCenter` + `HSLBand` + `HSLCubeBuilder` 순수 로직 추가. 8밴드 hue center, 45° cosine falloff, hue wrap-around, RGB↔HSL 변환, RGBA cube data(`size^3*4`)를 구현했다. `swift test --filter HSLCubeBuilder` PASS (6 tests: identity passthrough, red saturation -1 grayscale, blue unaffected, red hueShift toward orange, red-boundary falloff wrap, identity cube shape/endpoints). 렌더 체이닝/UI/iOS는 Inc 3+ 대상.
- 2026-07-05 G-02 Inc 3: `ColorGrade`에 optional `hslBands`/`curves`와 `ColorCurves`를 편입하고, `ColorGradePixelProcessor.apply`를 CDL → HSL `CIColorCube` → channel/master curve cube 순서로 체이닝했다. Mac/iOS preview/export는 기존 shared processor 호출부를 통해 새 필드를 소비하며, Inspector 슬라이더 re-init 경로가 HSL/curve 필드를 보존한다. 검증: `swift build` PASS, `swift test --filter 'ColorGrade|CurveEvaluator|HSLCubeBuilder|StaticContract|Golden'` PASS, Mac `xcodebuild` PASS, `scripts/run_e2e_export.sh` PASS(`G-02 HSL/curve grade reflected in export`, base_rgb=5,1,0 → grade_rgb=5,5,5). Caveat: HSL/Curve UI 편집기는 Inc 5~6 범위.

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
- 2026-07-15 Inc 3에서 실제 `TimelineView` 비디오 클립 배경에 시간가변 프레임 소비 경로를 연결했다. named horizontal viewport 좌표계에서 clip frame과 실제 scroll viewport를 교차해 반 화면씩 prefetch하며, offscreen은 skip하고 request identity(가시 window/zoom/source/media/geometry)가 바뀌면 이전 Task를 취소한다. 기존 단일 썸네일 타일은 async 준비·실패·취소 중 폴백으로 유지한다. 호버와 signpost/perf 측정은 아직 없다.

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
- 2026-07-14 Inc 1~2 검증: `FilmstripPlanningTests` **5/5 PASS**(tile-center 시각·4단계 줌 버킷·cache key 분리), actual app DEBUG E2E가 2초 fixture에서 `frames=4`, requested `0.250,0.750,1.250,1.750`, actual `0.233,0.733,1.233,1.733`, `max_height=60`, `cache_hit=1/cache_miss=2/cache_inserts=1/cache_limit=134217728/cache_invalidate=1`을 기록했다. AC1~5는 Inc 3~5/UI·성능 측정 전이므로 미완료다.
- 2026-07-15 Inc 3 검증: focused `swift test --filter Filmstrip` **11/11 PASS**(실제 scroll viewport 범위·양끝 clamp·offscreen nil·zoom/request identity·stale reject·cancel/failure fallback). actual app DEBUG E2E의 **실제 `TimelineView` consumer**가 `frames=32`, `distinct_digests=32`, `distinct_times=32`, `visible_span=21.600/30.000`, `visible_count=32/67`, `offscreen_skipped=1`, `cancelled=1`, `stale_rejected=1`, `fallback_before_ready=1`, `fallback_after_cancel=1`을 기록하고 전체 `E2E check OK`로 끝났다. Inc 3 범위는 완료했지만 AC1/AC2 성능·메모리 실측, AC3 4단계 실제 UI 밀도 측정, AC4 호버, AC5 비디오 외 시각 회귀 증거가 남아 **G-04 완료는 선언하지 않는다**.
- `[진행중] 다음 증분: Inc 4, 시작점: App/MovieCutMac/TimelineView.swift:975`

---

### G-05. 오디오 스위트 — 보컬 분리 배선 + 보이스 FX + 청감 검증 — P1 / S3 / 규모 M

#### 요구사항
1. 오디오/비디오 클립에서 "Remove Vocals"(karaoke) / "Isolate Vocals" 원클릭 적용.
2. 보이스 FX 프리셋 6종(Deep/Chipmunk/Echo/Radio/Megaphone/Robot)을 클립에 적용.
3. EQ/NR/덕킹의 청감 검증 부채를 실오디오 fixture로 상환.

#### 현재 상태 (실사)
- `VocalSeparationService`(`Sources/MovieCutCore/Audio/VocalSeparationService.swift`): `CenterChannelVocalSeparator`(mid/side DSP, `removeVocals`/`isolateCenter`, amount 0~1, ML seam 프로토콜 `AudioStemSeparator`) — **알고리즘은 실재하나 앱 호출 0회 dead code** (A6 위반 사례 2호).
- 배선 전례: `NoiseReductionService` — offline render → denoise 파일 생성 → 클립 소스 destructive 교체, `MOVIECUT_UITEST_DENOISE` E2E 훅. 이 패턴 그대로 복제 가능.
- V8 기준 EQ/NR/덕킹 청감 검증은 G-12 #1~#3에서 상환됐다. G-05의 잔여 핵심은 보컬 분리 앱 배선/E2E와 보이스 FX다.

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
- V8 caveat: `.github/workflows/ci.yml`은 `swift test`만 확인되며 iOS build job은 아직 명시되지 않았다. `PLATFORM_PARITY_MATRIX.md`도 스스로 "iOS simulator W1 녹화는 아직 미수행"이라고 제한한다. 따라서 G-09는 Inc 1~2 진행중이며 AC 1/3/4 완료가 아니다.

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
- 2026-07-04 G-12 #4 모션 트래킹 실영상: `moving_subject_320x240_2s_30fps.mp4` fixture + `MotionTrackingProviderTests.trackFollowsMovingSubjectFixtureByFrameIoU` 실제 `provider.track` PASS. 15fps sampling 31 samples, meanIoU=0.7929, minIoU=0.7095 (thresholds mean>=0.75, min>=0.65).
- 2026-07-04 G-12 #5 옵티컬 플로우 실영상: `moving_subject_320x240_2s_30fps.mp4` fixture + `MOVIECUT_UITEST_PLAYBACK_RATE=0.25` + `MOVIECUT_UITEST_OPTICAL_FLOW=1` 앱 하니스 + `scripts/run_e2e_export.sh` ffprobe/frame-diff 측정 PASS. 0.25× export=8.000000s, 120/1fps, 960 frames. 기존 AVFoundation stretch-only probe는 adjacent MAD=0.0000으로 duplicate 반복이었으나, motion-aware slow-motion render 경로 후 adjacent_mad=0.001519, mid_vs_blend=0.001845, anchor_mad=0.005642.
- 2026-07-04 G-12 #8 플랫폼 프리셋 5종: `bars_320x240_3s_30fps.mp4` fixture + `MOVIECUT_UITEST_PLATFORM_PRESET` 앱 하니스 + `scripts/run_e2e_export.sh` ffprobe 측정 PASS. TikTok/Reels/Shorts=1080x1920 30/1 h264 mp4, YouTube Standard=1920x1080 30/1 h264 mp4, Instagram Post=1080x1080 30/1 h264 mp4.
- 2026-07-04 G-12 #10 오디오 추출: `solid_red_tone_320x240_2s_30fps.mp4` fixture + `MOVIECUT_UITEST_EXTRACT_AUDIO` 앱 하니스 + `MOVIECUT_UITEST_EXPORT_AUDIO` audio-only export를 `scripts/run_e2e_export.sh` ffprobe/RMS로 검증 PASS. `extract_audio_clips=1`, clip_duration=2.000s, export_duration=2.066576s, codec=aac, rms=0.087598.
- 2026-07-05 G-12 #6 텍스트 애니메이션 13종: DEBUG 앱 하니스 `MOVIECUT_UITEST_TEXT_ANIMATION_PRESET=<rawValue>` + `scripts/run_e2e_export.sh` none-baseline 대비 frame-diff 측정 PASS. 13종 전체 export proof: none overlay_mad=16.512326, non-none max_residual_temporal_mad min=2.870069(fadeOut) / max=6.594722(popIn), E2E `text animations + E2E check OK` 통과.
- 2026-07-05 G-12 #7 타이틀 템플릿 14종: DEBUG 앱 하니스 `MOVIECUT_UITEST_TEXT_TEMPLATE_NAME=<name>`가 실제 템플릿 클립을 화면 안 fixture 중앙에 추가하고, `scripts/run_e2e_export.sh`가 no-template baseline 대비 frame-diff를 14종 전체에 대해 측정 PASS. 실측 max_overlay_mad: Title 7.450278, Subtitle 7.109653, Lower Third 6.524444, Caption 6.459444, Credits 7.125347, News Banner 6.722222, Quote 6.725417, Callout 6.875694, Kinetic 6.848056, Handwritten 6.700069, Neon Glow 6.790208, Outline 6.636806, Typewriter 6.506250, Social Handle 6.885069.
- 2026-07-05 G-12 #9 챕터/비트 마커 메타데이터: DEBUG 앱 하니스 `MOVIECUT_UITEST_CHAPTER_MARKERS=1` + `MOVIECUT_UITEST_BEAT_CHAPTERS=1`가 표준 마커 Intro/Outro와 beat marker `Beat 1`을 command path로 추가하고, ExportEngine이 AssetWriter timed metadata track + `.chapterList` track association으로 실제 chapter atoms를 기록한다. `scripts/run_e2e_export.sh` ffprobe 실측 PASS: `count=3 starts=0.25,0.75,1.25 ends=0.75,1.25,1.75`. Caveat: ffprobe/QuickTime chapter atom timing proof이며 현재 ffprobe title tag는 AVFoundation timed metadata 특성상 빈 문자열로 표시되어 하니스 status로 marker name/count를 함께 검증한다.
- 2026-07-05 loop-6/loop-7/V10 재감사: `docs/GAP_ANALYSIS_V10_FUNC_UI_20260705.md` 기준 G-12는 #9 상환 후 **10/14**로 갱신한다. v1.4 게이트에 따라 자동 선택은 이제 S1 **G-02 Inc 3**(ColorGrade 저장 필드 + HSL/curve renderer chain + golden/E2E)로 전환한다.
- V10 원장 재편(2026-07-05, v1.4 게이트 완화): #11/#12는 선행 fixture 제작을 독립 증분으로 분리 — `#11a/#12a: scripts/make_fixtures.sh`에 이동 피사체(합성 도형 애니메이션 mp4) 및 실인물 대체(합성 인물 실루엣 또는 사용자 제공 클립 절차 문서화) fixture 추가 → `#11b/#12b`: 해당 fixture로 E2E 측정. **#13(iCloud 2기기)/#14(Photos 드래그)는 "수동 검증 대기"로 분리** — 자동 선택에서 제외하고, 사용자 실기기 세션용 절차를 각 1페이지로 준비하는 것까지가 자동 세션의 몫. A6 보강에 따라 dead-value 4계열(CurveEvaluator·HSLCubeBuilder·CurvePoint/HSLBand 미편입·wordTimings 미소비)을 원장에 등재하며, 상환처는 각각 G-02 Inc 3, G-01 Inc 2다.

---

### G-13. 내추럴 리터치 — P3 / S5 / 규모 M ⚠️ 착수 전 합의 필요

**권장 최소 범위**: Vision 얼굴 관찰(`VNDetectFaceRectanglesRequest`+landmarks) → 피부 영역 소프트 마스크 → 마스크 한정 주파수 분리 근사(고주파 보존 + 중주파 스무딩 블렌드) — "Natural Retouch" 슬라이더 1개(0~1). 과장 보정(눈 확대/윤곽 변형)은 만들지 않는다(브랜드 결정).
**AC(합의 후 확정)**: 피부 영역 노이즈 감소가 골든으로 측정되고 눈/입/모발 선명도 유지(엣지 에너지 측정), 얼굴 미검출 시 무변경.

### G-14. Mac 녹화 스위트 — P3 / S5 / 규모 L ⚠️ 착수 전 합의 필요

**권장 범위**: ① ScreenCaptureKit 화면+시스템 오디오 → 라이브러리 자동 import ② AVCaptureSession 웹캠 PiP 클립 ③ 텔레프롬프터 오버레이(텍스트 클립 원고 스크롤). 보이스오버 녹음 UI/권한 패턴 재사용. 상세 스펙은 합의 후 본 문서에 증분 추가.

---

### G-15. 이미지(사진) 클립 파이프라인 — **P0 / 최우선(v1.6 게이트)** / 규모 M ⭐

> 트리거: 사용자 실사용 버그 보고(2026-07-06) + 헤드리스 재현 확정. 상세 배경: `GAP_ANALYSIS_V12_FUNC_UI_20260706.md` §1.

#### 요구사항
1. 사진 파일(png/jpg/heic)을 import→타임라인 배치하면 **preview에 즉시 보인다**(기본 duration 5s, trim으로 연장/단축 가능).
2. export 결과물에 사진이 반영된다(사진 단독·사진+비디오 혼합 타임라인 모두).
3. 기존 효과 체인(색보정/그레이드/HSL·커브/키프레임/전환/마스크)이 사진 클립에도 동일 적용된다.
4. iOS 동일 동작.
5. EXIF 회전이 올바르게 반영되고, 대형 사진(예: 48MP)은 캔버스 해상도 상한으로 다운스케일된다.

#### 현재 상태 (2026-07-06 실사 — **미구현 확정**)
- 재현: `MOVIECUT_UITEST_IMPORT=<blue png>` + `EXPORT` → **clips=1, error=Cannot Open, export 파일 미생성**.
- `PlaybackEngine.swift:494` — 클립 소스 삽입이 `loadTracks(withMediaType: .video).first` 전제. 이미지 파일은 비디오 트랙 0개 → **조용히 스킵**(preview 무표시, 에러 없음).
- `ExportEngine` — 이미지 클립 분기 없음(이미지 렌더는 sticker `stickerImageURL` 오버레이·GIF export·정지프레임 저장뿐).
- `MediaImporter:38`의 `.image` 분류, `EditorViewModel:421`의 이미지 클립 생성 허용, 썸네일/메타데이터(F-06)는 정상 — **파이프라인의 앞부분만 존재**.
- E2E 전 시나리오가 mp4/wav fixture → 이 경로가 한 번도 검증된 적 없음(fixture 다양성 부채 → A7 신설).

#### 구현 방향 결정
- **채택: (B) 이미지→비디오 세그먼트 사전 렌더** — `ReverseRenderService`(역재생용 임시 asset 생성→composition 삽입)와 동일한 검증된 패턴. 소스가 진짜 비디오가 되므로 preview/export/iOS/효과 체인(색·그레이드·키프레임·전환)이 **무수정으로 상속**된다.
- 기각: (A) blank 트랙 + custom compositor 직접 드로잉 — AVFoundation은 소스 트랙 없는 구간에 compositor instruction을 호출하지 않아 placeholder 트랙 편법이 필요하고, two-source 전환·speed 경로 전반의 재작업 위험이 큼.

#### 구현 증분

| Inc | 내용 | 파일 |
|---|---|---|
| 1 | **`ImageVideoRenderService`**(앱 레이어, A4): `render(imageURL:duration:renderSize:) async throws -> URL` — CGImageSource(EXIF 회전 적용, 캔버스 해상도 상한 다운스케일) → `AVAssetWriter` h264 mp4(정지 프레임, `scaleTimeRange` 허용). 캐시 키 `(imageURL, duration버킷, renderSize)` — temp 디렉토리, `ReverseRenderService` 수명 관리 패턴 복제 | 신규 `App/MovieCutMac/Media/ImageVideoRenderService.swift` |
| 2 | **엔진 배선**: `PlaybackEngine`/`ExportEngine` 클립 순회에서 asset kind `.image`이면 렌더된 세그먼트 asset을 소스로 삽입 — reverse 클립 분기와 같은 위치. 클립 생성 시 기본 duration 5s 부여 확인 | `PlaybackEngine.swift:494` 인근, `ExportEngine.swift`, `EditorViewModel.swift` |
| 3 | **E2E + W-스모크**: ① 재현 케이스 codify — blue png import→export 성공 + 중간 프레임 RGB≈(0,0,255) 측정 ② **실사용 스모크 시나리오 상설**: 사진 1+비디오 1+텍스트 1 혼합 타임라인 → export 성공+duration 검증, `run_e2e_export.sh` 최상단 배치(FAIL 시 이후 체크 중단) | `scripts/run_e2e_export.sh`, `UITestHarness.swift` |
| 4 | **iOS 배선** + trim/duration GUI 확인 + **사용자 실기기 확인 요청**(사진 드래그→재생→export 1회 — Works-First DoD) | `App/MovieCutiOS/`(IOSPlaybackEngine/IOSExportEngine) |

#### AC
1. 재현 케이스 역전: blue png → export **성공** + 중간 프레임 픽셀 RGB≈(0,0,255) (E2E — 이번 버그가 그대로 회귀 잠금).
2. 사진+비디오 혼합 타임라인 export 성공, 총 duration = 클립 합 (E2E 스모크).
3. 사진 클립에 warm grade 적용 → export 평균색 이동 (기존 grade E2E 패턴 재사용).
4. preview에서 사진이 보임 + trim으로 duration 변경 반영 (실기기 확인).
5. EXIF 회전 jpg가 올바른 방향으로 렌더 (fixture 추가 + 픽셀 위치 검사).
6. iOS 동일 E2E 1건.
7. 4K 캔버스에 대형 이미지 배치 시 다운스케일 확인(메모리 측정 로그).

검증 기록:
- 2026-07-06 G-15 Inc 1~3 부분 완료: `ImageVideoRenderService`를 `ReverseRenderService.swift`에 추가해 still image를 EXIF transform 적용 thumbnail → sRGB H.264 30fps mp4 segment로 렌더하고, Mac `PlaybackEngine`/`ExportEngine`이 `MediaKind.image` 클립을 기존 video composition source track으로 삽입한다. `scripts/run_e2e_export.sh` 최상단에 Works-First image smoke를 추가해 `Tests/Fixtures/swatch_blue_64x64.png`를 실제 DEBUG 앱 하니스(`MOVIECUT_UITEST_IMPORT`→`MOVIECUT_UITEST_EXPORT`)로 export한 뒤 duration과 중간 프레임을 측정한다. 검증: `swift build` PASS, `swift test --filter 'ImageVideo|StaticContract|Golden|Export|Playback'` PASS, Mac `xcodebuild` PASS, `scripts/run_e2e_export.sh` PASS — AC1 실측 `duration=5.000000s`, middle frame `rgb=0,0,171`(blue-dominant). Caveat: AC3 warm grade, AC4 실기기 preview/trim, AC5 EXIF fixture, AC6 iOS E2E, AC7 대형 이미지 메모리 로그는 [진행중].
- 2026-07-07 G-15 AC2 완료: DEBUG 하니스에 `MOVIECUT_UITEST_IMPORT_EXTRA`를 추가해 `swatch_blue_64x64.png`(5s image) 뒤에 `solid_red_320x240_2s_30fps.mp4`(2s video)를 한 번의 `importMediaAndAddToTimeline` 호출로 순차 삽입한다. `ExportEngine` layer instruction opacity를 clip timeRange 밖 0으로 제한해 이전 image frame hold가 뒤 clip을 가리던 mixed export 회귀를 수리했다. E2E 실측: `scripts/run_e2e_export.sh` PASS — timeline `video:image=0.000-5.000,video:video=5.000-7.000`, export `duration=7.000000s`, image sample `rgb=0,0,171`, video sample `rgb=5,0,0`. Caveat: AC3 warm grade, AC4 실기기 preview/trim, AC5 EXIF fixture, AC6 iOS E2E, AC7 대형 이미지 메모리 로그는 [진행중]. 다음 증분: AC3/Inc 3 확장, 시작점: `scripts/run_e2e_export.sh` G-15 mixed smoke 아래에 image+warm grade 평균색 이동 smoke 추가.
- 2026-07-12 G-15 AC3 완료: 기존 command-backed `MOVIECUT_UITEST_GRADE=1` 경로로 `swatch_blue_64x64.png`를 실제 앱 export하고 AC1 baseline과 동일한 t=2.5s 평균색을 비교하는 Works-First smoke를 추가했다. E2E 실측: `duration=5.000000s`, baseline `rgb=0,0,171` → warm grade `rgb=100,0,153`(`red_delta=+100`, `blue_delta=-18`) PASS. Caveat: AC4 실기기 preview/trim, AC5 EXIF fixture, AC6 iOS E2E, AC7 대형 이미지 메모리 로그는 [진행중]. 다음 자동 증분은 AC4이며 사용자 실기기 확인이 필요하다.

#### 검증 계획
- fixture 추가: EXIF 회전 jpg (`scripts/make_fixtures.sh`).
- `ImageVideoRenderServiceTests`(해상도 상한/회전/캐시) + E2E(기존 `MOVIECUT_UITEST_IMPORT`에 png 사용).
- 실기기: 사용자 확인 1회(Inc 4) — Photos 앱 드래그(G-12 #14)와 묶어 진행 권장.

#### 리스크
- trim 연장 시 세그먼트 길이 부족 — 여유 길이(최대 30s)로 렌더 후 trim으로 흡수(권고) 또는 duration 버킷 재렌더.
- HEIC/Display P3 → h264 변환 색 시프트 — sRGB 변환 명시.
- 프로젝트 재로드 시 temp 세그먼트 소실 → imageURL 기준 lazy 재렌더 필수.

---

### G-16. 타임라인 스크럽 — **P0 / 사용자 보고 편집 체감** / 규모 S~M ⭐

> 대응 기준: `CAPCUT_BENCHMARK_STANDARD.md` B-I2. 룰러 클릭·드래그와 플레이헤드 드래그에 프리뷰가 프레임 단위로 즉시 추종해야 한다.

#### 요구사항
1. 타임라인 룰러의 시간축 영역을 클릭하거나 드래그하면 플레이헤드와 프리뷰가 해당 시각으로 즉시 이동한다.
2. 2pt 플레이헤드에는 좌우 약 6pt 이상의 투명 hit target을 제공하며 자유 드래그를 지원한다.
3. 재생 중 스크럽을 시작하면 먼저 pause하고, 스크럽에는 클립 이동용 스냅을 적용하지 않는다.
4. 연속 입력은 프레임당 약 1회로 coalesce하되, 드래그 종료 시 요청한 최종 프레임을 정확히 표시한다.

#### 현재 상태 (2026-07-13 구현/검증)
- `TimelineView.timeRuler` 시간축은 `DragGesture(minimumDistance: 0)`로 shared `TimelineScrubMath` 좌표 변환을 거쳐 `EditorViewModel.scrubPlayhead`를 호출한다.
- 2pt 플레이헤드는 14pt hit target과 스냅 없는 직접 드래그를 제공하고, 시작 시 pause·중간 요청 16ms coalescing·종료 exact seek를 transport 상태로 처리한다.
- DEBUG 하니스 `MOVIECUT_UITEST_SCRUB=1.25` 실측은 `playhead=1.250 playback=1.250`으로 30fps ±1프레임 기준을 통과했다. 실기기 100ms 체감 확인은 사용자 확인 대기다.

#### 데이터/명령 경계
- 프로젝트 모델 필드 추가 없음. 일시적인 scrubbing/coalescing 상태는 `EditorViewModel` 앱 상태로만 둔다.
- 시킹은 비파괴 transport 동작이므로 편집 undo command를 만들지 않는다. 단, 편집 상태를 바꾸는 신규 동작은 계속 `EditorSession.dispatch(Command)` 규율을 따른다.
- 공개 진입점 예: `scrubPlayhead(to:phase:)`; 내부에서 timeline duration clamp, pause-on-begin, seek coalescing, final exact seek를 책임진다.

#### 구현 증분
| Inc | 내용 | 파일 |
|---|---|---|
| 1 | 룰러 시간축에 `DragGesture(minimumDistance: 0)`. 트랙 헤더 80pt를 제외한 local X를 `pixelsPerSecond`로 환산하고 `0...timeline.duration` clamp. 시작 시 재생 pause | `TimelineView.swift`, `EditorViewModel.swift` |
| 2 | 플레이헤드 자체 드래그. 시각 2pt와 별도의 좌우 약 6pt 투명 hit target, 스냅 없는 자유 이동 | `TimelineView.swift` |
| 3 | seek coalescing·프레임 정확도. 연속 요청은 display-frame 수준으로 합치고 종료 요청은 zero-tolerance exact seek. DEBUG 하니스 `MOVIECUT_UITEST_SCRUB=<t>`와 Works-First E2E 추가 | `EditorViewModel.swift`, `PlaybackEngine.swift`, `UITestHarness.swift`, `scripts/run_e2e_export.sh` |

#### AC
1. [PASS 2026-07-13] behavioral/runtime: `TimelineScrubBehaviorTests` 3/3 PASS, actual app `playhead=1.250 playback=1.250`으로 30fps ±1프레임 동기화 통과.
2. [PASS 2026-07-13] E2E: `MOVIECUT_UITEST_SCRUB=1.25`가 ruler X=`requested×timelineZoom` shared 환산 경로와 공개 scrub API를 구동하고 exact status를 기록함.
3. [사용자 확인 필요] 실기기 룰러 클릭·드래그/플레이헤드 드래그 화면 녹화와 B-U1 100ms 체감 확인 미수행.
4. [부분 PASS 2026-07-13] 음수/초과/non-finite coordinate clamp behavioral 2/2 PASS, pause-on-begin 및 final exact seek 코드·Mac build PASS. 실기기 재생 중 스크럽 체감은 AC3와 함께 확인 필요.

#### 검증 계획
- `TimelineScrubBehaviorTests`: 좌표→시간 변환/clamp, pause-on-begin, ±1프레임 동기화, final exact seek.
- `scripts/run_e2e_export.sh`: 짧은 fixture import → 룰러 좌표 기반 t=1.25s 스크럽 → `playhead=1.250` status 검사.
- 실기기: ruler click/drag + playhead drag를 화면 녹화하고 100ms 반응성 기준을 사용자에게 확인 요청.

#### 리스크
- `DragGesture`가 마커 hit target·가로 스크롤과 충돌할 수 있어 시간축 영역과 플레이헤드 hit region의 우선순위를 분리해야 한다.
- AVPlayer seek 폭주 시 프리뷰가 뒤늦게 따라올 수 있으므로 중간 요청만 coalesce하고 최종 요청은 버리지 않는다.
- SwiftUI local/global 좌표 혼용 시 80pt 트랙 헤더 오프셋이 중복 적용될 수 있어 순수 좌표 변환 테스트로 잠근다.

---

### G-17. 클립 복사/잘라내기/붙여넣기 — **P0 / 사용자 보고 편집 체감** / 규모 M ⭐

> 대응 기준: `CAPCUT_BENCHMARK_STANDARD.md` B-F2.1. Cmd+C/X/V로 단일·다중 클립을 복사/잘라내고 플레이헤드 위치에 붙여넣으며 undo 1회로 원복해야 한다.

#### 요구사항
1. 선택한 단일 또는 복수 클립을 앱 내부 클립보드에 복사하고 Cmd+C/X/V 및 context menu로 실행한다.
2. 붙여넣기는 클립군의 상대 시간 간격을 보존해 플레이헤드 위치를 anchor로 배치한다. 새 UUID를 부여하며 원본은 copy에서 불변이다.
3. cut은 copy+delete를 하나의 undo 그룹으로, paste도 하나의 command/undo 단계로 처리한다.
4. 원본 트랙·대상 시각에 충돌이 있으면 CapCut 실동작 확인 결과를 따른다. 확인 불가 시 같은 kind의 빈 트랙, 없으면 신규 트랙을 사용한다.

#### 현재 상태 (2026-07-14 구현/검증)
- Core `ClipboardPayload`·`PasteClipsCommand`·`CutClipsCommand`가 전체 clip 값 사본, 플레이헤드 anchor, 결정론적 충돌 회피와 single-dispatch undo를 제공한다.
- `EditorViewModel` 비영속 clipboard가 Cmd+C/X/V 메뉴와 clip context menu 양쪽에서 동일 command-backed API를 호출한다. NSText focus에서는 native copy/cut/paste로 forwarding한다.
- actual app 하니스가 두 2초 clip을 copy→10초 paste→undo/redo→cut→undo하고, `timeline=0-2,2-4,10-12,12-14` 및 14초 export를 검증한다.

#### 데이터 모델/명령 경계
- clipboard는 `EditorViewModel`의 비영속 앱 상태: source clip 값 사본, source track id, earliest start, relative offset 배열. 시스템 pasteboard와 프로젝트 Codable은 변경하지 않는다.
- Core command 계층에 atomic paste command와 cut용 composite/batch command를 추가한다. 실제 timeline 변형은 반드시 `EditorSession.dispatch(Command)`를 경유한다.
- pasted clip은 새 id를 사용하되 asset/effect/transform/text/audio metadata는 값 복사한다. group 관계는 선택 집합 내부 관계만 새 group id로 remap한다.

#### 구현 증분
| Inc | 내용 | 파일 |
|---|---|---|
| 1 | Command 계층에 atomic paste·cut batch 추가. ViewModel clipboard와 단일 clip copy/cut/paste API, 플레이헤드 anchor·겹침 정책 구현 | `Sources/MovieCutCore/Commands/`, `EditorViewModel.swift` |
| 2 | Cmd+C/X/V 메뉴·단축키, clip context menu, 멀티 선택과 상대 간격/group 관계 보존 | `MovieCutMacApp.swift`, `TimelineView.swift`, `EditorViewModel.swift` |
| 3 | DEBUG 하니스 `MOVIECUT_UITEST_CLIPBOARD=1`: 2개 import→copy→10초 paste→undo/redo→cut→undo, `timeline=` dump와 14초 export. Works-First E2E smoke 추가 | `UITestHarness.swift`, `scripts/run_e2e_export.sh` |

#### AC
1. [PASS 2026-07-14] behavioral 6/6: 10초 anchor, 원본 불변, 충돌 없는 호환 트랙/신규 트랙 정책과 multi-track cut을 검증했다.
2. [PASS 2026-07-14] paste undo/redo 및 cut undo가 각각 1회로 전체 선택과 신규 트랙을 exact project snapshot으로 복원한다.
3. [PASS 2026-07-14] actual app `timeline=0-2,2-4,10-12,12-14`, `error=none`; ffprobe video, duration `14.000000s`.
4. [PASS 2026-07-14] `paste_starts=10.000,12.000 relative=2.000 new_ids=1`; group 관계는 새 group id로 remap되고 원본/외부 링크는 불변이다.
5. [PASS 2026-07-14] Mac static contract 3/3 + xcodebuild PASS: Cmd+C/X/V·context menu가 동일 ViewModel API를 호출하고 NSText copy/cut/paste를 native forwarding한다. 실기기 메뉴 클릭 확인만 잔여.

#### 검증 계획
- [완료] CapCut 공식 `how-to-use-capcut` 및 motion-tracking 문서에서 Copy 후 원본 위/별도 트랙 paste를 [확인]. Cmd/Ctrl+C/V·playhead anchor는 2026 shortcut/desktop 튜토리얼로 교차 확인. 충돌 시 내부 트랙 탐색 순서는 미공개라 [추정] fallback(원본→같은 kind 빈 트랙→신규 트랙)을 채택했다.
- [완료] `ClipboardCommandTests` 6/6: 상대 간격, 새 id, 원본 불변, 충돌 트랙, group remap, cut/paste 1회 undo/redo.
- [완료] `scripts/run_e2e_export.sh`: actual app status exact compare + ffprobe 14초 export.
- 실기기: 단일·멀티 선택에서 Cmd+C/X/V와 context menu 왕복 확인.

#### 리스크
- 기존 magnetic packing이 paste 위치를 재배치할 수 있으므로 command 결과와 B-F2.1 anchor 정책의 우선순위를 테스트로 고정해야 한다.
- cut을 copy 후 개별 delete command로 dispatch하면 undo가 여러 번 필요해진다. 반드시 composite/snapshot atomic command를 사용한다.
- 시스템 텍스트 필드에서 Cmd+C/X/V를 가로채면 안 되므로 기존 `MovieCutShortcutGuard`를 재사용한다.
- linked/grouped clip 일부만 선택했을 때 관계 복사 정책이 모호하다. 1차는 선택 집합 내부 관계만 보존하고 외부 링크는 끊는다.

---

### G-18. 카드 문서 모델 + 편집기 — **P0 / 카드뉴스 핵심 경로** / 규모 L ⭐

> 대응 기준: UB-C1/C3/C4, SC-C1. 카드 시퀀스를 별도 문서 모델로 만들고 페이지 편집과 캔버스 인라인 텍스트 수정을 command 경계 안에서 제공한다.

#### 요구사항
1. 카드(페이지)를 추가·복제·삭제·순서 변경하고 한 문서 안에서 1:1·4:5·9:16 규격을 선택한다.
2. 카드 캔버스의 텍스트를 더블클릭하면 별도 Inspector 이동 없이 그 자리에서 인라인 수정한다.
3. 규격을 바꿔도 텍스트·로고의 상대 좌표/크기가 유지되며, 모든 카드 편집은 `EditorSession.dispatch(Command)`를 경유하고 undo/redo된다.
4. G-19 템플릿/마스터 스타일과 G-21 export가 소비할 안정적인 페이지·요소 ID와 순서를 제공한다.

#### 현재 상태 실사 (2026-07-14)
- `CardDocument`/`CardPage`/카드 편집 화면/카드 command는 코드 검색 0건이다. 기존 `Timeline`/`Clip`은 시간축 편집 모델이고 카드 페이지 시퀀스를 표현하지 않는다.
- 재사용 블록은 `CanvasPreset`의 1:1·4:5·9:16, `TextClipContent`/`TextOverlayPixelProcessor`, 이미지 클립 G-15이며 전용 카드 워크플로우로 배선되지 않았다.
- 따라서 UB-C1/C3/C4와 SC-C1의 기능 전제조건이 없고 현재 판정은 ❌다.

#### 데이터 모델 (A5)
```swift
public struct CardDocument: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var format: CardFormat                 // legacy decode default: .square
    public var pages: [CardPage]
    public var masterStyle: CardMasterStyle?      // G-19, optional
}
public enum CardFormat: String, Codable, Sendable { case square, portrait, story } // 1:1, 4:5, 9:16
public struct CardPage: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var role: CardPageRole                 // cover/body/emphasis/closing
    public var elements: [CardElement]
    public var duration: TimeInterval?            // G-21 영상화, nil = default
}
public struct CardElement: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var kind: CardElementKind              // text/image/logo
    public var normalizedFrame: NormalizedRect    // 규격 독립 0...1 좌표
    public var text: TextClipContent?
    public var mediaAssetID: UUID?
}
```
- 기존 MovieCut 프로젝트에 `cardDocument: CardDocument?`를 optional로 추가하며, 누락 시 `nil`로 decode하는 legacy fixture 테스트를 의무화한다.

#### 구현 증분
| Inc | 내용 | 파일 |
|---|---|---|
| 1 | 모델+command: `CardDocument`/페이지/요소 타입과 Add/Duplicate/Delete/Move/UpdateCardElement command. 프로젝트 optional 저장+legacy decode+undo snapshot 테스트 | `Sources/MovieCutCore/Models/`, `Commands/`, 모델 테스트 |
| 2 | Mac 카드 편집기: 페이지 썸네일 레일, 추가/복제/삭제/드래그 순서 변경, 규격 picker. ViewModel API는 전부 `EditorSession.dispatch(Command)` | `App/MovieCutMac/CardNews/`, `EditorViewModel.swift` |
| 3 | 캔버스: normalized layout, 텍스트 더블클릭 인라인 편집, 이미지 교체. 편집 완료를 단일 command/undo로 확정 | `CardCanvasView.swift` |
| 4 | DEBUG 하니스: 5장 생성→복제/삭제/재정렬→규격 3종 전환→인라인 텍스트 변경 후 프로젝트 저장/재로드 상태 dump | `UITestHarness.swift`, `scripts/run_e2e_export.sh` |

#### AC (측정 가능 — UB 목표값 원문 고정)
1. UB-C1: **“카드(페이지) 추가/복제/삭제/순서 변경이 각각 ≤2클릭”** — 하니스 액션 카운터에서 네 동작 각각 2 이하, 결과 페이지 ID/순서 일치.
2. UB-C3: **“규격 프리셋 1:1·4:5·9:16, 규격 전환 시 텍스트·로고 상대 배치 유지”** — 3종 전환 전후 모든 요소 normalized frame 오차 ≤0.001.
3. UB-C4: **“카드 위 텍스트 더블클릭 → 그 자리 인라인 수정”**, 목표 **“더블클릭 1회”** — 실제 캔버스 이벤트 후 동일 element ID의 텍스트 변경과 undo 1회 복원을 E2E 상태로 기록.
4. SC-C1: **“≤10분, 막힘 0 / P-반복 ≤5분”** — 기능 전제 완성 후 화면 녹화+타임스탬프 사용자 시나리오로 판정하며 자동 완료 선언하지 않는다.
5. 구버전 프로젝트 JSON이 `cardDocument == nil`로 decode되고 기존 timeline/export 골든이 비트 동일하다.

#### 검증 계획
- `CardDocumentCommandTests`: 네 페이지 동작, 순서/ID 결정성, single-step undo/redo, legacy decode.
- `CardLayoutTests`: 1:1↔4:5↔9:16 normalized-frame 보존.
- 앱 E2E: DEBUG 하니스의 click count + 저장/재로드 dump. SC-C1 시간/막힘은 `[사용자 확인 대기]`로 별도 녹화한다.

#### 리스크
- timeline `Project`에 카드 모델을 섞으면 기존 저장 포맷과 UI 상태가 복잡해진다. optional 최상위 필드와 명시적 editor mode로 격리한다.
- 인라인 편집 중 IME 조합 텍스트를 command마다 dispatch하면 undo가 폭증한다. 조합 중 로컬 draft, commit 시 command 1회로 처리한다.
- absolute pixel 좌표는 규격 전환 시 파손되므로 normalized frame을 source of truth로 고정한다.

---

### G-19. 카드 템플릿 세트 + 마스터 스타일 — **P0 / 카드뉴스 핵심 경로** / 규모 L ⭐

> 대응 기준: UB-C2/C5, SC-C1. 표지/본문/강조/마무리가 한 세트인 템플릿 10종과 전 카드 일괄 스타일을 제공한다.

#### 요구사항
1. 최소 10개 템플릿 세트가 각각 cover/body/emphasis/closing 페이지 구성을 제공하고 선택 즉시 편집 가능한 5장 초안을 만든다.
2. 마스터 폰트·색·로고 위치 변경을 한 번 확정하면 전 카드의 상속 요소에 반영한다. 페이지별 override는 유지/해제할 수 있다.
3. 템플릿 적용과 마스터 변경은 각각 atomic command로 undo 1회에 복원한다.

#### 현재 상태 실사 (2026-07-14)
- `TextTemplate.builtIn` 14종은 단일 timeline 텍스트 클립 프리셋이며 다중 페이지 세트/카드 role/마스터 상속이 없다.
- `CardTemplateSet`/`CardMasterStyle`/전 카드 스타일 적용 소비처는 0건이다. UB-C2/C5와 SC-C1의 템플릿 전제는 ❌다.

#### 데이터 모델 (A5)
```swift
public struct CardTemplateSet: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var pages: [CardTemplatePage]          // cover/body/emphasis/closing 포함
    public var defaultMasterStyle: CardMasterStyle
}
public struct CardMasterStyle: Codable, Sendable, Equatable {
    public var fontFamily: String
    public var primaryColorHex: String
    public var secondaryColorHex: String
    public var logoPlacement: NormalizedRect?
}
```
- G-18 `CardDocument.masterStyle`은 optional이고 구버전/미설정 decode 시 템플릿 기본값을 런타임에서 사용한다. 페이지 override도 optional로 추가한다.

#### 구현 증분
| Inc | 내용 | 파일 |
|---|---|---|
| 1 | 템플릿/마스터 모델, 상속·override resolver, ApplyTemplateSet/SetMasterStyle atomic commands와 legacy decode 테스트 | `Sources/MovieCutCore/CardNews/`, `Commands/` |
| 2 | 결정적 내장 세트 10종(각 cover/body/emphasis/closing 완비), thumbnail fixture와 manifest 검증 | `Templates/BuiltinCardTemplates.swift`, resources |
| 3 | 템플릿 갤러리와 마스터 스타일 패널. 선택→적용 및 폰트·색·로고 변경을 command-backed API로 배선 | `App/MovieCutMac/CardNews/` |
| 4 | 실제 앱 하니스: 10종 enumerate, 1종으로 5장 생성, master 변경→5장 렌더 상태/undo dump | `UITestHarness.swift`, `scripts/run_e2e_export.sh` |

#### AC (측정 가능 — UB 목표값 원문 고정)
1. UB-C2: **“일관 세트 템플릿 ≥10종”**, **“선택→적용 ≤2클릭”** — manifest/runtime 모두 정확히 10종 이상, 하니스 click count 2 이하.
2. 각 세트에 표지/본문/강조/마무리 role이 모두 존재하고 5장 생성 후 비어 있는 필수 텍스트/이미지 슬롯 0건.
3. UB-C5: **“일괄 스타일(마스터 스타일): 폰트·색·로고 위치 변경 1회가 전 카드에 반영, ≤3클릭”** — 8장 fixture에서 세 속성 모두 전파되고 click count 3 이하.
4. SC-C1: 템플릿 선택부터 5장 교체/export까지 **“≤10분, 막힘 0 / P-반복 ≤5분”** — G-18/G-21 완료 후 사용자 녹화로 판정.
5. 템플릿 적용/마스터 변경 각각 undo 1회로 exact document snapshot 복원.

#### 검증 계획
- `CardTemplateTests`: 10종 수/role/필수 slot/결정적 ID, resolver override 우선순위, legacy decode.
- `CardMasterStyleCommandTests`: 8장 전파와 single-step undo.
- 앱 E2E click counter + 5장 render-state dump; SC-C1은 `[사용자 확인 대기]`.

#### 리스크
- 10종을 이름만 바꾼 복제본으로 채우면 일관 세트 요구를 형식적으로만 통과한다. 레이아웃/타이포/색 토큰 fingerprint 중복을 테스트로 제한한다.
- 마스터와 page override의 우선순위가 불명확하면 일괄 변경이 일부 카드에 조용히 누락된다. 상속 여부를 UI에 표시하고 resolver를 단일화한다.
- 로고 media 참조는 프로젝트 이동 시 깨질 수 있어 G-20 자산 복사 정책과 정렬한다.

---

### G-20. 브랜드 킷 — **P1 / 반복 사용자 필수** / 규모 M

> 대응 기준: UB-C6, SC-C2. 로고·브랜드 색·폰트를 프로젝트 밖 저장소에 보존하고 새 카드 문서에 빠르게 적용한다.

#### 요구사항
1. 이름 있는 브랜드 킷에 로고 자산, primary/secondary/accent 색, heading/body 폰트를 저장·편집·삭제한다.
2. 다른 프로젝트에서 저장된 킷을 선택해 G-19 마스터 스타일과 모든 카드의 브랜드 슬롯에 적용한다.
3. 로고 파일은 security-scoped 외부 URL에만 의존하지 않고 App Support 저장소에 복사해 재실행 후에도 유효해야 한다.

#### 현재 상태 실사 (2026-07-14)
- `BrandKit`/브랜드 저장소/적용 command는 코드 검색 0건이다. 사용자 텍스트 스타일 preset은 단일 텍스트 스타일이고 로고/색/프로젝트 간 묶음 재사용을 제공하지 않는다.
- UB-C6 및 SC-C2의 기능 전제조건이 없어 현재 ❌다.

#### 데이터 모델
```swift
public struct BrandKit: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var logoAssetFilename: String?
    public var colors: BrandColors
    public var headingFontFamily: String
    public var bodyFontFamily: String
    public var updatedAt: Date
}
```
- `BrandKitStore`는 App Support의 versioned JSON + copied logo assets를 관리한다. `CardDocument`에는 적용 당시 `brandKitID: UUID?`와 optional inline snapshot을 저장해 외부 저장소 삭제 후에도 렌더를 보존하고 legacy decode를 검증한다.

#### 구현 증분
| Inc | 내용 | 파일 |
|---|---|---|
| 1 | `BrandKit`/versioned store: CRUD, atomic file replace, logo copy, 손상 JSON 격리와 migration/legacy decode 테스트 | `App/MovieCutMac/CardNews/BrandKitStore.swift` |
| 2 | ApplyBrandKit command: G-19 master style/브랜드 slot 갱신, 8장 atomic undo | `Sources/MovieCutCore/Commands/`, `EditorViewModel.swift` |
| 3 | 브랜드 킷 관리/적용 UI와 접근성, 새 카드 프로젝트 생성 경로에 최근 킷 제안 | `App/MovieCutMac/CardNews/` |
| 4 | 재실행 E2E: 킷 저장→앱 재실행→새 문서 8장 적용→폰트/색/logo hash dump | `UITestHarness.swift`, `scripts/run_e2e_export.sh` |

#### AC (측정 가능 — UB 목표값 원문 고정)
1. UB-C6: **“로고·브랜드 색·폰트 저장, 새 프로젝트 적용 ≤2클릭”** — 재실행 후 새 문서 적용 click count 2 이하, 8장 모두 동일 logo hash/색/폰트 resolver 결과.
2. SC-C2: **“브랜드 킷 적용 → 8장 제작 → 일괄 스타일 1회 변경(폰트+색) → export”**, 목표 **“≤5분”** — G-19/G-21 완료 후 사용자 녹화로 판정.
3. 로고 원본 이동/삭제 뒤에도 copied asset으로 8장 렌더가 성공하고, store 삭제 뒤 이미 저장된 문서는 inline snapshot으로 동일하게 열린다.
4. ApplyBrandKit undo 1회로 문서 전체가 exact snapshot 복원되고 redo 1회로 재적용된다.

#### 검증 계획
- `BrandKitStoreTests`: CRUD/재실행/원본 삭제/손상 파일/migration.
- `ApplyBrandKitCommandTests`: 8장 전파, snapshot fallback, undo/redo.
- 앱 컨텍스트 재실행 E2E + click counter. SC-C2 시간은 `[사용자 확인 대기]`.

#### 리스크
- 사용자 폰트가 다른 Mac에 없으면 레이아웃이 달라진다. 폰트 이름과 fallback을 함께 저장하고 missing-font 경고를 노출한다.
- 로고 복사본 정리 시 사용 중 자산 삭제 위험이 있다. 문서 snapshot 참조를 검사하는 보수적 GC만 허용한다.
- 전역 store 변경은 timeline 프로젝트 저장과 별도이므로 실패/동시 쓰기를 atomic replace로 막는다.

---

### G-21. 카드 일괄 export + 원클릭 영상화 — **P0 / 출력 완성** / 규모 L ⭐

> 대응 기준: UB-C7/C8, SC-C3. 카드 세트를 순번 이미지 파일로 일괄 출력하고 동일 문서를 기본 duration·전환·BGM 슬롯이 있는 9:16 영상으로 변환·export한다.

#### 요구사항
1. 모든 카드를 PNG 또는 JPG로 한 번에 렌더해 선택 폴더에 순번 파일명으로 기록한다. 1:1·4:5·9:16 픽셀 규격과 색 공간을 검증한다.
2. “Export as Video” 한 번으로 카드별 기본 duration, 기본 전환, optional BGM 슬롯을 적용한 9:16 timeline/export package를 만든다.
3. 이미지 세트와 영상은 G-18/G-19/G-20의 resolved layout을 같은 renderer로 소비해 preview/output 차이를 막는다.

#### 현재 상태 실사 (2026-07-14)
- `ExportEngine`의 video/GIF/still 경로와 G-15 이미지 클립은 있으나 `CardDocument` 전체 페이지 renderer, 순번 이미지 세트 writer, 카드→영상 orchestration은 0건이다.
- UB-C7/C8 및 SC-C3의 결과물 생성 경로가 없어 현재 ❌다.

#### 데이터/서비스 경계
```swift
public struct CardImageExportOptions: Sendable, Equatable {
    public var format: CardImageFormat            // png/jpeg
    public var scale: Double
    public var filenamePrefix: String
}
public struct CardVideoPlan: Sendable, Equatable {
    public var pageDuration: TimeInterval
    public var transition: TransitionType
    public var bgmAssetID: UUID?
    public var canvasPreset: CanvasPreset         // 항상 9:16
}
```
- export는 문서를 변형하지 않는 서비스다. “timeline으로 열기”를 제공할 경우 생성 프로젝트 전체를 단일 command/snapshot으로 교체하며 app caller+E2E를 같은 커밋에 둔다(A6).

#### 구현 증분
| Inc | 내용 | 파일 |
|---|---|---|
| 1 | shared `CardPageRenderer`: resolved page→CGImage, 1:1/4:5/9:16 결정적 해상도/색공간, golden pixel tests | `Sources/MovieCutCore/Rendering/` 또는 앱 renderer seam |
| 2 | `CardImageSetExporter`: PNG/JPG, zero-padded 순번 파일명, temp directory 후 atomic move, 실패 cleanup | `App/MovieCutMac/CardNews/Export/` |
| 3 | `CardVideoPlanner`: 페이지 render→G-15 image clips, 기본 duration/transition/BGM slot, 9:16 export package. app caller+DEBUG E2E 동반 | Core planner + `EditorViewModel.swift` + `UITestHarness.swift` |
| 4 | export UI와 `scripts/run_e2e_export.sh` card smoke: 장수·해상도·파일명·video duration/transition metadata/9:16 ffprobe | CardNews UI, scripts |

#### AC (측정 가능 — UB 목표값 원문 고정)
1. UB-C7: **“전 카드 PNG/JPG 일괄 export (순번 파일명, 인스타 규격 검증)”** — 5장 입력에서 PNG/JPG 각각 정확히 5파일, `card_01...card_05`, 누락/중복 0, 1:1=1080×1080·4:5=1080×1350·9:16=1080×1920.
2. UB-C8: **“원클릭 영상화: 카드당 기본 duration+전환+BGM 슬롯이 자동 적용된 9:16 영상 export”** — 하니스 1 action 뒤 ffprobe 1080×1920, duration=`pageCount×defaultDuration - transition overlaps` ±1 frame, 전환 수=`pageCount-1`, BGM slot 상태 기록.
3. SC-C3: **“완성된 카드 세트 → 원클릭 9:16 슬라이드쇼 영상 export”**, 목표 **“조작 ≤1분(렌더 시간 제외)”** — 기능 E2E 후 사용자 녹화로 판정.
4. 5장 image set과 video의 각 카드 중앙 frame perceptual hash가 shared renderer golden 허용 오차 안에서 일치한다.
5. 부분 실패 시 최종 폴더에 불완전 세트가 남지 않고 재시도 성공한다.

#### 검증 계획
- `CardPageRendererGoldenTests`, `CardImageSetExporterTests`(장수/해상도/순번/cleanup), `CardVideoPlannerTests`(duration/transition/BGM).
- 실제 앱 E2E로 PNG/JPG set probe와 ffprobe video smoke를 `run_e2e_export.sh`에 상설한다.
- SC-C3 조작 시간은 `[사용자 확인 대기]`.

#### 리스크
- 5~10장의 1080p 이미지를 동시에 메모리에 두면 피크가 커진다. 페이지 단위 streaming write와 autorelease pool을 사용한다.
- JPEG alpha/색공간 차이와 폰트 fallback이 이미지·영상 불일치를 만들 수 있다. renderer와 color space를 공유한다.
- 영상화가 G-15 임시 segment 수명에 의존하므로 export 완료까지 강한 참조와 실패 cleanup을 보장한다.

---

### G-22. 대본 자동 카드 분배 — **P2 / 차별화** / 규모 M

> 대응 기준: UB-C9, SC-C4. 붙여넣은 대본을 문단 단위 카드 초안으로 분배하고 선택적으로 온디바이스 요약하되 문안 창작은 하지 않는다.

#### 요구사항
1. 대본 붙여넣기 시 빈 줄/문단 경계를 보존해 카드 후보를 만들고 cover/body/closing role을 결정적으로 배정한다.
2. 긴 문단은 온디바이스 요약 또는 길이 기반 분할을 선택할 수 있으며 원문과 매핑을 보존한다. 새로운 주장/문안 생성은 범위 밖이다.
3. 미리보기에서 분배 결과를 수정한 뒤 G-18 문서로 한 번에 적용하며 undo 1회로 원복한다.

#### 현재 상태 실사 (2026-07-14)
- 대본→문단 parser/카드 분배/요약 provider/적용 UI는 0건이다. `AssistantCommandParser`와 자막 segment는 목적과 모델이 달라 재사용 소비처가 없다.
- UB-C9/SC-C4의 전제 기능이 없어 현재 ❌다.

#### 데이터 모델
```swift
public struct ScriptCardDraft: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var sourceParagraphRange: Range<Int>
    public var sourceText: String
    public var proposedText: String
    public var role: CardPageRole
    public var wasSummarized: Bool
}
public protocol OnDeviceScriptSummarizer: Sendable {
    func summarize(_ paragraph: String, maxCharacters: Int) async throws -> String
}
```
- draft는 적용 전 비영속 상태다. 적용 후에는 G-18 `CardPage`/`CardElement`만 저장하므로 새 Codable 필드는 만들지 않는다.

#### 구현 증분
| Inc | 내용 | 파일 |
|---|---|---|
| 1 | 결정적 paragraph parser/distributor: 빈 줄, 목록, 최대 글자 수, cover/closing 규칙과 한국어/영어 fixture tests | `Sources/MovieCutCore/CardNews/ScriptCardDistributor.swift` |
| 2 | 온디바이스 summarizer seam + 원문 보존/실패 시 비요약 fallback. 문안 생성 금지 guard | `App/MovieCutMac/CardNews/` |
| 3 | paste→preview→2장 수정→Apply UI. 적용은 G-18 batch command 1회 | CardNews UI, `EditorViewModel.swift` |
| 4 | DEBUG 하니스: 대본 paste→draft count/source ranges→2장 수정→export-ready 5장 document dump | `UITestHarness.swift`, scripts |

#### AC (측정 가능 — UB 목표값 원문 고정)
1. UB-C9: **“대본 붙여넣기 → 문단 단위 자동 카드 분배 (+온디바이스 요약·분배, 문안 창작은 범위 밖)”** — fixture의 모든 문단이 정확히 한 source range에 매핑되고 누락/중복 0, 생성 문장이 원문/요약 provider 결과 밖에 없음.
2. SC-C4: **“대본 텍스트 붙여넣기 → 자동 카드 분배 → 2장 수정 → export”**, 목표 **“≤5분”** — G-21 완료 후 사용자 녹화로 판정.
3. Apply undo 1회로 기존 CardDocument exact snapshot 복원, redo 1회로 동일 page/element ID 재생성.
4. summarizer unavailable/error 상태에서도 결정적 비요약 분배로 5장 문서를 만들고 다음 행동 안내를 표시한다.

#### 검증 계획
- `ScriptCardDistributorTests`: 한국어/영어/목록/빈 문단/긴 문단, source mapping, 결정성.
- fake summarizer behavioral tests로 요약/오류 fallback과 창작 금지 경계를 검증한다.
- 앱 E2E 상태 dump + G-21 export smoke 연계. SC-C4 시간은 `[사용자 확인 대기]`.

#### 리스크
- 요약 모델 가용성/OS 버전 차이로 결과가 비결정적일 수 있다. E2E는 fake provider, 실기기는 품질 표본을 별도로 기록한다.
- 한국어 문단/목록 구분이 줄바꿈 습관에 민감하다. 원문 range를 보존해 사용자가 쉽게 병합/분할하게 한다.
- 자동 분배가 문안 생성으로 확장되지 않도록 provider 계약과 UI 카피에 범위를 명시한다.

---

## 5. UI 명세 (U-ID) — v1.1 신설 (2026-07-03)

> 근거 분석: `GAP_ANALYSIS_V8_FUNC_UI_20260704.md` §4~§9. UI 트랙은 기능 S-마일스톤과 **병행 슬롯**으로 실행한다.
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
- `Track.isMuted`/`isHidden`은 UI 배선됨.
- V8 정정: ~~`Track.isLocked`는 모델만 존재하는 dead model field~~ 가 아니다. `TimelineView.swift`에 lock/open 헤더 버튼이 있고, `EditorViewModel.toggleTrackLock(_:)`가 `SetTrackPropertyCommand(.isLocked)`를 호출하며, Core command support가 locked track edit을 거부한다.
- 잔여: 잠긴 트랙의 감광/워터마크 같은 시각 상태, drop target 제외/실조작 검증, 트랙 높이 프리셋은 아직 없다. `trackHeight`는 고정 상수다.

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

#### 현재 상태 (V8 실사)
- `MediaLibraryPanel.swift`에는 10개 rail tab(Media/Audio/Text/Captions/Stickers/Effects/Transitions/Filters/Adjust/Smart), `LazyVGrid(columns: libraryGridColumns)`, `browserGridCard`, Effects/Filters/Adjustments/Transitions hover preview surface가 이미 있다. 따라서 V7의 브라우저 격차는 일부 축소됐다.
- 잔여는 별도 `BrowserCard` 공통 컴포넌트화, G-07 20종 이펙트 썸네일/라이브 프리뷰, G-08 실제 음악/SFX/스티커 팩 콘텐츠, Captions 스타일 카드(G-01 완료 후)다.
- U-07을 "브라우저가 없음"으로 재보고하지 말고, G-07/G-08/G-01 UI와 병합되는 제품화 항목으로 다룬다.

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

검증 기록:
- 2026-07-06 U-08 Inc 1~2: `scripts/ui_capture.sh`와 `scripts/ui_regression.sh`를 추가해 Debug `MovieCutMac.app`을 deterministic populated harness(`MOVIECUT_UITEST_IMPORT` + `MOVIECUT_UITEST_TEXT_TEMPLATE_NAME=Title`)로 실행하고, 실제 창을 `screencapture`로 캡처한 뒤 normalized PNG dHash로 `Tests/UIEvidence/golden_populated_editor.png`와 비교한다. 산출물은 `artifacts/ui/`에 저장하고 `.gitignore`로 제외, committed evidence는 `Tests/UIEvidence/`로 분리했다. 검증: `scripts/ui_regression.sh --update-golden` PASS, `scripts/ui_regression.sh` PASS(distance=0/threshold=4), 임시 golden negate 이빨 확인 FAIL(distance=56/threshold=4) 후 복원 PASS, `swift build` PASS, `swift test --filter 'UIRegression|StaticContract|Golden'` PASS, Mac `xcodebuild` PASS, `scripts/run_e2e_export.sh` PASS. Caveat: 현재 committed golden은 populated editor 1종이며, 4표면 확장과 Inc 3 클릭수 metric은 [진행중].

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

### U-10. 카드뉴스 진입점 — **P1 / 반복 사용자 필수** / 규모 S

> 대응 기준: SC-C1 첫 단계와 UB-C2 템플릿 선택 경로. 앱 시작/신규 프로젝트에서 영상 편집과 카드뉴스 제작을 명확히 분기한다.

#### 요구사항
1. 홈 또는 New Project 표면에 “Card News” 주 진입점을 제공하고 선택 즉시 G-19 템플릿 갤러리로 이동한다.
2. 1:1·4:5·9:16 빠른 시작과 빈 카드 문서 선택지를 제공하며 영상 프로젝트 생성 흐름을 회귀시키지 않는다.
3. DEBUG/UITest 하니스는 기존 editor 직행을 유지하고 별도 env로 카드 진입을 자동화한다.

#### 현재 상태 실사 (2026-07-14)
- `MovieCutMacApp`은 `ContentView` 영상 에디터로 직행하고 U-01 홈도 미구현이다. “card/card news” 신규 프로젝트 분기와 카드 템플릿 갤러리 라우팅은 0건이다.
- 따라서 SC-C1 시작점 전제와 카드 템플릿 발견 경로가 없어 현재 ❌다.

#### 상태/라우팅 모델
```swift
enum ProjectCreationMode: Sendable, Equatable { case video, cardNews }
enum AppStage: Sendable, Equatable { case home, videoEditor, cardEditor }
```
- 앱 일시 상태이며 프로젝트 Codable 필드 추가 없음. U-01이 먼저 도입되면 같은 `AppStage`를 확장하고, 아니면 New Project sheet의 로컬 route로 시작해 중복 router를 만들지 않는다.

#### 구현 증분
| Inc | 내용 | 파일 |
|---|---|---|
| 1 | New Project chooser: Video/Card News, 접근성 label/hint/keyboard focus, 기존 File > New 회귀 방지 | `MovieCutMacApp.swift`, `ContentView.swift` |
| 2 | Card News 선택→G-19 템플릿 갤러리/규격 quick start→G-18 editor routing | `App/MovieCutMac/CardNews/` |
| 3 | DEBUG 하니스 `MOVIECUT_UITEST_CARD_ENTRY=1`: cold launch→card chooser→template gallery route/click count 상태 기록 | `UITestHarness.swift`, scripts |

#### AC (측정 가능 — UB 목표값 원문 고정)
1. cold launch에서 카드뉴스 템플릿 갤러리까지 마우스 2클릭 이하, 키보드만으로도 도달하고 VoiceOver label/hint가 존재한다.
2. UB-C2의 **“선택→적용 ≤2클릭”** 경로를 U-10→G-19 경계에서 유지한다(갤러리 진입 후 선택·적용 2 이하를 별도 집계).
3. SC-C1: **“카드뉴스 템플릿 선택 → 5장 텍스트/이미지 교체 → 1:1 PNG 세트 export”**, 목표 **“≤10분, 막힘 0 / P-반복 ≤5분”** — G-18/G-19/G-21 완료 후 사용자 녹화로 판정.
4. 기존 video New Project와 `MOVIECUT_UITEST` editor 직행 E2E가 무회귀다.

#### 검증 계획
- route reducer/chooser behavioral test, keyboard/accessibility UI contract, actual app harness route/click log.
- `scripts/run_e2e_export.sh` 기존 video smoke와 별도 card-entry smoke를 모두 실행한다.
- SC-C1 시간/막힘은 `[사용자 확인 대기]`.

#### 리스크
- U-01 홈보다 먼저 만들면 나중에 진입 UI를 두 번 구현할 수 있다. routing state와 chooser component를 재사용 가능하게 격리한다.
- 카드 기능이 미완인 동안 노출하면 막다른 화면이 된다. G-18/G-19 최소 편집 경로와 같은 릴리스 게이트로 묶는다.
- 기존 E2E가 홈/chooser에서 멈추지 않도록 UITest 직행 환경변수 우선순위를 고정한다.

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
