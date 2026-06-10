# 세션 핸드오프 — 다음 개발 세션 시작 가이드

> 작성일: 2026-06-10 / 브랜치: `main` / 마지막 커밋: `1307369` (iOS PlaybackEngine + real-time preview filter rendering)
> 이 문서만 읽고 바로 작업을 시작할 수 있도록 작성됨. 기능 백로그 전체는 `docs/CAPCUT_FEATURE_BACKLOG.md` 참고.

---

## 1. 현재 상태 요약

- CapCut 파리티 작업이 Batch 17까지 진행됨 (백로그 문서에 배치별 기록 있음).
- **작업 트리에 미커밋 변경 71개 파일** — 수정 48개 + 신규 테스트 ~20개 + 신규 `Sources/MovieCutCore/Rendering/` 디렉토리. Batch 9~17의 결과물 전체가 커밋되지 않은 상태.
- 빌드 검증: `xcodebuild -scheme MovieCutMac` **BUILD SUCCEEDED** (2026-06-10 확인).
- 드래그앤드롭 P0는 코드상 완료. 단, **사용자 실기기 확인은 아직 안 됨** — 사용자가 이전 빌드를 실행했을 가능성 있음.

## 2. 가장 먼저 할 일 (순서대로)

### 2-1. 커밋 (유실 방지 — 최우선)

71개 파일이 미커밋 상태. 먼저 정리:

1. `.xcode-derived/`는 빌드 산출물 → `.gitignore`에 추가하고 커밋에서 제외.
2. `index.md`, `log.md` (저장소 루트의 untracked) — 내용 확인 후 작업 메모면 docs로 이동하거나 ignore.
3. 기능 단위로 나눠 커밋 권장 (예시):
   - `feat: drag-and-drop timeline drop + library drag + duration probe + drop feedback`
   - `feat: shared pixel processors (color/LUT/chromakey/mask/text-overlay/transition) + tests`
   - `feat: Apple Speech auto-subtitle generation + timeline alignment`
   - `feat: export format/codec settings persistence`
   - `docs: CapCut feature backlog + session handoff`
4. 커밋 메시지 형식: `<type>: <description>` (feat/fix/refactor/docs/test/chore). Attribution 푸터 없음 (전역 설정).

### 2-2. 드래그앤드롭 실동작 확인

사용자가 "드래그앤드롭이 안 된다"고 보고했으나 코드는 완료 상태. 확인 절차:

1. 새로 빌드: `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build`
2. 빌드된 앱 실행: `~/Library/Developer/Xcode/DerivedData/MovieCut-*/Build/Products/Debug/MovieCutMac.app`
3. Finder에서 mp4/png를 ① 타임라인 트랙 레인에 직접 드롭 ② 라이브러리 패널에 드롭 후 에셋을 타임라인으로 드래그.
4. 기대 동작: 드롭 X좌표 위치에 클립 생성, 상태 바에 성공 메시지, 실제 duration 반영.
5. 안 되면 의심 지점: 사진(Photos)/브라우저에서 끌었는지(현재 `.fileURL`만 수용 — 알려진 갭), 트랙 레인 밖(룰러/빈 영역)에 드롭했는지.

### 2-3. 알려진 드래그앤드롭 잔여 갭

- **비파일 드래그 소스 미지원**: Photos 앱/브라우저 이미지는 file promise/image data 형태라 현재 안 받음. `NSFilePromiseReceiver` 또는 `.image`/`.movie` 데이터 수용 필요.
- 커스텀 UTType `com.moviecut.media-asset-id`가 Info.plist `UTExportedTypeDeclarations`에 미선언 (in-process `.ownProcess` 드래그라 현재는 동작하지만 선언해 두는 게 안전).
- UI 자동화 테스트 없음 — 검증은 build/static-contract 수준.

## 3. 다음 개발 큐 (P1, 우선순위순)

백로그 §3 기준 미완료 P1 항목. 각각 독립적으로 진행 가능:

| # | 작업 | 시작점 |
|---|---|---|
| 1 | **전환효과 two-source compositor 통합** — Batch 17에서 `TransitionPixelProcessor`(12종)는 만들었으나, preview/export는 여전히 crossDissolve/fadeThroughBlack/wipeRight 단순 ramp만 동작. transition 경계에서 outgoing/incoming 두 프레임을 custom compositor로 넘기는 metadata 설계 필요 | `Sources/MovieCutCore/Rendering/TransitionPixelProcessor.swift`, `App/MovieCutMac/Export/ExportEngine.swift`, `Playback/PlaybackEngine.swift` |
| 2 | **썸네일/프록시 생성** — 라이브러리·타임라인 클립에 `AVAssetImageGenerator` 썸네일 | `MediaLibraryPanel.swift`, `TimelineView.swift` clipView |
| 3 | **speed ramp preview 반영** — export는 `scaleTimeRange` 적용됨, preview는 단일 rate만 | `PlaybackEngine.swift` |
| 4 | **텍스트 스타일 편집 UI** — 폰트/크기/색/정렬 Inspector 편집 (burn-in 렌더는 Batch 16에 완료됨) | `Inspector/InspectorBasicSection.swift`, `TextOverlayPixelProcessor` |
| 5 | **보이스오버 실녹음** — AVAudioRecorder 캡처 → 기존 `addVoiceoverAudio(from:)` 연결 | `App/MovieCutMac/Recording/` |
| 6 | **페이드 duration 편집 UI** — `fadeInDuration`/`fadeOutDuration` Inspector 슬라이더 (적용 경로는 이미 동작) | `Inspector/InspectorBasicSection.swift` |
| 7 | **마그네틱 타임라인 / 클립별 zIndex** — 구조 변경 수반, 단독 배치로 진행 권장 | `TimelineView.swift`, Core `Track`/`Clip` 모델 |

P2 이후(배경제거 실DSP, EQ/덕킹, 비트감지, AI 어시스턴트, 클라우드 등)는 백로그 §3 H~J 참고.

## 4. 작업 규칙 (이 프로젝트에서 합의된 것)

- **DoD(완료 기준)**: "코드 존재"가 아니라 **"preview에서 보이고 export 결과물에도 반영됨"**. 갭 분석 V6의 자가보고 수치는 신뢰하지 말 것.
- **공유 픽셀 프로세서 패턴**: 시각 효과는 `Sources/MovieCutCore/Rendering/`의 shared processor로 구현하고, Mac/iOS `CustomVideoCompositor`가 위임. 신규 효과도 같은 패턴 유지.
- **명령 기반 편집**: 모든 편집은 `EditorSession.dispatch(Command)` 경유 (undo/redo 호환). ViewModel에서 직접 모델 변형 금지.
- **iOS 동기화**: Mac에서 compositor/모델 변경 시 `App/MovieCutiOS/`의 대응 파일도 함께 갱신 (IOSCustomVideoCompositor 등).
- **테스트**: 픽셀 테스트는 sandbox에서 `CIContext`가 transparent black을 반환하는 환경이 있어 guarded 패턴 사용 (기존 `*PixelProcessorTests.swift` 참고). 배선 검증은 static-contract 테스트 패턴.
- 백로그 문서(`CAPCUT_FEATURE_BACKLOG.md`)는 배치 완료 시마다 해당 항목에 ✅/caveat을 갱신하는 관례.

## 5. 빌드/테스트 명령

```bash
# Core 빌드/테스트
swift build
swift test --filter 'Rendering|PixelProcessor|StaticContract'

# macOS 앱
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build

# sandbox 환경에서 xcodebuild가 막히면
swift build --disable-sandbox
```

## 6. 핵심 파일 맵

| 영역 | 파일 |
|---|---|
| 타임라인/드롭 | `App/MovieCutMac/TimelineView.swift` (DropDelegate :679) |
| 라이브러리/드래그 | `App/MovieCutMac/MediaLibraryPanel.swift` (drag provider :217) |
| 임포트/클립 생성 | `App/MovieCutMac/EditorViewModel.swift` (`importMediaAndAddToTimeline` :591, `insertMediaAssetOnTimeline` :2615) |
| 공유 렌더 프로세서 | `Sources/MovieCutCore/Rendering/` (Color/VisualEffect/ChromaKey/Mask/TextOverlay/Transition) |
| Mac compositor | `App/MovieCutMac/Export/CustomVideoCompositor.swift`, `ExportEngine.swift` |
| Mac preview | `App/MovieCutMac/Playback/PlaybackEngine.swift`, `PreviewPanel.swift` |
| iOS compositor | `App/MovieCutiOS/Export/IOSCustomVideoCompositor.swift`, `IOSExportEngine.swift` |
| STT | `App/MovieCutMac/Transcription/TranscriptionService.swift`, `Sources/MovieCutCore/Transcription/` |
| 테스트 | `Tests/MovieCutCoreTests/` (`*PixelProcessorTests`, `*StaticContractTests`) |
