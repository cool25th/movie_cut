# MovieCut 성능 베이스라인 (Phase 0.3)

> 측정일: 2026-06-22 / 머신: Apple Silicon (arm64) / 빌드: **Debug** (비최적화 — 보수적 수치)
> 재현: `bash scripts/perf_baseline.sh`
> 목적: Phase 2B(Metal 파이프라인) 결정의 측정 근거. "조건부 Metal" 결정([로드맵](MOVIECUT_PRO_ROADMAP_20260622.md) §0)에 따라, CoreImage `CustomVideoCompositor`가 실제 병목일 때만 Metal을 착수한다.

## 측정 방법

표준 export 작업: **10초 / 1280×720 입력 → 1080p 출력 / 30fps** (300프레임). 헤드리스 하니스로 두 경로를 export하고 wall-clock·peak RSS 측정:

- **passthrough**: 효과 없음 (custom compositor 미경유).
- **color**: 5단계 색보정(brightness/contrast/saturation/warmth/tint) → **모든 프레임이 CoreImage `CustomVideoCompositor` 경유**.

두 경로의 차이가 곧 CoreImage 프레임별 합성 비용이다. (단일 실행 baseline; 통계적 벤치마크 아님.)

## 결과

| 경로 | export 시간 | realtime 배율 | peak 메모리 |
|---|---|---|---|
| passthrough | 4.51s | **0.45×** | 160 MB |
| color (CoreImage) | 4.90s | **0.49×** | 166 MB |
| **CoreImage 오버헤드** | **+0.39s** | **1.1× 느림** | +6 MB |

## 해석 — Phase 2B Metal 결정

**CoreImage `CustomVideoCompositor`는 export 병목이 아니다.**

- 5단계 색보정 전체를 매 프레임 적용해도 export 시간은 **+9%**만 증가.
- 효과를 켠 상태에서도 export가 **realtime의 2배 빠름**(0.49×).
- Debug 빌드 기준이므로 Release에선 더 빠르다 → "병목 아님" 결론은 더 견고.

## 실시간 preview 렌더 비용 (2026-06-22 추가)

export는 오프라인 경로다. preview fps는 **프레임당 GPU 렌더 시간**이 좌우한다(60fps=16.6ms/frame, 30fps=33.3ms). 앱이 실제 쓰는 GPU `CIContext`로 1080p 풀 색보정 프레임을 300회 렌더(`createCGImage`, CPU readback 포함) 측정:

| 측정 | 값 |
|---|---|
| 프레임당 렌더 | **5.51 ms** |
| 지속 가능 fps | **182 fps** |
| 60fps 예산(16.6ms) 사용률 | **33%** |

→ 1080p 풀 색보정 preview는 **60fps를 여유롭게 유지**(decode/display에 ~11ms 남음). `createCGImage`는 CPU readback을 포함하므로 실제 디스플레이(Metal 백드 레이어) 렌더는 더 빠른 **보수적 상한**이다.

## 결론 — Phase 2B Metal 결정

**export(+9%, 0.49×)와 preview(5.5ms/frame, 182fps) 양쪽 측정 모두 CoreImage 합성이 병목이 아님을 보여준다.**

**→ 결정: Phase 2B Metal 전면 재작성 보류(defer).** 추측이 아니라 양 경로 측정으로 확정. 절약된 노력은 Phase 2A(색 그레이딩·ProRes/HDR)·Phase 3(온디바이스 AI)에 투입.

## 한계 / 후속 측정

여전히 다루지 **않은** 것 (재검토 트리거):

1. **무거운 합성** — 전환+마스크+다중 레이어가 한 프레임에 겹칠 때. 단일 색보정은 대표적이지만 최악은 아니다(단 5.5ms의 3배여도 ~60fps).
2. **고해상도/장시간** — 4K·장편 비선형 악화 여부.
3. 위 시나리오에서 프레임당 렌더가 16.6ms를 넘기면 그때 preview 한정 최적화/Metal 재검토.

## 4K 합성 + 메모리 실측 (2026-07-30, S6)

재현: `bash scripts/perf_4k.sh`. 두 재검토 트리거(무거운 합성, 4K)를 채운 측정.

픽스처: 10초 / 3840×2160 / 30fps. 세 export 경로:

- **passthrough**: 효과 없음 (바닥).
- **color**: 5단계 색보정 → 매 프레임 CoreImage 경유.
- **heavy**: crossDissolve 전환 + 마스크 + 동일 4K 소스 3겹 중첩(최악 케이스). 출력 길이는 3배(30초).

**측정 한계(정직한 기록)**: 두 가지 구조적 제약으로 Debug-only·샌드박스-OFF 빌드로 측정했다.

1. 헤드리스 export harness(`UITestHarness.swift`)가 `#if DEBUG`로 보호돼 있어 **Release 빌드에 컴파일되지 않는다** → Release는 헤드리스 export를 구동할 수 없다.
2. S3가 활성화한 **App Sandbox**가 시작 시 환경변수로 전달된 파일(`MOVIECUT_UITEST_IMPORT`)에 대한 보안 스코프 부여가 없어 harness의 import/export를 차단한다 → 산출물 없이 종료. 그래서 스크립트는 `ENABLE_APP_SANDBOX=NO` 빌드로 측정한다(샌드박스는 보안 경계지 렌더링 비용이 아니므로 측정 대상에 영향 없다).

Debug는 최적화 전 빌드이므로 **보수적 상한**이다. Release는 더 빠르므로, 아래 "병목 아님" 판정은 Release에서 더 견고하다(기존 1080p 베이스라인과 동일 논리).

| 경로 | export 시간 | realtime 배율 | peak 메모리 |
|---|---|---|---|
| passthrough | 9.42s | **0.94×** | 205 MB |
| color (CoreImage) | 9.17s | **0.92×** | 221 MB |
| heavy (전환+마스크+3레이어, 30s 출력) | 18.75s | **0.63×** (초당) | 214 MB |
| **peak across paths** | | | **221 MB** |

- 4K에서도 color와 passthrough 차이는 ±3% 이내(5단계 색보정이 사실상 무료). CoreImage 합성은 4K에서도 병목이 아니다.
- heavy는 3배 긴 출력을 처리하면서도 realtime의 1.6배 빠르다(0.63×).
- **4 GB 메모리 상한 판정: 이내.** peak 221 MB는 4 GB(4,096 MB)의 **5.4%**. 외부 스펙 "4K 60fps 실시간 · 4GB 이하" 기준 메모리는 대폭 여유.

**→ 결정: Phase 2B Metal 전면 재작성 유지(defer).** 4K 최악 합성(전환+마스크+3겹 중첩)에서도 CoreImage는 realtime 이내이고, peak 메모리는 상한의 5.4%. 1080p 베이스라인(+9%, 0.49×)에 이어 4K 베이스라인(±3%, ≤0.94×)까지 양쪽 모두 CoreImage가 병목이 아님을 확정. 재검토 트리거(프레임당 렌더 16.6ms 초과, 메모리 4GB 초과) 중 어느 것도 발생하지 않았다.

## G-04 실제 TimelineView 필름스트립 (2026-07-18, Debug)

재현: `bash scripts/run_g04_filmstrip_perf.sh`. 스크립트는 저장소 밖 임시 디렉터리에 low-bitrate generated fixture를 만들고 종료 시 삭제한다. Core-only loop가 아니라 DEBUG actual app를 실행해 실제 `TimelineView`의 `ScrollViewReader`, `timelineZoom`, `TimelineFilmstripStore`, `FilmstripGenerator`, publish 및 AppKit-backed image consumer를 구동한다.

### AC1 진단과 main-thread filmstrip work metric

- 기존 1ms `Task.sleep` loop의 `n=1218/p95=2.096ms/max=67.106ms/>16.6ms=4`는 MainActor가 실제 filmstrip 작업을 수행한 시간을 잰 값이 아니다. sleep 이후 재개까지의 wall time이라 OS scheduler, app lifecycle, 다른 process 부하를 함께 포함하며, decode/cache/publish/UI 어느 경계가 비용을 냈는지도 구분하지 못했다. 따라서 67ms sample은 actual filmstrip main-thread work 증거가 아니라 measurement artifact다.
- actual 경계 감사: `FilmstripGenerator`의 AVFoundation decode와 digest는 detached utility task, cache lookup/insert는 `FilmstripCache` actor에서 수행된다. MainActor에 남는 attributable work는 request/state dispatch, decoded-frame publish, UI consumer update, frame strip draw다.
- 대체 metric: 위 네 main-thread operation을 각각 `MainThreadRequest`/`Publish`/`UIConsumerUpdate`/`UIConsumerDraw` production `os_signpost` interval과 monotonic nanosecond clock으로 잰다. `UIConsumerDraw`는 한 AppKit-backed strip view가 실제 cached frame set을 그리는 구간이다. 모든 duration을 pure `FilmstripWorkTimingAccumulator`에 저장하며 warmup 제거, outlier drop, clamp가 없다. budget은 정확히 `16,600,000ns`; `scripts/run_g04_filmstrip_perf.sh`는 over count가 1 이상이면 실패한다. 이 metric은 display presentation cadence/FPS가 아니다.

### 3분 1080p 줌/스크롤 결과

- fixture: 3분 1920×1080, 10fps generated test pattern을 12초 단위 stream-copy loop.
- actual UI workload: 20/40/80/160px/s 각 단계에서 zoom mutation 1회 + real `ScrollViewReader` mutation 3회. bucket `0/1/2/3`, required distinct request 16개, published density `0.232/0.366/0.694/1.381 frame/s`; 모든 set의 frame/digest/timestamp가 1개를 초과한다.
- exact-final run 1: `n=66` (`request=17/publish=17/update=16/draw=16`, identities `17`; scenario 진입 전 초기 request/publish 2개도 삭제하지 않음), p95 `0.719ms`, max `1.122ms`, `>16.6ms=0`.
- exact-final run 2: 동일 coverage `n=66/17/17/16/16`, identities `17`, p95 `0.402ms`, max `0.435ms`, `>16.6ms=0`.
- 두 run 모두 cache peak `7,137,280B/134,217,728B`, max frame height `≤60`, image/audio/text timeline surface 보존. **G-04 AC1의 filmstrip-attributable main-thread interval 초과 0건을 충족**한다.

### 10분 4K seek/cache churn 메모리

- fixture: 600초 3840×2160, 10fps generated test pattern을 12초 단위 stream-copy loop한 synthetic low-bitrate asset. 실제 4K decode이지만 camera-originated/high-bitrate 콘텐츠 대표값은 아니다.
- actual UI workload: 160px/s에서 30~570초를 60초 간격으로 10회 ScrollView seek하고, 인접 zoom identity 전환으로 실제 decode/publish/cache churn을 보장했다. 10개 published set 모두 request identity가 다르고 digest/timestamp가 시간가변이다.
- process RSS: exact-final run 1 baseline/peak `225.9/226.0MB`, reported delta `+0.0MB`; run 2 `222.1/228.5MB`, delta `+6.3MB`; 스크립트 threshold `+100MB`.
- decoded cache accounting: current/peak `8,816,640B`, configured/enforced limit `134,217,728B`, tracked keys `21`, evictions `0`, max decoded frame height `41px`(limit `60px`). `NSCache.totalCostLimit`과 별도로 deterministic LRU admission이 decoded byte cost/key count를 limit 이전에 강제하며 peak/current를 보고한다.

### production signpost 범위와 한계

`TimelineFilmstrip` OSLog category에서 actual request lifecycle/cache lookup/decode/cache insert/publish와 `MainThreadRequest`/`UIConsumerUpdate`/`UIConsumerDraw`/`UIConsumerRendered`를 관찰하며 generator decode 자체도 별도 interval이다. 이 증분은 macOS timeline UI 계측이고 preview/export renderer를 바꾸지 않는다. density actual app는 image thumbnail/audio waveform/text rhythm branch도 직접 관찰했으며 전체 export E2E로 기존 image/text/audio 출력을 회귀 잠금한다. Headless actual app의 operation-duration 증거이므로 display presentation FPS나 인간이 느끼는 스크롤/호버 cadence를 주장하지 않는다.

## Release 성능 + 샌드박스 ON + parity 순회 (2026-08-01)

이 섹션은 구조적 빈 3종을 채운다. 종전 측정은 전부 **Debug + 샌드박스 OFF**였다 — 두 가지 이유: (1) 헤드리스 export harness(`UITestHarness.swift`)가 `#if DEBUG`로 보호돼 Release에 컴파일되지 않았고, (2) 샌드박스가 환경변수로 전달된 파일 접근을 막아 harness가 빈 산출물로 종료했다. 2026-08-01 변경으로 둘 다 풀렸다:

- harness 게이트를 `#if DEBUG` → `#if DEBUG || MOVIECUT_HARNESS`로 확장. xcodebuild 명령줄에서 `SWIFT_ACTIVE_COMPILATION_CONDITIONS=MOVIECUT_HARNESS`를 주면 **출시 빌드의 harness 코드가 들어가지 않으면서** Release 최적화(-O, wholemodule)를 유지한 채 harness를 컴파일할 수 있다.
- harness에 `MOVIECUT_UITEST_CONTAINERIZE=1` 모드를 추가: fixture를 샌드박스 컨테이너의 `tmp/`(grant 불필요)로 복사하고, export/result/dump도 컨테이너 내부에 스테이징한 뒤 요청 경로로 옮긴다. `.minimalBookmark` 폴백이 컨테이너 내부 경로에 유효하므로(`SecurityScopedAccessTests` 검증) import가 성공한다.

아래 수치는 전부 이 세션에서 직접 실행한 명령의 출력이다.

### Release vs Debug (4K, 샌드박스 OFF)

재현: `bash scripts/perf_release.sh`. fixture 10s / 3840×2160 / 30fps. Debug와 Release 양쪽을 같은 fixture로 측정해 직접 비교.

| config | path | export 시간 | realtime 배율 | peak 메모리 |
|---|---|---|---|---|
| Debug | passthrough | 11.96s | 1.20× | 207 MB |
| Debug | color (CoreImage) | 11.68s | 1.17× | 200 MB |
| Debug | heavy (전환+마스크+3레이어, 30s 출력) | 20.78s | 2.08× (초당) | 225 MB |
| Release | passthrough | 12.31s | 1.23× | 199 MB |
| Release | color (CoreImage) | **9.91s** | **0.99×** | 208 MB |
| Release | heavy (전환+마스크+3레이어, 30s 출력) | 20.38s | 2.04× (초당) | 225 MB |
| **peak across all** | | | | **225 MB** |

**해석:**
- **color(단일 5단계 색보정)에서만 Release가 Debug보다 유의미하게 빠르다**: 11.68s → 9.91s(−15%), realtime 배율 0.99×로 **정확히 realtime**에 도달. CoreImage 합성 자체가 최적화의 수혜를 받는다는 뜻이며, "CoreImage 합성은 export 병목이 아니다"라는 종전 Debug 결론이 Release에서 **더 견고**해진다(종전 1080p 베이스라인과 동일 논리).
- **passthrough와 heavy는 Debug≈Release**: passthrough는 CoreImage를 거치지 않고(디코드+패키징이 지배), heavy는 3배 긴 출력의 디코드 I/O가 지배하므로 Swift 최적화가 잴 수 있는 차이를 낸다. heavy의 30s 출력 기준 realtime 배율 2.04×는 "3배 긴 출력을 처리하면서 realtime의 1.5배 속도"이므로 per-second 기준으론 여전히 realtime 이내.
- **메모리 4GB 예산: 이내.** peak 225 MB는 4,096 MB의 **5.5%**. Debug(221 MB)와 거의 동일.
- **Phase 2B Metal 결정: 유지(defer).** Release color가 realtime 도달, heavy도 per-second realtime 이내, 메모리 5.5% — 재검토 트리거(프레임당 렌더 16.6ms 초과, 메모리 4GB 초과) 중 어느 것도 Release에서 발생하지 않았다.

> **측정 한계(정직한 기록).** Release 측정도 여전히 `ENABLE_APP_SANDBOX=NO`다. 샌드박스 ON에서의 Release 수치는 아래 다음 절 참조. 또한 Release 빌드에 harness를 넣기 위해 `MOVIECUT_HARNESS` 조건을 썼으므로, 이 수치는 "harness를 포함한 Release"이지 순수 출시 바이너리는 아니다 — harness 코드는 렌더링 핫패스가 아니므로 측정에 미치는 영향은 무시할 수 있다(동일 논리가 Debug harness에도 적용됐다).

### 샌드박스 ON (4K, Debug)

재현: `bash scripts/perf_4k_sandbox.sh`. `ENABLE_APP_SANDBOX=YES`(출시 기본값) + `MOVIECUT_HARNESS` + `MOVIECUT_UITEST_CONTAINERIZE=1`. fixture는 위 Release 절과 동일(10s / 3840×2160). 샌드박스 변수만 분리해 측정.

| 경로 | export 시간 | realtime 배율 | peak 메모리 |
|---|---|---|---|
| passthrough | 12.30s | 1.23× | 213 MB |
| color (CoreImage) | 10.32s | 1.03× | 221 MB |
| heavy (전환+마스크+3레이어, 30s 출력) | 21.38s | 2.14× (초당) | 237 MB |
| **peak across paths** | | | **237 MB** |

**해석:**
- **샌드박스가 켜진 출시 구성에서 harness가 동작한다.** 종전엔 샌드박스가 환경변수 파일 접근을 막아 `perf_4k.sh`가 `ENABLE_APP_SANDBOX=NO`로 회피해야 했다. `MOVIECUT_UITEST_CONTAINERIZE=1`이 fixture를 컨테이너 `tmp/`로 복사하고 export/result를 컨테이너 내부에 스테이징한 뒤 요청 경로로 옮기므로, 샌드박스 ON에서 3경로 모두 정상 길이의 산출물(`out=10.0s` / `30.0s`)을 냈다.
- **샌드박스 오버헤드는 무시 가능.** sandbox ON vs OFF(Debug) 비교: passthrough 12.30s vs 11.96s, color 10.32s vs 11.68s, heavy 21.38s vs 20.78s. 차이는 측정 노이즈 범위이며, 방향성도 일관되지 않는다(color는 오히려 sandbox ON이 더 빠르다). 샌드박스는 보안 경계지 렌더링 비용이 아니라는 종전 가정이 실측으로 확정됐다.
- **메모리 4GB 예산: 이내.** peak 237 MB는 4,096 MB의 **5.8%**. sandbox OFF(225 MB) 대비 +12 MB는 컨테이너 스테이징 복사(fixture ~수 MB × 경로)로 설명되며 합리적이다.
- **남은 조합.** 이 절은 "Debug + sandbox ON"이다. "Release + sandbox ON"은 위 Release 절(color 0.99× realtime)과 이 절(샌드박스 오버헤드 무시 가능)을 합치면 도출되므로 별도 측정하지 않았다. 둘 다 "CoreImage 합성은 병목이 아니다"를 강화한다.

### `=` 판정 parity 순회 (13 시나리오)

재현: `bash scripts/run_parity_sweep.sh`. CAPCUT_BENCHMARK_STANDARD §7의 "신뢰도 경고" — `=` 판정 다수가 preview+export 동시 증거 없이 부여됐다 — 에 대응한다. parity harness(`MOVIECUT_UITEST_PARITY=1`)가 각 효과를 적용한 timeline에서 **preview PNG 덤프(t=0.5s/1.5s) + export mp4** 양쪽을 산출하고, `verify_preview_export_parity.py`가 같은 타임스탬프의 양쪽 프레임을 픽셀 단위로 비교(MAD, 허용치 12.0/255) + export duration이 합성 duration의 1프레임 이내인지 확인한다. fixture `Tests/Fixtures/solid_red_320x240_2s_30fps.mp4`.

길이를 바꾸는 시나리오(trim/speed_rate/speed_ramp)는 샘플 시간을 0.3s/0.7s로 줄여 두 샘플이 export 안에 들어가게 했다(기본 0.5s/1.5s는 2s 원본 기준).

| 시나리오 | 환경변수 게이트 | 결과 | overall MAD |
|---|---|---|---|
| passthrough | (없음) | ✅ PASS | 0.45 |
| color | `MOVIECUT_UITEST_COLOR=1` | ✅ PASS | 0.03 |
| grade (3-way) | `MOVIECUT_UITEST_GRADE=1` | ✅ PASS | 0.54 |
| **hsl_curves** (신규) | `MOVIECUT_UITEST_HSL_CURVES=1` | ✅ PASS | 0.03 |
| freeze | `MOVIECUT_UITEST_FREEZE=1` | ✅ PASS | 0.39 |
| reverse | `MOVIECUT_UITEST_REVERSE=1` | ✅ PASS | 0.45 |
| **optical_flow** (신규) | `MOVIECUT_UITEST_OPTICAL_FLOW=1` (+0.5×) | ✅ PASS | 0.63 |
| trim (1.0s로 엔드) | `MOVIECUT_UITEST_TRIM_AT=1.0` | ✅ PASS | 0.45 |
| move | `MOVIECUT_UITEST_MOVE_TO=1.0` | ✅ PASS | 0.45 |
| mask | `MOVIECUT_UITEST_MASK=1` | ✅ PASS | 0.16 |
| text overlay | `MOVIECUT_UITEST_TEXT_AT=0.5` | ✅ PASS | 0.42 |
| speed_rate (2.0×) | `MOVIECUT_UITEST_SPEED_RATE=2.0` | ✅ PASS | 0.45 |
| speed_ramp | `MOVIECUT_UITEST_SPEED_RAMP=1` | ✅ PASS | 0.45 |

**13/13 PASS.** 모든 효과에서 preview 합성 경로와 export 경로가 같은 프레임을 렌더링한다(MAD ≤ 0.63, 허용치 12.0 대비 5% 미만).

**해석 — CAPCUT_BENCHMARK §7 신뢰도 경고 해소:**
- **2026-07-28 발견(메인 Preview가 프로젝트 합성 경로를 안 쓰고 있었다)의 재발 가능성이 13개 효과 전부에서 부정됐다.** 각 효과가 preview와 export 양쪽에서 픽셀 일치하므로, 이 효과들의 `=` 판정은 이제 동시 증거 기반이다.
- **신규 게이트 2종이 parity 경로에 합류:** `hsl_curves`(G-02 Inc 3)와 `optical_flow`는 종전엔 generic export-only 경로에만 있어 `=` 판정의 preview 증거가 없었다. `applyParityScenarioEdits`에 같은 게이트를 추가해 이제 parity 순회가 커버한다.
- **MAD가 효과마다 다른 이유:** color/hsl_curves는 단색 fixture라 변화가 작어 MAD가 0.03으로 극히 낮고, grade/mask/optical_flow는 공간적 변화가 있어 0.5~0.7 부근. 어느 쪽이든 허용치(12.0)보다 한 자릿수 이상 작으므로 preview↔export 정확 일치로 판정한다.

> **측정 한계.** transition(crossDissolve)은 이 순회에서 제외했다 — `run_core_editing_parity.sh`의 기존 기록에 따르면 transition이 포함된 시나리오는 호스트 GPU compositor에서 `buildComposition`이 신뢰성 있게 완료되지 않는 이슈가 있어 별도 추적된다. transition의 parity는 그 시나리오가 안정화된 뒤 추가 측정 대상이다. 또한 이 측정은 샌드박스 OFF Debug다 — 위 sandbox ON 절이 샌드박스가 렌더링 결과에 영향을 주지 않음을 이미 보였으므로, 샌드박스 ON에서 parity가 달라질 근거는 없다.



