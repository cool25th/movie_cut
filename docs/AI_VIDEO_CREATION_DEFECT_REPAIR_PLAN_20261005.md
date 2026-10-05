# AI 영상 제작 E2E 결함 수리 계획

작성: 2026-10-05 저녁 · 근거: 외부 리뷰(2026-10-05) + 코드·`task-511.log` 재확인(정적) · 상태: **계획 / 구현 전**

이 문서는 결함 수리 계획 요청의 산출물이다. 이 세션에서 제품 코드를 변경하지 않았고 빌드·테스트를 실행하지 않았다. 외부 리뷰의 지적 6건을 전부 코드로 대조했고, 그중 램프 중첩의 정확한 발생 메커니즘을 정적으로 특정했다(§1). 수리 증분은 [AI_VIDEO_CREATION_IMPLEMENTATION_PLAN_20261005.md](AI_VIDEO_CREATION_IMPLEMENTATION_PLAN_20261005.md) §14의 **AI-03a**로 등록한다.

## 0. 현재 상태 요약

- Core·Mac 빌드·플래너 단위 테스트는 통과. **첫 E2E(`AIPhotoMontageE2ETests`, 2026-10-05 16:15)는 프리뷰 구성 단계에서 오디오 램프 중첩 예외로 실패**했다(export 도달 못 함).
- 같은 로그에 샌드박스 파일 접근 거부(`[scoped] Could not open() … Operation not permitted`, `AVAudioFile` open 실패)가 함께 기록되어 있다. fixture가 저장소 `Tests/Fixtures/`에 있어 샌드박스 앱이 직접 열 수 없기 때문이다.
- "Core 1,543 테스트 통과"는 16:14 실행 시점 수치다. 이후 수정분을 포함한 전체 재검증 전까지 완료 판정에 확대 해석하지 않는다.
- `applyPhotoMontage` 진입점은 테스트에서만 호출된다. 사용자 UI 진입점은 아직 없다(§3 기능 순서 참조).

## 1. [P1] 오디오 램프 중첩 — 원인 특정 완료

**증거**: `task-511.log` 16:15:19 `NSInvalidArgumentException: … _setRamp: The timeRange of a ramp must not overlap…`, 스택 `PlaybackEngine.buildComposition` → `loadProject`(프리뷰 재구성).

**메커니즘(전부 코드에서 확인)**:

1. `EditorViewModel.buildAudioProcessingOptions()`(`EditorViewModel.swift:4804`)이 `duckLevel: 0.3`을 항상 넣고, `voiceClipIds`에 **비디오 트랙 클립 전부(volume > 0)** 를 담는다. 몽타주 사진 클립 3개(트랙 kind는 `.video`)가 "음성"으로 분류된다.
2. `PlaybackEngine` 전역 덕킹 블록(`PlaybackEngine.swift:1640–1672`)이 음성 범위 × 오디오 트랙 클립의 교집합마다 **상수 볼륨 램프**를 클립 fade와 같은 `AVMutableAudioMixInputParameters` 객체에 추가한다. 이 블록은 클립 fade 창과의 중첩 검사가 없다(클립 단위 덕킹 경로인 `applyDuckingRamps:810–815`에는 fade 회피 로직이 있는 것과 대조).
3. 몽타주 타임라인: 음성 범위 = 사진 3구간 [0,5],[5,10],[10,15] → 전 구간. 음악 clip0 [0,4] × [0,5] 교집합 램프 [0,4]가 기존 fadeIn 램프 [0,0.5]와 **중첩** → 예외. (clip3 fadeOut [13.5,15] ⊂ 덕킹 램프 [12,15]도 중첩. 인접 램프 [4,5]/[5,8]의 경계 접촉이 예외를 내는지는 별도 확인 필요.)
4. 부수 결함: 사진(무음)이 덕킹 트리거가 되어 음악이 영상 전체에서 30% 감소된다 — 의도하지 않은 제품 동작.

**범위 판정**: 이 결함은 AI 경로 전용이 아니라 "클립 fade + (비디오 트랙 클립 존재 + 오디오 클립)" 조합의 기존 잠복 결함이다. 기존 시나리오가 fade와 덕킹을 동시에 겹치지 않았을 뿐이다. 수리는 몽타주뿐 아니라 기존 프로젝트에도 적용된다.

**수리 방향(M1)**:

- **M1a — 트랙별 gain 곡선 합성기(Core 신규, 정석 수리)**: 클립 볼륨·fadeIn/out·클립 덕킹·전역 덕킹을 한 곡선으로 합성해 **인접하되 비중첩인 램프 집합만** 발행하는 순수 함수. 위치는 `Sources/MovieCutCore/Audio/`(기존 `AudioDuckingPlanner.mergeOverlapping` 관례 확장). `PlaybackEngine`의 `applyAudioVolumeAndFades`·`applyDuckingRamps`·전역 덕킹 블록이 각자 `setVolumeRamp`를 직접 호출하는 구조를 이 합성기 경유로 교체. `setVolume(_:at:)` 지점도 곡선에서 함께 정렬해 발행한다.
- **M1b — 음성 분류 수정(App)**: `voiceClipIds` 판정에서 오디오를 가질 수 없는 이미지 클립을 제외한다. 사진은 덕킹 트리거가 아니다. 기존 음성 덕킹 동작(SpeechDucking 관련 테스트)의 회귀 확인이 필요하다.
- export 경로는 `exportSession.audioMix = playerItem.audioMix`(`PlaybackEngine.swift:511`)로 프리뷰와 같은 객체를 재사용하므로 한 곳 수리로 양쪽이 해결된다.
- **완료 기준**: ① Core 단위 테스트 — fade+덕킹+볼륨 조합에서 램프 비중첩 불변식, 기존 덕킹 시나리오 회귀 통과. ② Mac E2E — 4초 음악→15초 반복, 프리뷰 로드·재생, Undo/Redo, 실제 export가 모두 예외 없이 성공. ③ 전역 덕킹이 켜진 기존 프로젝트 프리뷰 회귀 없음.

## 2. 나머지 결함 — 검증 결과와 수리 항목

### M2. [P1] 플래너 입력 제한

확인: `PhotoMontagePlanner.swift:25–30`은 `!photos.isEmpty`, `targetDuration > 0`뿐이다. `+Infinity`는 통과하고, 반복 배치 `while`(113행)은 검증(compile 시점) 전에 액션을 무한히 쌓는다 — 종료되지 않거나 과도한 액션을 만든다. 길이 미상 음원은 목표 길이로 추측한다(90행). 참고로 DSL `addClip`에는 `isFinite` 검사가 있으나(`EditingActionDSL.swift:216–219`) 플래너 무한 루프를 막지 못한다.

수리:

- 목표 길이·음원 길이의 유한성(`isFinite`)·상한(제품 최대 영상 길이와 정합 — 구현 시 기존 상수 확인), 사진 개수 상한, 최소 음원 길이, 최대 반복 수를 검사하고 `while`에 반복 상한을 둔다.
- 음원 길이 미상(`duration == nil`)은 probe를 요구하며 거부한다. 앱 경로는 `PreparedAssetStore.prepareMusicAsset`가 항상 probe하므로(길이 비유한 값도 이미 거부, `PreparedAssetStore.swift:67`) 정상 플로우에 영향이 없다.
- 오류 유형을 분리한다(`emptyRange` 재사용 금지).
- **완료 기준**: Infinity·NaN·길이 미상·극소 길이·과대 반복이 프로젝트 변경 없이 제한 시간 안에 명확한 오류로 거부.

### M3. [P1] 북마크 존재와 실제 파일 접근 구분

확인: `makeBookmark`는 보안 스코프 북마크 실패 시 일반(minimal) 북마크로 폴백한다(`SecurityScopedAccess.swift:136–150`). 따라서 `originalBookmark != nil`은 샌드박스 접근을 보장하지 않는다. 현재 E2E의 JSON 왕복도 재열기 후 접근을 검증하지 않는다. `task-511.log`의 `Operation not permitted`·`AVAudioFile` open 실패가 이 간극의 실측 증거다.

수리:

- **M3a(선행·소규모)**: E2E fixture를 접근 허용 경로로 복사해 사용한다(기존 `UITestHarness`의 Support 디렉터리 관례, `UITestHarness.swift:2391` 참조). entitlement는 건드리지 않는다.
- **M3b**: 북마크 생성 결과를 종류별로 구분해 기록하고(보안 스코크 vs minimal 폴백), probe는 `withSecurityScope` 안에서 수행한다. 저장 → 새 세션 로드 → 북마크 해석 → 사진·음원 읽기 → 출력까지 E2E로 검증한다. 실제 프로세스 재시작 왕복은 테스트 러너 제약을 명시하고 세션 재생성 수준으로 먼저 검증한다.
- **완료 기준**: 재열기 후 파일 읽기 성공, 로그에 sandbox 접근 거부 소멸.

### M4. [P1] 기존 프로젝트에 적용할 동작 정의

확인: 플래너는 잠금 여부와 무관하게 빈 비디오 트랙을 재사용하고(`PhotoMontagePlanner.swift:43`), 사진·음악을 항상 0초부터 배치하며, 프로젝트 캔버스를 무조건 바꾼다(39행). `Track.isLocked` 필드는 존재한다.

수리:

- 배치 모드를 명시적으로 구분한다: `새 프로젝트 제작 / 지정 위치 삽입 / 선택 구간 교체`. 1차 증분은 "새 프로젝트 제작"만 기본 동작으로 확정한다.
- 기존 콘텐츠가 있는 프로젝트에서는: 잠긴 트랙 재사용 금지, 캔버스 변경은 타임라인이 비어 있을 때만, 콘텐츠가 있으면 `needsInput`으로 거부한다.
- **완료 기준**: 기존 클립·잠금 트랙·30초 이상 타임라인이 있는 프로젝트에서 의도한 구간만 변경되고 나머지는 무변경(Core 테스트).

### M5. [P2] 반복 음악 접합 품질

확인: 반복 클립은 이어붙이기만 하고 접합부 페이드가 없다. 범위 초과는 해결됐으나 클릭·급격한 변화 가능성이 남는다.

수리: 짧은 equal-power 크로스페이드(예: 30–50ms) 또는 루프 지점 선택, 마지막 잔여 구간의 프레임·샘플 정렬. 접합부 전후를 실제 디코딩해 클릭·무음·과도 peak 검사(기존 오디오 측정 경로 재사용). **완료 기준**: 접합부 실측에서 이상 없음.

### M6. [P2] 검증 경계·E2E 강화

확인: `setClipFade`는 `>= 0`만 검사해 `+Infinity`를 통과시킨다(`EditingActionDSL.swift:263–266`). transform·keyframe은 주로 클립 존재만 확인한다. `registerAsset`은 `ImportMediaCommand`로 직행해 동일 자산 재사용/갱신이 구분되지 않는다(`EditingPlanCompiler.swift:137–138`). E2E는 `#expect(audioClips.count == 4)` 직후 배열 인덱싱(전제 위반 시 크래시), undo는 클립·길이·캔버스만 비교, 출력은 1초 프레임 1장 + 오디오 트랙 존재만 확인한다.

수리:

- fade·키프레임 시간/값·transform의 유한성·허용 범위 검사를 DSL/컴파일러에 추가. `registerAsset`은 동일 자산(URL·종류 일치) 재사용과 명시적 갱신을 구분.
- 테스트에서 배열 인덱싱 전 `#require`로 전제조건 확인, 초기 프로젝트 전체 저장 후 단일 undo로 자산·트랙·캔버스까지 전체 비교.
- 출력 검증 확대: 세 사진 구간 구분 프레임, 움직임(키프레임 반영), EXIF 방향, 마지막 구간까지 음악 가청 샘플 확인.
- **완료 기준**: 위 검사가 모두 자동 테스트로 존재하고 기존 E2E가 동일하게 통과.

## 3. 실행 순서와 게이트

```
M3a(fixture 접근, 소규모·선행)
 → M1(램프 중첩 — E2E 재개의 선행 조건)
 → M2·M4(Core 측, M1과 병행 가능)
 → M3b(저장·재열기 실접근)
 → M5(접합 품질) → M6(검증 경계·E2E 강화)
 → 기능 작업: 실제 파일 첨부 UI 연결 → 저장·재열기 검증 → planId 중복 적용 방지·취소 → 자연어 플래너 연결(구현 계획 AI-04~)
```

- 각 증분은 직접 대응하는 Core/Mac 행동 테스트를 수반한다. E2E·export급 실행 전 `scripts/disk_guard.sh --start-gate`로 디스크 여유를 확인한다(현재 디스크 정책은 실행 시점 확인).
- 증거는 `artifacts/ai_creation/<run-id>/`에 저장. 합성 fixture를 커밋하지 않는다(기존 원칙).
- 부분 통과는 가짜 수정으로 취급한다(원복+기준선 원칙).

## 4. 진행 기록 정정 (반영 완료)

- 구현 계획 §14 AI-03 상태: "구현 완료 (E2E 대기)" → **"구현 완료·E2E 결함 발견"**. "디스크 13.69GiB로 START_GATE_DENIED 보류" 표기는 사실과 달라 삭제 — E2E는 16:15에 실행되었고 램프 예외로 실패했다.
- AI-03a(결함 수리) 행을 신규 등록했고, AI-04의 "다음 작업 대상" 표기를 AI-03a 이후로 이동했다.
- [AI_VIDEO_CREATION_HANDOFF_20261005.md](AI_VIDEO_CREATION_HANDOFF_20261005.md)에 다음 세션이 M3a→M1부터 시작한다는 갱신을 추가했다.
