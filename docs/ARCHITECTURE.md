# MovieCut 아키텍처 명세서 (Architecture Specification)

> **버전:** 1.2 (2026-08-22 — G-24/G-25/G-26/G-28 완성·G-03 반영·네트워크 증명 체계 정밀화)  
> **대상 플랫폼:** macOS (14.0+), iOS (17.0+)  
> **기술 스택:** Swift 6, SwiftUI, AVFoundation, CoreImage, CoreAudio/AVAudioEngine, Vision

---

## 1. 아키텍처 개요 및 설계 철학

MovieCut은 **"단일 Core 로직, 동일한 Preview/Export 렌더링 결과, 완전한 오프라인 로컬 우선(Local-first)"**을 목표로 하는 고성능 비선형 영상 편집기(NLE)입니다.

```mermaid
graph TD
    UI[App 계층: SwiftUI View / Panels<br/>MovieCutMac / MovieCutiOS] --> VM[EditorViewModel / Router]
    VM --> Session[MovieCutCore: EditorSession]
    Session --> Command[Command Pattern: Undo/Redo Engine]
    Command --> Model[Project / Timeline / Track / Clip State]
    
    Model --> Flattener[CompoundFlattener -> FlattenedTimeline Snapshot]
    Flattener --> Playback[PlaybackEngine: AVPlayer / Preview]
    Flattener --> Export[ExportEngine: AVAssetExportSession / Writer]
    
    Playback --> Compositor[CustomVideoCompositor]
    Export --> Compositor
    Compositor --> SharedPixel[Shared PixelProcessors<br/>Blend / Chroma / Mask / PersonSegmentation / Text / Transition]
    
    Model --> Storage[Storage Layer: ProjectStore / SchemaMigrations v1-v4]
    Storage --> Bookmark[SecurityScopedAccess: App Sandbox]
```

### 핵심 설계 원칙
1. **렌더링 파리티 (Rendering Parity)**: 메인 프리뷰(`PlaybackEngine`)와 내보내기(`ExportEngine`)는 완전히 동일한 snapshot(`FlattenedTimeline`)과 공유 픽셀 프로세서(`PixelProcessor`) 파이프라인을 통과합니다.
2. **트랜잭션 기반 단일 변경 (Command Pattern)**: 모든 타임라인 변경 및 프로퍼티 수정은 `EditorSession.dispatch(Command)`를 경유하며, 원자적 Undo/Redo 단위를 보장합니다.
3. **App Sandbox & 보안 북마크 격리**: 파일 I/O는 `SecurityScopedAccess`가 단일 소유하며, 프로젝트 파일은 스키마 버전 체인(v1~v4)을 통해 무손실 로드/마이그레이션됩니다.
4. **로컬 우선 & 외부 전송 없음**: Mac 앱은 App Sandbox에서 `network.client` entitlement가 없어 외부 발신이 OS 수준에서 차단된다(2026-08-22 entitlements 확인). iOS는 별도 증명 체계를 사용한다 — ① 코드 감사(네트워크 API 부재, 2026-08-22 확인) ② 네트워크 차단 환경 대표 작업 통과 ③ 트래픽 캡처(②③은 P0 미실행). STT는 `requiresOnDeviceRecognition` 강제 + 미지원 시 명시적 실패로 서버 폴백이 없다. 모든 AI/DSP(STT, 보컬 분리, 인물 세그멘테이션)가 온디바이스에서 처리된다.

---

## 2. 계층별 세부 구조

### 2.1 Core 모델 계층 (`Sources/MovieCutCore/Models/`)

* **`Project`**: 프로젝트 최상위 모델. `id`, `name`, `timeline`, `canvas`, `compounds`, `schemaVersion`을 포함합니다.
* **`Timeline`**: 다중 트랙(`[Track]`)과 재생 프레임레이트(`frameRate`), 마커, 오디오 믹스 설정을 소유합니다.
* **`Track`**: 비디오/오디오/텍스트 등의 타입을 가지며, 클립 목록(`[Clip]`)과 잠금/음소거(`isLocked`, `isMuted`) 상태를 가집니다.
* **`Clip`**: 개별 미디어 조각.
  * 시간 매핑: `timelineRange` (타임라인 상 위치/길이) ↔ `sourceRange` (원본 소스 시간)
  * 속성: `speed`, `speedRamp`, `isReversed`, `opacity`, `blendMode`, `zIndex`, `volume`, `fadeInDuration`, `fadeOutDuration`, `isBackgroundRemoved`, `chromaKeySettings`
* **`CompoundDefinition`**: 컴파운드 클립(중첩 시퀀스)을 정의하며, 단일 레벨 Flatten 처리를 위한 자식 클립들을 격리 보관합니다.
* **조정 클립(G-03)**: 타임라인 구간에 색·필터를 일괄 적용하는 오버레이형 클립. Mac UI·렌더 체인과 iOS 렌더 배선이 완료됐다(b9d0e58).

### 2.2 명령 및 세션 계층 (`Sources/MovieCutCore/Commands/`)

`EditorSession`은 현재 `Project` 상태와 Undo/Redo 스택을 관리합니다.

* **`Command` 프로토콜**: `apply(to: inout Project) throws -> CommandResult` 및 `invert(from: Project) -> any Command`
* **주요 명령 집합**:
  * `AddClipCommand`, `DeleteClipCommand` (빈틈 유지), `RippleDeleteClipCommand` (빈틈 폐쇄)
  * `SplitClipCommand`, `TrimClipCommand`, `MoveClipCommand`
  * `SlipClipCommand` (sourceRange만 이동), `SlideClipCommand` (timelineRange 및 인접 클립 경계 이동)
  * `SetClipPropertyCommand` (블렌딩 모드, 투명도, 오디오 페이드 등 단일 프로퍼티 변경)
  * `CreateCompoundClipCommand`, `ReleaseCompoundClipCommand`
  * `ImportAndSetClipSourceCommand` (보컬 분리 등 자산 교체와 타임라인 갱신을 단일 undo로 원자 실행)

### 2.3 렌더링 & 합성 파이프라인 (`Sources/MovieCutCore/Rendering/`)

macOS/iOS의 `CustomVideoCompositor`는 프레임 단위로 CoreImage 기반의 공유 프로세서에 합성을 위임합니다.

| 프로세서 | 역할 및 구현 방식 |
|---|---|
| [`BlendPixelProcessor`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Rendering/BlendPixelProcessor.swift) | 12종 블렌딩 모드(Normal, Multiply, Screen, Overlay, Darken, Lighten, ColorDodge, ColorBurn, SoftLight, HardLight, Difference, Exclusion). `.normal`은 무비용 패스스루. |
| [`PersonSegmentationCompositor`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Rendering/PersonSegmentationCompositor.swift) | Vision 프레임워크 기반 온디바이스 인물 마스크 생성 및 배경 제거. 프리뷰는 고속 모드, Export는 정밀 모드. |
| [`ChromaKeyPixelProcessor`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Rendering/ChromaKeyPixelProcessor.swift) | 특정 색상 크로마키 추출, 허용치(Tolerance), 경계 축소(Edge Shrink), 부드러움(Softness) 처리. |
| [`MaskPixelProcessor`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Rendering/MaskPixelProcessor.swift) | 사각형/원형/선형/미러/별/하트 및 브러시 마스크 합성, 반전(Invert) 및 페더(Feather) 지원. |
| [`TextOverlayPixelProcessor`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Rendering/TextOverlayPixelProcessor.swift) | 폰트, 크기, 정렬, 배경 박스, 자막 오버레이 렌더링. |
| [`TransitionPixelProcessor`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Rendering/TransitionPixelProcessor.swift) | 인접 클립 간 12종 Two-source 화면 전환 (Cross Dissolve, Dip to Black/White, Wipe, Slide, Zoom, Glitch 등). |
| [`ColorCorrectionPixelProcessor`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Rendering/ColorCorrectionPixelProcessor.swift) | Brightness, Contrast, Saturation, Exposure, Warmth, Tint, 3-way Lift/Gamma/Gain 및 톤 커브. HSL 8밴드 큐브 렌더 체인(G-02 Inc5, 파리티 `hsl_curves` 실증) 및 편집 UI 연결 완료. |
| 안정화 warp (G-24) | Vision 등록(homography) → 경로 평활화 → CoreImage warp → confidence fallback. 렌더 체인 통합(1dbf49a, Mac·iOS 컴포지터). |
| [`RenderColorConfiguration`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Rendering/RenderColorConfiguration.swift) | 프리뷰(AVPlayer 디코드 ICC 태그)·출력(무태그) 양쪽 다리의 소스 색 해석을 작업 공간으로 고정(2026-08-17, 파리티 `crop_rect_video` MAD 10.25→0.50). G-29 색관리 전환의 토대. |
| LUT/필터 (`VisualEffectPixelProcessor`) | `.cube` LUT 임포트 + 절차적 LUT/필터를 프리뷰·출력 공통 경로에 연결. |

### 2.4 오디오 DSP 파이프라인 (`Sources/MovieCutCore/Audio/`)

* **`VocalSeparationRenderer`**: 센터 채널 위상 상쇄 및 분리 기법을 통해 스테레오 트랙에서 보컬 제거(Remove Vocals) 또는 센터 분리(Isolate Center)를 고속 오프라인 렌더링하여 CAF로 교체.
* **`AudioDuckingPlanner`**: 비디오/보이스오버 트랙의 볼륨을 감지하여 BGM 트랙의 볼륨을 자동으로 낮추는 램프 볼륨 커브 생성.
* **`NoiseReductionService`**: 음성 노이즈 억제 필터링.
* **`BeatDetector`**: 오디오 에너지 분석을 통한 비트 지점 마커 자동 생성.

### 2.4.1 오디오 렌더 그래프 (G-25/G-26, 2026-08 완성)

* **`AudioRenderGraphSpec`** ([`AUDIO_RENDER_GRAPH_SPEC_20260817.md`](AUDIO_RENDER_GRAPH_SPEC_20260817.md) v1.1): 프리뷰와 출력이 **같은 명세에서 각자 그래프를 생성**하며, 그 외 어떤 경로도 오디오 샘플을 만들지 않는다. 덕킹은 플래너 산출물의 스트립 게인 자동화로 구현.
* **G-25 믹싱 골격**: 좌우 팬, 채널 매핑(mono/stereo/dual-mono), 트랙·마스터 미터, master bus, mute/solo, LUFS·true-peak 분석. 실증 — 프리뷰↔출력 null test(±1 샘플·−0.02LU), 혼합 sample rate 60분 드리프트 0.
* **G-26 프로세서 기본선**: 컴프레서·피크 리미터·리버브(Apple Audio Unit 우선), 트랙 채널 스트립, master limiter, 프리셋 + 그래프 직렬화(Codable, version 1) + 마스터 체인 UI. 측정 게이트 — LUFS ±0.2LU·true-peak ±0.2dB·transfer curve 자동 검사 통과.

### 2.5 스토리지 & App Sandbox (`Sources/MovieCutCore/Storage/`)

* **`ProjectStore`**: `.moviecut` 번들/JSON 파일 저장 및 로드.
* **`ProjectSchemaVersioning`**: 스키마 버전 1 → 2(Security Bookmark) → 3(Thermal/Preview) → 4(Blend/Compound) 마이그레이션 체인 보장.
* **`RecentProjectsStore`**: Application Support 디렉토리에 보안 북마크와 메타데이터가 포함된 최근 프로젝트 목록 영속화.
* **`SecurityScopedAccess`**: macOS App Sandbox 환경에서 외부 미디어 파일 접근 권한을 유지하기 위한 Bookmark 생성/해석/Scope 단일 관리자.

---

## 3. 플랫폼별 App 계층 구조

### 3.1 macOS 앱 (`App/MovieCutMac/`)
* **`MovieCutMacApp` / `AppStageRouter`**: 홈 화면(`HomeView`)과 편집기 화면(`ContentView`) 간 라이프사이클 및 저장 확인 제어.
* **`EditorViewModel`**: 뷰 상태, 타임라인 제어, 비디오/오디오 엔진, 인스펙터 선택 상태를 총괄하는 메인 ViewModel.
* **레이아웃 구조**:
  * Top Toolbar (Home, Undo/Redo, Project Name, Preview Quality, Export 버튼)
  * Left: `MediaLibraryPanel` (미디어 자산, 텍스트 프리셋, 오디오 라이브러리)
  * Center: `PreviewPanel` (`AVPlayerView`, Safe Zone 가이드, 실시간 스코프 3종)
  * Right: `InspectorPanel` (Basic, Effects, Audio, Vocal, Text, Subtitles)
  * Bottom: `TimelineView` (다중 트랙 타임라인, 타임라인 툴바, 줌 컨트롤, 룰러)
* **효과·템플릿 브라우저(G-28)**: 검색·미리보기·비용 등급(`EffectCostProfile`, ms/frame 실측 — instant/moderate/heavy)·KPI 모델. 브라우저 메모리 측정은 메인 스레드 밖에서 수행(836d246).

### 3.2 iOS 앱 (`App/MovieCutiOS/`)
* **`MovieCutiOSApp` / `iOSContentView`**: 모바일/아이패드 환경에 최적화된 적응형 레이아웃.
* **`IOSEditorViewModel`**: Mac ViewModel과 동일한 Core 엔진을 공유하며, 터치 인터랙션과 Bottom Sheet 기반 인스펙터 지원.
* **`IOSCustomVideoCompositor`**: Core의 공유 `PixelProcessor`를 활용하여 동일한 렌더링 결과 보장.
* **`IOSExportEngine`**: 프리젠트별 특수 분기 포함 — 정지프레임(tiny source → scaleTimeRange), 역재생(`ReverseRenderService` 사전 렌더), 스피드램프(세그먼트 워커), 조정 레이어. **iOS 실기기 런타임 검증은 G-27 대기 중**(시뮬레이터 E2E·환경 게이트 하니스 `IOSUITestHarness` 구축 완료).
* **`IOSPreviewCompositionBuilder`**: 프리뷰 합성 구성 로직의 분리 추출(G-27, e15a8c4) — Mac 경로와 동일한 `Clip.makeTimeMapping()` 기반 시간 매핑.

---

## 4. 관측성 및 발열 제어 (Observability & Thermal Management)

* **`OSSignposter` (`AppLog.Signpost`)**: Instruments를 통한 성능 계측:
  * `playback.seek`: 타임라인 탐색 지연
  * `playback.buildComposition`: 프리뷰 합성 빌드 시간
  * `export.preset`: 인코딩 전 구간
  * `import.openProject`: 프로젝트 로드 및 마이그레이션 시간
  * `proxy.generate`: 프록시 생성 시간
* **`ProxyDowngradePolicy` (Thermal Ladder)**:
  * `nominal`: 사용자가 선택한 프리뷰 해상도 유지
  * `fair`: 렌더 해상도를 최대 1/2로 자동 클램프 (프레임 드롭 방지)
  * `serious`: 고화질 미디어를 720p 프록시 미디어로 자동 전환
  * `critical`: 기기 과열 방지를 위해 Export 차단 및 쿨다운 안내
