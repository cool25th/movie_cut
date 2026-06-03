# MovieCut vs CapCut 심층 갭 분석 (코드 검증 기반)

## 요약
- 전체 CapCut 비교 기능: 72개
- 완전 구현 (실제 로직 있음): 55개 (76.4%)
- 부분 구현 (모델/UI 있으나 핵심 로직 스텁 또는 렌더링 연동 불명확): 9개 (12.5%)
- 미구현 (스텁, no-op, mock, placeholder 또는 기능 없음): 8개 (11.1%)

본 문서는 이전 `GAP_ANALYSIS.md`처럼 모델, 명령, UI 파일의 존재만으로 완료 여부를 판단하지 않고, 실제 런타임 동작 가능성을 기준으로 재분류한다. 특히 provider의 `isAvailable=false`, 빈 결과 반환, 원본 그대로 반환, mock 네트워크, 시뮬레이션 progress, AVPlayer 미연동 placeholder UI는 완료 구현으로 보지 않는다.

## 이전 분석과의 차이
이전 분석의 100% 완료 판정은 기능 표면적이 존재하는지를 중심으로 판단한 결과로 보인다. 실제 코드 검증 기준에서는 다음 항목들이 완료 구현으로 볼 수 없다.

- 모델과 커맨드는 존재하지만 export/render/playback 파이프라인에서 실제 효과가 적용되는지 확인되지 않은 항목이 있다.
- 일부 provider는 타입만 존재하고 빈 결과, 빈 마스크, 원본 이미지, no-op 처리를 반환한다.
- cloud sync와 template marketplace는 실제 네트워크/API 연동이 아니라 mock 또는 지연 후 성공 처리다.
- export progress는 `AVAssetExportSession.progress`와 직접 연결되지 않은 시뮬레이션 상태다.
- iOS 앱의 주요 화면은 실제 편집기와 플레이어가 아니라 placeholder 수준이다.

따라서 이번 분석은 "파일이 있다"가 아니라 "사용자가 CapCut 동등 기능으로 실제 사용할 수 있다"를 기준으로 한다.

## 카테고리별 상세

### 카테고리 요약
| 카테고리 | 전체 | ✅ 완전 | 🟡 부분 | ❌ 미구현 |
|---|---:|---:|---:|---:|
| A. 미디어 가져오기 및 관리 | 5 | 5 | 0 | 0 |
| B. 타임라인 편집 | 11 | 11 | 0 | 0 |
| C. 비디오 이펙트/필터 | 9 | 5 | 4 | 0 |
| D. 전환 | 4 | 4 | 0 | 0 |
| E. 텍스트/자막 | 5 | 4 | 1 | 0 |
| F. 오디오 | 9 | 7 | 1 | 1 |
| G. 스티커/오버레이 | 5 | 4 | 1 | 0 |
| H. 내보내기 | 4 | 3 | 1 | 0 |
| I. AI 기능 | 6 | 3 | 1 | 2 |
| J. 템플릿 | 3 | 2 | 0 | 1 |
| K. 캔버스 | 3 | 3 | 0 | 0 |
| L. 키프레임 | 3 | 3 | 0 | 0 |
| M. 클라우드 | 3 | 1 | 0 | 2 |
| N. iOS 앱 | 2 | 0 | 0 | 2 |
| **합계** | **72** | **55** | **9** | **8** |

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
| 필터 강도 | `Effect.parameters`에 `intensity` 존재 | 🟡 |
| 색보정 | `SetColorCorrectionCommand` | ✅ |
| 블러 | `BlurEffectPlugin` | ✅ |
| 속도 램핑 | `SpeedRampPoint` 모델, `ExportEngine` `playbackRate` | 🟡 |
| 역재생 | `ReverseClipCommand`, `isReversed` 플래그 | 🟡 |
| 정지 프레임 | `FreezeFrameCommand` | ✅ |
| PIP | 다중 트랙, `ClipTransform` | ✅ |
| 마스킹 | `Mask` 모델, `SetClipMaskCommand` | 🟡 |

부분 구현 판정 사유: 필터 강도가 실제 플러그인 처리에 반영되는지, 속도 램핑 곡선 편집이 UI와 export에 완전히 연결되는지, 역재생 렌더링과 마스크 적용이 export/render 경로에서 실제 동작하는지 추가 검증이 필요하다.

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
| 텍스트 애니메이션 | `TextAnimation` 7종 | 🟡 |
| 자동 자막 | `SpeechTranscriptionProvider` | ✅ |
| 자막 스타일링 | `TextClipContent` | ✅ |
| 텍스트 템플릿 | `TextTemplate` 5종 | ✅ |

부분 구현 판정 사유: 텍스트 애니메이션은 모델 정의는 있으나 실제 렌더링 단계에서 시간 기반 애니메이션이 적용되는지 불명확하다.

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
| 이퀄라이저 | `EqualizerPreset` | 🟡 |
| 노이즈 감소 | `NoiseReductionProcessor` | ❌ |

미구현/부분 구현 판정 사유: 이퀄라이저는 프리셋 데이터는 있으나 실제 EQ 필터 적용 로직이 없고, 노이즈 감소는 no-op 스텁이다.

### G. 스티커/오버레이
| 기능 | 구현 근거 | Status |
|---|---|---|
| 이모지 | `StickerAsset` 16개 | ✅ |
| 애니메이션 스티커/GIF | `TextAnimation` 모델 | 🟡 |
| 커스텀 이미지 | 다중 트랙 오버레이 | ✅ |
| 크로마키 | `ChromaKeyCompositor` (`AVVideoCompositing`) | ✅ |
| 제스처 리사이즈 | `GestureTransform` | ✅ |

부분 구현 판정 사유: GIF 재생은 지원되지 않고 애니메이션 정의만 존재한다.

### H. 내보내기
| 기능 | 구현 근거 | Status |
|---|---|---|
| 해상도/프레임레이트/코덱 | `ExportPreset` 6종 | ✅ |
| 진행률+취소 | `ExportProgress` | 🟡 |
| 소셜 공유 | `SocialShareService` | ✅ |
| 프로젝트 저장 | `ProjectStore` (JSON) | ✅ |

부분 구현 판정 사유: export 진행률은 실제 `AVAssetExportSession` 진행률과 연동되지 않고 시뮬레이션된 상태다.

### I. AI 기능
| 기능 | 구현 근거 | Status |
|---|---|---|
| 자동 컷 | `SilenceDetectionProvider`, `AutoCutEngine` | ✅ |
| 장면 감지 | `SceneChangeProvider` | ✅ |
| 스마트 트림 | `AutoCutEngine` | ✅ |
| 배경 제거 | `BackgroundRemovalProvider` | ❌ |
| 자동 리프레임 | `AutoReframeProvider` | 🟡 |
| 스타일 트랜스퍼 | `StyleTransferProvider` | ❌ |

미구현/부분 구현 판정 사유: 배경 제거는 빈 마스크를 반환하고, 스타일 트랜스퍼는 원본 이미지를 그대로 반환한다. 자동 리프레임은 단순화된 구현이며 실제 Vision 기반 피사체 추적 수준인지 검증이 필요하다.

### J. 템플릿
| 기능 | 구현 근거 | Status |
|---|---|---|
| 프리메이드 템플릿 | `TemplateStore` 3종 | ✅ |
| 마켓플레이스 | `TemplateMarketplace` | ❌ |
| 프로젝트를 템플릿으로 저장 | `SaveAsTemplateCommand` | ✅ |

미구현 판정 사유: marketplace는 실제 온라인 서비스가 아니라 mock 데이터 기반이다.

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
| 동기화 | `CloudSyncService` | ❌ |
| 협업 | 없음 | ❌ |
| 버전 히스토리 | `VersionHistory` (로컬 in-memory) | ✅ |

미구현 판정 사유: cloud sync는 실제 네트워크 통신 없이 1초 지연 후 성공을 반환하는 mock 동기화이며, 협업 기능은 존재하지 않는다.

### N. iOS 앱
| 기능 | 구현 근거 | Status |
|---|---|---|
| iOS 편집 UI | `App/MovieCutiOS/ContentView.swift` | ❌ |
| iOS 프리뷰 | `App/MovieCutiOS/Views/PreviewView.swift` | ❌ |

미구현 판정 사유: iOS `ContentView`는 "No Project Open" placeholder이고, `PreviewView`는 `AVPlayer` 없이 재생/정지 상태 토글만 제공한다.

## 스텁/미구현 파일 목록

제공된 분석 요약에는 "18개 파일"이라고 되어 있으나, 요청 본문에서 파일/타입명이 직접 명시된 스텁/모의/미구현 항목은 10개다. 아래는 명시된 10개와, 기능 갭 판정상 실제 구현 대상에 해당하지만 파일명이 명시되지 않은 8개 구성요소를 함께 정리한 목록이다.

| 번호 | 파일/구성요소 | 상태 | 비고 |
|---:|---|---|---|
| 1 | `Sources/MovieCutCore/Analysis/StubAnalysisProvider.swift` | 의도적 스텁 | `isAvailable=false`, 빈 결과 반환. 실제 분석 provider는 별도 존재 |
| 2 | `Sources/MovieCutCore/Transcription/StubTranscriptionProvider.swift` | 의도적 스텁 | `isAvailable=false`, 빈 결과 반환. 실제 구현은 `SpeechTranscriptionProvider` |
| 3 | `Sources/MovieCutCore/Analysis/BackgroundRemovalProvider.swift` | 미구현 | 빈 마스크 반환, Vision 기반 person segmentation 미구현 |
| 4 | `Sources/MovieCutCore/Analysis/StyleTransferProvider.swift` | 미구현 | 원본 이미지를 그대로 반환 |
| 5 | `Sources/MovieCutCore/Audio/NoiseReductionProcessor.swift` | 미구현 | no-op 처리 |
| 6 | `Sources/MovieCutCore/Cloud/CloudSyncService.swift` | 모의 구현 | 네트워크 통신 없이 지연 후 성공 반환 |
| 7 | `Sources/MovieCutCore/Templates/TemplateMarketplace.swift` | 모의 구현 | 실제 온라인 marketplace가 아니라 mock 데이터 |
| 8 | `Sources/MovieCutCore/Export/ExportProgress.swift` | 부분 구현 | 실제 export progress와 미연동된 시뮬레이션 |
| 9 | `App/MovieCutiOS/ContentView.swift` | 미구현 | "No Project Open" placeholder |
| 10 | `App/MovieCutiOS/Views/PreviewView.swift` | 미구현 | `AVPlayer` 없는 상태 토글 UI |
| 11 | 필터 intensity 적용 경로 | 부분 구현 | `Effect.parameters`는 있으나 플러그인별 실제 반영 확인 필요 |
| 12 | 속도 램핑 곡선 편집/렌더링 경로 | 부분 구현 | 모델과 `playbackRate`는 있으나 UI/곡선 적용 검증 필요 |
| 13 | 역재생 export/render 경로 | 부분 구현 | `isReversed` 플래그는 있으나 실제 역방향 렌더링 불명확 |
| 14 | 마스크 render/composite 경로 | 부분 구현 | 모델/명령은 있으나 실제 마스크 적용 불명확 |
| 15 | 텍스트 애니메이션 render 경로 | 부분 구현 | `TextAnimation` 모델 정의만 확인됨 |
| 16 | 애니메이션 스티커/GIF 재생 경로 | 부분 구현 | GIF 재생 미지원, 애니메이션 정의만 있음 |
| 17 | EQ 필터 적용 경로 | 부분 구현 | `EqualizerPreset` 데이터만 있고 실제 필터 처리 없음 |
| 18 | 협업/원격 프로젝트 상태 관리 | 미구현 | 실시간 협업 기능 없음 |

## 실제 구현이 필요한 항목 (우선순위)

### Critical (기능이 실제로 동작하지 않음)
1. iOS 편집 화면 구현: placeholder `ContentView`를 실제 프로젝트 로딩, 타임라인, 미디어 import, inspector 연결 화면으로 대체.
2. iOS 프리뷰 플레이어 구현: `PreviewView`에 `AVPlayer` 기반 재생, seek, 현재 시간, 프로젝트 preview composition 연결.
3. 배경 제거 구현: `BackgroundRemovalProvider`를 Vision person segmentation 또는 대체 segmentation pipeline과 연결.
4. 노이즈 감소 구현: `NoiseReductionProcessor` no-op을 실제 오디오 필터 또는 `AVAudioEngine`/AudioUnit 기반 처리로 교체.
5. 클라우드 동기화 구현: `CloudSyncService` mock 성공 처리를 실제 인증, 업로드, 다운로드, 충돌 처리 API로 교체.
6. 템플릿 마켓플레이스 구현: `TemplateMarketplace` mock 데이터를 실제 remote catalog, download, cache, versioning으로 교체.
7. 협업 기능 구현: 프로젝트 공유, presence, conflict resolution, 권한 모델, 변경 이벤트 동기화 추가.

### High (핵심 로직이 스텁 또는 렌더링 연동 불명확)
1. Export progress 연결: `ExportProgress`를 `AVAssetExportSession.progress`, cancel 상태, 실패 상태와 직접 연동.
2. 스타일 트랜스퍼 구현: `StyleTransferProvider`가 원본 반환 대신 실제 Core Image filter chain 또는 ML style model을 적용.
3. 역재생 렌더링 구현: `ReverseClipCommand`의 `isReversed`를 export/render pipeline에서 실제 역방향 프레임 샘플링으로 반영.
4. 마스크 렌더링 구현: `Mask`와 `SetClipMaskCommand` 결과를 video composition 단계에서 적용.
5. 텍스트 애니메이션 렌더링 구현: `TextAnimation`을 시간 기반 transform/opacity/style animation으로 export와 preview 양쪽에 적용.
6. 속도 램핑 검증 및 보강: 램핑 곡선 UI, interpolation, export time mapping을 통합 검증.
7. 이퀄라이저 적용 구현: `EqualizerPreset`을 실제 EQ filter chain에 연결.

### Medium (기능은 있으나 품질 개선 필요)
1. 필터 intensity 일관화: 모든 effect plugin에서 `intensity` 파라미터를 동일한 방식으로 반영.
2. 자동 리프레임 고도화: 단순 구현을 Vision 기반 피사체 추적, smoothing, crop boundary 처리로 개선.
3. 애니메이션 스티커/GIF 지원: GIF decode/playback, timeline duration, export frame rendering 추가.
4. 버전 히스토리 영속화: 현재 로컬 in-memory 기준을 파일/DB 기반 history로 확장.
5. 의도적 스텁 provider 분리: `StubAnalysisProvider`, `StubTranscriptionProvider`가 완료율 계산에 섞이지 않도록 test/mock namespace나 명확한 fallback 등록 정책으로 분리.
