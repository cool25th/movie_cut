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
