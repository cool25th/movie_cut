# 역재생 편집 + parity 게이트 신뢰화 수정 기록

> 작성일: 2026-07-29
> 브랜치: `fix/reverse-clip-editing-and-parity-gates`
> 기준: main `75b6421`
> 목적: V13 재검토에서 보고된 P1 3종 + parity 인프라 불신뢰 수정 및 검증

## 1. 수정 요약

### P1-1 역재생 클립 분할 — `SplitClipCommand.swift`
역재생 클립은 source를 `.end → .start` 방향으로 재생한다. 분할 시 timeline-left
절반은 이미 **상위** source sub-range를 재생했으므로 `[splitSourceTime, sourceEnd]`을
가져야 하고, timeline-right 절반은 `[sourceStart, splitSourceTime]`을 가져야 한다.
기존 코드는 정방향 가정으로 두 절반의 source sub-range가 뒤바뀌었다.

`clip.isReversed` 분기를 추가해 sub-range 배정을 뒤집는다. timelineRange는 방향과
무관하게 항상 정방향이므로 건드리지 않는다. ramp 재정규화는 각 sub-clip의 자체
`sourceRange`를 `intoSubSourceRange`로 넘기는 것으로 정방향/역방향 모두 올바르다
(ramp는 source→rate 매핑이고, reverse는 재생 순서만 뒤집는다).

### P1-2 역재생 클립 트림 — `ClipTrimMath.swift`
mapping 자체는 역재생을 인지하지만, range 조립이 정방향 전용이었다.
- 역재생 start-trim: timeline 시작이 sourceRange.end를 재생하므로, 매핑된 source
  값이 새 **sourceEnd**가 된다 (`sourceRange.start` 고정).
- 역재생 end-trim: timeline 끝이 sourceRange.start를 재생하므로, 매핑된 source 값이
  새 **sourceStart**가 된다 (`sourceRange.end` 고정).

`computeStartTrim`/`computeEndTrim`에 `clip.isReversed` 분기 추가. 정방향 경로,
image clip 무확장, asset-duration clamp, 최소 길이 정책은 모두 유지.

### P1-3 ViewModel 이중 시간 변환 — `EditorViewModel.swift`
`syncTimelinePlayhead(to:)`가 composition timeline time(이미 프로젝트 타임라인
도메인)을 `timelineTime(forSourceTime:)`(절대 source 초 입력)에 넣어 이중 변환했다.
배속·램프 클립에서 프레임/초 이동이 왜곡되었다.

`PreviewPanel`의 올바른 invariant와 동일하게 `playheadTime = min(max(0, playbackTime),
currentProject.timeline.duration)`만 수행하도록 단순화.

### P1-4 parity 스크립트 신뢰화
- `run_preview_export_parity.sh`: 순서 의존적 `case` glob을 순서 무관 grep 파싱으로
  교체 (`error=none`, `composition_error=none`, `parity_done`, `dumped_frames≥1`).
  180초 watchdog + 실패 시 WORK 보존 trap 추가.
- `run_core_editing_parity.sh`: `run_scenario`에 240초 watchdog + evidence 보존 추가.
  순서 무관 status 검사. 시간이 짧아지는 시나리오 샘플 시간 수정:
  - Scenario 2 (2x → ~1.0s): `0.25,0.75`
  - Scenario 3 (ramp → ~1.4s): `0.25,1.0`
  - Scenario 8 (삭제 후 2.0s): `0.5,1.5`
- `verify_preview_export_parity.py`: ffprobe로 export duration 사전 측정, 범위 밖
  timestamp 즉시 FAIL, export 프레임 파일 존재/크기 확인 후 read.

## 2. 검증 결과

### 단위 테스트
- `swift build`: 성공
- `swift test`: **1000 tests / 163 suites 통과** (신규 6개: 역재생 분할 3 + 역재생
  트림 3)
- macOS `xcodebuild` Debug: **BUILD SUCCEEDED**

### 실제 앱 parity harness (live app)

**`run_preview_export_parity.sh`: PASS** (Step 1 게이트)
- t=0.5s MAD=0.45, t=1.5s MAD=0.45 (허용치 12.0)

**`run_core_editing_parity.sh`: 5/7 시나리오 PASS**

| 시나리오 | 결과 | MAD | 비고 |
|----------|------|-----|------|
| 2 (2x 분할) | ✅ PASS | 0.40 | split 수정 end-to-end 검증 |
| 3 (속도 램프) | ✅ PASS | 0.45 | 샘플 시간 수정 |
| 4 (텍스트 오버레이) | ❌ FAIL | — | **사전 존재 앱 hang** (아래 참조) |
| 5 (BGM) | ✅ PASS | 0.45 | |
| 6 (필터+마스크+자막) | ❌ FAIL | — | **사전 존재 앱 hang** (아래 참조) |
| 7 (이미지+비디오) | ✅ PASS | 0.69 | |
| 8 (일반 삭제) | ✅ PASS | 0.45 | 샘플 시간 수정 |

## 3. 잔존 과제 (이 수정 범위 밖)

### Scenario 4 / 6 — headless harness composition build 미완료 (사전 존재)
두 시나리오 모두 앱이 `parity_checkpoint stage=scenarios_applied`에서 멈추고
composition build를 완료하지 못한다. V13 재검토에서도 "텍스트·필터·마스크
시나리오는 이번 실행에서 export 증거를 생성하지 못했다"로 이미 보고된 동일
증상이다. 이번 수정과 무관하며(수정 대상: split/trim/playhead/parity-스크립트), 앱
composition 파이프라인의 호스트/GPU 의존적 한계다.

개선점: 이제 watchdog가 240초에 앱을 강제 종료하므로(이전엔 무한 대기) 하네스가
막히지 않고, 실패 시 WORK 디렉토리가 보존되어 원인 조사가 가능하다.

해결 방향은 `docs/CORE_REPAIR_FOLLOWUP_WORKORDER_20260728.md` Task E가 다룬다:
duration 비교 추가, working GPU compositor host에서의 실행. 본 문서와 별개 과제.

### Scenario 1 (전환) — 여전히 의도적 제외
`run_core_editing_parity.sh`의 주석에 문서화된 대로, two-source transition의
composition build가 headless harness에서 안정적이지 않아 제외됨.
`TransitionPixelProcessorTests`로 소프트웨어 렌더러 경로는 커버됨.

### Scenario 8의 시나리오 의미
`deleteClip()`이 항상 마지막으로 import된 clip(VIDEO_B)을 삭제하므로, 현재
harness에서는 "gap preserved"를 실제로 검증하지 못하고 남은 단일 clip의
Preview↔Export 일치만 검증한다. 실제 gap을 남기려면 harness가 비-마지막 clip을
삭제하도록 변경해야 한다. 본 수정은 게이트가 신뢰 가능하도록 만드는 데
집중했고, 시나리오 의미 확장은 별개다.

## 4. 결론

세 P1 버그(역재생 분할·트림·playhead 이동)가 수정되었고 단위 테스트로 고정되었다.
parity 게이트는 이제 순서·범위·hang에 대해 신뢰 가능하며, 7개 핵심 시나리오 중
5개가 실제 앱에서 PASS한다. 남은 2개(text, filter/mask)는 사전 존재 앱 composition
한계로 본 수정 범위 밖이며 기존 work order Task E에서 추적된다.
