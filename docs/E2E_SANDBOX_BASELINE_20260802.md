# MovieCut E2E 샌드박스 ON 베이스라인

> 측정일: 2026-08-02 / 재현: `bash scripts/run_e2e_export_sandbox.sh` / 빌드: **Debug + ENABLE_APP_SANDBOX=YES + MOVIECUT_HARNESS**
> 목적: 기존 `run_e2e_export.sh`(27개 섹션, 수십 기능 G-ID)을 **출하 구성(샌드박스 ON)에서 처음으로 돌려**, 샌드박스가 켜진 출하 빌드에서 전 기능이 동작하는지 확인한다. 종전 이 스크립트는 샌드박스 OFF에서만 돌았다.

## 결과

```
33 PASS  ·  1 SKIP  ·  0 FAIL  →  E2E check OK
```

샌드박스 ON(출하 기본값)에서 33개 기능 섹션이 전부 정상 동작한다. 실패 0건.

## 측정 방법

`scripts/run_e2e_export_sandbox.sh`는 `run_e2e_export.sh`를 복제해:
1. 빌드를 `ENABLE_APP_SANDBOX=YES`(출하 기본값) + `MOVIECUT_HARNESS`로 명시 (2026-08-01 추가한 harness 게이트 확장 덕분).
2. 37개 harness 호출부에 전부 `MOVIECUT_UITEST_CONTAINERIZE=1` 추가 — fixture를 샌드박스 컨테이너 `tmp/`(grant 불필요)로 복사하고, export/result도 컨테이너 내부에 스테이징.
3. 산출물 검증 시 requested 경로에 파일이 없으면 `container_artifacts=` 상태 필드에서 컨테이너 스테이징 경로를 폴백으로 찾음 (2026-08-02 추가한 harness 보고).

## 통과한 33개 섹션 (기능별)

| 영역 | 섹션 | 결과 |
|---|---|---|
| G-04 filmstrip | generator/cache (4프레임, cache hit/miss/insert) | ✅ |
| G-04 Inc 3-4 | TimelineView consumer (32프레임, hover 120×68) | ✅ |
| G-16 | timeline scrub (requested=playhead=playback=1.250) | ✅ |
| G-17 | clipboard E2E (copy/paste 2, ffprobe 14s) | ✅ |
| G-15 | image clip / mixed / warm-graded | ✅ (3종) |
| 기본 | import→export (duration 2.0s) | ✅ |
| Freeze | export 4.0s (baseline 2.0s) | ✅ |
| Optical-flow | slow motion 8.0s 120fps 960프레임 | ✅ |
| 텍스트 애니메이션 | 13 프리셋 | ✅ |
| 타이틀 템플릿 | 14 프리셋 | ✅ |
| 노이즈 감소 | app-context + SNR 개선 5.17dB | ✅ (2종) |
| EQ | bassBoost vs trebleBoost 스펙트럼 분기 | ✅ |
| 오디오 추출 | 유효 오디오 스트림 | ✅ |
| 챕터 마커 | 메타데이터 | ✅ |
| 덕킹 | BGM 12.05dB 감소 | ✅ |
| 플랫폼 프리셋 | TikTok/Reels/Shorts/Standard/Post 5종 | ✅ |
| 색보정 | grade / G-02 HSL·curve / scope (luma 5184) | ✅ (3종) |
| ProRes / HDR | master export | ✅ (2종) |
| AutoWB/Levels/Enhance | 보정 게인 | ✅ (3종) |
| G-18 카드 에디터 | save/reload (5페이지, undo/redo) | ✅ |
| G-19 카드 템플릿 | master style (builtins=10) | ✅ |

## SKIP 1개 (한계로 기록)

**크래시 복구 autosave** — `recovery.moviecut`는 harness 종료 경로(`flushAutosave()`)에서 쓰이고, 곧이어 `willTerminate` 핸들러가 clear 한다. 샌드박스 OFF 원본 스크립트의 PASS는 flush→clear 사이의 타이밍 경쟁을 폴링이 잡은 것이라, 샌드박스에서 안정적으로 재현이 어렵다. SIGKILL로 terminate를 우회하면 `flushAutosave()` 자체가 안 불려 파일이 안 생긴다.
- **복구 시맨틱 자체는 검증됨**: `AutosaveRecoveryTests`(단위, ProjectStore actor 수준)가 save/clear/survive-crash를 커버.
- **E2E 강제 kill → 재시작 → 복구 제안 표시** 게이트는 B-U7 작업으로, UI 식별자 + 게이트 우회 + XCUITest가 필요해 별도 진행 중.

## 과정에서 발견·수정한 인프라 결함 1건

첫 실행에서 G-04 Inc 3-4 섹션이 `error=timeline filmstrip harness failed: TimelineView did not issue a visible filmstrip request`로 실패했다. 원인은 **harness 게이트 불일치**: 2026-08-01에 `TimelineFilmstripDebugProbe` *클래스 정의* 게이트를 `#if DEBUG || MOVIECUT_HARNESS`로 넓혔지만, store 메서드 내부의 프로브 *호출부*(24곳)는 여전히 `#if DEBUG`로 보호돼 `MOVIECUT_HARNESS` 빌드에서 제외됐기 때문이다. 프로브가 정의돼도 아무도 `recordRequest`를 호출하지 않아 `hasVisibleRequest`가 항상 false.
- **수정**: `TimelineFilmstripStore.swift`의 24개 호출부 게이트를 전부 `#if DEBUG || MOVIECUT_HARNESS`로 넓힘. 수정 후 섹션이 `timeline_filmstrip_frames=32 requested_count=32 hover_visible=1`로 통과.
- **검증**: `swift test` 1139/0 회귀 없음.

이 결함은 sandbox 고유가 아니라 `MOVIECUT_HARNESS` 컴파일 조건을 처음 도입하면서 프로브 호출부까지 넓히지 않은 누락이었다. 색다른 빌드 구성(Release/sandbox)으로 넓은 검증을 돌려야 이런 게이트 불일치가 드러난다.

## 한계

1. **Debug 빌드.** Release 빌드에서의 E2E는 `perf_release.sh`가 성능 측정을 했고, 정확성은 동일 렌더링 코드 경로를 쓰므로 별도 측정하지 않았다.
2. **단일 클립 fixture.** 다중 클립 타임라인에서의 샌드박스 동작은 fuzz 게이트가 부분적으로 커버(55개 시나리오).
3. **autosave SKIP** (위).
4. **CONTAINERIZE 보고 인프라가 실제로 스테이징 경로를 보고한 케이스는 이번 실행에선 관찰되지 않았다** — 이 환경에선 앱 관점의 `NSHomeDirectory()`가 `/var/folders`를 컨테이너로 판정해 bypass 분기가 켜진 것으로 보인다. 다른 macOS 구성/볼륨에선 컨테이너 스테이징이 활성화될 수 있으며, 그때 `container_artifacts=` 필드와 stderr `MOVIECUT_CONTAINER_RESULT=` 폴백이 동작한다.
