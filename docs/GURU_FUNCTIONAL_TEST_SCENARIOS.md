# MovieCut NLE 코어 엔진 아키텍처 리팩터링(1차·2차) 기능 및 성능 검증 테스트 시나리오

본 문서는 1차(`49a0668`) 및 2차(GURU Refactoring Plan V2) 아키텍처 리팩터링으로 변경된 **5대 코어 도메인(렌더링, 미디어 I/O, 타임라인/동시성, 오디오 DSP, UI/UX)**의 기능적 무결성(Functional Parity)과 성능 목표 달성 여부를 검증하기 위한 **자동화(CLI) 및 수동(In-App QA) 테스트 시나리오 명세서**입니다.

---

## Part 1. 타겟팅 자동화 유닛/골든 테스트 시나리오 (Targeted CLI Tests)

> [!IMPORTANT]
> 과도한 전체 테스트 실행을 피하기 위해, 수정된 모듈과 직결된 핵심 유닛 테스트만 `--filter`로 개별 실행하여 **수치/픽셀 정합성(Regression Zero)**을 즉시 검증합니다.

| 시나리오 ID | 검증 도메인 및 대상 파일 | 실행 명령어 (`swift test --filter`) | 합격 기준 (Pass Criteria) |
| :--- | :--- | :--- | :--- |
| **UT-01** | **1D 분리형 커브 평가 & 3D LUT** (`CurveEvaluator.swift`, `ColorGradePixelProcessor.swift`) | `swift test --filter CurveEvaluatorTests`<br>`swift test --filter ColorGradeGoldenTests` | • `prepare` + `evaluatePrecomputed` 결과가 기존 단조 3차 에르미트 보간값과 $10^{-12}$ 이내 일치<br>• 마스터+RGB 커브 합성 3D LUT 골든 이미지 픽셀 오차 0 |
| **UT-02** | **HSL 8밴드 3D Cube 빌더** (`HSLCubeBuilder.swift`) | `swift test --filter HSLCubeBuilderTests` | • Identity 밴드 사전 필터링(`activeBands`) 후에도 단일/복합 밴드 색상 변환 결과가 기존과 100% 일치 |
| **UT-03** | **자막 오버레이 `NSCache` & 카라오케** (`TextOverlayPixelProcessor.swift`) | `swift test --filter TextOverlayPixelProcessorTests`<br>`swift test --filter StyledCaptionWordTimingTests` | • 동일 상태 자막 반복 호출 시 캐시 히트된 `CIImage`가 첫 렌더와 동일한 픽셀 출력<br>• 카라오케 단어 타이밍 경계 통과 시 캐시 키가 갱신되어 하이라이트 색상이 즉시 반영됨 |
| **UT-04** | **컬러 스코프 단일 패스(`analyzeAll`)** (`ScopeAnalyzer.swift`) | `swift test --filter ScopeAnalyzerTests` | • `analyzeAll`이 반환한 Histogram, Waveform, Vectorscope, RGB Parade가 개별 함수 4회 호출 결과와 완전히 일치 |
| **UT-05** | **정적/Ken Burns 이미지 비디오 렌더링** (`ImageVideoRenderService.swift`) | `swift test --filter ImageVideoRenderScaleTests`<br>`swift test --filter KenBurnsEffectTests` | • `kenBurnsEffect == nil`에서 단일 `CVPixelBuffer` 재사용으로 생성된 `.mp4` 세그먼트의 총 프레임 수·해상도·픽셀 정상 출력<br>• `kenBurnsEffect != nil`에서 프레임별 줌/팬 보간 정상 동작 |
| **UT-06** | **`CMTime` 키프레임 정규화 & `EditorSession` Undo Cap** (`Project.swift`, `EditorSession.swift`) | `swift test --filter KeyframeBezierTests`<br>`swift test --filter EditorSessionRevisionTests`<br>`swift test --filter UndoIntegrityTests` | • `CMTime`(timescale 600) 기반 근접 키프레임 병합 정상 동작<br>• `undoStack` 상한(200) 적용 후에도 `commandCount`, `undo()`, `redo()`, `revision` 단조 증가 계약 유지 |
| **UT-07** | **Zero-Allocation 라우드니스 & 오디오 믹스** (`AudioGraphLoudness.swift`, `AudioGraphRendering.swift`) | `swift test --filter AudioGraphLoudnessTests`<br>`swift test --filter AudioGraphRenderingTests`<br>`swift test --filter AudioGraphEngineNullTests` | • `Oversampler.pushAndMaxAbs` 및 `Analyzer.pushFrame` 적용 후 BS.1770-4 통합 LUFS 및 4× True Peak(dBTP) 측정값이 기존 기준값과 소수점 오차 없이 일치<br>• Dictionary 인덱싱 적용 후 오프라인 렌더러-실시간 엔진 간 Null Test 통과 |
| **UT-08** | **필름스트립 계획 & 타임라인 스크러빙** (`TimelineFilmstripStore.swift`, `PlaybackEngine.swift`) | `swift test --filter FilmstripPlanningTests`<br>`swift test --filter TimelineScrubBehaviorTests` | • 뷰포트 버킷 변경 시 불필요한 작업 재시작 없이 증분 프레임만 로드<br>• 스크러빙 시 최신 타겟 시간으로 수렴 |

---

## Part 2. 도메인별 인앱(In-App) 기능 및 엣지 케이스 검증 시나리오

### Domain 1. 렌더링 및 컴포지션 파이프라인 (Render Graph & Compositing)

#### TC-R01: RGB 커브 및 HSL 슬라이더 실시간 드래그 반응성 & 스코프 연동
* **전제 조건**: 1080p 또는 4K 비디오 클립 1개를 타임라인에 배치하고 선택하여 우측 인스펙터의 **Color** 탭 및 **Scopes(Histogram / Waveform / Vectorscope / RGB Parade)**를 활성화합니다.
* **테스트 절차**:
  1. RGB 커브(Master, Red, Green, Blue)에 제어점을 추가하고 마우스로 초당 60회 이상 빠르게 원을 그리듯 드래그합니다.
  2. HSL 8개 색상 밴드 중 Red, Blue의 Hue/Saturation/Luminance 슬라이더를 연속으로 왕복 드래그합니다.
  3. 설정된 커브 포인트를 고정한 상태에서 타임라인을 재생합니다.
* **기대 결과**:
  - 드래그 중(LUT 캐시 미스 구간)에도 1D 분리형 LUT 최적화 덕분에 메인 스레드 프리징 없이 프리뷰 화면과 4종 컬러 스코프(`analyzeAll`)가 즉시 갱신되어야 합니다.
  - 재생 중(LUT 캐시 히트 구간)에는 `curveCubeCache` / `hslCubeCache`에서 3D LUT가 재사용되어 프레임 드랍 없이 재생되어야 합니다.

#### TC-R02: 정적 자막 캐싱 vs 애니메이션/카라오케 자막 동적 갱신
* **전제 조건**: 비디오 클립 위에 (A) 일반 정적 자막 클립(5초), (B) 페이드인 애니메이션 자막 클립(3초), (C) 카라오케(`karaokeEnabled = true`, 단어별 `wordTimings` 보유) 자막 클립(5초)을 배치합니다.
* **테스트 절차**:
  1. (A) 정적 자막 구간을 재생 및 익스포트합니다.
  2. (A) 정적 자막의 폰트 색상이나 위치를 인스펙터에서 변경합니다.
  3. (B) 애니메이션 자막 구간과 (C) 카라오케 자막 구간을 프레임 단위로 스크러빙 및 재생합니다.
* **기대 결과**:
  - (A) 정적 자막 구간에서는 첫 프레임 래스터화 이후 `TextOverlayPixelProcessor.overlayCache`가 히트되어 추가 `CGContext` 생성 없이 동일한 자막이 선명하게 합성됩니다.
  - 자막 속성(색상/위치/텍스트)을 수정하면 즉시 캐시 키가 달라져 변경된 스타일이 프리뷰에 반영됩니다(Stale 캐시 잔상 없음).
  - (B), (C) 구간에서는 진행률(`state.opacity`, `state.translation`) 또는 활성 카라오케 단어 인덱스(`activeKaraokeIndex`)가 변할 때마다 정확히 새 프레임이 그려져 애니메이션과 단어 하이라이트가 누락 없이 동작합니다.

---

### Domain 2. 디코딩, 인코딩 및 미디어 I/O (Hardware Acceleration & Media I/O)

#### TC-M01: 정적 이미지 클립 고속 렌더링 및 프리뷰 세그먼트 캐시 재사용
* **전제 조건**: 고해상도 사진(예: 4000×3000 JPG/HEIC) 3장을 타임라인에 각각 5초 길이로 추가합니다.
  - 클립 1: `Ken Burns` 비활성화 (정적 이미지)
  - 클립 2: `Ken Burns` 활성화 (`startScale: 1.0 -> endScale: 1.3`)
* **테스트 절차**:
  1. 최초 타임라인 로드 시 클립 1과 클립 2가 정상적으로 프리뷰에 표시되는지 확인합니다.
  2. 사진 클립과 무관한 다른 비디오/오디오 클립의 볼륨을 조절하거나 자막을 추가하여 `rebuildPreviewComposition`을 5회 연속 발생시킵니다.
  3. 클립 1에 `Ken Burns` 효과를 새로 켜거나 지속 시간을 5초에서 8초로 늘립니다.
* **기대 결과**:
  - 절차 1에서 클립 1은 첫 프레임 `CVPixelBuffer`를 150프레임 동안 재사용하여 즉시 인코딩되고, 클립 2는 부드러운 줌인 애니메이션으로 렌더링됩니다.
  - 절차 2에서 `PlaybackEngine.cachedImagePreviewSegments`가 히트되어 사진 클립 3장을 재인코딩하지 않고 **즉시(0ms 지연)** 프리뷰 컴포지션이 리빌드됩니다.
  - 절차 3에서 클립 1의 `ImagePreviewCacheKey`(`durationMs`, `kenBurns`)가 변경되므로 캐시가 자동 무효화되고 새 설정으로 재렌더링됩니다.

#### TC-M02: 클립 역재생(Reverse) 청크 렌더링 및 iOS 임시 파일 정리 검증
* **전제 조건**: 10초 이상의 1080p/4K 비디오 클립을 타임라인에 올리고 **Reverse(역재생)** 옵션을 활성화합니다.
* **테스트 절차**:
  1. 역재생 활성화 후 프리뷰 재생 및 익스포트를 수행하며 Activity Monitor(또는 Xcode Memory Gauge)에서 피크 메모리를 확인합니다.
  2. (iOS 타겟 / `IOSExportEngine`) 역재생 클립이 포함된 상태에서 타임라인 편집을 여러 번 수행한 뒤 `FileManager.default.temporaryDirectory` 내 `MovieCutiOSReverse-*.mov` 파일 개수를 확인합니다.
* **기대 결과**:
  - 30프레임 GOP 청크 단위 역방향 인코딩(`ReverseRenderService`)으로 인해 클립 길이가 길어도 메모리가 수백 MB 이내로 일정하게 유지됩니다(OOM 크래시 없음).
  - iOS에서 컴포지션 리빌드/해제 시 이전 `MovieCutiOSReverse-*.mov` 임시 파일이 `imageRenderURLs`를 통해 삭제되어 디스크 누수가 발생하지 않습니다.

---

### Domain 3. 타임라인 데이터 모델 및 동시성 (Timeline Data Model & Concurrency)

#### TC-T01: 재생 중 연속 편집 시 플레이헤드·재생 상태·볼륨 단일 복원 검증
* **전제 조건**: 30초 분량의 비디오 클립을 재생(`Play`) 상태로 두고, 프리뷰 볼륨을 50%(`0.5`)로 설정합니다.
* **테스트 절차**:
  1. 재생 중인 상태에서 5초, 7초, 9초 지점에서 연속으로 분할(`Split`, `⌘B`)을 빠르게 실행합니다.
  2. 정지 상태에서 15초 위치로 플레이헤드를 이동한 뒤, 클립의 컬러 그레이드나 오디오 EQ 프리셋을 변경합니다.
* **기대 결과**:
  - `EditorViewModel`의 20ms 슬립 폴링 루프가 제거되고 `PlaybackEngine.schedulePlaybackRestore` 단일 경로로 복원되므로, 연속 분할 시 플레이헤드가 과거 위치로 튀거나 오디오가 두 번 겹쳐 재생되는 현상 없이 **직전 재생 위치/상태/볼륨(0.5)**이 정확히 1회 복원됩니다.

#### TC-T02: 장시간 연속 편집 시 `EditorSession` Undo 스택 상한(Cap) 및 Undo/Redo 무결성
* **전제 조건**: 편집 세션(`EditorSession`)에서 클립 이동/트림/볼륨 변경 등의 명령을 연속 실행합니다.
* **테스트 절차**:
  1. 250회의 편집 명령을 연속 디스패치(`dispatch`)합니다.
  2. `session.commandCount` 값을 확인합니다.
  3. `Undo`(`⌘Z`)를 연속 호출하고, 다시 `Redo`(`⇧⌘Z`)를 호출합니다.
* **기대 결과**:
  - `undoStack` 내부 배열 크기는 `EditorSession.maxUndoHistory`(200개)를 초과하지 않아 메모리가 무한 증가하지 않습니다.
  - `session.commandCount`는 누적 디스패치 횟수(250)를 정확히 반환하며, Undo/Redo 시 최근 200단계 이내의 모든 프로젝트 상태가 정확히 복원됩니다.

---

### Domain 4. 오디오 엔진 동기화 및 DSP 처리 (Audio-Visual Sync & Processing)

#### TC-A01: 마스터 라우드니스 측정(LUFS / True Peak) 및 타겟 노멀라이즈 속도·정확도 검증
* **전제 조건**: 3~5분 분량의 스테레오 오디오(또는 비디오) 클립이 포함된 프로젝트를 준비합니다.
* **테스트 절차**:
  1. 마스터 오디오 인스펙터에서 라우드니스 측정(Integrated LUFS, True Peak dBTP, Sample Peak dBFS)을 실행합니다.
  2. 타겟 라우드니스 노멀라이즈(예: `-14.0 LUFS`) 또는 AAC 오디오 익스포트를 수행합니다.
* **기대 결과**:
  - `AudioGraphLoudness.measure` 내부의 힙 배열 할당이 **0회**로 제거되어, 수 분 분량의 오디오 측정이 UI 멈춤 없이 즉각 완료됩니다.
  - 측정된 LUFS-I 및 dBTP 수치가 ITU-R BS.1770-4 기준값과 정확히 일치합니다.

#### TC-A02: 실시간 오디오 그래프 재생(`AudioGraphLiveRing`) 안정성
* **전제 조건**: 다중 오디오 트랙(대사 + BGM + 효과음)과 볼륨 오토메이션/페이드가 설정된 타임라인을 구성합니다.
* **테스트 절차**:
  1. 처음부터 끝까지 재생하면서 트랙 Mute / Solo 버튼을 토글합니다.
  2. 재생 중 시스템 CPU 부하가 있는 상태에서도 오디오 팝 노이즈(Pop/Click)나 A/V 싱크 밀림이 없는지 확인합니다.
* **기대 결과**:
  - 오디오 실시간 렌더 콜백(`AVAudioSourceNodeRenderBlock`)이 `os_unfair_lock` 없이 Lock-free SPSC 링버퍼(`AudioGraphLiveRing`)에서 원자적(Atomic)으로 샘플만 읽어오므로 우선순위 역전(Priority Inversion)에 의한 오디오 드랍아웃이 발생하지 않습니다.

---

### Domain 5. UI/UX 퍼포먼스 및 크로스플랫폼 아키텍처 (macOS & iOS/iPadOS)

#### TC-U01: 대형 타임라인(32개 초과 클립) 수평 스크롤 뷰포트 컬링 및 드래그 제스처 유지
* **전제 조건**:
  - **케이스 A (소형)**: 클립 10개가 있는 트랙
  - **케이스 B (대형)**: 블레이드(`⌘B`) 분할 등으로 클립 80개가 생성된 트랙
* **테스트 절차**:
  1. 케이스 A에서 타임라인의 모든 클립 선택, 이동, 트림이 정상 동작하는지 확인합니다.
  2. 케이스 B에서 타임라인을 줌인(`timelineZoom` 확대)한 뒤 가로 스크롤바를 좌우 끝까지 빠르게 스크롤합니다.
  3. 케이스 B에서 왼쪽 화면 시작점의 클립을 마우스로 잡고 오른쪽으로 화면 밖까지 길게 드래그하여 이동(`commitMove`)시킵니다.
* **기대 결과**:
  - 케이스 A(≤ 32개)는 컬링 없이 전체 클립을 그대로 반환하여 기존 접근성/UI 동작과 100% 동일하게 동작합니다.
  - 케이스 B(> 32개)는 현재 스크롤 뷰포트(`timelineScrollOffsetX ± 600pt`)와 겹치는 클립만 SwiftUI 뷰로 인스턴스화하여 고속 스크롤 시 끊김이 없습니다.
  - 절차 3에서 드래그 중인 클립(`draggedClipId`)과 선택된 클립(`selectedClipId`)은 뷰포트 밖으로 벗어나도 컬링에서 항상 제외되므로 드래그 제스처가 중간에 끊기지 않고 끝까지 커밋됩니다.

#### TC-U02: 필름스트립(`TimelineFilmstripImageStripNSView`) 부분 리드로우 및 줌 반응성
* **전제 조건**: 비디오 클립이 배치된 타임라인에서 플레이헤드만 천천히 이동하거나 타임라인 줌 슬라이더를 조절합니다.
* **테스트 절차**:
  1. 비디오 클립 위를 플레이헤드가 지나갈 때 필름스트립 썸네일이 깨지거나 깜빡이지 않는지 확인합니다.
  2. `⌘ + 스크롤`로 타임라인을 연속 줌인/줌아웃합니다.
* **기대 결과**:
  - `[CGImage]` 직접 드로잉 및 `dirtyRect.intersects(targetRect)` 컬링 덕분에 플레이헤드가 지나가는 타일만 최소 비용으로 다시 그려지며, Aspect-Fill 비율이 정확히 유지됩니다.

#### TC-U03: macOS 및 iOS 타임라인 플레이헤드 고속 스크러빙 (Chase-Seek 검증)
* **전제 조건**: Long-GOP(H.264 / HEVC) 4K 비디오 클립이 올라간 타임라인(macOS 및 iOS 프리뷰).
* **테스트 절차**:
  1. 타임라인 룰러 또는 플레이헤드 핸들을 잡고 좌우로 3초간 빠르게 왕복 스크러빙한 뒤 손가락/마우스를 뗍니다.
* **기대 결과**:
  - 스크러빙 도중 `AVPlayer.seek` 큐가 밀리지 않고(`isSeeking` + `pendingSeekTime` Chase-Seek 동작), 마우스를 떼는 즉시 마지막 플레이헤드 위치의 정확한 프레임에 멈춥니다(손을 뗀 후 뒤늦게 과거 프레임들이 순차 재생되는 디코더 적체 현상 없음).

---

## Part 3. 원클릭 경량 검증 스크립트 (Quick Smoke Command)

터미널에서 아래 명령어 한 줄로 수정된 모든 핵심 도메인의 유닛 테스트만 빠르게(약 3~5초) 일괄 검증할 수 있습니다:

```bash
swift test --filter "CurveEvaluatorTests|HSLCubeBuilderTests|TextOverlayPixelProcessorTests|ScopeAnalyzerTests|ImageVideoRenderScaleTests|EditorSessionRevisionTests|AudioGraphLoudnessTests|AudioGraphRenderingTests"
```


---

## Part 4. `Xcode.app` 미설치 환경을 위한 Part 2 CLI 자동화 검증 명세 (`GuruArchitectureVerificationTests.swift`)

> **목적**: `Xcode.app`이 없는 CLI(SwiftPM) 환경에서도 Part 2(TC-R01 ~ TC-U03)의 핵심 런타임 동작 및 App 레이어 배선 계약을 100% 자동 검증하고, 작업 완료 후 관련 문서와 테스트를 커밋합니다.

### 작업 지침 (작업자 에이전트용)

1. 신규 테스트 파일 [`Tests/MovieCutCoreTests/GuruArchitectureVerificationTests.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Tests/MovieCutCoreTests/GuruArchitectureVerificationTests.swift)를 생성하고 아래 **7개 테스트 케이스**를 구현하십시오:
   - **`reverseRenderServiceMultiChunkReversesFrameOrder` (TC-M02 런타임)**:
     - 1.6초(`maxSeconds: 1.0` 청크 경계를 넘어 **2개 이상의 역방향 청크**로 분할되는 길이) 합성 비디오(예: 64×64, 전반부 0~0.8초는 순수 Red, 후반부 0.8~1.6초는 순수 Blue)를 임시 `.mp4`로 생성한 뒤 `ReverseRenderService().renderReversed(clip:timeRange:outputURL:progress:)`를 실행합니다.
     - 결과 역재생 `.mov`/`.mp4` 파일의 duration이 유효하고, 시작 구간 프레임은 Blue가 우세($B > R$)하며 끝 구간 프레임은 Red가 우세($R > B$)한지 확인하여 멀티 청크 역방향 렌더링을 런타임 검증합니다.
   - **`editorViewModelUsesSinglePassAnalyzeAllAndSingleRestorePath` (TC-R01 & TC-T01 계약)**:
     - `App/MovieCutMac/EditorViewModel.swift` 소스를 읽어 `refreshScopes()`가 `ScopeAnalyzer.analyzeAll(`을 호출하는지 확인하고, `rebuildPreviewComposition`이 20ms 슬립 폴링(`for _ in 0..<150`) 없이 `playbackEngine.schedulePlaybackRestore(`를 호출하는지 검증합니다.
   - **`playbackEngineCachesImagePreviewSegmentsAndRestoresState` (TC-M01 & TC-T01 계약)**:
     - `App/MovieCutMac/Playback/PlaybackEngine.swift` 소스를 읽어 `ImagePreviewCacheKey`, `cachedImagePreviewSegments`, `schedulePlaybackRestore`가 정의·연결되어 있는지 검증합니다.
   - **`iosExportEngineTracksReversedTemporaryMovieForCleanup` (TC-M02 iOS 디스크 누수 방지 계약)**:
     - `App/MovieCutiOS/Export/IOSExportEngine.swift` 소스를 읽어 `renderReversedAsset(for: clip, from: asset)`이 반환한 URL이 `imageRenderURLs.append(`로 등록되어 임시 `.mov` 파일이 누수되지 않는지 검증합니다.
   - **`audioGraphLiveRingLockFreeSPSCContract` (TC-A02 계약)**:
     - `Sources/MovieCutCore/Audio/AudioGraphSourceAdapter.swift` 소스를 읽어 `AudioGraphLiveRing` 내부에서 `os_unfair_lock`이 제거되고 Lock-free 원자적 배리어(`OSAtomicAdd64Barrier`) 기반으로 동작하는지 검증합니다.
   - **`timelineViewportCullingAndFilmstripCGImageDirectDrawContract` (TC-U01 & TC-U02 계약)**:
     - `App/MovieCutMac/TimelineView.swift`에서 `clipsForDisplay`가 `all.count > 32` 기준 뷰포트 컬링 및 `selectedId` / `activeDraggedId` 보존을 수행하는지 확인하고, `App/MovieCutMac/Media/TimelineFilmstripStore.swift`의 `TimelineFilmstripImageStripNSView`가 `[CGImage]` 보유 + `dirtyRect.intersects(targetRect)` 컬링 + `cgContext.draw(cgImage, in:)` 직접 드로잉을 사용하는지 검증합니다.
   - **`macAndIOSChaseSeekContract` (TC-U03 계약)**:
     - `App/MovieCutMac/Playback/PlaybackEngine.swift` 및 `App/MovieCutiOS/Views/PreviewView.swift`가 각각 `isSeeking` / `isSeekingPlayer` 및 `pendingSeekTime` 기반의 Chase-Seek 상태 머신을 사용하는지 검증합니다.

2. **최소 검증 실행 (과도한 전체 테스트 금지)**:
   - 오직 아래 단일 필터 명령만 실행하여 신규 스위트 통과를 확인하십시오:
     ```bash
     swift test --filter GuruArchitectureVerificationTests
     ```

3. **Git 커밋 마무리**:
   - 테스트 통과 확인 후, 신규 테스트 파일과 미커밋된 `docs/GURU_*.md` 문서 3종(`docs/GURU_ARCHITECTURE_REFACTORING_PLAN.md`, `docs/GURU_ARCHITECTURE_REFACTORING_PLAN_V2.md`, `docs/GURU_FUNCTIONAL_TEST_SCENARIOS.md`)을 스테이징하여 커밋하십시오.
