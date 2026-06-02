# MovieCut vs CapCut 기능 갭 분석

## 요약
- 전체 CapCut 기능: 88개
- 완전 구현: 41개 (46.6%)
- 부분 구현: 17개 (19.3%)
- 미구현: 30개 (34.1%)

> 판정 기준: `✅완료`는 요약상 모델, 편집 흐름, UI 또는 렌더링 경로가 명확히 구현된 기능입니다. `🟡부분`은 데이터 모델, 프로토콜, 일부 UI, 또는 제한된 구현은 있으나 CapCut 수준의 사용 경험이나 내보내기 반영이 불완전한 기능입니다. `❌없음`은 요약에 구현 근거가 없거나 명시적으로 stub인 기능입니다.

## 카테고리별 상세

### A. 미디어 가져오기 및 관리
| 기능 | 상태 | 비고 |
|------|------|------|
| 카메라롤 가져오기 | ✅완료 | iOS `MediaBrowserView(PhotosPicker)`로 사진 보관함 가져오기 흐름이 구현되어 있음 |
| 드래그앤드롭 가져오기 | ❌없음 | macOS 드래그앤드롭 가져오기 구현이 요약에 없음 |
| 썸네일 생성 | ✅완료 | `ThumbnailGenerator`가 `AVAssetImageGenerator` 기반 썸네일 추출을 구현 |
| 다중 선택 가져오기 | ❌없음 | 다중 선택 import 흐름이 명시되어 있지 않음 |
| 폴더 정리 | ❌없음 | 미디어 폴더, 앨범, 컬렉션 기반 정리 기능 없음 |

### B. 타임라인 편집
| 기능 | 상태 | 비고 |
|------|------|------|
| 트림(핸들 드래그) | 🟡부분 | `TrimClip` 명령과 `TimelineView`는 있으나 핸들 드래그 UX는 명시되지 않음 |
| 분할 | ✅완료 | `SplitClip` 명령 구현 |
| 삭제 | ✅완료 | `DeleteClip` 명령 구현 |
| 이동 | ✅완료 | `MoveClip` 명령 구현 |
| 복사/붙여넣기 | ✅완료 | `CopyClipCommand` 구현 |
| 중복 | ✅완료 | `DuplicateClipCommand` 구현 |
| 리플 편집 | ✅완료 | `RippleDeleteCommand` 구현 |
| 스냅 | ❌없음 | 클립 경계, 재생 헤드, 마커 기준 스냅 기능 없음 |
| 타임라인 줌 | ❌없음 | 줌 레벨 또는 타임 스케일 조절 기능 없음 |
| 트랙 잠금 | ✅완료 | `SetTrackPropertyCommand`의 `isLocked` 제어 구현 |
| 트랙 음소거 | ✅완료 | `SetTrackPropertyCommand`의 `isMuted` 제어 구현 |
| 트랙 숨기기 | ✅완료 | `SetTrackPropertyCommand`의 `isHidden` 제어 구현 |
| 실행취소/다시실행 | ✅완료 | `EditorSession(actor)` 기반 undo/redo 구현 |

### C. 비디오 이펙트/필터
| 기능 | 상태 | 비고 |
|------|------|------|
| 필터 프리셋 | ✅완료 | `Effect` 모델과 Grayscale/Sepia/Blur 등 내장 필터 프리셋 구현 |
| 필터 강도 | 🟡부분 | 이펙트 모델과 Inspector는 있으나 전용 강도 조절 UX/렌더 적용 범위가 명확하지 않음 |
| 색보정(밝기/대비/채도/색온도) | ✅완료 | `SetColorCorrectionCommand`로 brightness/contrast/saturation/warmth/tint 제어 구현 |
| 블러(배경/방사형) | 🟡부분 | Blur 이펙트는 있으나 배경 블러, 방사형 블러 같은 세부 모드는 없음 |
| 속도 램핑 | 🟡부분 | `SpeedRampPoint` 모델은 있으나 실제 편집 UX와 내보내기 적용이 명확하지 않음 |
| 역재생 | ✅완료 | `ReverseClipCommand`와 `isReversed` 상태 구현 |
| 정지 프레임 | ✅완료 | `FreezeFrameCommand` 구현 |
| PIP(화중화) | ✅완료 | 다중 트랙, `ClipTransform`, 위치/크기 조절을 통해 오버레이 편집 가능 |
| 마스킹 | ❌없음 | 도형/브러시/선형 마스크 기능 없음 |

### D. 전환
| 기능 | 상태 | 비고 |
|------|------|------|
| 페이드 전환 | ✅완료 | `BuiltinTransitionPlugins`의 Fade 전환과 CoreImage 렌더링 구현 |
| 디졸브 전환 | ✅완료 | `BuiltinTransitionPlugins`의 Dissolve 전환과 CoreImage 렌더링 구현 |
| 슬라이드 전환 | ✅완료 | `BuiltinTransitionPlugins`의 Slide 전환과 CoreImage 렌더링 구현 |
| 와이프 전환 | ✅완료 | `BuiltinTransitionPlugins`의 Wipe 전환과 CoreImage 렌더링 구현 |
| 줌 전환 | ❌없음 | 전환 4종 외 확장 프리셋 구현 없음 |
| 글리치 전환 | ❌없음 | 전환 4종 외 확장 프리셋 구현 없음 |
| 전환 지속시간 | 🟡부분 | 전환 모델에 포함될 가능성은 있으나 렌더 적용이 확실하지 않음 |
| 오디오 크로스페이드 | ❌없음 | 전환 구간 오디오 크로스페이드 기능 없음 |

### E. 텍스트/자막
| 기능 | 상태 | 비고 |
|------|------|------|
| 폰트 선택 | 🟡부분 | `TextClipContent`와 자막 Inspector는 있으나 명확한 폰트 선택 UI는 요약에 없음 |
| 텍스트 애니메이션: 페이드 | ❌없음 | 텍스트 전용 애니메이션 프리셋 없음 |
| 텍스트 애니메이션: 타입라이터 | ❌없음 | 타입라이터 애니메이션 없음 |
| 텍스트 애니메이션: 바운스 | ❌없음 | 바운스 애니메이션 없음 |
| 자동 자막(STT) | ✅완료 | Apple Speech 온디바이스 기반 `SpeechTranscriptionProvider`와 `SubtitleGenerator` 구현 |
| 자막 스타일링(폰트/색/배경/위치) | 🟡부분 | 텍스트 콘텐츠와 Inspector는 있으나 CapCut 수준의 세부 스타일링 전체는 명확하지 않음 |
| 텍스트 템플릿 | ❌없음 | 텍스트 디자인 템플릿 또는 프리셋 없음 |

### F. 오디오
| 기능 | 상태 | 비고 |
|------|------|------|
| 클립별 볼륨 | ✅완료 | `SetVolume` 명령과 Inspector 볼륨 제어 구현 |
| 페이드인/아웃 | ✅완료 | `AudioFadeCommand`로 `fadeInDuration`/`fadeOutDuration` 제어 구현 |
| 배경음악 라이브러리 | ✅완료 | `MusicLibrary`와 `MusicLibraryView` 구현 |
| 비디오에서 오디오 추출 | ❌없음 | Extract audio 기능 없음 |
| 음성해설 녹음 | ✅완료 | `VoiceoverRecorder(AVAudioEngine)`와 녹음 UI 구현 |
| 오디오 더킹 | ❌없음 | 음성 감지 시 음악 볼륨 자동 감소 기능 없음 |
| 효과음 라이브러리 | ❌없음 | SFX 라이브러리 없음 |
| 이퀄라이저 | ❌없음 | EQ 필터 또는 UI 없음 |
| 노이즈 감소 | ❌없음 | 노이즈 리덕션 처리 없음 |

### G. 스티커/오버레이
| 기능 | 상태 | 비고 |
|------|------|------|
| 이모지 스티커 | ✅완료 | `StickerAsset` 16개 이모지와 `StickerPickerView` 구현 |
| 애니메이션 스티커/GIF | ❌없음 | Animated sticker 또는 GIF 지원 없음 |
| 커스텀 이미지 오버레이 | 🟡부분 | 미디어 자산과 다중 트랙으로 유사 구현 가능하나 전용 스티커/오버레이 흐름은 명확하지 않음 |
| 크로마키 | ✅완료 | `ChromaKeySettings`, `ChromaKeyView`, `ChromaKeyCompositor(AVVideoCompositing)` 기반 Export 렌더링 구현 |
| 제스처 리사이즈/회전 | 🟡부분 | `ClipTransform`은 있으나 iOS 제스처 기반 resize/rotate 구현은 명시되지 않음 |

### H. 내보내기
| 기능 | 상태 | 비고 |
|------|------|------|
| 해상도 프리셋(720p/1080p/4K) | 🟡부분 | `ExportSettings`와 `CanvasPreset`은 있으나 해당 프리셋 세트가 명확하지 않음 |
| 프레임레이트(24/30/60) | 🟡부분 | `ExportSettings`는 있으나 프레임레이트 프리셋 UI/검증이 명확하지 않음 |
| 코덱 선택 | 🟡부분 | `ExportSettings`는 있으나 사용자 선택 가능한 코덱 옵션이 명확하지 않음 |
| 비트레이트 설정 | 🟡부분 | `ExportSettings`는 있으나 CapCut식 비트레이트 제어 UX는 명확하지 않음 |
| 진행률+취소 | ❌없음 | Export 진행률 표시 및 취소 기능이 요약에 없음 |
| 소셜 공유 | ❌없음 | TikTok/YouTube/Instagram 등 공유 흐름 없음 |
| 프로젝트 저장/불러오기 | ✅완료 | `ProjectStore(JSON 직렬화)` 구현 |

### I. AI 기능
| 기능 | 상태 | 비고 |
|------|------|------|
| 자동 컷(침묵 제거) | ✅완료 | `SilenceDetectionProvider`와 `AutoCutEngine` 구현 |
| 장면 감지 | ✅완료 | AVFoundation 히스토그램 기반 `SceneChangeProvider` 구현 |
| 스마트 트림 | 🟡부분 | 자동 컷 제안과 명령 변환은 있으나 의미 기반 스마트 트림은 제한적 |
| 배경 제거 | ❌없음 | 인물/객체 분리 기반 배경 제거 없음 |
| 자동 리프레임 | ❌없음 | 피사체 추적 기반 비율 변환 없음 |
| 스타일 트랜스퍼 | ❌없음 | 영상 스타일 변환 AI 기능 없음 |

### J. 템플릿
| 기능 | 상태 | 비고 |
|------|------|------|
| 프리메이드 템플릿 | ✅완료 | `TemplateStore`와 3개 내장 템플릿 구현 |
| 템플릿 마켓플레이스 | ❌없음 | 외부/온라인 템플릿 탐색 및 다운로드 없음 |
| 기존 프로젝트에서 템플릿 생성 | ❌없음 | 현재 프로젝트를 템플릿으로 저장하는 기능 없음 |

### K. 캔버스/비율
| 기능 | 상태 | 비고 |
|------|------|------|
| 9:16 프리셋 | ✅완료 | Shorts/Reels 템플릿과 CanvasPreset 기반 지원 |
| 16:9 프리셋 | ✅완료 | Landscape Tutorial 템플릿과 CanvasPreset 기반 지원 |
| 1:1 프리셋 | ✅완료 | Square Social 템플릿과 CanvasPreset 기반 지원 |
| 4:5 프리셋 | 🟡부분 | 커스텀 캔버스로 가능할 수 있으나 명시적 프리셋은 없음 |
| 21:9 프리셋 | 🟡부분 | 커스텀 캔버스로 가능할 수 있으나 명시적 프리셋은 없음 |
| 커스텀 비율 | ✅완료 | `SetProjectCanvas`와 `CanvasSettingsView` 구현 |
| 안전영역 가이드 | ❌없음 | 플랫폼별 safe area/title safe 가이드 없음 |

### L. 키프레임
| 기능 | 상태 | 비고 |
|------|------|------|
| 위치 키프레임 | ✅완료 | `Keyframe` 7개 속성과 `KeyframeEditorView` 구현 |
| 크기 키프레임 | ✅완료 | `ClipTransform`과 키프레임 속성으로 지원 |
| 회전 키프레임 | ✅완료 | `ClipTransform`과 키프레임 속성으로 지원 |
| 불투명도 키프레임 | ✅완료 | opacity 속성과 키프레임 지원 |
| 이징 커브 | ✅완료 | 5개 보간법 구현 |
| 그래프 에디터 | 🟡부분 | `KeyframeEditorView`는 있으나 곡선 그래프 편집기 수준인지는 명확하지 않음 |

### M. 클라우드
| 기능 | 상태 | 비고 |
|------|------|------|
| 프로젝트 동기화 | ❌없음 | 로컬 JSON 저장은 있으나 클라우드 sync 없음 |
| 협업 | ❌없음 | 다중 사용자 편집, 댓글, 공유 권한 기능 없음 |
| 버전 히스토리 | ❌없음 | 프로젝트 변경 이력 또는 복원 기능 없음 |

## 우선순위 권장사항

### Critical (앱이 정상 동작하지 않음)
1. 신규 구현으로 `ThumbnailGenerator`가 `AVAssetImageGenerator` 기반 썸네일 추출을 제공.
2. 신규 구현으로 `WaveformGenerator`가 `AVAssetReader` 기반 파형 데이터 생성을 제공.
3. 신규 구현으로 크로마키 Export 렌더링이 `ChromaKeyCompositor(AVVideoCompositing)`에 반영됨.

### High (핵심 편집 경험)
1. 타임라인 생산성 기능 추가: 스냅, 줌.
2. 전환 보강: 줌/글리치 전환 같은 확장 프리셋과 전환 지속시간 제어 완성.
3. 오디오 기본 편집 확장: 비디오 오디오 추출, 오디오 더킹을 우선 구현.
4. Export UX 보강: 진행률, 취소, 해상도/프레임레이트/코덱/비트레이트 프리셋 UI를 명확히 제공.
5. 색보정 및 속도 기능 보강: 필터 강도, 속도 램핑 렌더 적용.

### Medium (완성도)
1. 텍스트 기능 확장: 폰트 선택, 자막 스타일링, 텍스트 애니메이션, 텍스트 템플릿.
2. 스티커/오버레이 확장: GIF/애니메이션 스티커, 커스텀 이미지 오버레이 워크플로, 제스처 기반 resize/rotate.
3. 캔버스 보강: 4:5, 21:9 명시적 프리셋과 안전영역 가이드 추가.
4. 키프레임 고도화: 실제 그래프 에디터와 커브 조정 UI 제공.
5. AI 편집 보강: 스마트 트림을 침묵/장면 기반에서 의미 기반 추천으로 확장하고 자동 리프레임을 추가.

### Low (있으면 좋음)
1. 템플릿 마켓플레이스와 기존 프로젝트 기반 템플릿 생성.
2. 소셜 공유 연동.
3. 효과음 라이브러리, 이퀄라이저, 노이즈 감소.
4. 배경 제거, 스타일 트랜스퍼 같은 고급 AI 기능.
5. 클라우드 프로젝트 동기화, 협업, 버전 히스토리.
