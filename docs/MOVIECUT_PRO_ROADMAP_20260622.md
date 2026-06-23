# MovieCut Pro 로드맵 — "CapCut을 능가한다"

> 작성일: 2026-06-22 / 브랜치: `feat/core-backend-expansion`
> 이 문서는 전략 전환점을 기록한다. 이전 모든 작업은 **CapCut 파리티(따라잡기)** 가 목표였다.
> 이제부터의 목표는 **기능·화면 모두 CapCut을 월등히 능가하는 것**이다.
> 상위 기능 백로그는 `CAPCUT_FEATURE_BACKLOG.md`, 명세는 `CAPCUT_PARITY_SPEC.md`, UI 격차는 `MOVIECUT_CAPCUT_DESIGN_GAP_AUDIT_20260619.md` 참조.

---

## 0. 확정된 전략 결정 (2026-06-22)

| 결정 | 선택 | 의미 |
|---|---|---|
| **포지셔닝** | **Pro / 프로슈머** | 성능·화질(ProRes/HDR)·색보정·키프레임으로 능가. CapCut이 구조적으로 약한 전문 영역을 공략. |
| **플랫폼** | **Mac + iOS 동시 파리티** | Core 변경 시 Mac/iOS compositor·뷰 동시 갱신. 생태계 일관성 유지. |
| **착수점** | **Phase 0 기반 경화 (순수)** | 새 기능 0개. 검증 인프라·🟡 스윕에만 집중. 모래 위에 더 쌓지 않는다. |
| **경쟁 기준선** | **"CapCut을 Pro급으로"** | CapCut의 우수한 UX/속도는 유지·계승하고 **화질·출력·제어만 Pro급**으로 격상. FCP/Resolve 전면 추격은 비목표(난이도·범위 폭증). 단 색보정/키프레임 설계 시 그들을 *참조*는 한다. |
| **Metal 파이프라인** | **조건부 (Phase 2B)** | 전면 재작성을 미리 확정하지 않는다. Phase 0.3 성능 베이스라인이 CoreImage/compositor 구조를 **실제 병목으로 증명할 때만** 착수. 그전엔 저위험 색그레이딩·ProRes/HDR(2A) 우선. |

---

## 1. 진단 요약 (왜 전환이 필요한가)

현재 코드베이스는 **폭은 넓지만 검증이 얕다.**

- 백로그 자가진단: 자가보고 파리티 97% vs **실동작 체감 55~65%**.
- 테스트 94개 중 **49개가 static contract**(문자열 존재 검사). 드래그앤드롭 버그가 교과서 사례 — static contract는 통과했으나 런타임은 깨져 있었다.
- 그 결과 `🟡 구현+테스트 완료` 항목 대량: 배경제거·EQ/노이즈감소·덕킹·비트감지·자동컷·자동리프레임·캔버스배경·TTS·클라우드충돌·자막워크플로우 — **전부 "preview에 보이고 export에 반영됨"이 미검증**.
- UI 작업은 5루프 연속 **"CapCut 유사도 ≥ 0.75"** 를 목표로 함. **유사도로는 능가가 불가능**하다(모순).

**결론**: 능가하려면 (a) 기반을 진짜로 굳히고, (b) CapCut을 기준점이 아닌 추월 대상으로 재설정해야 한다.

---

## 2. 차별화 명제 — CapCut의 약점 = 우리의 기회

| CapCut 약점 | MovieCut 기회 (네이티브 Mac/iOS) | 어느 Phase |
|---|---|---|
| 클라우드 의존·강제 로그인·텔레메트리·프라이버시 논란 | 완전 오프라인·프라이버시 우선·로그인 불필요 | 전반 |
| 워터마크·구독 페이월·기능 잠금 | 워터마크 없음·Pro export 무제한 | 전반 |
| 클라우드 AI (느림·비공개 우려) | **온디바이스 AI** (Vision/Speech/Core ML/FoundationModels) | Phase 3 |
| 소비자 화질(h.264 중심) | **ProRes / HDR / 10-bit / 고비트레이트** | Phase 2 |
| 얕은 색보정·키프레임 | **스코프·커브·HSL 그레이딩**, 진짜 키프레임 커브 에디터 | Phase 2/4 |
| Electron/크로스플랫폼 무게 | **Metal 실시간 파이프라인** — 더 빠른 반응성 | Phase 2 |
| 폐쇄적 | **플러그인 SDK** (레지스트리 이미 보유) | Phase 4 |

---

## 3. Phase 개요

> 캘린더 추정을 의도적으로 뺐다(AI 에이전트 주도·단일 흐름이라 주(週) 추정은 신뢰도 낮음). **순서·의존성·완료기준**으로 관리한다.

| Phase | 이름 | 목표 | 선행조건 |
|---|---|---|---|
| **0** | 기반 경화 (순수) | 🟡 → 진짜 ✅. 검증 인프라 교체. 성능 베이스라인. **안정성 트랙 착수.** | 없음 (현재) |
| **1** | 핵심 편집 루프 완성도 | 매 세션 동작을 흠 없이. Mac/iOS 격차 해소. 안정성 강화. | Phase 0 종료 |
| **2A** | 색 그레이딩 + Pro 출력 ⭐ | 스코프·커브·HSL + ProRes/HDR/10-bit. **저위험·고가시성.** | Phase 0.3 베이스라인 |
| **2B** | Metal 파이프라인 (조건부) | 실시간 60fps·export 가속. **베이스라인이 병목 증명 시에만.** | 2A + 병목 증명 |
| **3** | 온디바이스 AI로 능가 ⭐ | Vision/Speech/Core ML/FoundationModels | Phase 1 |
| **4** | UX·Pro 기능으로 능가 | 키프레임 커브·플러그인 SDK·macOS 통합 | Phase 2A |
| **UI** | 자체 디자인 시스템 (병행) | 유사도 지표 폐기 → 반응성·밀도·발견성 | 전 단계 병행 |

---

## 4. Phase 0 — 기반 경화 (현재 착수) 🔨

> 새 기능 0개. 신뢰도 100%. 이 Phase의 산출물은 **증거**다.

### 0.1 검증 인프라 교체 (최우선)

현 상태: static contract 49개(문자열 검사) + 기존 `scripts/verify_moviecut_export_golden.py`(2026-06-12 단일 fixture preflight로 **의도적으로 좁게** 스코프됨). XCUITest 타깃 **없음**.

| 작업 | 내용 | 산출물 |
|---|---|---|
| **0.1a 결정적 fixture 세트** | ffmpeg로 작은 실미디어 생성(2~3s mp4, png, wav, 다중 클립 프로젝트). 결정적·재현 가능하게 스크립트화. | `scripts/make_fixtures.sh`, `Tests/Fixtures/` |
| **0.1b 골든 export 하니스 확장** | 기존 single-fixture verifier를 **다중 기능 골든 export**로 확장: 색보정·전환·텍스트번인·크로마키 각각 export → 출력 프레임 픽셀/perceptual hash를 커밋된 골든과 비교. Mac·iOS 양쪽. | `Tests/.../GoldenExportTests.swift`, `scripts/verify_*` 확장 |
| **0.1c XCUITest GUI E2E 타깃** | `project.yml`에 UI test 타깃 추가. 핵심 플로우 자동화: import → 타임라인 추가 → split → export. 런타임 회귀를 잡는 진짜 안전망. | `project.yml` 신규 타깃, `App/.../UITests/` |
| **0.1d static contract 역할 강등** | 회귀 잠금용으로만 유지. **"완료 증거"로 인정 금지.** | 문서 규칙 |

### 0.2 🟡 → ✅/❌ 실검증 스윕 (Pro 가치순 정렬)

각 🟡 항목을 실 fixture로 **preview + export** 확인하고 증거를 남긴다. 못 고치면 정직하게 ❌로 강등. **Pro 포지셔닝 가치순**으로 정렬한다 — 숏폼 지향 항목은 후순위로 미루거나 drop.

- **티어 1 (Pro 핵심, 최우선)**: **EQ/노이즈감소 DSP(F-16, ❌ 가능성 높음 — Pro 오디오 품질 직결)** · 배경제거(F-08, 화질) · 색보정 warmth/tint 보강 · 정지프레임 export.
- **티어 2 (편집 신뢰)**: 오디오덕킹(F-14) · 자동컷(F-18) · 자막워크플로우/SRT(F-13) · 캔버스배경(F-11) · 클라우드충돌(F-22).
- **티어 3 (숏폼 지향, Pro 후순위 — 검증 후 drop/연기 판단)**: 비트감지(F-15) · 자동리프레임(F-19) · TTS(F-17) · 자동하이라이트(F-20).

각 항목 DoD: `{ 기능, preview 증거(스크린샷/녹화), export 증거(출력 해시), 판정 ✅/❌, Pro 로드맵 유지/drop }`.

### 0.3 성능 베이스라인 측정 (Pro 포지셔닝 필수)

Phase 2(Metal)에서 "더 빠르다"를 증명하려면 먼저 현재 수치를 박아야 한다.

- 측정: 1080p·4K 표준 프로젝트의 **export 시간**, **preview fps**, **메모리 피크**.
- 도구: `os_signpost` / `XCTMetric` 또는 간단한 타이밍 스크립트.
- 산출물: `docs/PERF_BASELINE_20260622.md` (Phase 2 비교 기준).

### 0.4 Mac ↔ iOS 파리티 감사 (플랫폼 동시 결정 반영)

- Core 기능별로 Mac compositor / iOS compositor / 양쪽 뷰 배선 매트릭스 작성.
- 누락(Mac만 있고 iOS 없음 등) 목록화 → Phase 1에서 해소.
- 산출물: `docs/PLATFORM_PARITY_MATRIX.md`.

### 0.5 정직한 상태판 리셋

- `CAPCUT_FEATURE_BACKLOG.md`를 **증거 기반**으로 재작성: 각 기능에 ✅(증거 링크)/🟡(검증 중)/❌. 자가보고 수치 제거.

### 0.6 안정성·신뢰성 트랙 착수 (Pro 핵심 가치)

> Pro 사용자에게 "안 깨진다"는 기능만큼 중요하다. CapCut 대비 명확한 우위 지점이기도 하다.

- **자동저장 + 크래시 복구**: 주기적 스냅샷, 비정상 종료 후 마지막 안전 상태 복원. (`ProjectStore` 확장)
- **되돌리기 무결성**: 모든 command의 undo/redo 왕복을 fixture 프로젝트로 검증(현재 command 다수가 동작은 하나 무결성 미검증).
- **대용량 미디어 안정성**: 4K/장시간 클립에서 메모리·크래시 가드 (Phase 0.3 측정과 연계).
- 산출물: 자동저장/복구 동작 + undo 무결성 테스트(behavioral).

### 0.7 UI 디자인 방향 구체화 (산출물 있는 트랙)

> "자체 디자인 언어"를 추상에서 실행 가능으로. CapCut 모방이 아닌 Pro 정체성.

- **디자인 원칙 1p**: 반응성·정보밀도·발견성·접근성을 측정 가능한 원칙으로 명문화.
- **핵심 화면 2~3개 목업**: 색 그레이딩 화면, Pro export 화면, 타임라인 밀도 — 방향을 시각화(구현 아님).
- 산출물: `docs/UI_DESIGN_PRINCIPLES.md` + 목업.

### Phase 0 종료 기준 (Definition of Done)
- [ ] fixture 세트 + 골든 export 하니스가 4개 이상 기능을 실픽셀로 검증.
- [ ] XCUITest가 import→export 플로우를 자동 통과.
- [ ] 모든 🟡 항목이 ✅(증거 포함) 또는 ❌/drop으로 판정됨 (Pro 가치순).
- [ ] 자동저장/복구 + undo 무결성 behavioral 테스트 통과.
- [ ] 성능 베이스라인·플랫폼 파리티 매트릭스·UI 디자인 원칙 문서화.
- [ ] `swift build`, `swift test`, `xcodebuild MovieCutMac/MovieCutiOS build` 통과.

---

## 5. Phase 1~4 (요약 — Phase 0 종료 후 상세화)

### Phase 1 — 핵심 편집 루프 완성도
- 표준 워크플로우 완주: 미디어→컷→텍스트→BGM→Export, 자동자막→스타일.
- 타임라인 반응성·스냅·매그네틱 정밀도, 실시간 preview 끊김 제거.
- Phase 0.4 매트릭스의 Mac/iOS 누락 전부 해소.

### Phase 2A — 색 그레이딩 + Pro 출력 ⭐ (저위험·고가시성, 먼저)
- **색 그레이딩 스위트**: 파형/벡터스코프/히스토그램, 커브, HSL. (Resolve/FCP를 설계 *참조*, 전면 추격은 아님)
- **ProRes / HDR(10-bit) / 고비트레이트** export — CapCut 미제공 Pro 출력.
- Mac/iOS 공유 픽셀 프로세서 패턴 위에 구현(기존 아키텍처 유지).

### Phase 2B — Metal 파이프라인 (조건부) ⚠️
- **선행조건: Phase 0.3 성능 베이스라인이 CoreImage/compositor 구조를 실제 병목으로 증명**해야 착수.
- 증명되면: 현 CoreImage per-frame compositor → Metal. preview 60fps, export 가속.
- 증명 안 되면: 병목 지점만 국소 최적화(캐시·비동기 compositing)로 대체하고 전면 재작성은 보류.

### Phase 3 — 온디바이스 AI로 능가 ⭐
- Vision(인물/객체 세그멘테이션·모션트래킹), Speech(실시간 자막·화자분리).
- FoundationModels(iOS 26+)/Core ML로 자연어 편집 어시스턴트(`AssistantCommandParser` 1단계 → 로컬 LLM 격상), 롱폼→숏폼 자동 하이라이트.
- 전부 **오프라인·워터마크 없음**.

### Phase 4 — UX·Pro 기능으로 능가
- 진짜 키프레임 **커브 에디터**, 플러그인 SDK 공개, ProRes 프록시 워크플로우, macOS 깊은 통합(Shortcuts/Quick Look/다중 윈도우).

---

## 6. UI 전략 트랙 (전 단계 병행) ⭐

> **"CapCut 유사도" 지표 폐기.** 능가가 목표인데 유사도를 재는 것은 모순.
> 단 경쟁 기준선 결정("CapCut을 Pro급으로")에 따라 **CapCut의 우수한 UX/속도/발견성은 계승**하고, 그 위에 Pro 밀도·제어를 얹는다.

- 측정 전환: 유사도 → **반응성(상호작용 지연)·정보 밀도·발견성(기능 도달 클릭 수)·접근성**.
- `MovieCutTheme` 토큰을 **자체 Pro 다크 에디터 디자인 언어**로 발전(모방 아닌 정체성). 방향은 Phase 0.7 산출물(`UI_DESIGN_PRINCIPLES.md` + 목업)로 구체화.
- 실제 사용자 플로우를 XCUITest로 녹화·회귀 보호(시각 지표 스크립트와 병행).

---

## 7. 엔지니어링 규율 (확정 변경)

1. static contract 테스트는 **회귀 잠금 전용** — 신규 "완료 증거"로 불인정.
2. **증거 기반 DoD** — 모든 완료는 export 해시 또는 GUI 녹화 첨부.
3. **성능 1급 지표화** — 주요 PR에 export/preview 벤치마크.
4. **정직한 상태판** — 미검증은 🟡 아닌 ❌. 자가보고 수치 신뢰 금지.
5. **Mac/iOS 동시** — Core 변경 시 양 플랫폼 compositor/뷰 동시 갱신·검증.

---

## 8. 다음 작업 (Phase 0 착수 순서)

1. `0.1a` fixture 세트 생성 스크립트 + `Tests/Fixtures/`.
2. `0.1b` 골든 export 하니스 — **색보정부터 1개 실픽셀 검증으로 패턴 확립** (← 첫 한 수).
3. `0.1c` XCUITest 타깃 추가 + import→export 1개 플로우.
4. `0.2` 🟡 스윕 — **티어 1부터**(EQ/노이즈감소 DSP 판정 → 배경제거 → 색보정 warmth/tint → 정지프레임).
5. `0.6` 안정성 — 자동저장/복구 + undo 무결성 테스트.
6. `0.3`/`0.4`/`0.5`/`0.7` 문서 산출물(성능 베이스라인·파리티 매트릭스·상태판·UI 원칙).

### 진행 기록 (2026-06-22)

- ✅ **검증 패턴 확립**: `Tests/MovieCutCoreTests/Support/GoldenPixelHarness.swift` — `CIContext(useSoftwareRenderer:true)` 기반 결정적·sandbox-safe 렌더러. 레거시 `coreImageRenderingAvailable()` **silent-skip 안티패턴 제거** → `assertRendererFunctional()`이 망가진 렌더러를 *소리내어* 실패시킨다.
- ✅ **첫 골든 (색보정)**: `ColorCorrectionGoldenTests.swift` — 커밋된 골든 픽셀값(brightness/saturation/combined). 프로세서를 일시 identity로 망가뜨려 **4개 골든이 실제로 실패함을 증명**(이빨 확인) 후 revert.
- ✅ **결정적 fixture 세트 (0.1a)**: `scripts/make_fixtures.sh` + `Tests/Fixtures/`(red 2s·bars 3s·tone 2s·blue png, ffprobe로 속성 검증). `MediaFixtures` 헬퍼(#filePath 기준) + `MediaFixtureTests`가 실 AVFoundation 로드로 duration/해상도 검증 → "실미디어 in test" 패턴 고정.
- 검증: `swift test --filter 'StaticContract|...Golden|MediaFixture'` **309 tests/72 suites pass**, `git diff --check` clean.
- ✅ **앱 레벨 E2E (0.1c)**: `App/MovieCutMacUITests/`(XCUITest) + DEBUG 런치 하니스(`App/MovieCutMac/UITestHarness.swift`, env-var 게이트) + `exportProject(to:)` seam + `scripts/run_e2e_export.sh`. 실제 import→타임라인→export 파이프라인이 **유효한 h264 mp4(1920×1080, duration 2.0s)를 생성함을 런타임으로 증명**. ⚠️ XCUITest 자동화 실행은 macOS Accessibility/Automation 권한 필요(비대화형 터미널에서 "automation mode" 타임아웃) → 헤드리스 `run_e2e_export.sh`로 권한 없이 파이프라인 검증. CI/대화형 세션에서 XCUITest 별도 실행 권장.
- ⚠️ **xcodegen 함정 발견·수정**: `xcodegen generate`가 Mac `Info.plist`를 덮어써 드래그앤드롭 UTType 선언(`com.moviecut.media-asset-id`)+마이크 권한을 날렸음(잠복 회귀). project.yml의 `info:` 생성 블록을 제거하고 hand-maintained plist를 `INFOPLIST_FILE`로만 참조하도록 영구 수정 → 재생성에도 보존 확인.
- ⚠️ **iOS 빌드 미검증**: 이 머신에 iOS 26.5 플랫폼/런타임 미설치로 `MovieCutiOS` 빌드 실행 불가. 구조 배선(plist·INFOPLIST_FILE)은 Mac과 동일하게 온전. iOS 플랫폼 설치된 환경에서 빌드 확인 필요.
### 0.2 스윕 결과 — 티어1 EQ/노이즈감소 판정 (2026-06-22)

증거 기반 판정 (`AudioEqualizerGapTests` + 코드 추적):

| 기능 | 알고리즘 블록 | preview | export | 판정 |
|---|---|---|---|---|
| **EQ** | `AudioEqualizerService`(5밴드 `AVAudioUnitEQ`) — **앱에서 호출 0회 = dead code**, offline render 호출 시 `'player started when in a disconnected state'` **크래시**(노드 연결 순서 1회 수정 시도 실패) | `PlaybackEngine.applyEQBands` → **평균게인 단일 볼륨 배수**(주석이 자인) | `ExportEngine.eqVolumeMultiplier` → **평균게인 단일 볼륨 배수** | **❌** 실 EQ 미반영. bassBoost `[6,4,1,0,0]`/trebleBoost `[0,0,1,4,6]`는 평균게인 동일→볼륨 근사가 둘을 **구분 못 함**(`AudioEqualizerGapTests`로 잠금) |
| **노이즈감소** | `NoiseReductionService`(HPF+LPF+Dynamics) — `applyNoiseReduction(for:)`에서 호출, denoise 파일 생성 후 **클립 소스 교체**(destructive apply) | (live 미적용; 교체된 소스로 반영) | (교체된 소스로 반영) | **🟡** 알고리즘 real + 배선 존재하나 **런타임 미검증**(EQ와 같은 offline-render 패턴 → 동일 크래시 위험). 실오디오 GUI 확인 필요 |

- **Pro 함의**: Pro 오디오엔 실 EQ가 필수. 현재 타임라인 EQ는 볼륨 장식. **Phase 2A 과제 신설**: preview/export에 `MTAudioProcessingTap`(또는 pre-render bake)로 실제 5밴드 EQ/NR 적용 + 골든 오디오 검증. AVAudioEngine offline 크래시도 거기서 정조준.
- 검증: `swift test --filter AudioEqualizerGapTests` pass(크래시 없는 갭 증명). 실 DSP 호출 테스트는 `swift test` 프로세스에서 SIGABRT → 제외.

### 0.2 스윕 결과 — 티어1 배경제거(F-08) 판정 (2026-06-22)

EQ와 대조적으로 **건강한 상태** — 증거:

| 레이어 | 상태 |
|---|---|
| 합성 헬퍼 `PersonSegmentationCompositor.removeBackground`(`CIBlendWithMask`) | ✅ real + **non-skippable 골든**(`BackgroundRemovalGoldenTests`: center alpha **255**, corner **0**). 레거시 `BackgroundRemovalTests`의 silent-skip 픽셀 단언을 골든으로 보강 |
| Vision 세그멘테이션 `VNGeneratePersonSegmentationRequest` | ✅ real + Mac(`CustomVideoCompositor:956`)·iOS(`IOSCustomVideoCompositor:793`) 양쪽 배선, `.fast`/`.accurate`, no-person guard |
| preview/export 배선 | ✅ static contract(`isBackgroundRemoved` threading) |
| **실인물 E2E**(Vision이 실제 인물 마스크 생성→합성→export) | 🟡 **미검증** — 테스트는 synthetic mask 사용, 실인물 fixture 없음. Vision 요청 자체는 테스트에서 실행된 적 없음 |

- **판정**: **대부분 ✅** (알고리즘·합성·배선 real+검증). 잔여 🟡는 **실인물 E2E 1건**(실인물 비디오 fixture 또는 디바이스 캡처 필요). EQ(❌ dead+broken)와 격이 다름.

### 0.2 스윕 결과 — 색보정 warmth/tint ❌→✅ 구현 (2026-06-22)

- **발견**: warmth/tint **슬라이더가 Mac(`InspectorEffectsSection`)·iOS(`IOSEffectsInspectorView` "색온도")에 이미 존재**하고 모델에 배선됐으나, `ColorCorrectionPixelProcessor`가 **둘을 무시(no-op)** → 사용자가 슬라이더를 움직여도 preview/export에 **아무 변화 없음**(작동 안 하는 컨트롤). Pro 색보정엔 치명적.
- **구현**: shared `ColorCorrectionPixelProcessor.apply`에 `CITemperatureAndTint` 단계 추가(`hasTemperatureAdjustments` 게이트). 부호는 grading-intuitive — **warmth+ = 따뜻함(red↑/blue↓)**, tint+ = 마젠타. shared processor 경유라 Mac/iOS preview+export에 자동 반영.
- **검증**: non-skippable 골든(`ColorCorrectionGoldenTests`: warmth+1 → `[166,148,121]`, tint+1 → `[191,124,185]`, 소프트웨어 렌더러로 실측·잠금) + 레거시 no-op 테스트를 "applied" 동작으로 갱신. `swift test --filter ColorCorrection*` **15/3 pass**, Mac `xcodebuild` BUILD SUCCEEDED.
- **판정**: **✅** (preview+export 실반영). 잔여: 실영상 GUI 육안 확인은 선택.

### 0.2 스윕 결과 — 노이즈감소(NR) 🟡→✅ 앱 컨텍스트 런타임 확정 (2026-06-22)

- **위험**: `NoiseReductionService`는 EQ와 동일한 AVAudioEngine offline 패턴 → `swift test`에서 SIGABRT 위험이라 앱 컨텍스트로 검증 필요.
- **검증**: 하니스에 `MOVIECUT_UITEST_DENOISE` 훅 + `MOVIECUT_UITEST_RESULT` 결과파일 추가. tone fixture import → `applyNoiseReduction(for:)`(실 HPF 80Hz + LPF 12kHz + Dynamics offline render) 실행 → **앱 종료코드 0(크래시 없음), 결과 `error=none`, 클립 소스 denoise 파일로 교체**. `run_e2e_export.sh`에 codify.
- **판정**: **✅ 앱 런타임 동작 확정**(크래시 없이 실행 + 소스 swap). EQ의 `swift test` SIGABRT는 **테스트 환경 artifact**였음이 입증됨(앱 오디오 컨텍스트에선 offline render 정상). 잔여: 실잡음 오디오 효과 청감은 선택. **EQ가 ❌인 이유는 크래시가 아니라 dead code(미배선)+볼륨근사** — NR은 배선됨이 결정적 차이.

### 0.2 스윕 결과 — 정지프레임(freeze frame) ❓→✅ export 반영 확정 (2026-06-22)

- **상태**: 백로그가 "🟡 export 반영 미확인"으로 둔 항목. 코드 추적 결과 export(`ExportEngine` `isFreezeFrame` 감지 → `freezeFrameSourceTimeRange` 1프레임 source range → `scaleTimeRange`로 freezeDuration까지 확장)·preview(`PlaybackEngine`) **양쪽에 표준·정확한 기법으로 구현**됨. 단 전용 테스트 0개였음.
- **E2E 검증**: 헤드리스 하니스에 `MOVIECUT_UITEST_FREEZE` 훅 추가 → 2s fixture 중간에 2s freeze 적용 후 export. **baseline 2.000s → freeze 4.000s, delta 정확히 2.00s** = freeze duration. `scripts/run_e2e_export.sh`에 codify(반복 가능).
- **판정**: **✅ export 실반영 확정**(런타임 측정).

### 0.3 성능 베이스라인 — Metal 결정 해소 (2026-06-22)

`scripts/perf_baseline.sh` (10s/1080p export, Debug). 상세는 `docs/PERF_BASELINE_20260622.md`.

| 경로 | 시간 | realtime | 메모리 |
|---|---|---|---|
| passthrough | 4.51s | 0.45× | 160 MB |
| color (CoreImage `CustomVideoCompositor`) | 4.90s | 0.49× | 166 MB |
| **CoreImage 오버헤드** | **+0.39s (1.1×)** | | +6 MB |

- **preview 렌더**: 1080p 풀 색보정 프레임당 GPU 렌더 **5.51ms → 182fps 용량**(60fps 예산의 33%). preview도 60fps 여유.
- **결정: Phase 2B Metal 전면 재작성 보류(defer) — 양 경로 측정 확정.** export(+9%, 0.49×)·preview(5.5ms/frame, 182fps) 모두 CoreImage 합성이 병목 아님. 조건부 Metal이 "보류"로 닫힘. 절약된 노력은 2A(색그레이딩·ProRes/HDR)·3(온디바이스 AI)으로.
- **후속(재검토 트리거)**: 무거운 합성(전환+마스크+다중레이어)·4K에서 프레임당 16.6ms 초과 시 preview 한정 재검토.

### 이전 커밋 회귀 검증 (2026-06-22)

사용자 요청으로 기존 커밋 건전성 점검:
- **Mac 앱 빌드**: `eb63f1d`(사용자 본인 커밋 — `MOVIECUT_BOOTSTRAP_PROJECT` env 게이트 스크린샷 부트스트랩, 제 UITest seam과 다른 env/`.task`라 무충돌) + 제 모든 변경 함께 **BUILD SUCCEEDED**.
- **전체 스위트**(네트워크/Speech/마이크 통합 6스위트 제외): **633 tests passed / 0 failed**. 모델·명령·전 렌더/픽셀 프로세서·static contract·cloud/collab + 신규 골든 전부 통과 → **로직 회귀 없음**.
- ⚠️ **검증 인프라 부채(기록)**: `swift test` 전체가 헤드리스에서 완주 곤란 — (a) `ClaudeEditingProvider`(네트워크)·`TextToSpeech`/`Voiceover`/`Transcription`(Speech·마이크 권한)은 hang/권한 프롬프트, (b) `TransitionExportFixture` 등 실 AVFoundation export 픽셀 테스트는 분 단위로 느림. **Phase 0.1 후속**: 통합/느린 테스트에 trait 태깅 + CI 분리(`.tags`/별도 스킴)로 헤드리스 완주 보장.
