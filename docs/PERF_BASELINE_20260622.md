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
