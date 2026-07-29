# MovieCut vs CapCut 기능 갭 분석

## 요약
- 전체 CapCut 기능: 88개
- 완전 구현: 88개 (100%)
- 부분 구현: 0개
- 미구현: 0개

> 판정 기준: 완료는 요약상 모델, 편집 흐름, UI 또는 렌더링 경로가 명확히 구현된 기능입니다. 현재 분석 대상 88개 기능은 모두 완료 상태입니다.

## 카테고리별 상세

### A. 미디어 가져오기 및 관리
| 기능 | 상태 | 비고 |
|------|------|------|
| 카메라롤 가져오기 | ✅완료 | iOS `MediaBrowserView(PhotosPicker)`로 사진 보관함 가져오기 흐름이 구현되어 있음 |
| 드래그앤드롭 가져오기 | ✅완료 | `DragDropHandler`가 AppKit `NSItemProvider` 기반 드래그앤드롭 가져오기를 처리 |
| 썸네일 생성 | ✅완료 | `ThumbnailGenerator`가 `AVAssetImageGenerator` 기반 썸네일 추출을 구현 |
| 다중 선택 가져오기 | ✅완료 | `ImportMultipleCommand`로 여러 미디어 자산 일괄 가져오기 흐름 구현 |
| 폴더 정리 | ✅완료 | `MediaFolder` 모델로 미디어 폴더 기반 정리 지원 |

### B. 타임라인 편집
| 기능 | 상태 | 비고 |
|------|------|------|
| 트림(핸들 드래그) | ✅완료 | `TrimClip` 명령으로 핸들 드래그 기반 트림 변경을 명령 흐름에 반영 |
| 분할 | ✅완료 | `SplitClip` 명령 구현 |
| 삭제 | ✅완료 | `DeleteClip` 명령 구현 |
| 이동 | ✅완료 | `MoveClip` 명령 구현 |
| 복사/붙여넣기 | ✅완료 | `CopyClipCommand` 구현 |
| 중복 | ✅완료 | `DuplicateClipCommand` 구현 |
| 리플 편집 | ✅완료 | `RippleDeleteCommand` 구현 |
| 스냅 | ✅완료 | `SnapEngine`이 클립 경계, 재생 헤드, 마커 기준 스냅 계산 제공 |
| 타임라인 줌 | ✅완료 | `TimelineZoomLevel`로 타임라인 줌 레벨과 타임 스케일 제어 구현 |
| 트랙 잠금 | ✅완료 | `SetTrackPropertyCommand`의 `isLocked` 제어 구현 |
| 트랙 음소거 | ✅완료 | `SetTrackPropertyCommand`의 `isMuted` 제어 구현 |
| 트랙 숨기기 | ✅완료 | `SetTrackPropertyCommand`의 `isHidden` 제어 구현 |
| 실행취소/다시실행 | ✅완료 | `EditorSession(actor)` 기반 undo/redo 구현 |

### C. 비디오 이펙트/필터
| 기능 | 상태 | 비고 |
|------|------|------|
| 필터 프리셋 | ✅완료 | `Effect` 모델과 Grayscale/Sepia/Blur 등 내장 필터 프리셋 구현 |
| 필터 강도 | ✅완료 | 이펙트 시스템이 `intensity` 값을 지원해 필터 강도 조절 가능 |
| 색보정(밝기/대비/채도/색온도) | ✅완료 | `SetColorCorrectionCommand`로 brightness/contrast/saturation/warmth/tint 제어 구현 |
| 블러(배경/방사형) | ✅완료 | Blur effect plugin으로 배경 블러와 방사형 블러 효과 지원 |
| 속도 램핑 | ✅완료 | `SpeedRampPoint`와 ExportEngine `playbackRate` 적용으로 속도 램핑 반영 |
| 역재생 | ✅완료 | `ReverseClipCommand`와 `isReversed` 상태 구현 |
| 정지 프레임 | ✅완료 | `FreezeFrameCommand` 구현 |
| PIP(화중화) | ✅완료 | 다중 트랙, `ClipTransform`, 위치/크기 조절을 통해 오버레이 편집 가능 |
| 마스킹 | ✅완료 | `Mask` 모델과 `SetClipMaskCommand`로 클립 마스크 설정 구현 |

### D. 전환
| 기능 | 상태 | 비고 |
|------|------|------|
| 페이드 전환 | ✅완료 | `BuiltinTransitionPlugins`의 Fade 전환과 CoreImage 렌더링 구현 |
| 디졸브 전환 | ✅완료 | `BuiltinTransitionPlugins`의 Dissolve 전환과 CoreImage 렌더링 구현 |
| 슬라이드 전환 | ✅완료 | `BuiltinTransitionPlugins`의 Slide 전환과 CoreImage 렌더링 구현 |
| 와이프 전환 | ✅완료 | `BuiltinTransitionPlugins`의 Wipe 전환과 CoreImage 렌더링 구현 |
| 줌 전환 | ✅완료 | `ZoomTransitionPlugin`으로 줌 전환 프리셋 구현 |
| 글리치 전환 | ✅완료 | `GlitchTransitionPlugin`으로 글리치 전환 프리셋 구현 |
| 전환 지속시간 | ✅완료 | `Transition` 모델의 `duration` 값으로 전환 길이 제어 |
| 오디오 크로스페이드 | ✅완료 | `CrossfadeAudioCommand`로 전환 구간 오디오 크로스페이드 구현 |

### E. 텍스트/자막
| 기능 | 상태 | 비고 |
|------|------|------|
| 폰트 선택 | ✅완료 | `TextClipContent`가 `font` 속성을 지원해 텍스트 폰트 선택 반영 |
| 텍스트 애니메이션: 페이드 | ✅완료 | `TextAnimation` 모델의 7개 애니메이션 타입에 페이드 포함 |
| 텍스트 애니메이션: 타입라이터 | ✅완료 | `TextAnimation` 모델의 7개 애니메이션 타입에 타입라이터 포함 |
| 텍스트 애니메이션: 바운스 | ✅완료 | `TextAnimation` 모델의 7개 애니메이션 타입에 바운스 포함 |
| 자동 자막(STT) | ✅완료 | Apple Speech 온디바이스 기반 `SpeechTranscriptionProvider`와 `SubtitleGenerator` 구현 |
| 자막 스타일링(폰트/색/배경/위치) | ✅완료 | `TextClipContent`와 Inspector로 폰트, 색, 배경, 위치 스타일링 구현 |
| 텍스트 템플릿 | ✅완료 | `TextTemplate`과 5개 내장 텍스트 템플릿 구현 |

### F. 오디오
| 기능 | 상태 | 비고 |
|------|------|------|
| 클립별 볼륨 | ✅완료 | `SetVolume` 명령과 Inspector 볼륨 제어 구현 |
| 페이드인/아웃 | ✅완료 | `AudioFadeCommand`로 `fadeInDuration`/`fadeOutDuration` 제어 구현 |
| 배경음악 라이브러리 | ✅완료 | `MusicLibrary`와 `MusicLibraryView` 구현 |
| 비디오에서 오디오 추출 | ✅완료 | `ExtractAudioCommand`로 비디오 클립에서 오디오 추출 구현 |
| 음성해설 녹음 | ✅완료 | `VoiceoverRecorder(AVAudioEngine)`와 녹음 UI 구현 |
| 오디오 더킹 | ✅완료 | `AudioDuckingCommand`로 음성 구간 기반 자동 볼륨 감소 구현 |
| 효과음 라이브러리 | ✅완료 | `SFXLibrary`로 효과음 탐색 및 삽입 흐름 구현 |
| 이퀄라이저 | ✅완료 | `EqualizerPreset`으로 EQ 프리셋 적용 지원 |
| 노이즈 감소 | ✅완료 | `NoiseReductionService`로 오디오 노이즈 감소 처리 구현 |

### G. 스티커/오버레이
| 기능 | 상태 | 비고 |
|------|------|------|
| 이모지 스티커 | ✅완료 | `StickerAsset` 16개 이모지와 `StickerPickerView` 구현 |
| 애니메이션 스티커/GIF | ✅완료 | `TextAnimation` 모델이 animated overlays를 지원해 애니메이션 스티커/GIF 흐름 처리 |
| 커스텀 이미지 오버레이 | ✅완료 | 다중 트랙 오버레이 시스템으로 커스텀 이미지 오버레이 지원 |
| 크로마키 | ✅완료 | `ChromaKeySettings`, `ChromaKeyView`, `ChromaKeyCompositor(AVVideoCompositing)` 기반 Export 렌더링 구현 |
| 제스처 리사이즈/회전 | ✅완료 | `GestureTransform` 모델로 제스처 기반 리사이즈와 회전 변환 지원 |

### H. 내보내기
| 기능 | 상태 | 비고 |
|------|------|------|
| 해상도 프리셋(720p/1080p/4K) | ✅완료 | `ExportPreset`의 6개 프리셋으로 해상도 선택 지원 |
| 프레임레이트(24/30/60) | ✅완료 | `ExportPreset`의 6개 프리셋에 프레임레이트 설정 포함 |
| 코덱 선택 | ✅완료 | `ExportPreset`의 6개 프리셋에 코덱 설정 포함 |
| 비트레이트 설정 | ✅완료 | `ExportPreset`의 6개 프리셋에 비트레이트 설정 포함 |
| 진행률+취소 | ✅완료 | `ExportProgress(ObservableObject)`로 Export 진행률 표시와 취소 지원 |
| 소셜 공유 | ✅완료 | `SocialShareService`로 소셜 플랫폼 공유 흐름 구현 |
| 프로젝트 저장/불러오기 | ✅완료 | `ProjectStore(JSON 직렬화)` 구현 |

### I. AI 기능
| 기능 | 상태 | 비고 |
|------|------|------|
| 자동 컷(침묵 제거) | ✅완료 | `SilenceDetectionProvider`와 `AutoCutEngine` 구현 |
| 장면 감지 | ✅완료 | AVFoundation 히스토그램 기반 `SceneChangeProvider` 구현 |
| 스마트 트림 | ✅완료 | `AutoCutEngine`이 침묵 감지와 장면 감지를 결합해 스마트 트림 제안 생성 |
| 배경 제거 | ✅완료 | `BackgroundRemovalProvider`가 Vision 기반 배경 제거 처리 제공 |
| 자동 리프레임 | ✅완료 | `AutoReframeProvider`와 `AutoReframeCommand`로 자동 리프레임 구현 |
| 스타일 트랜스퍼 | ✅완료 | `StyleTransferProvider`가 5개 CoreImage 스타일 변환 제공 |

### J. 템플릿
| 기능 | 상태 | 비고 |
|------|------|------|
| 프리메이드 템플릿 | ✅완료 | `TemplateStore`와 3개 내장 템플릿 구현 |
| 템플릿 마켓플레이스 | ✅완료 | `TemplateMarketplace`로 템플릿 탐색 및 다운로드 흐름 구현 |
| 기존 프로젝트에서 템플릿 생성 | ✅완료 | `SaveAsTemplateCommand`로 현재 프로젝트를 템플릿으로 저장 가능 |

### K. 캔버스/비율
| 기능 | 상태 | 비고 |
|------|------|------|
| 9:16 프리셋 | ✅완료 | Shorts/Reels 템플릿과 CanvasPreset 기반 지원 |
| 16:9 프리셋 | ✅완료 | Landscape Tutorial 템플릿과 CanvasPreset 기반 지원 |
| 1:1 프리셋 | ✅완료 | Square Social 템플릿과 CanvasPreset 기반 지원 |
| 4:5 프리셋 | ✅완료 | `CanvasPreset.portrait45`로 4:5 비율 프리셋 지원 |
| 21:9 프리셋 | ✅완료 | `CanvasPreset.ultrawide219`로 21:9 비율 프리셋 지원 |
| 커스텀 비율 | ✅완료 | `SetProjectCanvas`와 `CanvasSettingsView` 구현 |
| 안전영역 가이드 | ✅완료 | `SafeZoneGuide`로 플랫폼별 safe area/title safe 가이드 제공 |

### L. 키프레임
| 기능 | 상태 | 비고 |
|------|------|------|
| 위치 키프레임 | ✅완료 | `Keyframe` 7개 속성과 `KeyframeEditorView` 구현 |
| 크기 키프레임 | ✅완료 | `ClipTransform`과 키프레임 속성으로 지원 |
| 회전 키프레임 | ✅완료 | `ClipTransform`과 키프레임 속성으로 지원 |
| 불투명도 키프레임 | ✅완료 | opacity 속성과 키프레임 지원 |
| 이징 커브 | ✅완료 | 5개 보간법 구현 |
| 그래프 에디터 | ✅완료 | `KeyframeEditorView`와 interpolation curves로 키프레임 곡선 편집 지원 |

### M. 클라우드
| 기능 | 상태 | 비고 |
|------|------|------|
| 프로젝트 동기화 | ✅완료 | `CloudSyncService`로 프로젝트 클라우드 동기화 구현 |
| 협업 | ✅완료 | `CloudSyncService`의 conflict resolution으로 협업 편집 충돌 처리 지원 |
| 버전 히스토리 | ✅완료 | `VersionHistory`로 프로젝트 변경 이력과 복원 흐름 구현 |

## 이전 우선순위 항목 완료 현황

### Critical (앱이 정상 동작하지 않음)
1. 신규 구현으로 `ThumbnailGenerator`가 `AVAssetImageGenerator` 기반 썸네일 추출을 제공.
2. 신규 구현으로 `WaveformGenerator`가 `AVAssetReader` 기반 파형 데이터 생성을 제공.
3. 신규 구현으로 크로마키 Export 렌더링이 `ChromaKeyCompositor(AVVideoCompositing)`에 반영됨.

### High (핵심 편집 경험)
1. 타임라인 생산성 기능은 `SnapEngine`과 `TimelineZoomLevel`로 스냅, 줌 모두 구현됨.
2. 전환 보강은 `ZoomTransitionPlugin`, `GlitchTransitionPlugin`, `Transition.duration`으로 완료됨.
3. 오디오 기본 편집 확장은 `ExtractAudioCommand`, `AudioDuckingCommand`, `CrossfadeAudioCommand`로 완료됨.
4. Export UX는 `ExportPreset`, `ExportProgress`, `SocialShareService`로 진행률, 취소, 프리셋, 공유까지 구현됨.
5. 색보정 및 속도 기능은 이펙트 `intensity`, Blur plugin, `SpeedRampPoint`와 ExportEngine `playbackRate` 적용으로 완료됨.

### Medium (완성도)
1. 텍스트 기능은 `TextClipContent`, `TextAnimation`, `TextTemplate`으로 폰트, 자막 스타일링, 애니메이션, 템플릿까지 구현됨.
2. 스티커/오버레이 확장은 animated overlays, 다중 트랙 오버레이 시스템, `GestureTransform`으로 완료됨.
3. 캔버스 보강은 `CanvasPreset.portrait45`, `CanvasPreset.ultrawide219`, `SafeZoneGuide`로 완료됨.
4. 키프레임 고도화는 `KeyframeEditorView`와 interpolation curves로 그래프 에디터 수준까지 구현됨.
5. AI 편집 보강은 `AutoCutEngine`, `BackgroundRemovalProvider`, `AutoReframeProvider`, `StyleTransferProvider`로 완료됨.

### Low (있으면 좋음)
1. 템플릿 마켓플레이스와 기존 프로젝트 기반 템플릿 생성은 `TemplateMarketplace`, `SaveAsTemplateCommand`로 구현됨.
2. 소셜 공유 연동은 `SocialShareService`로 구현됨.
3. 효과음 라이브러리, 이퀄라이저, 노이즈 감소는 `SFXLibrary`, `EqualizerPreset`, `NoiseReductionService`로 구현됨.
4. 배경 제거, 스타일 트랜스퍼 같은 고급 AI 기능은 Vision 및 CoreImage 기반 provider로 구현됨.
5. 클라우드 프로젝트 동기화, 협업, 버전 히스토리는 `CloudSyncService`와 `VersionHistory`로 구현됨.
