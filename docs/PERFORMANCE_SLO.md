# MovieCut 성능 SLO (v1, SDR Rec.709 Mac 단일)

> 기준 측정: `docs/PERF_BASELINE_20260622.md`. 이 문서는 측정을 **강제 가능한 목표**로 고정한다.
> 게이트 위치가 표시된 항목은 `scripts/perf_*.sh` 또는 nightly에서 자동 위반 탐지 대상이다.
> 위반 시 어느 값이 문제인지 바로 알 수 있도록 목표와 현재 측정치를 함께 둔다.

## 측정 등급 (기준 장비)
v1 출시 검증을 위한 최소 두 등급. 절대값은 장비에 따라 조정되나 **게이트 자체의 존재**는 불변.
- **주력 Apple Silicon Mac** — Release 빌드 측정 기준 (`perf_release.sh`).
- **최소 지원 사양 Mac** — Debug 빌드 회귀 기준 (`perf_4k.sh`).

---

## SLO 표

| 지표 | v1 목표 | 현재 측정치(기준 장비) | 게이트 | 위반 시 의미 |
|---|---|---|---|---|
| **메모리 피크** | 4 GB 미만 | 4K Debug 237 MB (5.8%) / Release 225 MB | `perf_4k.sh` `MEM_LIMIT_BYTES=4GB` | 메모리 누수 또는 4K 처리 비정상 |
| **4K export 실시간 배수** | Release ≤ 1.2× / Debug ≤ 1.5× | Release color 0.99× / Debug color 0.92× | `perf_release.sh`·`perf_4k.sh` `REALTIME_LIMIT` (신규) | 인코딩 파이프라인 회귀 (CoreImage 병목 의심 지점) |
| **1080p 단일트랙 프리뷰** | 30 fps 유지 | 5.51 ms/frame → 182 fps (33% of 60fps 예산) | signpost `playback.buildComposition` + 수동 측정 | 프리뷰 렌더 회귀 |
| **4K 프리뷰** | 자동 프록시 전환 또는 드롭률 < 5% | thermalState `.serious`/`.critical` 시 `autoProxyDowngrade` | `ThermalProxyDowngradeTests`(정책) + signpost | 열 부하 시 프리뷰 끊김 방어 회귀 |
| **타임라인 seek 응답** | 중앙값 100 ms 이하 | (아직 미측정 — signpost `playback.buildComposition` 후 측정 예정) | 추후 게이트 | seek 지연 회귀 |
| **10분 프로젝트 열기** | 3초 이하 | (아직 미측정 — signpost `import.openProject` 후 측정 예정) | 추후 게이트 | 프로젝트 로드/마이그레이션 회귀 |
| **자동 저장** | 편집 후 수초 내 | edit-driven `scheduleAutosave` 매 편집 (비동기) | `AutosaveRecoveryTests` | 복구 가능성 회귀 |
| **강제 종료 복구** | 최근 자동 저장 시점까지 | `recovery.moviecut` 재로드 | `run_recovery_gate.sh` | 크래시 후 작업 유실 |
| **export 실패** | 사용자에게 원인·재시도 안내 | `FileOperationError.classify` → userMessage | `FileOperationErrorTests` | 불투명 에러 회귀 |

## 게이트 상태 요약
- **현재 강제 중(자동)**: 메모리 4GB (`perf_4k.sh`), autosave/복구(`AutosaveRecoveryTests`·`run_recovery_gate.sh`), export 에러 분류(`FileOperationErrorTests`), thermal 프록시 정책(`ThermalProxyDowngradeTests`).
- **이번 주 추가**: 4K export 실시간 배수 게이트(`REALTIME_LIMIT` in `perf_4k.sh`·`perf_release.sh`·`perf_baseline.sh`).
- **signpost 기반(수동 Instruments)**: `export.preset`, `playback.buildComposition`. seek/열기/마이그레이션은 signpost 추가 후 측정→게이트화 예정.

## Metal 재평가 트리거 (유지)
Phase 2B Metal 재작성은 **연기**. 재평가 조건(둘 중 하나 발생 시):
1. 프레임당 렌더 > 16.6 ms (현재 5.51 ms)
2. 메모리 > 4 GB (현재 237 MB)

둘 다 미발생. 근거는 `docs/PERF_BASELINE_20260622.md` 참조.

## 관측성 (OSLog signpost)
`AppLog.Signpost`가 각 카테고리별 `OSSignposter`를 노출. Instruments에서:
- `export.preset` — 프리셋 export 전 구간(prepare→encode→finalize)
- `playback.buildComposition` — 프리뷰 합성 빌드
- filmstrip — 기존 `TimelineFilmstripInstrumentation`

MetricKit은 **도입하지 않음** — 로컬 우선 프라이버시 포지셔닝(`AppLog.swift` 정책). 관측성은 OSLog signpost + shell 측정으로 충당.
