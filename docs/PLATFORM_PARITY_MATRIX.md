# Mac ↔ iOS 플랫폼 파리티 매트릭스 (Phase 0.4)

> 작성일: 2026-06-24 / 결정: **Mac + iOS 동시 파리티**([로드맵](MOVIECUT_PRO_ROADMAP_20260622.md) §0).
> 목적: Core 기능별 양 플랫폼 배선 감사 → Phase 1에서 격차 해소. 코드 grep 기반 정적 감사(런타임 검증 아님).

## 매트릭스

| 기능 | Mac | iOS | 비고 |
|---|---|---|---|
| **색보정(밝기/대비/채도)** | ✅ shared `ColorCorrectionPixelProcessor` | ⚠️ **인라인 재구현** | iOS가 shared 미사용 → 분기 위험 |
| **warmth/tint** | ✅ `6500 - warmth*2000`(warmth+=따뜻) | ⚠️ `6500 + warmth*1500`(**반대 방향·다른 스케일**) | **방향 정반대 = 가시 버그** |
| 필터/LUT (VisualEffect) | ✅ | ✅ shared | |
| 마스킹 | ✅ | ✅ shared | |
| 텍스트 burn-in | ✅ | ✅ shared | |
| 캔버스 배경 | ✅ | ✅ shared | |
| 오디오 덕킹 | ✅ | ✅ | |
| EQ (볼륨근사) | ✅ | ✅ | 양쪽 다 실 EQ 아님(백로그 ❌) |
| 노이즈감소 배선 | ✅ | ✅ | |
| 크로마키 | ✅ shared `ChromaKeyPixelProcessor` | ❌ | iOS 미배선 |
| 전환 two-source | ✅ `TransitionPixelProcessor` | ❌ | iOS 미배선 |
| 배경제거 Vision | ✅ shared 합성 헬퍼 | ⚠️ Vision은 있으나 inline 합성 | shared `PersonSegmentationCompositor` 미사용 |
| **정지프레임** | ✅ | ❌ | iOS export에 freeze 없음 |
| **speed ramp** | ✅ | ❌ | iOS 미배선 |
| **역재생** | ✅ | ❌ | iOS 미배선 |
| 노이즈감소 apply 액션 | ✅ | ❌ | iOS에 destructive denoise 없음 |
| **자동저장/크래시 복구** | ✅ (0.6) | ❌ | Mac만 배선됨 |
| ProRes export | ✅ | ❌ | Pro 출력, Mac 우선 가능 |
| GIF / 스틸프레임 export | ✅ | ❌ | |

## 핵심 발견 — 색보정 분기 (P0)

iOS는 색보정을 shared `ColorCorrectionPixelProcessor`로 위임하지 않고 **인라인 재구현**한다(`IOSCustomVideoCompositor` + `PreviewView`). 그 결과:

- **warmth/tint 방향이 Mac과 정반대** — Core(`6500 - warmth*2000`, warmth+ = 따뜻함) vs iOS(`6500 + warmth*1500`, warmth+ = 차가움). 같은 슬라이더가 두 플랫폼에서 반대로 동작 = **가시 버그**.
- 2026-06-23 Core warmth/tint 구현은 **Mac에만 자동 반영**(shared processor 경유). iOS는 별도 인라인이라 갱신 안 됨.

**→ 권장(Phase 1)**: iOS compositor/preview가 shared Core 프로세서(`ColorCorrectionPixelProcessor` 등)에 위임하도록 통일. "공유 픽셀 프로세서 패턴"(세션 핸드오프 §4 규칙)을 iOS에도 강제.

## 우선순위 격차 (Phase 1 해소 대상)

| P | 격차 | 근거 |
|---|---|---|
| **P0** | 색보정 shared 위임 + warmth/tint 방향 통일 | 가시 버그(슬라이더 반대 동작), 분기 |
| **P1** | 정지프레임·speed ramp·역재생 iOS 배선 | 사용자가 양 플랫폼에서 기대하는 편집 기능 |
| **P1** | 크로마키·전환 two-source·배경제거 shared 헬퍼 iOS | 렌더 파리티 |
| **P1** | 자동저장/크래시 복구 iOS | 안정성(Pro 핵심) — `ProjectStore` autosave는 Core라 iOS도 호출만 하면 됨 |
| P2 | 노이즈감소 apply 액션 iOS | |
| P2 | ProRes/GIF/스틸 export iOS | Pro 출력은 Mac 우선 허용 가능 |

## 검증 한계

- 정적 grep 기반(런타임 미검증). iOS는 이 머신에 iOS 26.5 플랫폼 미설치로 빌드/실행 검증 불가([로드맵](MOVIECUT_PRO_ROADMAP_20260622.md) 참조). Phase 1 iOS 작업은 iOS 플랫폼 환경에서 빌드·E2E 필요.
- "✅"는 코드 경로 존재를 뜻하며 DoD(preview+export 반영)와 다르다 — 각 항목 실측은 Mac 패턴(골든/E2E)을 iOS로 확장.
