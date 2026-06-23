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

**→ 결정: Phase 2B Metal 전면 재작성 보류(defer).** 측정이 병목을 증명하지 못했으므로, 조건부 Metal은 착수하지 않는다. 절약된 노력은 Phase 2A(색 그레이딩·ProRes/HDR)·Phase 3(온디바이스 AI)에 투입.

## 한계 / 후속 측정

이 베이스라인이 다루지 **않은** 것 (Metal 결정을 뒤집을 수 있는 잠재 요인):

1. **실시간 preview(60fps 스크러빙/재생)** — export(오프라인)와 다른 경로(`PlaybackEngine`). 다중 효과 레이어 preview가 끊기면 preview 한정 최적화가 필요할 수 있다. **다음 측정 대상**.
2. **무거운 합성** — 전환+마스크+다중 레이어가 한 프레임에 겹칠 때. 색보정 단일 효과는 대표적이지만 최악은 아니다.
3. **고해상도/장시간** — 4K·장편에서 비선형 악화 여부.

후속: preview fps 측정 하니스 + 4K/heavy-composite 시나리오 추가.
