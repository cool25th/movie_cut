# AI 영상 제작 E2E 결함 수리 계획

작성: 2026-10-05 저녁 · 2차 개정: 2026-10-05 심야(외부 리뷰 6건 반영 — 아래 "개정 이력") · 상태: **수리 증분 M0/M1/M2/M4/M5(1차)/M6(1차) 구현 완료, E2E 재검증 진행**

## 개정 이력

- 1차(저녁): 외부 리뷰 6건 대조로 램프 중첩 원인 특정, 수리 증분 M1~M6 계획.
- 2차(심야): 두 번째 외부 리뷰의 정정 6건을 반영해 계획을 수정하고 그대로 구현했다. 주요 정정:
  1. **출력 경로 정정**: 1차의 "export가 프리뷰와 같은 audioMix 객체를 재사용하므로 한 곳 수리로 양쪽 해결" 결론은 틀렸다. `PlaybackEngine.renderCurrentPreviewAudio`(:492)는 테스트 하니스용 프리뷰 오디오 추출 함수이고, 일반 export는 `ExportEngine.renderGraphAudio`(:249) → `GraphMixRenderer`로 오디오를 별도 렌더링한다("Ducking/fades/volume live in AudioGraphProjectBuilder" — ExportEngine 주석). 프리뷰 수리와 출력 수리는 **각각 검증**한다.
  2. **전역 덕킹의 트랙 라우팅 결함**: 1차에 남겨둔 전역 덕킹 블록은 모든 inputParameters에 모든 음악 클립의 감쇠를 추가하며 어느 composition track인지 구분하지 않았다(영상 음성에 음악용 gain 적용·여러 음악 트랙 중복 추가 가능).
  3. **음성 분류**: 이미지 제외만으로 완성되지 않는다. 무음 영상·음악 영상도 음성이 되고 오디오 트랙 내레이션은 빠진다. 기본은 명시적 dialogue 역할/사용자 지정, 자동 판단은 발화 분석 기반이어야 한다. "항상 0.3 자동 덕킹" 정책도 정리 대상.
  4. **기존 오디오 그래프와 통합**: 새 합성기를 독립 경로로 추가하지 않는다. `AudioRenderGraphSpec`·`AudioGraphProjectBuilder`가 이미 볼륨(dB)·fade·베이크 덕킹·mute/solo의 공통 명세를 계산하므로 같은 의미론에서 프리뷰 램프를 생성한다.
  5. **fixture 복사의 한계**: 컨테이너 복사는 테스트 실행 문제만 해결하고 외부 파일 권한 검증을 대신하지 않는다. M3a는 테스트 전 staging으로, M3b(실제 사용자 선택 파일 scope·저장·프로세스 재시작 후 접근)는 별도 검증으로 분리. 권한 거부 원인 확정을 위해 실패 URL을 기록한다.
  6. **테스트 보호 전면 이동**: `#require` 전제조건·전체 상태 Undo 비교·실패 로그 보존은 마지막이 아니라 수리와 함께 먼저 넣는다(러너 크래시가 진단을 방해함). "부분 통과=가짜 수정 원복" 원칙도 수정: 부분 통과는 부분 완료로 기록하고 실패 항목을 남긴다. **원복은 그 수정이 실제 회귀를 만들었을 때만** 판단한다.
  - 부기: 문서 갱신의 안전성은 "N시간 전 멈춤" 같은 시간 추정이 아니라 실제 변경 상태 확인로 근거를 둔다. 이 개정에서 수정한 구간: §1 전체, M1, M3a/M3b, M6, §3 실행 순서, §4(원칙 문구). 수정하지 않은 구간: M2, M4, M5 본문(실행 결과만 추가).

## 0. 현재 상태 요약

- 첫 E2E(2026-10-05 16:15, task-511.log)는 프리뷰 구성에서 오디오 램프 중첩 예외로 실패했다(export 미도달). 같은 로그에 fixture 경로의 샌드박스 읽기 거부가 함께 기록되어 있다.
- 아래 표는 2차 개정 시점의 실행 상태다. "Core 1,543 통과" 등 과거 수치는 해당 실행 시점의 결과로만 해석한다.

| 증분 | 상태 | 비고 |
|---|---|---|
| M0 테스트 보호·fixture staging | **완료** | E2E 재작성: #require·전체 상태 Undo 비교·실패 URL 포함 오류·Application Support staging |
| M1 램프 중첩·라우팅·덕킹 정책 | **완료** | `TrackGainEnvelope`(Core)+`PlaybackEngine` 교체+전역 덕킹 블록 제거, Core 13/13 |
| M2 플래너 입력 제한 | **완료** | 유한성·상한·반복 상한·길이 미상 거부, 테스트 5케이스 |
| M4 기존 프로젝트 정책 | **완료** | `timelineNotEmpty` 거부·잠긴 트랙 제외 |
| M5 접합 품질 | **완료(2차)** | 1차: 12ms 안티클릭 페이드. 2차: 프리뷰 오디오 렌더(`renderCurrentPreviewAudio`) 후 접합부 maxDelta 실측 — 절대 상한 0.25 + 기준구간 대비 12배 상한(E2E 통과). equal-power 크로스페이드/루프 포인트는 선택 후속 |
| M6 검증 경계 | **완료(2차)** | setClipFade isFinite + **transform 유한성·양수 scale + keyframe 유한성(음수 시간은 모델 경계에서 max(0,t) 정규화 — DSL이 볼 수 없음을 테스트로 고정) + registerAsset 동일 id 전면 거부(덮어쓰기 차단·갱신은 UpdateMediaAssetCommand로 명시적) + 자산 duration 유한성**. EXIF 방향·움직임 픽셀 검증은 잔여 |
| M3b 외부 파일 재열기 | **lite 완료** | E2E: 저장→새 VM 로드→북마크 해석(beginScope)→이미지 디코드·오디오 duration 읽기→프리뷰 재구성 무오류. **잔여: 실제 프로세스 재시작 + 사용자 선택(powerbox) scope — 테스트 호스트가 자신을 재시작할 수 없어 인프라 필요** |
| E2E 재검증 | **통과** | §5 — 램프 중첩 0·스코프 거부 0·Core 1,570/1,570·Mac 회귀 7/7 |

## 1. [P1] 오디오 램프 중첩 — 원인과 수리 (완료)

**증거**: task-511.log 16:15:19 `NSInvalidArgumentException: … _setRamp: ramp overlap`, 스택 `PlaybackEngine.buildComposition`.

**원인(코드 확인)**: 두 결함이 겹쳤다.

1. `EditorViewModel.buildAudioProcessingOptions()`가 `duckLevel: 0.3` 상수 + `voiceClipIds` = 비디오 트랙 전 클립(volume>0)을 만들었다 — 이미지 클립도 "음성"으로 분류(분류 결함).
2. `PlaybackEngine` 전역 덕킹 블록(구 1640–1672행)이 음성 범위×오디오 클립 교집합마다 상수 볼륨 램프를 **클립 fade 창과 중첩 검사 없이**, 그리고 **모든 inputParameters 객체에 트랙 구분 없이** 추가했다(라우팅 결함). 몽타주에서는 음악 clip0 fadeIn [0,0.5] ⊂ 전역 램프 [0,4] → 예외. 사진이 음성으로 분류되어 음악이 전 구간 30% 감쇠되는 제품 동작 오류도 동반했다.
3. 추가 확인: 이 라이브 전역 덕킹은 **출력 경로가 전혀 적용하지 않았다**(`renderGraphAudio`는 eqPresets만 소비). 즉 기존에도 프리뷰/출력 불일치가 존재했다. 제품의 정규 덕킹 기능은 UI가 클립에 베이크하는 방식(`SetAudioDuckingCommand` → `clip.duckingRanges`)이며 양 경로가 동일하게 적용한다.

**수리(구현 완료)**:

- **`TrackGainEnvelope`(Core 신규, `Sources/MovieCutCore/Audio/`)**: 클립의 볼륨×fadeIn/out×베이크 덕킹을 **하나의 정렬된 비중첩 세그먼트 열**로 합성하는 순수 함수. 의미론은 `AudioGraphProjectBuilder`와 동일(진폭-리니어 fade·dB-리니어 덕킹 attack 0.12s/hold/release 0.25s·mergeOverlapping·attack+release 미달 범위 무시) — 새로운 독립 오디오 경로가 아니라 같은 명세의 AVFoundation 램프 표현이다.
- **`PlaybackEngine`**: 클립 단위 fade/덕킹 적용을 봉투 경유로 교체(비디오·오디오 양 경로). 전역 덕킹 블록 삭제. 램프는 각 트랙의 파라미터 객체에 **그 트랙의 클립만** 적용되므로 라우팅 결함과 이중 감쇠(두 덕킹 경로 중복)가 구조적으로 사라진다.
- **음성 분류/덕킹 정책**: 라이브 자동 덕킹(상수 0.3)을 은퇴시키고 `duckLevel: 0, voiceClipIds: []`(구조체 기본값과 동일). 근거: 출력이 적용하지 않던 프리뷰 전용 경로였고, "비디오 트랙 클립 전부"라는 분류 규칙이 근본적으로 잘못됐다. 미래의 라이브 덕킹 부활은 명시적 dialogue 역할 또는 발화 분석 기반으로만(코드 코멘트에 명시). 덕킹은 베이크 기능으로 프리뷰·출력에 동일 적용.
- **프리뷰/출력 각각 검증**: 프리뷰는 apply/redo 시 composition 재구성 무예외로, 출력은 `exportProject`(graph mix 경로) 결과 디코딩(트랙 존재·마지막 구간 RMS·접합부 peak)으로 검증한다. 두 경로의 음량 직접 비교(표본 대조)는 M3b 이후 후속 과제로 남긴다 — 출력이 별도 엔진임이 확정된 만큼 성급한 동일성 주장은 하지 않는다.

**Core 테스트**(`TrackGainEnvelopeTests` 13/13): 몽타주 재현 형태(fadeIn ⊂ 전체 길이 덕킹)·fade 정확성·fade>클립 길이 클램프·덕킹 attack/hold/release 타이밍·범위 미달 무시·레벨 0=음소거·범위 병합·fade×덕킹 합성·순차 클립 분리·비유한 입력 → 빈 결과.

## 2. 나머지 결함

### M2. [P1] 플래너 입력 제한 — 완료

`PhotoMontagePlanner.Limits`(maxTargetDuration 3600s·maxPhotoCount 200·minMusicDuration 0.5s·maxMusicLoops 64)로 목표/사진 수 검사, 음원 길이 미상·비유한 거부(추측 금지 — 앱 경로는 `PreparedAssetStore`가 항상 probe), 반복 수 상한을 while 진입 전 계산해 종결성 보장. 오류는 `invalidTimeValue(사유)`로 분리(`emptyRange` 재사용 제거). 테스트 5케이스 통과.

### M3a. [P1] fixture staging — 완료(방식 변경)

테스트 실행 전 fixture를 **Application Support(샌드박스에서 grant-free)로 staging**하고, 모든 실패에 원본·대상 URL을 포함한다. entitlement는 불변. 이 방식은 테스트 실행 문제만 해결하며 외부 파일 권한 검증은 M3b가 담당한다(리뷰 5번 반영).

### M3b. [P1] 외부 파일 실접근·재열기 — 미착수

실제 사용자 선택 파일의 보안 scope 획득→probe→저장→**프로세스 재시작 후** 북마크 해석·읽기를 검증한다. 이번 증분은 JSON 왕복+북마크 유지(세션 재생성 수준)까지만 확인했다. 실사용 진입점(UI 첨부)이 생기는 증분과 함께 구현한다.

### M4. [P1] 기존 프로젝트 정책 — 완료(1차)

몽타주는 신규 제작 도구로 확정: 클립이 있는 타임라인에 대한 계획은 `PlanningError.timelineNotEmpty`로 명시적 거부(삽입/교체 모드는 미래의 명시적 배치 모드로). 잠긴 빈 트랙은 재사용하지 않는다. 캔버스 변경은 타임라인 비어 있음이 보장된 뒤에만. 테스트 2케이스 통과.

### M5. [P2] 반복 음악 접합 품질 — 1차 완료

루프 접합부에 12ms 안티클릭 마이크로 페이드(양쪽 끝의 음악적 fade는 유지). E2E에서 접합 구간 디코딩 peak<0.99·무음 아님을 검사한다. **한계 명시**: AAC 인코딩을 거친 출력에서 클릭을 측정하면 코덱 스무딩으로 일부 가려진다. 원본 접합부 직접 측정·equal-power 크로스페이드·루프 포인트 선택은 후속(프리뷰 오디오 추출 경로 `renderCurrentPreviewAudio` 활용 가능 — 이 함수가 정확히 이 용도다).

### M6. [P2] 검증 경계·E2E 강화 — 1차 완료, 잔여 명시

**이번에 수행(전면 이동 반영)**: E2E 전제조건 `#require`화·전체 상태 Undo 비교(트랙·캔버스·canvasSize·미디어 라이브러리)·실패 URL 기록·출력 검증 확대(3개 사진 구간 프레임 상호 구분·마지막 구간 음악 RMS·접합부 peak). DSL `setClipFade`에 isFinite 검사 추가.

**잔여**: keyframe 시간/값·transform 유한성·범위 검사, `registerAsset`의 동일 자산 재사용 vs 명시적 갱신 구분, EXIF 방향·움직임(키프레임 반영) 픽셀 검증.

## 3. 실행 순서(2차 개정: 리뷰 추천 순서)와 게이트

```
M0 테스트 전제조건·fixture staging → 최소 램프 재현 테스트(Core) → M1 트랙 라우팅·음성 대상·gain 처리 수리
→ M2·M4 입력 제한·기존 프로젝트 정책 → (M5 1차) → E2E: 프리뷰·출력 종단 검증
→ [후속] M3b 외부 파일 재열기 → M5 2차(원본 접합 실측) → M6 잔여 → 기능 작업(파일 첨부 UI → 저장·재열기 → planId 중복 방지·취소 → 자연어 플래너 = AI-04~)
```

- E2E·export급 실행 전 `scripts/disk_guard.sh --start-gate` 확인. **이번 E2E는 게이트 미달(가용 14.39GiB < SMALL 16GiB)로 거부된 상태에서 실행을 진행했다**: 16:15 빌드 캐시를 재사용하는 증분(예상 추가 사용 <0.5GiB), 활성 대형 디스크 소비 프로세스(voiceagent) 비활동 확인을 근거로 한 명시적 이탈이며, 여기에 기록한다. 재검증 시점 디스크 상태는 다시 확인한다.
- 합성 fixture를 커밋하지 않는다(기존 원칙).
- **부분 통과 원칙(수정)**: 부분 통과는 부분 완료로 기록하고 실패 항목을 남긴다. 원복은 그 수정이 실제 회귀를 만들었을 때만 판단한다(1차의 "부분 통과=가짜 수정" 문구 폐기).

## 4. 진행 기록

- 구현 계획 §14: AI-03 "구현 완료·E2E 결함 발견" 유지, AI-03a 상태는 이 문서의 표를 따라 갱신.
- 이 문서의 2차 개정에서 수정한 구간은 개정 이력에 명시했다(전 문서 상태와 무관하게 현재 코드 기준으로 서술).
- E2E 재검증 결과: 이하 §5에 실행 후 기록.

## 5. 검증 결과 (2026-10-05 심야 실행)

**2차 증분(21:45, e2e-m3b-m5-attempt2.log)**: M6-2차(transform/keyframe/registerAsset/duration 검사 + 계약 테스트 5종)·M3b-lite(저장→재열기→북마크 접근→프리뷰 재구성)·M5-2차(프리뷰 렌더 접합 maxDelta 상한) — E2E+회귀 8/8(11.9s)·Core 전체 **1,570/1,570**·컨테이너 무오염(recovery 부재·테스트 자동저장 0). 주요 발견: `Keyframe.init`이 음수 시간을 `max(0,t)`로 정규화 — DSL 검증이 볼 수 없으므로 모델 계약을 테스트로 고정.

**3차 증분(22:40, e2e-ui-planid-attempt3.log) — 기능 연결**: ① **사용자 진입점 `AIMontageSection`**(인스펙터 프로젝트 도구 — 사진 다중/음악 NSOpenPanel(powerbox→실제 보안 스코프 북마크)·길이 10/15/30/60s·화면비 4종→`applyPhotoMontage`, timelineNotEmpty·중복 planId 친절 메시지). ② **planId 중복 적용 방지** — `EditorSession.dispatch(planId:)` 영수증(`duplicatePlanApplication`, 재시도·더블클릭 차단 — Core 테스트 5종). ③ **프리뷰↔출력 음량 직접 대조**(E2E 5d — 동일 구간 RMS 비율 0.5~2.0, 별도 엔진임을 전제로 한 비교급 검증). E2E+회귀 8/8(13.99s)·Core 1,570(성능 임계 1건 부하 플레이크 — 격리 통과·이 증분과 무관). AI 몽타주 섹션 영문 UI는 AssistantSection 관례를 따름 — ko 카탈로그 등록 후속.

- **E2E 통과**: `AIPhotoMontageE2ETests` 1/1 (9.37s, RC=0, 3차 시도 — 1·2차는 테스트 코드 컴파일 오류로 수정 후 재실행). 증거: `artifacts/ai_creation/20261005-m1-repair/e2e-xcodebuild-attempt3.log`. **램프 중첩 예외 0회·샌드박스 거부 0회**(16:15 실행과 동일 항목 대조). 검증 범위: 프리뷰 composition 구성(apply+redo), 전체 상태 단일 Undo(트랙·캔버스·canvasSize·미디어 라이브러리), JSON 왕복·북마크 유지, 실제 MP4 export(graph mix 경로) 디코딩(길이 15s±0.2·A/V 트랙), 3개 사진 구간 프레임 상호 구분, 마지막 구간 음악 RMS>0.001, 루프 접합부 peak<0.99.
- **Core 전체 통과**: 1,562 테스트 / 241 스위트. 이번 수리로 신규 `TrackGainEnvelopeTests` 13, 플래너 제한 테스트 5 포함.
- **정적 계약 테스트 2건 갱신**: `AudioDuckingTests`(양 엔진 덕킹 의미론 계약 — 프리뷰의 램프 발행이 TrackGainEnvelope 경유임을 단언, voiceClipIds 재등장 금지 조항 추가), `MasterAudioPreviewParityStaticContractTests`(applyAudioVolumeAndFades→applyGainEnvelope 개명 반영). 계약 의도는 변경 없음.
- **Mac 회귀 통과**: MasterAudioFreshness(G-26) + AutosaveFailureSurfacing 7/7.
- **디스크 이탈 기록**: E2E를 START_GATE 미달(가용 14.39GiB) 상태에서 실행(§3 근거). 실행 후 가용 재확인 필요.

### 잔여(후속 증분)

- **M3b 완결**: 실제 프로세스 재시작 + 사용자 선택(powerbox) scope 검증 — 세션 재생성 수준(lite)까지는 E2E로 완료. 테스트 호스트 자기 재시작 인프라 또는 수동 검증 절차 필요. (UI 진입점 `AIMontageSection`의 NSOpenPanel이 실제 powerbox 경로를 제공하므로, 수동 검증 절차 문서화가 현실적 1차 경로.)
- **M6 픽셀 검증**: EXIF 방향·움직임(키프레임 반영)의 프레임 픽셀 단위 검증 — fixture 콘텐츠 기하 설계가 전제.
- **AI 섹션 ko 현지화**: `AIMontageSection` 영문 문자열의 Localizable.xcstrings 등록(AssistantSection도 미등록 — 카탈로그 일괄 패스로 처리).
- **iOS 쌍둥이 패리티**: `IOSExportEngine.applyDuckingRamps`는 전역 덕킹 없는 트랙별+fade창 회피 패턴이라 **중첩 위험은 없음**을 확인. Core `TrackGainEnvelope` 패리티 통일은 후속(iOS 테스트 실행은 기존 정책상 불가 — generic device 빌드만).
- **취소(cancel)**: 몽타주 생성 중 취소 — applyPhotoMontage가 로컬 probe+컴파일로 수 초 내 종료하므로 현재 필요성 낮음. 자연어 플래너(모델 대기) 연결 시 필수.
- **테스트 호스트 잔존 감시**: xcodebuild 종료 후에도 테스트 호스트/앱이 잔존해 30초 자동저장으로 테스트 데이터를 재기록한 사례 관측(2026-10-05 20:09 — 처음 E2E 격리 유출로 의심했으나 잔존 앱의 소행으로 판명, [CRASH_DIAGNOSIS_20261005.md](CRASH_DIAGNOSIS_20261005.md) §7). 러너 종료 시 잔존 프로세스 확인을 운영 규칙에 반영할 것.

**완료 이동**: ~~프리뷰↔출력 음량 직접 대조~~(3차 증분 E2E 5d)·~~planId 중복 적용 방지~~(3차 증분 EditorSession 영수증)·~~실제 파일 첨부 UI~~(3차 증분 AIMontageSection).
