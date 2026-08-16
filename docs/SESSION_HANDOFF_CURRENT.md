# 세션 핸드오프 — 현재 (2026-08-17)

> 마스터 프롬프트(`AGENT_MASTER_PROMPT_20260815.md`) 프로토콜 6번의 세션 종료 산출물.
> 최신 세션이 이 파일의 최상단에 기록한다. 실행 순서의 근거는 `DEVELOPMENT_DIRECTION_20260815.md` §3·§9.

## 2026-08-17 세션 (프리뷰 색공간 발산 수정 — G-29 전도부, 사용자 결정 A 이행)

**게이트**: `verify_gate.sh` 4단계 PASS (swift build / swift test **1,155 tests / 169 suites** / xcodebuild Mac / xcodebuild iOS). `run_core_editing_parity.sh` **14/14 시나리오 PASS**(신규 15번 `crop_rect_video` 포함, 시나리오 1 전환은 기존대로 스킵).

### 완료 — 프리뷰 색공간 발산 결함 수정 (증분 1개)
1. **원인 규명(실측)**: AVPlayer의 디코드 다리는 컴포지터 소스 BGRA에 ICC 색공간 태그를 붙이고(미태그 BT.601 SD → "Composite NTSC", SMPTE_C/601 계열) AVAssetExportSession의 디코드 다리는 `kCVImageBufferCGColorSpaceKey=nil`로 전달한다. 컴포지터의 `CIImage(cvPixelBuffer:)`가 프리뷰 다리에서만 핀된 sRGB 작업 공간으로 ICC 변환을 수행 — 순수 레드 (254,0,0)→(247,36,0), 파리티 MAD 10.25. 독립 Swift 실험(최소 컴포지터 재현)으로 각 단계 버퍼 태그·값을 직접 측정해 확정. 종전 가설(YUV↔RGB 매트릭스 불일치)은 부분 정확 — 실체는 "프리뷰만 ICC 색 관리 개입"이었다.
2. **수정**: `RenderColorConfiguration.sourceImage(from:)` 신규(Core) — `CIImage(cvPixelBuffer:options:[.colorSpace: workingSpace])`로 컴포지터 소스 해석을 작업 공간에 고정(디코더 태그 무관). Mac `CustomVideoCompositor` 4개 지점(transition 2·primary·layering)·iOS `IOSCustomVideoCompositor` 4개 지점 교체. **양 다리가 정의상 동일 해석** — "same project → same pixels" 계약 강화.
3. **실증(DoD 충족)**: 파리티 시나리오 `crop_rect_video`(스크립트 15번) 신설·상시화 — 비디오판 크롭(미태그 BT.601 SD 소스가 캔버스를 채움 → 색조 회전이 레터박스·마스킹·crush 뒤에 숨을 수 없는 구조). 수정 전 FAIL MAD 10.25(G=27.0) → 수정 후 **PASS MAD 0.50**(R=1.5 인코딩 반올림 수준). 기존 13개 시나리오 무회귀(전체 14/14).
4. **테스트**: `ColorSpaceParityTests` +2 — `sourceImageIsPinnedToTheWorkingColorSpace`(해석 고정), `sourceImageIgnoresDecoderICCTag`(AdobeRGB ICC 태그 부착 버퍼에서도 값 불변 + 통과 패스스루 ±1).
5. **문서**: VERIFICATION_STANDARD §2.2 시나리오 표 12→14(#13 crop_rect·#14 crop_rect_video + 스크립트 번호 차이 주석), 백로그 §0.5 G-29 전도부 이행 기록, REQUIREMENTS 변경 이력 1줄.

### 발견·기록(범위 밖 — 후속 감사 대상)
- **무컴포지터(plain) 경로의 절대 색상 회전**: plain 프로젝트는 양 다리가 같은 회전값(출력 (255,23,0))을 내므로 **파리티는 일관**(MAD 0.40)하나, 원본 소스 의도 색상 (254,0,0)과는 미세 차이. 이번 수정은 컴포지터 경로만 다룸(DoD 범위) — plain 경로 절대 색상은 G-29 본 증분(3단계 색관리 전면 감사)으로 이월. **파리티 게이트는 일관성이지 정답이 아님**의 두 번째 실측 사례.
- **plain 경로의 자연 크기 렌더링 재확인**: plain 합성은 캔버스(1920×1080)에 소스를 좌상단 자연 크기(320×240)로 배치(CI 원점 기준 좌하단). 정규화 비교 격자에서 비디오가 차지하는 면적이 작아 색 편차가 희석됨 — 시나리오 통과의 숨은 요인.

### 발견한 함정(다음 세션 참고)
- **`open -n -W` 프로브 직접 실행 시 프리뷰 덤프가 검정 프레임이 될 수 있다**: 실제 파리티 스크립트 경로(시나리오 편집 → rebuild → wait → 스냅샷)에서는 재현 안 됨. 프로브용 축약 하니스보다 **스크립트의 run_scenario를 그대로 재사용**할 것(이번 세션 교훈: 재현은 스크립트 구조로).
- **`open`에 앱 번들 경로 전달 필수**(`.app/Contents/MacOS/...` 내부 바이너리 아님 — LaunchServices가 무시하고 result만 MISSING).
- `CGImage.colorSpace`·`CVBufferGetAttachment`로 디코드 버퍼의 실제 태그를 직접 확인 가능 — 색 문제 디버깅의 1차 도구.

### 다음 세션 인계 (우선순위 순)
1. **EXECUTION_PLAN §3 Inc 2 — EditorViewModel 분해 1호 경계(timeline editing)**: 색공간 수정 완료로 계획 원위치(LOOP_STATE 이전 기준). 순수 이동 리팩터링, 파리티 14·ui_regression으로 무회귀 확인.
2. **G-02 Inc5 HSL 편집 UI** 착수(방향 문서 §3 순서).
3. T1/T2/T3 스트레스 타임라인 fixture 확정 + PERFORMANCE_SLO.md p50/p95 기록.
4. lint 신규 error 0 CI 반영.
5. 장형(≥10분) fixture 제작 후 `run_latency_baseline.sh` 재측.

### 사용자 결정 대기 사항
- Track A(A-1 아이콘/A-2 App Store Connect)는 사용자 작업으로 계속 대기.
- 신규 없음(색공간 우선순위는 결정 A로 해결됨).

## 2026-08-16 세션 2 (G-23 Inc 2 — 크롭 캔버스 에디터 + 파리티 시나리오 + **사전 존재 결함 2건 발견**)

**게이트**: `verify_gate.sh` 4단계 PASS (swift build / swift test **1,153 tests / 169 suites** / xcodebuild Mac / xcodebuild iOS). `run_core_editing_parity.sh` **13/13 시나리오 PASS**(시나리오 1 전환은 기존대로 스킵, 신규 14번 `crop_rect` 포함).

### 완료 — G-23 Inc 2
1. **Core — `CropRectEditingMath`** (`Sources/MovieCutCore/Editing/`): 정규화 크롭 창 이동/리사이즈 순수 수학. 8방향 핸들+내부, 유닛 프레임 클램프, 반전 방지, 최소 크기 바닥, Shift 캔버스 비율 잠금(aspect). `NormalizedRect`에 `maxX`/`maxY` 접근자 추가. 테스트 10개(앵커/클램프/반전/바닥/비율잠금/interior) 전부 PASS.
2. **Mac — `CropCanvasView`** (`App/MovieCutMac/Effects/`): 프리뷰 캔버스 위에 **크롭되지 않은 원본 소스**(에셋 썸네일, aspect-fit)를 백드롭으로 띄우고 크롭 창을 편집(CapCut 방식 — 컴포지션에 이미 크롭이 구워 있어 프리뷰 픽셀로는 원본 맥락을 줄 수 없음). 4모서리+4에지 핸들, 내부 드래그 이동, 외부 디밍, 3분할 가이드, 리셋/완료 툴바, 접근성 라벨. 제스처 종료 시 1회 커밋(`SetClipPropertyCommand.cropRect`) = **드래그 전체가 단일 undo**. 풀프레임 rect는 nil로 정규화(미크롭 프로젝트 JSON 바이트 동일).
3. **배선**: `EditorViewModel.isCropEditorActive`(마스크 에디터와 상호 배제, 선택/프로젝트 변경 시 리셋 3곳) + `updateSelectedCropRect`. 인스펙터 크롭 섹션에 Canvas/Done 토글 버튼.
4. **하니스/스크립트**: `MOVIECUT_UITEST_CROP=1` 게이트(파리티+제네릭 양쪽 — 인스펙터 1:1 프리셋과 동일한 centered 1:1 크롭 계산). `run_core_editing_parity.sh` 시나리오 14 `crop_rect`(이미지 fixture) 추가 — **실측 overall MAD 0.14/0.70 (허용 2.00), 지속 5.000s 정합**.
5. **iOS — 크롭 UI 진입점**: `IOSInspectorSheet` Crop 섹션(비율 프리셋 6종, 활성 프리셋 하이라이트) + `IOSEditorViewModel.updateSelectedCropRect`/`selectedClipSourceAspect`. 공유 `CropPixelProcessor`로 Mac과 동일 영역 크롭.

### 발견·수정한 사전 존재 결함 (Inc 1 드리프트 — 파리티 시나리오가 즉시 포착)
- **[수정] `PlaybackEngine.usesCustomVideoCompositor` 트리거에 `cropRect != nil` 누락**: Inc 1 커밋 메시지는 "양쪽 엔진 트리거 추가"를 주장했지만 코드에는 Export만 있었다. 프리뷰가 크롭을 무시하는 플레인 경로를 타서 크롭-only 프로젝트의 프리뷰≠출력(R 채널 MAD 182). 트리거 1줄 추가로 폐쇄. **교훈: DoD의 "파리티 시나리오"가 없으면 커밋 메시지와 코드의 불일치는 잡히지 않는다.**

### 발견·미수정 결함 (사용자 결정 대기 — 조기 경보 §5(c))
- **프리뷰 커스텀 컴포지터 경로의 untagged SD 비디오 색조 회전**: 태그 없는 BT.601 SD 영상(320×240 fixture)을 커스텀 컴포지터로 스케일하면 프리뷰에만 색조 회전 발생 — 순수 레드 (254,0,0)이 프리뷰 (247,36,0)/출력 (254,0,0), overall MAD ≈ 10.25 (허용 2.00). **크롭 무관**: 크롭된 PNG 소스는 MAD ≤ 2로 양쪽 일치(크롭 배선 자체는 패리티 청결). 기존 녹색 시나리오들이 이를 가려온 이유: 현존 커스텀 컴포지터 시나리오는 전부 (a) 색보정으로 신호를 crush하거나 (b) 마스크로 가시 면적을 ~1%로 줄인다. 즉 **실사용자의 untagged SD 영상에 마스크/크로마키/컬러보정을 적용하면 프리뷰 색상이 출력과 다르게 보이는 실결함**.
  - 추정 메커니즘: 컴포지터 진입 소스 YUV→RGB와 CIContext 출력 RGB→YUV의 행렬(601/709) 가정이 프리뷰 다리에서 어긋남(출력 다리와 달리). `AVPlayerItemVideoOutput`에 `kCVImageBufferCGColorSpaceKey`로 sRGB 태그를 강제하는 실험은 조합 빌드를 행업시켜 폐기(되돌림).
  - 제안: 다음 세션 증분 1로 정착(G-29 색관리 감사의 전도부). 매트릭스 수준 실험 필요 — `CIImage(cvPixelBuffer:)` 태깅/`matchedFrom`/컴포지터 내 정규화 경로. 수정 전까지 스크립트의 비디오판 크롭 시나리오는 주석 처리(근거 각주 스크립트 내 참조).

### 발견한 함정(다음 세션 참고)
- `writeHarnessStatus`는 **truncate-write** — 하니스 결과는 마지막 한 줄만 살아남는다(전 세션 노트 재확인). 진행 체크포인트는 디버깅용.
- **패리티 게이트는 일관성이지 정답이 아니다**: 무효과 플레인 경로는 소스를 캔버스에 자연 크기로 렌더링(캔버스 채움 아님)하는데 양쪽 다 같아서 PASS. 색 결함도 "양쪽이 같은 잘못"이면 통과 — 신호를 crush하지 않는 시나리오(순색+무보정)를 추가로 둘 것(이번 crop_rect가 그 역할).
- xcodegen으로 재생성한 직후 DerivedData가 다른 경로(`/tmp/MovieCutParityDerivedData`)의 첫 빌드는 5분+ 걸릴 수 있다.

### 다음 세션 인계 (우선순위 순)
1. **프리뷰 색공간 발산 결함 수정**(위 결함 — 조기 경보. 비디오판 크롭 파리티 시나리오 재활성화가 완료 판정).
2. **G-02 Inc5 HSL 편집 UI** 착수(방향 문서 §3 순서 원위치).
3. T1/T2/T3 스트레스 타임라인 fixture 확정 + PERFORMANCE_SLO.md p50/p95 기록.
4. lint 신규 error 0 CI 반영 + `EditorViewModel` 분해 1호 경계(timeline editing).
5. 장형(≥10분) fixture 제작 후 `run_latency_baseline.sh` 재측.

### 사용자 결정 대기 사항
- ~~프리뷰 색공간 발산 결함의 우선순위~~ → **결정됨(2026-08-16): 선택 A — 다음 증분으로 색공간 수정 우선.** G-02 Inc5 HSL UI는 그 뒤로. fixture bt709 태깅(C안)은 기각.
- Track A(A-1 아이콘/A-2 App Store Connect)는 사용자 작업으로 계속 대기.

## 2026-08-16 세션 (프로토콜 0 + 증분 2개)

**게이트**: 전 증분 `verify_gate.sh` 4단계 PASS (swift build / swift test **1,143 tests / 168 suites** / xcodebuild Mac / xcodebuild iOS). 커밋 `ab35763`→`6a3845f`까지 6건, main 로컬 (미푸시).

### 완료
1. **프로토콜 0a — WIP 커밋**: `ab35763` docs 재편, `5bec84d` 컴파운드 Phase 2 + 프로 도구 V/C/Y/U, `a66dd6b` iOS 컴포지터 패리티 + 문자열 카탈로그, `eb61487` 방향 문서 채택.
2. **프로토콜 0b — §8 문서 반영**: 백로그 §0.5에 G-23~G-29 등록(G-05/G-07 재정의 포함), VERIFICATION_STANDARD §6(검증 업그레이드 6항), PERFORMANCE_SLO(Metal 트리거 7개 표, 스트레스 타임라인 T1/T2/T3, EffectCostProfile), REQUIREMENTS §13.14 + 체인지로그 + 아카이브 링크 수정.
3. **증분 1 — G-23 크롭 Inc 1** (`0c37215`):
   - `CropPixelProcessor`(Core 공유): 정규화 top-left rect → y-플립 → 픽셀 crop → 캔버스 aspect-fill 중앙 정렬. 전체 프레임은 무변경 게이트.
   - `Clip.cropRect: NormalizedRect?` (레거시 디코드 nil, 미설정 JSON 바이트 동일) + `ClipProperty.cropRect` 케이스(단일 undo).
   - 배선: `CustomCompositionClipEffect.cropRect` → Mac/iOS 컴포지터 `applyClipEffects` 크롭-퍼스트 + 양쪽 엔진 트리거에 `cropRect != nil` 추가(프리뷰=출력 동일 픽셀 경로 구조 보장).
   - UI: 인스펙터 Basic/visual 크롭 섹션 — 비율 프리셋 6종(Original/1:1/4:3/3:4/16:9/9:16), 소스 실제 픽셀 aspect 기반 중앙 크롭 계산.
   - 테스트 9개: 골든 픽셀 4(y-플립 고정, fill+센터링, no-op), 프리셋 수학 3, 명령/Codable 2.
   - **수반 수정(사전 존재 드리프트)**: 프리뷰 커스텀 컴포지터 경로가 transform/opacity/keyframes 미전달(출력만 적용) → `PlaybackClipInstructionMetadata`에 `clipTransform`/`keyframes` 추가해 폐쇄.
4. **증분 2 — 지연 측정 기반** (`6a3845f`): 하니스 `MOVIECUT_UITEST_LATENCY_BASELINE=<n>` + `scripts/run_latency_baseline.sh`(수집 게이트, `--enforce` 전환 가능). **첫 실측**: seek request p50 0.11ms / p95 0.17ms, scrub apply p50 0.07ms / p95 0.10ms, 소형 fixture 프로젝트 열기 121.6ms — PERFORMANCE_SLO.md 기록 완료.

### 발견한 함정(다음 세션 참고)
- `writeHarnessStatus`는 **truncate-write** — 하니스 결과는 마지막 한 줄만 살아남는다. 진행 체크포인트는 디버깅용이고, 최종 판정 라인이 반드시 마지막 write여야 한다.
- 하니스 시나리오는 `ContentView.task`에서 시작(홈 스테이지 아니어야 함 — 기존 게이트와 동일하게 `MOVIECUT_UITEST=1`이면 에디터로 라우팅됨). 시나리오 종료 시 `MOVIECUT_UITEST_QUIT=1` 처리를 직접 호출해야 앱이 종료된다.

### 다음 세션 인계 (우선순위 순)
1. **G-23 Inc 2**: 프리뷰 캔버스 크롭 핸들(마스크 캔버스 패턴 참조) + 파리티 시나리오 #13 `crop_rect`(하니스 `MOVIECUT_UITEST_CROP` + `run_core_editing_parity.sh` 추가) + iOS 크롭 UI 진입점.
2. **G-02 Inc5 HSL 편집 UI** 착수(1단계 최대 체감; 컬러휠/스코프 옆 8밴드 + 커브 에디터).
3. **T1/T2/T3 스트레스 타임라인 fixture** 확정 + `PERFORMANCE_SLO.md`에 p50/p95 기록.
4. lint 신규 error 0 CI 반영 + `EditorViewModel` 분해 1호 경계(timeline editing).
5. 장형(≥10분) fixture 제작 후 `run_latency_baseline.sh` 재측 — SLO "10분 프로젝트 열기 3초"의 원 의미 실측.

### 사용자 결정 대기 사항
- 없음(§7 열린 결정은 기본 채택값으로 진행 중). Track A(A-1 아이콘/A-2 App Store Connect)는 사용자 작업으로 계속 대기.
