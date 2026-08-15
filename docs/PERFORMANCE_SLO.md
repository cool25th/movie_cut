# MovieCut 성능 SLO (v1, SDR Rec.709 Mac 단일)

> 기준 측정: `docs/PERF_BASELINE_20260622.md`. 이 문서는 측정을 **강제 가능한 목표**로 고정한다.
> 게이트 위치가 표시된 항목은 `scripts/perf_*.sh` 또는 nightly에서 자동 위반 탐지 대상이다.
> 위반 시 어느 값이 문제인지 바로 알 수 있도록 목표와 현재 측정치를 함께 둔다.

## 측정 등급 (기준 장비)
v1 출시 검증을 위한 최소 두 등급. 절대값은 장비에 따라 조정되나 **게이트 자체의 존재**는 불변.
- **주력 Apple Silicon Mac** — Release 빌드 측정 기준 (`perf_release.sh`).
- **최소 지원 사양 Mac** — Debug 빌드 회귀 기준 (`perf_4k.sh`).
- **CI nightly 러너 (macos-15 VM)** — 정밀 측정 아님(**coarse signal**). GPU 없는 VM이라
  절대값 게이트 대상이 아니라 회귀 *방향* 탐지 전용. 러너 수치는 위 두 장비 열과
  **교환 비교 금지**.

---

## SLO 표

| 지표 | v1 목표 | 현재 측정치(기준 장비) | 게이트 | 위반 시 의미 |
|---|---|---|---|---|
| **메모리 피크** | 4 GB 미만 | 4K Debug 237 MB (5.8%) / Release 225 MB | `perf_4k.sh` `MEM_LIMIT_BYTES=4GB` | 메모리 누수 또는 4K 처리 비정상 |
| **4K export 실시간 배수** | Release ≤ 1.2× / Debug ≤ 1.5× | Release color 0.99× / Debug color 0.92× | `perf_release.sh`·`perf_4k.sh` `REALTIME_LIMIT` (신규) | 인코딩 파이프라인 회귀 (CoreImage 병목 의심 지점) |
| **1080p 단일트랙 프리뷰** | 30 fps 유지 | 5.51 ms/frame → 182 fps (33% of 60fps 예산) | signpost `playback.buildComposition` + 수동 측정 | 프리뷰 렌더 회귀 |
| **4K 프리뷰** | 자동 프록시 전환 또는 드롭률 < 5% | 단계 강등: `.fair` 프리뷰 1/2 클램프 → `.serious`+ 프록시 (`effectivePreviewQuality`) | `ThermalProxyDowngradeTests`(정책) + signpost | 열 부하 시 프리뷰 끊김 방어 회귀 |
| **타임라인 seek 응답** | 중앙값 100 ms 이하 | signpost `playback.seek` 확보 — 실측치는 Instruments 세션에서 수집 예정 | 추후 게이트 | seek 지연 회귀 |
| **10분 프로젝트 열기** | 3초 이하 | signpost `import.openProject` 확보 — 실측치는 Instruments 세션에서 수집 예정 | 추후 게이트 | 프로젝트 로드/마이그레이션 회귀 |
| **자동 저장** | 편집 후 수초 내 | edit-driven `scheduleAutosave` 매 편집 (비동기) | `AutosaveRecoveryTests` | 복구 가능성 회귀 |
| **강제 종료 복구** | 최근 자동 저장 시점까지 | `recovery.moviecut` 재로드 | `run_recovery_gate.sh` | 크래시 후 작업 유실 |
| **export 실패** | 사용자에게 원인·재시도 안내 | `FileOperationError.classify` → userMessage | `FileOperationErrorTests` | 불투명 에러 회귀 |

## 게이트 상태 요약
- **현재 강제 중(자동)**: 메모리 4GB (`perf_4k.sh`), autosave/복구(`AutosaveRecoveryTests`·`run_recovery_gate.sh`), export 에러 분류(`FileOperationErrorTests`), thermal 프록시 정책(`ThermalProxyDowngradeTests`).
- **이번 주 추가**: 4K export 실시간 배수 게이트(`REALTIME_LIMIT` in `perf_4k.sh`·`perf_release.sh`·`perf_baseline.sh`), thermal `.fair` 프리뷰 품질 클램프(`effectivePreviewQuality`, `ThermalProxyDowngradeTests`).
- **signpost 기반(수동 Instruments)**: `export.preset`, `playback.buildComposition`, `playback.seek`, `import.openProject`, `proxy.generate`, `storage.migrate`(Core), filmstrip. 실측치 수집 후 게이트화.

## 러너 베이스라인 (coarse signal, nightly)
2026-08-14 nightly(macos-15 VM, Xcode 26.3, 완화 한계 4× 봉투) 첫 전체 그린 시점:
- 메모리 피크: **165 MB** (4 GB 예산의 4%)
- 4K export: passthrough **1.18×** / color **1.57×** / heavy **2.50×** — 러너 봉투(4×) 내
- 의미: 러너에서 이 값들이 급증(예: 2× 악화)하면 실하드웨어 점검 트리거. 봉투는
  `MOVIECUT_PERF_REALTIME_LIMIT_DEBUG`로 nightly에서만 완화 — 실하드웨어 SLO(1.5×/1.2×)는 불변.

## Metal 재평가 트리거 (유지)
Phase 2B Metal 재작성은 **연기**. 재평가 조건(둘 중 하나 발생 시):
1. 프레임당 렌더 > 16.6 ms (현재 5.51 ms)
2. 메모리 > 4 GB (현재 237 MB)

둘 다 미발생. 근거는 `docs/PERF_BASELINE_20260622.md` 참조.

## 관측성 (OSLog signpost)
`AppLog.Signpost`가 각 카테고리별 `OSSignposter`를 노출. Instruments에서:
- `export.preset` — 프리셋 export 전 구간(prepare→encode→finalize)
- `playback.buildComposition` — 프리뷰 합성 빌드
- `playback.seek` — seek 요청 (요청-기반; 렌더 완료 관찰 아님)
- `import.openProject` — 프로젝트 열기 (decode+migrate+validate+세션 교체)
- `proxy.generate` — 프록시 인코딩 패스
- `storage.migrate` — 스키마 마이그레이션 스테핑 (Core측 signposter)
- filmstrip — 기존 `TimelineFilmstripInstrumentation`

MetricKit은 **도입하지 않음** — 로컬 우선 프라이버시 포지셔닝(`AppLog.swift` 정책). 관측성은 OSLog signpost + shell 측정으로 충당.
