# CapCut형 핵심 편집 경로 수리 핸드오프

> **[상태: 완료 — 역사 기록]** 현역 문서가 아니다. 전체 문서 지도는 [docs/README.md](README.md).
>
> - 판정 근거: Step 1~7 전부 main 병합 (`4088ee2`). 핵심 편집 경로 수리 종료.
> - 지금 볼 곳: 잔여 과제(iOS 검증 인프라·parity 전체 실행)는 `docs/NEXT_SESSION_WORKORDER_20260729.md` W4~W7로 이관됐다.
> - `docs/archive/`로 옮기지 않은 이유: StaticContract 테스트가 이 경로를 직접 읽는다(경로를 바꾸면 테스트가 깨진다).

> 작성일: 2026-07-27  
> 대상: 다음 개발 세션  
> 기준: 코드 감사 + macOS 전체 빌드 성공 + 핵심 선택 테스트 44개 통과  
> 목표: “기능이 존재한다”가 아니라 **타임라인에서 본 결과와 export 결과가 일치하는 편집기**로 복구

## 0. 현재 판정

MovieCut은 command/undo, import, export, 효과 processor, 오디오, 자막 등 기반 기능은 풍부하다. 그러나 현재 macOS 메인 Preview가 프로젝트 합성 경로를 사용하지 않고 선택한 원본 asset을 직접 재생하며, 모든 트랙에 동일한 magnetic compaction을 적용하고, 배속/Speed ramp의 timeline↔source 시간 일관성이 깨져 있다.

따라서 신규 기능 추가보다 아래 P0/P1 수리를 먼저 완료한다.

## 1. 작업 규율

1. 아래 순서를 바꾸지 않는다. P0 Preview와 트랙 정책이 닫히기 전 신규 기능을 추가하지 않는다.
2. 한 작업 단위마다 behavioral test와 실제 앱 E2E를 함께 추가한다.
3. source 문자열 존재만 확인하는 StaticContract 테스트로 완료 처리하지 않는다.
4. Core Image/AVFoundation 검증이 불가능하면 `return`으로 성공 처리하지 말고 명시적으로 실패시키거나 별도 지원 환경에서 실행되는 필수 테스트로 분리한다.
5. 각 단계 종료 시 `git diff --check`, focused test, Mac Xcode build를 실행한다.
6. 사용자가 요청하지 않는 한 iOS 확장은 macOS P0/P1 복구 뒤에 진행한다.

---

## 2. 권장 수정 순서

### Step 1 — P0: 메인 Preview를 프로젝트 합성 경로로 전환

#### 문제

- `PreviewPanel.loadSelectedClipAsset()`이 `playbackEngine.load(asset:)`로 선택 원본만 재생한다.
- `PlaybackEngine.loadProject(_:)`와 그 내부 custom composition/effect/audio 경로는 메인 Preview UI에서 호출되지 않는다.
- 타임라인의 다른 트랙, 전환, 필터, 마스크, 자막, 오디오 믹스, 캔버스 배경을 편집 중 최종 형태로 볼 수 없다.
- 선택 클립의 `sourceRange.end`가 지나도 원본 재생이 계속되고 playhead만 clip 끝에 고정된다.

#### 시작 파일

- `App/MovieCutMac/PreviewPanel.swift`
- `App/MovieCutMac/Playback/PlaybackEngine.swift`
- `App/MovieCutMac/EditorViewModel.swift`
- `App/MovieCutMac/Playback/VideoPreviewView.swift`

#### 구현 방향

1. `PreviewPanel`의 기본 재생 소스를 `currentProject` 전체 composition으로 바꾼다.
2. 선택 변경은 재생 asset 교체가 아니라 overlay/inspector selection만 바꾸도록 한다.
3. 프로젝트 내용 변경 시 composition을 비동기로 재생성한다.
4. composition 재생성 전후에 다음 상태를 보존한다.
   - 현재 timeline playhead
   - 재생/일시정지 상태
   - preview 전용 볼륨
   - 사용자 transport rate가 별도로 필요하다면 clip speed와 분리된 값
5. 오래 걸린 이전 rebuild 결과가 최신 프로젝트를 덮지 않도록 generation token 또는 cancellable task를 사용한다.
6. `PlaybackEngine` build 실패를 `clear()`로 조용히 삼키지 말고 UI에 전달 가능한 오류 상태로 노출한다.
7. 텍스트·스티커 canvas 편집 overlay는 유지하되, 영상 자체는 project composition frame을 사용한다.

#### 수용 기준

- 영상 2개 + 오디오 1개 + 텍스트 1개 프로젝트를 Preview에서 연속 재생할 수 있다.
- playhead가 클립 경계를 통과하면 다음 클립으로 자연스럽게 전환된다.
- 선택 클립을 바꿔도 재생 시간이 0으로 초기화되지 않는다.
- 필터/색보정/마스크/자막/전환 변경이 Preview에 반영된다.
- 동일 timestamp의 Preview 캡처와 export frame이 허용 오차 내에서 일치한다.
- trim한 clip의 source 범위 밖 원본 프레임이 Preview에 노출되지 않는다.

#### 필수 테스트

- `PreviewPanel`이 `load(asset:)`가 아니라 project composition을 소비하는 actual-app test
- 2개 클립 경계 전후 frame digest 비교
- text/effect가 없는 baseline 대비 적용 frame이 달라지는지 검사
- trim end 이후 다음 clip frame이 나오는지 검사
- rebuild 중 연속 변경에서 stale result가 publish되지 않는지 behavioral test

#### 커밋 권장

`fix(moviecut): wire main preview to project composition`

---

### Step 2 — P0: Magnetic timeline 정책을 트랙 역할별로 분리

#### 문제

- `Track.compactClipsMagnetically()`가 모든 트랙을 0초부터 빈틈없이 다시 배치한다.
- `AddClipCommand`, `MoveClipCommand`, `DeleteClipCommand`, `DuplicateClipCommand`가 트랙 종류와 상관없이 이를 호출한다.
- 텍스트/스티커/BGM/SFX/overlay를 원하는 timeline 위치에 자유 배치할 수 없다.
- 단일 clip을 5초로 이동해도 다시 0초로 돌아갈 수 있다.

#### 시작 파일

- `Sources/MovieCutCore/Commands/CommandSupport.swift`
- `Sources/MovieCutCore/Commands/AddClipCommand.swift`
- `Sources/MovieCutCore/Commands/MoveClipCommand.swift`
- `Sources/MovieCutCore/Commands/DeleteClipCommand.swift`
- `Sources/MovieCutCore/Commands/DuplicateClipCommand.swift`
- `Sources/MovieCutCore/Models/Track.swift`
- `App/MovieCutMac/TimelineView.swift`
- `App/MovieCutMac/EditorViewModel.swift`

#### 구현 방향

1. magnetic 여부를 암묵적으로 모든 track에 적용하지 않는다.
2. 최소 정책:
   - Main video track: magnetic 가능
   - Secondary video/overlay track: 자유 배치
   - Audio track: 자유 배치
   - Text/sticker track: 자유 배치
3. `Track`에 persisted editing policy를 추가하거나, main-track 판정 규칙을 Project/Timeline에 명시한다.
4. 기존 프로젝트 decode 시 안전한 기본값을 제공한다.
5. 일반 Delete는 gap을 유지하고, Ripple Delete만 뒤 클립을 당기도록 의미를 분리한다.
6. same-track drag는 실제 요청 위치를 유지한다.
7. main track magnetic reorder는 clip 순서와 duration만 보존하고 overlay 트랙에는 영향을 주지 않는다.

#### 수용 기준

- 빈 text track에 5초 위치로 text를 추가하면 start가 정확히 5초다.
- audio clip을 7.5초로 이동하면 해당 위치가 유지된다.
- 일반 Delete는 gap을 유지한다.
- Ripple Delete는 gap을 닫는다.
- main video track magnetic mode에서는 reorder가 정상 동작한다.
- 다른 트랙의 clip 위치는 add/move/delete의 부수 효과로 변하지 않는다.
- undo/redo가 모든 영향 track의 exact snapshot을 복원한다.

#### 필수 테스트

- 단일 자유 배치 clip `0 → 5초` 이동
- text/audio/secondary video add-at-playhead 위치 보존
- normal delete와 ripple delete의 결과 차이
- main video magnetic reorder
- mixed-track undo/redo exact equality
- 기존 `.moviecut` fixture legacy decode

#### 커밋 권장

`fix(moviecut): scope magnetic compaction to main video track`

---

### Step 3 — P1: 공통 Timeline↔Source 시간 매핑 도입

#### 문제

현재 시간 환산이 여러 파일에 중복되어 있다.

- constant speed: 일부 경로만 `timeline delta * playbackRate`
- Speed ramp: Playback/Export 내부에서 별도 계산
- Split: timeline 1초를 source 1초로 가정
- drag trim: constant speed조차 반영하지 않음
- hover scrub, motion tracking, subtitle alignment도 각자 환산식을 가진다.

이 상태에서는 기능별로 clip 경계가 달라진다.

#### 시작 파일

- `Sources/MovieCutCore/Models/SpeedRampCurve.swift`
- `Sources/MovieCutCore/Models/Clip.swift`
- 신규 권장: `Sources/MovieCutCore/Timeline/ClipTimeMapping.swift`
- `App/MovieCutMac/Playback/PlaybackEngine.swift`
- `App/MovieCutMac/Export/ExportEngine.swift`
- `App/MovieCutMac/TimelineView.swift`
- `App/MovieCutMac/EditorViewModel.swift`
- `Sources/MovieCutCore/Commands/SplitClipCommand.swift`
- `Sources/MovieCutCore/Commands/TrimClipCommand.swift`

#### 구현 방향

공통 value type을 만든다.

```swift
struct ClipTimeMapping {
    func sourceTime(forTimelineTime: TimeInterval) -> TimeInterval
    func timelineTime(forSourceTime: TimeInterval) -> TimeInterval
    var renderedTimelineDuration: TimeInterval
}
```

요구사항:

1. constant speed와 Speed ramp를 같은 API로 처리한다.
2. source/timeline 범위를 clamp한다.
3. 역재생과 freeze frame 정책을 명시한다.
4. 비정상 값(NaN, infinity, 0 이하 rate)은 fail-closed한다.
5. Playback, Export, Split, Trim, scrub, filmstrip hover가 동일 구현을 사용한다.
6. `SpeedRampCurve`의 normalized mapping을 실제 clip source range에 적용하는 방식과 역함수를 테스트한다.

#### 수용 기준

- constant 0.5×, 1×, 2×, 4×에서 source↔timeline round-trip 오차가 1 frame 이하다.
- Speed ramp preset 전부에서 mapping이 단조 증가하고 round-trip이 허용 오차 내다.
- clip 시작/끝 boundary가 Preview와 Export에서 동일하다.
- reverse/freeze 정책이 테스트로 고정된다.

#### 필수 테스트

- rate별 boundary와 midpoint mapping
- ramp segment boundary mapping
- inverse mapping round-trip
- trimmed source range offset
- invalid input
- 29.97/30/60fps frame tolerance

#### 커밋 권장

`feat(moviecut): centralize clip timeline source time mapping`

---

### Step 4 — P1: 배속/Speed ramp 변경 시 duration 일관성 보장

#### 문제

`SetClipPropertyCommand.playbackRate`와 `.speedRampPoints`는 속성만 바꾼다. 그러나 Playback/Export는 source duration을 속도로 다시 scale한다. 그 결과:

- 타임라인 clip width
- `Timeline.duration`
- snap point
- marker/transition 위치
- 다음 clip 시작
- 실제 preview/export duration

이 서로 달라질 수 있다.

#### 시작 파일

- `Sources/MovieCutCore/Commands/SetClipPropertyCommand.swift`
- `App/MovieCutMac/EditorViewModel.swift`
- `Sources/MovieCutCore/Models/Timeline.swift`
- Step 3의 `ClipTimeMapping`

#### 구현 방향

1. 속도 변경을 단순 property mutation으로 두지 말고 timeline duration 갱신까지 포함하는 atomic command로 승격한다.
2. 정책을 먼저 결정하고 테스트로 고정한다.
   - 권장: sourceRange 유지, rendered timeline duration 변경
3. main magnetic track이라면 뒤 clip을 새 duration에 맞게 이동한다.
4. 자유 배치 track은 다른 clip 위치를 자동 변경하지 않는다.
5. transition duration, fade duration, ducking range, keyframe timeline 표현을 새 길이에 맞게 clamp/reconcile한다.
6. undo 한 번으로 speed와 영향 clip 위치 전체를 복원한다.

#### 수용 기준

- source 10초 clip을 2×로 변경하면 timeline duration이 5초다.
- 0.5×면 20초다.
- Speed ramp는 공통 mapper의 rendered duration과 timelineRange가 일치한다.
- Preview duration, Timeline duration, Export duration 차이가 1 frame 이하다.
- undo/redo가 speed와 후속 clip 배치를 exact 복원한다.

#### 필수 테스트

- 0.5×/2× duration
- magnetic main track 후속 clip 이동
- free overlay track 후속 clip 위치 유지
- Speed ramp duration
- transition/fade clamp
- undo/redo

#### 커밋 권장

`fix(moviecut): keep speed changes and timeline duration consistent`

---

### Step 5 — P1: Split/Trim을 공통 시간 매핑으로 교체

#### 문제

- `SplitClipCommand`가 timeline delta를 그대로 source delta로 사용한다.
- `TimelineView` trim gesture가 timeline duration을 그대로 source duration으로 저장한다.
- ViewModel shortcut trim은 constant speed만 일부 고려하고 Speed ramp는 고려하지 않는다.

#### 시작 파일

- `Sources/MovieCutCore/Commands/SplitClipCommand.swift`
- `Sources/MovieCutCore/Commands/TrimClipCommand.swift`
- `App/MovieCutMac/TimelineView.swift`
- `App/MovieCutMac/EditorViewModel.swift`
- Step 3의 `ClipTimeMapping`

#### 구현 방향

1. split point를 mapper로 source time으로 변환한다.
2. 앞/뒤 clip의 sourceRange와 timelineRange를 mapper 결과로 생성한다.
3. Speed ramp split 시 각 clip의 normalized ramp point를 잘라서 다시 정규화한다.
4. trim gesture와 keyboard trim이 동일 ViewModel command factory를 사용하도록 통합한다.
5. UI drag 중 preview state와 command commit state가 같은 계산 함수를 사용하게 한다.
6. source asset duration 밖으로 늘리는 trim은 명시적으로 제한한다. Still image처럼 확장 가능한 kind는 별도 정책으로 처리한다.

#### 수용 기준

- 2× clip의 timeline 2초 지점 split이 source 4초 지점을 사용한다.
- 0.5× clip도 동일 원칙으로 동작한다.
- Speed ramp split 전후 총 source coverage와 총 rendered duration이 보존된다.
- drag trim과 keyboard trim 결과가 동일하다.
- source 범위를 벗어나는 trim이 발생하지 않는다.
- Preview/export에서 split frame이 동일하다.

#### 필수 테스트

- constant speed split
- Speed ramp segment 내부/boundary split
- left/right trim
- keyboard/drag parity
- minimum duration
- image clip extension policy
- undo/redo

#### 커밋 권장

`fix(moviecut): make split and trim speed aware`

---

### Step 6 — P1: Preview↔Export 비-skippable parity E2E 추가

#### 문제

현재 다수 픽셀 테스트는 CIContext가 투명 검정을 반환하면 `guard ... else { return }`으로 성공 처리된다. StaticContract는 코드 문자열의 존재만 보장한다.

#### 시작 파일

- `Tests/MovieCutCoreTests/TransitionPixelProcessorTests.swift`
- `Tests/MovieCutCoreTests/*PixelProcessorTests.swift`
- `Tests/MovieCutCoreTests/Support/GoldenPixelHarness.swift`
- `scripts/run_e2e_export.sh`
- `App/MovieCutMac/UITestHarness.swift`
- `App/MovieCutMacUITests/`

#### 구현 방향

1. 핵심 P0/P1 시나리오는 software renderer 또는 실제 앱 frame extraction으로 반드시 검증한다.
2. renderer 미지원은 pass가 아니라 명시적 failure 또는 별도 필수 CI job으로 처리한다.
3. Preview와 Export의 동일 timestamp frame을 저장하고 digest/pixel metric으로 비교한다.
4. 전체 E2E가 너무 길면 `scripts/run_core_editing_e2e.sh`로 핵심 편집 smoke를 분리한다.

#### 필수 시나리오

1. 비디오 A 2초 + 비디오 B 2초 + cross dissolve
2. 2× clip split/trim
3. Speed ramp clip
4. 5초 위치 text overlay
5. 7.5초 위치 BGM
6. filter + mask + subtitle
7. image + video mixed timeline
8. normal delete gap 유지 / ripple delete gap 닫기

각 시나리오는 다음을 검증한다.

- persisted project ranges
- Preview frame
- Export frame
- Export duration
- undo/redo round-trip

#### 수용 기준

- 핵심 시나리오에 silent skip이 없다.
- Preview와 Export가 정해진 pixel/digest 허용 오차를 만족한다.
- 결과 파일이 없거나 renderer가 동작하지 않으면 test가 실패한다.

#### 커밋 권장

`test(moviecut): add non-skippable preview export parity e2e`

---

### Step 7 — P2: macOS 안정화 뒤 iOS 파리티 복구

macOS P0/P1 완료 후에만 진행한다.

우선순위:

1. iOS Preview도 공통 project composition/time mapper 사용
2. two-source transition
3. Speed ramp
4. reverse/freeze frame
5. chroma key/background removal shared processor
6. audio ducking/EQ/noise reduction
7. export preset/format parity

`docs/PLATFORM_PARITY_MATRIX.md`를 현재 코드 기준으로 다시 감사하고 실제 simulator/device E2E가 없는 항목은 완료 처리하지 않는다.

---

## 3. 단계별 완료 게이트

각 Step에서 아래를 모두 통과해야 다음 Step으로 이동한다.

```bash
git diff --check

CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache" \
swift test --disable-sandbox --scratch-path "$PWD/.build-check" \
  --filter '<해당 focused suite>'

xcodebuild \
  -project MovieCut.xcodeproj \
  -scheme MovieCutMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

추가 게이트:

- Step 1, 2, 4, 5: actual app E2E 필수
- Step 3: pure behavioral mapping test 필수
- Step 6: non-skippable golden/E2E 필수
- 마지막: 신규 사용자 기준 숏폼 제작 수동 완주

## 4. 최종 수동 완주 시나리오

1. 영상 2개와 사진 1개를 import한다.
2. main video track에 영상→사진→영상을 배치한다.
3. 첫 영상은 2×, 사진은 3초, 마지막 영상은 Speed ramp를 적용한다.
4. 영상 경계에 transition을 적용한다.
5. 5초 위치에 text/sticker를 추가한다.
6. 2초 이후 시작하는 BGM과 중간 SFX를 추가한다.
7. 첫 영상을 split하고 양 끝을 drag trim한다.
8. 일반 Delete로 gap이 유지되는지 확인한다.
9. Undo 후 Ripple Delete로 gap이 닫히는지 확인한다.
10. Preview를 처음부터 끝까지 재생한다.
11. MP4로 export한다.
12. Preview와 export의 clip 경계, text/BGM 시작, transition, 전체 duration을 비교한다.

완료 조건:

- 막힘 없이 한 번에 완주
- Preview와 export의 시각·시간 결과가 일치
- 앱 오류 메시지 없음
- 저장 후 재실행해 project 위치/속도/trim 상태 보존

## 5. 다음 세션 시작 프롬프트

아래 문장을 그대로 새 세션에 전달할 수 있다.

> `docs/CAPCUT_CORE_EDITING_REPAIR_HANDOFF_20260727.md`를 기준으로 작업해줘. 먼저 git status와 현재 코드를 재확인한 뒤 Step 1만 구현해. PreviewPanel의 원본 asset 직접 재생을 프로젝트 composition preview로 교체하고, playhead/재생 상태 보존, stale rebuild 방지, 오류 노출, actual-app Preview↔Export 검증까지 완료해. 다음 Step은 착수하지 말고 focused tests, xcodebuild, E2E 결과와 남은 caveat를 보고해.

## 6. 주의할 기존 경로

- `PlaybackEngine.loadProject(_:)`는 구현되어 있지만 현재 메인 Preview 호출 경로가 없다.
- ExportEngine의 렌더 성공만으로 Preview 성공을 추론하지 않는다.
- `EditorSession`은 whole-project snapshot undo를 사용하므로 command inverse와 실제 UI undo 경로를 혼동하지 않는다.
- `currentProject`를 drag 중 직접 mutate한 뒤 command로 commit하는 TimelineView 흐름은 session snapshot과 divergence가 생길 수 있으므로 Step 5에서 함께 정리한다.
- 기존 magnetic tests는 “모든 트랙 compaction”을 완료 조건으로 고정하고 있으므로 Step 2에서 요구사항에 맞게 behavioral tests를 재작성한다.
- 문서의 과거 ✅ 표시는 현재 actual-app WYSIWYG 동작을 보장하지 않는다.
