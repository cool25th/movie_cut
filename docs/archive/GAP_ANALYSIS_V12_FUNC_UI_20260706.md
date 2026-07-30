# MovieCut vs CapCut 갭 분석 V12 — 실사용 동작 기준 재설정 — 2026-07-06

> **[보관 — 대체됨]** 이 문서는 `docs/archive/`에 있다. 현역이 아니며 갱신되지 않는다. 전체 문서 지도는 [docs/README.md](../README.md).
>
> - 상태: 2026-07-06 실사용 버그 기준 재설정(G-15 신설).
> - 지금 볼 곳: 최신 격차 분석은 `docs/GAP_ANALYSIS_V13_FUNC_UI_20260729.md`. 판정 기준은 `docs/CAPCUT_BENCHMARK_STANDARD.md`.

> 작성일: 2026-07-06 / 브랜치: `feat/core-backend-expansion` (기준 커밋: `89e3795`+)
> 기준선: V11 `docs/archive/GAP_ANALYSIS_V11_FUNC_UI_20260705.md` / 트리거: **사용자 실사용 버그 보고 — "사진을 넣으면 제대로 동작하지 않는다"**
> 원천 스펙: `docs/CAPCUT_SURPASS_SPEC_20260703.md` v1.6
> 이 감사의 실측: 헤드리스 재현 실험 1건(아래 §1), 코드 경로 추적, Mac 앱 빌드 PASS.

---

## 0. 한 줄 요약

사용자 보고를 재현했다: **사진(이미지) 파일은 import·타임라인 배치까지만 되고, preview에 아무것도 렌더되지 않으며 export는 "Cannot Open" 에러로 실패한다.** 이미지를 미디어 클립으로 재생/내보내는 파이프라인이 **애초에 존재하지 않는다**(이미지는 스티커 오버레이 경로만 구현됨). CapCut에서는 사진 편집이 가장 기본적인 동선(슬라이드쇼/밈/썸네일)이므로 이것은 **P0 실사용 격차**다. 이번 V12는 우선순위를 "검증된 백엔드 기능 축적"에서 **"사용자 기본 동선이 실제로 동작"** 기준으로 재설정한다: 신규 **G-15(이미지 클립 파이프라인)**가 모든 큐에 우선하고, E2E에 실사용 스모크 시나리오(사진+비디오 혼합)를 상설한다.

---

## 1. 버그 재현 증거 (2026-07-06 헤드리스 실측)

```
env MOVIECUT_UITEST=1 \
  MOVIECUT_UITEST_IMPORT=Tests/Fixtures/swatch_blue_64x64.png \
  MOVIECUT_UITEST_EXPORT=/tmp/photo_test.mp4 MOVIECUT_UITEST_RESULT=... MovieCutMac
→ 결과: UITEST_DONE clips=1 error=Cannot Open / export 파일 미생성
```

| 단계 | 동작 여부 | 근거 |
|---|---|---|
| 이미지 import → 라이브러리(썸네일/메타데이터) | ✅ 동작 | 기존 검증(F-06) + 재현에서 clips=1 |
| 타임라인 클립 생성 | ✅ 생성됨 | `EditorViewModel`이 `.image`를 `.video`처럼 클립 생성 허용(`:421,:4990`) |
| **preview 렌더** | ❌ **아무것도 안 보임** | `PlaybackEngine.swift:494` — `loadTracks(withMediaType: .video).first`만 소스로 삽입. PNG는 비디오 트랙 0개 → guard에서 **조용히 스킵**(에러도 없음) |
| **export** | ❌ **"Cannot Open" 실패** | `ExportEngine` 동일 구조. 이미지 전용 분기 grep 0건(스티커 `stickerImageURL`·GIF·정지프레임 export만 존재) |
| iOS | ❌ (추정 — 동일 구조) | iOS compositor/engine이 Mac 포팅 구조 |

**왜 지금까지 못 잡았나**: `run_e2e_export.sh`의 모든 시나리오가 **mp4/wav fixture만** 사용 — 이미지 fixture(`swatch_blue_64x64.png`)는 import 검증에만 쓰였고, 이미지→타임라인→렌더 경로는 한 번도 E2E에 오르지 않았다. **fixture 다양성 부채**로 명명하고 §4에서 규율화한다.

---

## 2. 판정 변화 (V11 대비)

- **신규 P0**: **G-15 이미지(사진) 클립 파이프라인** — 스펙 v1.6에 상세 명세 신설. **자동 선택 최우선**(U-08보다 앞 — 실사용 깨짐 > 인프라).
- **정정**: 과거 문서들의 "이미지 드래그앤드롭 ✅(실기기 검증)"는 **"라이브러리 진입까지만 ✅"로 강등** — 타임라인 이후 동작은 ❌였다. "Safari 이미지 드래그 → Video 1 클립 생성 성공"(F-01 기록)도 클립 생성까지만 사실이고 렌더는 깨져 있었다.
- **U-08 착수 확인(2026-07-06, 병행 세션)**: `scripts/ui_capture.sh`/`ui_regression.sh` + populated golden 1종 + 이빨 확인(negate FAIL→복원 PASS) — Inc 1~2 부분 완료, AC②(4표면 골든)·AC③(클릭수) [진행중]. **UI 트랙 5회 만에 첫 착수.**
- 나머지 G/U 현황은 V11과 동일(G-12 10/14, G-02 Inc 1~3 등).

## 3. CapCut 대비 — 이 격차의 무게

| CapCut | MovieCut 현재 |
|---|---|
| 사진 N장 드래그 → 즉시 슬라이드쇼, 기본 duration, 사진+영상 혼합 타임라인, 사진에 전환/효과/Ken Burns | 사진이 타임라인에 "보이지만" 재생·export 불가 — **사실상 영상 전용 에디터** |

사진 편집은 숏폼(밈/썸네일/슬라이드쇼)의 최빈 동선 중 하나로, 이 상태로는 W1(숏폼 제작) 워크플로우 자체가 사진 포함 시 완주 불가. **"능가" 이전에 "동작"이 먼저다.**

## 4. 방향성 재설정 — "동작하는 기준(Works-First)" 게이트

1. **W-스모크 상설**: `run_e2e_export.sh` 최상단에 **실사용 스모크 시나리오**(사진 1 + 비디오 1 + 텍스트 1 → 단일 타임라인 → export 성공 + 프레임 검사)를 추가한다. 이 스모크가 FAIL이면 모든 자동 세션은 신규 작업 금지·수리 우선(기존 "E2E FAIL 시" 규칙에 포함되나, 스모크는 **사용자 동선 형태**라는 점이 다름).
2. **fixture 다양성 규율**: 미디어 kind(video/audio/image)를 새로 소비하는 기능은 해당 kind fixture로 E2E 1건 의무(A7로 스펙 등재).
3. **게이트 순서 변경(v1.6)**: **G-15 → U-08 → G-02 Inc 5~6 → G-01 Inc 2~4**. G-15가 끝나야 사진 포함 W1이 성립한다.
4. **실기기 확인 상설**: 각 마일스톤 종료 시 워크플로우 수동 완주 규칙은 있었으나 실행된 적이 드물다 — G-15 완료 시 **사용자 실기기 확인 1회**(사진 드래그→재생→export)를 DoD에 명시하고 사용자에게 요청한다.

## 5. G-15 요약 (상세는 스펙 §3 G-15)

- **구현 방향(권고)**: `ImageVideoRenderService` — 이미지를 캔버스 해상도의 짧은 비디오 세그먼트로 변환(AVAssetWriter, EXIF 회전/다운스케일 처리, 캐시)해 기존 composition 경로에 소스로 삽입. **`ReverseRenderService`(역재생용 임시 asset 생성→삽입)와 동일한 검증된 패턴.** 소스가 진짜 비디오가 되므로 색보정/그레이드/키프레임/전환/HSL까지 기존 효과 체인이 무수정으로 적용된다.
- 대안(blank 트랙+compositor 직접 그리기)은 AVFoundation의 "소스 트랙 없으면 instruction 미호출" 제약과 효과 체인 재작업 때문에 비권고(스펙에 기록).
- AC 핵심: 재현 케이스가 그대로 회귀 테스트가 된다 — blue png → export 성공 + 중간 프레임 RGB≈(0,0,255).

## 6. 권장 실행 순서 (v1.6)

| 슬롯 | 작업 | 근거 |
|---|---|---|
| 1 | **G-15 Inc 1~3** (이미지 파이프라인 + W-스모크 E2E) | 실사용 P0 — 사용자 보고 재현됨 |
| 2 | G-15 Inc 4 (iOS) + **사용자 실기기 확인 요청** | 플랫폼 파리티 + Works-First DoD |
| 3 | U-08 잔여(AC② 4표면 골든·AC③ 클릭수) | Inc 1~2는 2026-07-06 착수됨 — 마감만 남음 |
| 4 | G-02 Inc 5~6 커브/HSL 편집기 UI → W5 완주 | 첫 체감 능가 |
| 5 | G-01 Inc 2~4 캡션 | wordTimings 상환 |
| 병행 | G-12 #11a/#12a fixture, #13/#14 수동 절차 | 기존 유지 |

## 7. 실사 증거 요약

- 재현: §1 헤드리스 실행 로그(clips=1, error=Cannot Open, export 미생성).
- 코드: `PlaybackEngine.swift:494`(video 트랙만), `ExportEngine` 이미지 분기 grep 0건, `MediaImporter.swift:38-39`(.image 분류는 존재), `EditorViewModel:421`(이미지 클립 생성 허용).
- E2E fixture 전수: mp4 5종/wav 4종/png 1종(import 전용) — 이미지 렌더 경로 검증 0건.
- Mac 앱 빌드 PASS (재현용 빌드).
