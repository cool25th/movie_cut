# MovieCut 실행 종료 원인 조사 — 2026-10-05

상태: 크래시 기록·실행 로그·코드 조사 및 새 앱 프로세스 확인. 제품 코드 수정·빌드·테스트 재실행 없음.

## 1. 확인된 종료 기록

| 한국 시간 | 프로세스 | 직접 원인 | 확인 근거 |
|---|---|---|---|
| 15:57:50 | PID 66913, 테스트 호스트 | Swift 배열 범위 초과 → SIGTRAP | `MovieCutMac-2026-10-05-155757.ips`, `AIPhotoMontageE2ETests.swift:67` 당시 바이너리 |
| 16:12:07 | PID 71465, 테스트 호스트 | Swift 배열 범위 초과 → SIGTRAP | `MovieCutMac-2026-10-05-161213.ips`, `AIPhotoMontageE2ETests.swift:81` 당시 바이너리 |
| 16:15:19 | PID 71811, 테스트 호스트 | 프리뷰 구성에서 볼륨 램프 중첩 → NSInvalidArgumentException | `task-511.log`, `PlaybackEngine.buildComposition` 스택 |
| 19:33:00 | PID 71811, 16:15부터 남아 있던 같은 프로세스 | 버튼 gesture 처리 중 잘못된 메모리 접근 → SIGSEGV | `MovieCutMac-2026-10-05-193312.ips`, `objc_msgSend → swift_getObjectType → MainActor.assumeIsolated → _ButtonGesture` |

19:33 크래시는 새로운 실행의 startup crash가 아니다. crash report의 procLaunch는 16:15:13이며, 오디오 예외를 낸 프로세스와 PID가 같다. 앞선 Objective-C 예외와 나중 메모리 오류의 인과관계는 아직 입증되지 않았다. 버튼 클릭 스택에 사용자 코드의 특정 handler가 나타나지 않아 해당 버튼도 확정할 수 없다.

## 2. 확정된 코드 결함

### A. 테스트 실패 뒤 배열 인덱싱

`AIPhotoMontageE2ETests`는 `#expect`로 배열 개수를 확인한 뒤 `[0]` 등을 사용한다. `#expect`는 실패해도 실행을 계속하므로 배열이 비어 있으면 테스트 호스트 앱 자체가 죽는다. 16:12 로그에는 기본 빈 트랙과 새 트랙이 중복되어 첫 오디오 트랙의 clips가 0인 상태에서 인덱싱한 기록이 있다.

수리: 인덱싱 전에 `#require`, 기대 트랙을 ID로 찾기, 초기 상태 snapshot 비교. 실패는 테스트 failure로 끝나야 하며 프로세스 trap으로 끝나면 안 된다.

### B. 프리뷰 전역 덕킹과 fade 램프 중첩

`EditorViewModel.buildAudioProcessingOptions()`는 모든 비디오 트랙의 volume > 0 클립을 voiceClipIds에 넣고 duckLevel 0.3을 전달한다. 사진 3개도 음성으로 분류된다.

`PlaybackEngine`은 음악 clip fadeIn [0,0.5]를 등록한 뒤 전역 덕킹으로 [0,4] 램프를 같은 audio mix parameter에 추가한다. AVFoundation은 겹치는 램프를 거부하며 Objective-C 예외를 발생시킨다. Swift `do/catch`만으로 정상 오류 처리된다고 가정해서는 안 된다.

전역 루프는 각 parameter가 어느 composition track에 속하는지도 구분하지 않고 음악 클립 구간을 모든 parameter에 추가한다. 음성 대상·track routing·fade/ducking 결합을 함께 수리해야 한다.

수리: 실제 음성 대상으로 제한, track ID별 gain 처리, 겹치지 않는 automation 생성, 기존 audio graph와 통합. preview와 ExportEngine의 graph 출력은 별도 경로이므로 양쪽 실제 음량·페이드를 검증한다.

## 3. 일반 앱 상태에 테스트 데이터가 섞임

새 프로세스로 앱을 열고 New Project를 눌렀을 때 다음 복구 안내를 실제 확인했다:

- 프로젝트: AIVideoTest
- 마지막 자동 저장: 2026-10-05 16:15

복구 원본:
`/Users/cool-mini4/Library/Containers/com.moviecut.mac/Data/Library/Application Support/MovieCut/recovery.moviecut`

내용은 사진 3클립·음악 4클립·텍스트 빈 트랙이며, E2E 몽타주와 일치한다. 테스트의 `EditorViewModel(project:)`가 일반 앱의 기본 ProjectStore를 사용한다. 이미 제공되는 `autosaveDirectory:` 주입점을 사용하지 않고 있다.

수리: 테스트별 임시 autosaveDirectory 사용, 테스트 파일·북마크·preferences 격리, 종료 시 테스트 소유 자원 정리. 일반 사용자의 복구 파일을 테스트가 덮어쓰거나 제거하지 않게 한다.

복구 안내 자체가 crash라는 증거는 없다. 다만 일반 앱에서 결함을 가진 테스트 프로젝트를 다시 열게 만드는 유입 경로다.

## 4. 새 실행 관찰과 한계

- 기존 Debug 실행 파일을 새 프로세스로 실행했다. 홈 화면과 New Project 버튼 클릭은 정상 동작했다.
- 복구 파일을 먼저 복사한 뒤 Recover를 눌렀다. AIVideoTest의 7클립 타임라인이 표시됐다.
- 이 관찰에서 fresh process의 19:33 버튼 메모리 오류는 재현되지 않았다. 모든 편집·재생·출력 안정성을 검증했다는 의미는 아니다.
- 같은 조사 시간대 별도 PID 6580의 unified log에는 오디오 램프 예외가 다시 나타났다. 그 프로세스는 본 조사에서 직접 실행한 PID 6135와 다르며, 실행 주체는 확정하지 않았다.
- 파일 접근 거부는 별도 문제다. crash report에 disk-full/OOM 종료라는 직접 근거는 없으며, 저장소 공간 부족을 이번 세 크래시의 직접 원인으로 판정하지 않는다.

## 5. 다음 수리 순서

1. 테스트 autosave 격리 + #require 적용: 테스트가 일반 앱 상태를 오염시키거나 프로세스를 죽이지 않게 한다.
2. 최소 fade+ducking 재현으로 램프 충돌 검증, 음성 분류·track routing·gain 적용 수리.
3. 종료된 테스트 호스트를 일반 앱처럼 계속 사용하지 않고 fresh process에서 회귀 검증.
4. 정상 입력으로 fresh process에서도 버튼 SIGSEGV가 재현되면 별도 이슈로 분리하고 버튼 handler·객체 수명·executor를 조사한다. 현재 메모리 오류를 오디오 예외의 결과로 확정하지 않는다.
5. 외부 파일 접근·저장 재열기·프리뷰 및 실제 export 종단 검증.

## 6. 증거 보존

복구 파일 백업:
`artifacts/crash_diagnosis_20261005/recovery-before-diagnosis.moviecut`

크래시 원본:
`/Users/cool-mini4/Library/Logs/DiagnosticReports/MovieCutMac-2026-10-05-{155757,161213,193312}.ips`

테스트 실행 로그:
`/Users/cool-mini4/.gemini/antigravity/brain/ae0bdc0d-9ce7-4710-919f-25d460a89504/.system_generated/tasks/task-473.log`
`/Users/cool-mini4/.gemini/antigravity/brain/ae0bdc0d-9ce7-4710-919f-25d460a89504/.system_generated/tasks/task-511.log`

## 7. 수리 처분 갱신 (2026-10-05 심야 — 커밋 044d09a + 저장 격리 증분)

- **§2-A 배열 인덱싱 → 수리 완료**(044d09a): `#require` 전제조건·전체 상태 비교로 전환. 실패는 테스트 failure로 끝나며 프로세스 trap 없음.
- **§2-B 램프 중첩 → 수리 완료**(044d09a): 음성 분류 오류(이미지→voice)와 전역 덕킹 램프(라우팅 없음·fade 무시)를 `TrackGainEnvelope` 비중첩 봉투 + 전역 블록 삭제로 해소. 프리뷰 재구성 무예외 E2E 통과(9.4s).
- **§3 테스트 데이터 오염 → 수리 완료**(이번 증분): `ProjectStore.namedAutosaveDirectory` 신설 — `EditorViewModel`의 명명 자동저장(30초 타이머)이 주입 디렉터리를 존중(기본 경로 불변, 회귀 AutosaveFailureSurfacing 통과). E2E는 per-run 임시 저장소(autosave·fixture·export 통합)를 사용하고 **실제 컨테이너 무변경을 단언**으로 검증.
- **§1 19:33 SIGSEGV → 감시 항목 유지**(인과 미입증·신규 프로세스 정상). 추가 사실: 16:15 테스트 호스트가 xcodebuild 종료 후에도 3시간+ 잔존했고, 이후 별도 실행된 앱이 이 테스트의 복구 프로젝트를 로드해 **30초 자동저장으로 테스트 데이터를 계속 재기록**하고 있었다(20:09 관측 — 처음 E2E 유출로 보였으나 잔존 앱의 소행으로 판명). 잔존 프로세스 3종(앱 2·xcodebuild 1) 정리로 해소. 교훈: 테스트 후 (1)호스트 프로세스 잔존 (2)복구 로드된 앱의 주기적 자동저장 — 두 경로가 테스트 누출로 오인될 수 있으므로 러너 종료 시 프로세스 확인을 운영 규칙에 추가.
