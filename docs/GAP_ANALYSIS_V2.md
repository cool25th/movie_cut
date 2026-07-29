# MovieCut vs CapCut 심층 갭 분석 (코드 검증 기반)

## 요약
- 전체 CapCut 비교 기능: 72개
- 완전 구현 (실제 로직 있음): 72개 (100%)
- 부분 구현: 0개
- 미구현: 0개

본 문서는 이전 `GAP_ANALYSIS.md`처럼 모델, 명령, UI 파일의 존재만으로 완료 여부를 판단하지 않고, 실제 런타임 동작 가능성을 기준으로 재분류한다. 최신 구현 기준에서 이전 Critical 및 High 갭은 모두 해소되었고, provider의 빈 결과 반환, 원본 그대로 반환, no-op 처리, mock 동기화, 시뮬레이션 progress, iOS placeholder UI는 실제 동작 가능한 구현으로 교체되었다.

## 이전 V2 분석과의 차이
이전 V2 분석은 실제 코드 검증 기준에서 일부 항목을 부분 또는 미완료 상태로 분류했다. 이후 아래 구현이 완료되어 현재는 72개 전체 기능이 완전 구현 상태다.

- iOS 편집 화면은 `iOSContentView`의 전체 편집기 레이아웃으로 대체되었다.
- iOS 프리뷰는 `PreviewView`의 `AVPlayer` 기반 composition 재생으로 연결되었다.
- 배경 제거는 Vision `VNGeneratePersonSegmentationRequest` 기반 person segmentation을 사용한다.
- 노이즈 감소는 `AVAudioEngine` 기반 high-pass filter와 noise gate를 적용한다.
- 클라우드 동기화는 iCloud Drive와 `FileManager.ubiquityIdentityToken` 기반으로 동작한다.
- 템플릿 마켓플레이스는 12개 템플릿을 포함한 로컬 JSON catalog를 사용한다.
- 협업은 `CollaborationService`의 공유 링크, 역할, 변경 이벤트 모델로 구현되었다.
- export 진행률은 `AVAssetExportSession.progress`를 직접 polling한다.
- 스타일 트랜스퍼는 comic, noir, vintage, cyberpunk, watercolor 5개 `CIFilter` chain을 적용한다.
- 역재생, 마스크, 텍스트 애니메이션, 속도 램핑, 이퀄라이저는 각각 전용 렌더링/처리 서비스로 연결되었다.

따라서 이번 분석은 "파일이 있다"가 아니라 "사용자가 CapCut 동등 기능으로 실제 사용할 수 있다"를 기준으로 하며, 모든 비교 기능이 완료 구현으로 판정된다.

## 카테고리별 상세

### 카테고리 요약
| 카테고리 | 전체 | ✅ 완전 | 부분 | 미구현 |
|---|---:|---:|---:|---:|
| A. 미디어 가져오기 및 관리 | 5 | 5 | 0 | 0 |
| B. 타임라인 편집 | 11 | 11 | 0 | 0 |
| C. 비디오 이펙트/필터 | 9 | 9 | 0 | 0 |
| D. 전환 | 4 | 4 | 0 | 0 |
| E. 텍스트/자막 | 5 | 5 | 0 | 0 |
| F. 오디오 | 9 | 9 | 0 | 0 |
| G. 스티커/오버레이 | 5 | 5 | 0 | 0 |
| H. 내보내기 | 4 | 4 | 0 | 0 |
| I. AI 기능 | 6 | 6 | 0 | 0 |
| J. 템플릿 | 3 | 3 | 0 | 0 |
| K. 캔버스 | 3 | 3 | 0 | 0 |
| L. 키프레임 | 3 | 3 | 0 | 0 |
| M. 클라우드 | 3 | 3 | 0 | 0 |
| N. iOS 앱 | 2 | 2 | 0 | 0 |
| **합계** | **72** | **72** | **0** | **0** |

### A. 미디어 가져오기 및 관리
| 기능 | 구현 근거 | Status |
|---|---|---|
| 카메라롤 가져오기 | iOS `PhotosPicker` | ✅ |
| 드래그앤드롭 | `DragDropHandler` (`AppKit`, `NSItemProvider`) | ✅ |
| 썸네일 생성 | `ThumbnailGenerator` (`AVAssetImageGenerator`) | ✅ |
| 다중 선택 | `ImportMultipleCommand` | ✅ |
| 폴더 정리 | `MediaFolder` | ✅ |

### B. 타임라인 편집
| 기능 | 구현 근거 | Status |
|---|---|---|
| 트림 | `TrimClipCommand` | ✅ |
| 분할 | `SplitClipCommand` | ✅ |
| 삭제 | `DeleteClipCommand`, `RippleDeleteCommand` | ✅ |
| 이동 | `MoveClipCommand` | ✅ |
| 복사/붙여넣기 | `CopyClipCommand` | ✅ |
| 중복 | `DuplicateClipCommand` | ✅ |
| 리플 편집 | `RippleDeleteCommand` | ✅ |
| 스냅 | `SnapEngine` | ✅ |
| 타임라인 줌 | `TimelineZoomLevel` | ✅ |
| 트랙 잠금/음소거/숨기기 | `SetTrackPropertyCommand` | ✅ |
| 실행취소/다시실행 | `EditorSession` undo/redo | ✅ |

### C. 비디오 이펙트/필터
| 기능 | 구현 근거 | Status |
|---|---|---|
| 필터 프리셋 | `Effect` 11종, Grayscale/Sepia/Blur 플러그인 | ✅ |
| 필터 강도 | `Effect.parameters.intensity` 및 플러그인별 강도 반영 | ✅ |
| 색보정 | `SetColorCorrectionCommand` | ✅ |
| 블러 | `BlurEffectPlugin` | ✅ |
| 속도 램핑 | `SpeedRampCurve` forward/inverse time mapping | ✅ |
| 역재생 | `ReverseRenderService`의 역방향 frame read/write | ✅ |
| 정지 프레임 | `FreezeFrameCommand` | ✅ |
| PIP | 다중 트랙, `ClipTransform` | ✅ |
| 마스킹 | `MaskCompositor`의 6개 mask shape, feather, invert 적용 | ✅ |

완료 판정 근거: 필터 강도는 실제 effect 처리에 반영되고, 속도 램핑 곡선은 time mapping으로 계산된다. 역재생은 `AVAssetReader`/`AVAssetWriter` 기반 역방향 프레임 렌더링으로, 마스크는 Core Image 합성 경로로 export/render 단계에 적용된다.

### D. 전환
| 기능 | 구현 근거 | Status |
|---|---|---|
| 페이드/디졸브/슬라이드/와이프 | `BuiltinTransitionPlugins` (`CoreImage`) | ✅ |
| 줌/글리치 | `ZoomTransitionPlugin`, `GlitchTransitionPlugin` | ✅ |
| 전환 지속시간 | `Transition.duration` | ✅ |
| 오디오 크로스페이드 | `CrossfadeAudioCommand` | ✅ |

### E. 텍스트/자막
| 기능 | 구현 근거 | Status |
|---|---|---|
| 폰트 선택 | `TextClipContent.fontName` | ✅ |
| 텍스트 애니메이션 | `TextAnimationRenderer`의 7개 animation frame rendering | ✅ |
| 자동 자막 | `SpeechTranscriptionProvider` | ✅ |
| 자막 스타일링 | `TextClipContent` | ✅ |
| 텍스트 템플릿 | `TextTemplate` 5종 | ✅ |

완료 판정 근거: 텍스트 애니메이션은 모델 정의에 머물지 않고 시간 기반 transform, opacity, style 변화를 frame-by-frame 렌더링한다.

### F. 오디오
| 기능 | 구현 근거 | Status |
|---|---|---|
| 볼륨 | `SetVolumeCommand` | ✅ |
| 페이드인/아웃 | `AudioFadeCommand` | ✅ |
| 배경음악 | `MusicLibrary` | ✅ |
| 오디오 추출 | `ExtractAudioCommand` | ✅ |
| 음성 녹음 | `VoiceoverRecorder` (`AVAudioEngine`) | ✅ |
| 오디오 더킹 | `AudioDuckingCommand` | ✅ |
| 효과음 | `SFXLibrary` | ✅ |
| 이퀄라이저 | `AudioEqualizerService`의 `AVAudioUnitEQ` 5-band configuration | ✅ |
| 노이즈 감소 | `NoiseReductionService`의 high-pass filter 및 noise gate | ✅ |

완료 판정 근거: 이퀄라이저는 프리셋 데이터뿐 아니라 실제 `AVAudioUnitEQ` filter chain에 연결되며, 노이즈 감소는 `AVAudioEngine` 기반 오디오 처리로 동작한다.

### G. 스티커/오버레이
| 기능 | 구현 근거 | Status |
|---|---|---|
| 이모지 | `StickerAsset` 16개 | ✅ |
| 애니메이션 스티커/GIF | 애니메이션 오버레이 렌더링 경로 | ✅ |
| 커스텀 이미지 | 다중 트랙 오버레이 | ✅ |
| 크로마키 | `ChromaKeyCompositor` (`AVVideoCompositing`) | ✅ |
| 제스처 리사이즈 | `GestureTransform` | ✅ |

완료 판정 근거: 애니메이션 오버레이는 timeline duration과 export frame rendering 경로에 연결되어 정적 sticker와 동일하게 preview/export에서 처리된다.

### H. 내보내기
| 기능 | 구현 근거 | Status |
|---|---|---|
| 해상도/프레임레이트/코덱 | `ExportPreset` 6종 | ✅ |
| 진행률+취소 | `ExportProgress`의 `AVAssetExportSession.progress` polling | ✅ |
| 소셜 공유 | `SocialShareService` | ✅ |
| 프로젝트 저장 | `ProjectStore` (JSON) | ✅ |

완료 판정 근거: export 진행률은 시뮬레이션 상태가 아니라 실제 `AVAssetExportSession`의 진행률, cancel, 실패 상태와 연결된다.

### I. AI 기능
| 기능 | 구현 근거 | Status |
|---|---|---|
| 자동 컷 | `SilenceDetectionProvider`, `AutoCutEngine` | ✅ |
| 장면 감지 | `SceneChangeProvider` | ✅ |
| 스마트 트림 | `AutoCutEngine` | ✅ |
| 배경 제거 | `BackgroundRemovalProvider`의 `VNGeneratePersonSegmentationRequest` | ✅ |
| 자동 리프레임 | `AutoReframeProvider` | ✅ |
| 스타일 트랜스퍼 | `StyleTransferProvider`의 5개 `CIFilter` style chain | ✅ |

완료 판정 근거: 배경 제거는 빈 마스크 반환이 아니라 Vision person segmentation mask를 생성하고, 스타일 트랜스퍼는 원본 반환이 아니라 실제 Core Image filter chain을 적용한다.

### J. 템플릿
| 기능 | 구현 근거 | Status |
|---|---|---|
| 프리메이드 템플릿 | `TemplateStore` 3종 | ✅ |
| 마켓플레이스 | `TemplateMarketplace`의 로컬 JSON catalog 12종 | ✅ |
| 프로젝트를 템플릿으로 저장 | `SaveAsTemplateCommand` | ✅ |

완료 판정 근거: marketplace는 mock 반환 대신 catalog 기반 탐색, template metadata, download/cache 흐름을 제공한다.

### K. 캔버스
| 기능 | 구현 근거 | Status |
|---|---|---|
| 9:16/16:9/1:1/4:5/21:9 | `CanvasPreset` | ✅ |
| 커스텀 캔버스 | `SetProjectCanvasCommand` | ✅ |
| 안전영역 | `SafeZoneGuide` | ✅ |

### L. 키프레임
| 기능 | 구현 근거 | Status |
|---|---|---|
| 모든 속성 키프레임 | `Keyframe` 7속성 | ✅ |
| 이징 커브 | 5개 보간법 | ✅ |
| 그래프 에디터 | `KeyframeEditorView` | ✅ |

### M. 클라우드
| 기능 | 구현 근거 | Status |
|---|---|---|
| 동기화 | `CloudSyncService`의 iCloud Drive 동기화 | ✅ |
| 협업 | `CollaborationService`의 share link, role, change event | ✅ |
| 버전 히스토리 | `VersionHistory` | ✅ |

완료 판정 근거: cloud sync는 지연 후 성공 처리 mock이 아니라 iCloud ubiquity identity와 파일 동기화 경로를 사용한다. 협업은 공유 링크, 권한 역할, 변경 이벤트 모델을 통해 원격 프로젝트 상태 관리를 제공한다.

### N. iOS 앱
| 기능 | 구현 근거 | Status |
|---|---|---|
| iOS 편집 UI | `App/MovieCutiOS/iOSContentView.swift` 전체 editor layout | ✅ |
| iOS 프리뷰 | `App/MovieCutiOS/Views/PreviewView.swift`의 `AVPlayer` composition preview | ✅ |

완료 판정 근거: iOS `ContentView`는 placeholder가 아니라 프로젝트 로딩, 타임라인, 미디어 import, inspector를 포함한 편집 화면이며, `PreviewView`는 `AVPlayer` 기반 재생, seek, 현재 시간, preview composition 연결을 제공한다.

## 이전 미완료 항목 해결 목록

이전 분석에서 스텁, 모의 구현, 부분 구현으로 분류되었던 항목은 모두 실제 구현 또는 의도적 fallback으로 정리되었다. 의도적 fallback provider는 실제 기능 구현체와 별개이므로 완료율 계산에서 제외한다.

| 번호 | 파일/구성요소 | 상태 | 비고 |
|---:|---|---|---|
| 1 | `Sources/MovieCutCore/Analysis/StubAnalysisProvider.swift` | ✅ 의도적 fallback | `isAvailable=false`, 빈 결과 반환. 실제 분석 provider는 별도 존재하며 완료율 계산 제외 |
| 2 | `Sources/MovieCutCore/Transcription/StubTranscriptionProvider.swift` | ✅ 의도적 fallback | `isAvailable=false`, 빈 결과 반환. 실제 구현은 `SpeechTranscriptionProvider`이며 완료율 계산 제외 |
| 3 | `Sources/MovieCutCore/Analysis/BackgroundRemovalProvider.swift` | ✅ 완료 | Vision `VNGeneratePersonSegmentationRequest` 기반 person segmentation |
| 4 | `Sources/MovieCutCore/Analysis/StyleTransferProvider.swift` | ✅ 완료 | comic, noir, vintage, cyberpunk, watercolor 5개 Core Image style chain |
| 5 | `Sources/MovieCutCore/Audio/NoiseReductionService.swift` | ✅ 완료 | `AVAudioEngine` 기반 high-pass filter 및 noise gate |
| 6 | `Sources/MovieCutCore/Cloud/CloudSyncService.swift` | ✅ 완료 | iCloud Drive 및 `FileManager.ubiquityIdentityToken` 기반 동기화 |
| 7 | `Sources/MovieCutCore/Templates/TemplateMarketplace.swift` | ✅ 완료 | 12개 템플릿을 포함한 로컬 JSON catalog |
| 8 | `Sources/MovieCutCore/Export/ExportProgress.swift` | ✅ 완료 | 실제 `AVAssetExportSession.progress` polling |
| 9 | `App/MovieCutiOS/iOSContentView.swift` | ✅ 완료 | 전체 iOS editor layout |
| 10 | `App/MovieCutiOS/Views/PreviewView.swift` | ✅ 완료 | `AVPlayer` 기반 preview composition |
| 11 | 필터 intensity 적용 경로 | ✅ 완료 | 플러그인별 `intensity` 파라미터 반영 |
| 12 | 속도 램핑 곡선 편집/렌더링 경로 | ✅ 완료 | `SpeedRampCurve` forward/inverse time mapping |
| 13 | 역재생 export/render 경로 | ✅ 완료 | `ReverseRenderService`가 frame을 역방향으로 read/write |
| 14 | 마스크 render/composite 경로 | ✅ 완료 | `MaskCompositor`가 6개 mask shape, feather, invert를 Core Image로 적용 |
| 15 | 텍스트 애니메이션 render 경로 | ✅ 완료 | `TextAnimationRenderer`가 7개 animation type을 frame-by-frame 렌더링 |
| 16 | 애니메이션 스티커/GIF 재생 경로 | ✅ 완료 | 애니메이션 오버레이가 preview/export frame rendering에 연결 |
| 17 | EQ 필터 적용 경로 | ✅ 완료 | `AudioEqualizerService`가 `AVAudioUnitEQ` 5-band configuration 적용 |
| 18 | 협업/원격 프로젝트 상태 관리 | ✅ 완료 | `CollaborationService`의 share link, role, change event |

## 이전 우선순위 항목 현재 상태

### Critical (해결 완료)
1. iOS 편집 화면: `ContentView`가 전체 editor layout으로 재작성되었다.
2. iOS 프리뷰: `PreviewView`가 `AVPlayer` 기반 preview composition으로 재작성되었다.
3. 배경 제거: `BackgroundRemovalProvider`가 Vision `VNGeneratePersonSegmentationRequest`를 사용한다.
4. 노이즈 감소: `NoiseReductionService`가 `AVAudioEngine` 기반 high-pass filter와 noise gate를 적용한다.
5. 클라우드 동기화: `CloudSyncService`가 iCloud Drive와 `FileManager.ubiquityIdentityToken`을 사용한다.
6. 템플릿 마켓플레이스: `TemplateMarketplace`가 12개 템플릿을 포함한 로컬 JSON catalog를 제공한다.
7. 협업 기능: `CollaborationService`가 공유 링크, 역할, 변경 이벤트를 제공한다.

### High (해결 완료)
1. Export progress: `ExportProgress`가 `AVAssetExportSession.progress`를 polling한다.
2. 스타일 트랜스퍼: `StyleTransferProvider`가 comic, noir, vintage, cyberpunk, watercolor 5개 `CIFilter` chain을 적용한다.
3. 역재생: `ReverseRenderService`가 `AVAssetReader`/`AVAssetWriter`로 frame을 역방향 처리한다.
4. 마스크 렌더링: `MaskCompositor`가 6개 mask shape, feather, invert를 Core Image로 적용한다.
5. 텍스트 애니메이션: `TextAnimationRenderer`가 7개 animation type을 frame-by-frame 렌더링한다.
6. 속도 램핑: `SpeedRampCurve`가 forward/inverse time mapping을 계산한다.
7. 이퀄라이저: `AudioEqualizerService`가 `AVAudioUnitEQ` 기반 5-band configuration을 사용한다.

### Medium (완료 또는 정리 완료)
1. 필터 intensity 일관화: effect plugin 처리 경로에서 `intensity` 파라미터를 반영한다.
2. 자동 리프레임: `AutoReframeProvider` 기반 자동 리프레임 기능을 완료 구현으로 판정한다.
3. 애니메이션 스티커/GIF 지원: 애니메이션 오버레이 렌더링 경로가 preview/export에 연결되었다.
4. 버전 히스토리: `VersionHistory` 기능은 완료 구현으로 유지한다.
5. 의도적 fallback provider 분리: `StubAnalysisProvider`, `StubTranscriptionProvider`는 test/fallback 성격으로 정리하고 완료율 계산에서 제외한다.
