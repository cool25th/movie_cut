# Mac ↔ iOS 플랫폼 파리티 매트릭스 (Phase 0.4)

> 작성일: 2026-06-24 / 결정: **Mac + iOS 동시 파리티**([로드맵](MOVIECUT_PRO_ROADMAP_20260622.md) §0).
> 목적: Core 기능별 양 플랫폼 배선 감사 → Phase 1에서 격차 해소. 코드 grep 기반 정적 감사(런타임 검증 아님).

## 매트릭스

| 기능 | Mac | iOS | 비고 |
|---|---|---|---|
| **색보정(밝기/대비/채도)** | ✅ shared `ColorCorrectionPixelProcessor` | ✅ shared (위임) | **2026-06-24 통일** |
| **warmth/tint** | ✅ `6500 - warmth*2000`(warmth+=따뜻) | ✅ shared (동일 방향) | **2026-06-24 P0 버그 수정** |
| **3-way 컬러 그레이딩 (Phase 2A)** | ✅ shared `ColorGradePixelProcessor` + 휠/스코프 UI | ✅ 렌더 shared (export+preview) | **2026-06-25 렌더 파리티**. iOS 조절 UI(휠/스코프)는 iOS-inspector 후속 |
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

## 핵심 발견 — 색보정 분기 (P0) — ✅ 2026-06-24 수정 완료

iOS가 색보정을 shared `ColorCorrectionPixelProcessor`로 위임하지 않고 **인라인 재구현**했었다(`IOSCustomVideoCompositor`+`PreviewView`). 결과: warmth/tint 방향이 Mac과 정반대(`6500 + warmth*1500` vs Core `6500 - warmth*2000`) = 같은 슬라이더가 iOS에서 거꾸로 동작하는 **가시 버그**, 그리고 export compositor는 warmth/tint를 아예 누락.

**수정**: iOS의 두 색보정 진입점(`IOSCustomVideoCompositor.apply(colorCorrection:to:)`, `PreviewView.apply(colorCorrection:to:)`)을 **shared `ColorCorrectionPixelProcessor.apply`에 위임**으로 교체. 이제 Mac/iOS·preview/export가 동일 처리(밝기/대비/채도 + 올바른 방향 warmth/tint). 골든(`ColorCorrectionGoldenTests`)이 공유 동작을 검증하고, `IOSColorCorrectionParityStaticContractTests`가 위임을 회귀로부터 잠근다.

**한계**: iOS 빌드는 이 머신에 iOS 26.5 미설치로 미실행. Core(`swift build`)·골든·심볼/임포트 정합은 통과. iOS 플랫폼 환경에서 실기기 색보정 육안 확인 잔여.

## 우선순위 격차 (Phase 1 해소 대상)

| P | 격차 | 근거 |
|---|---|---|
| ~~P0~~ ✅ | ~~색보정 shared 위임 + warmth/tint 방향 통일~~ **2026-06-24 완료** | 가시 버그(슬라이더 반대 동작), 분기 → 해소 |
| **P1** | 정지프레임·speed ramp·역재생 iOS 배선 | 사용자가 양 플랫폼에서 기대하는 편집 기능 |
| **P1** | 크로마키·전환 two-source·배경제거 shared 헬퍼 iOS | 렌더 파리티 |
| **P1** | 자동저장/크래시 복구 iOS | 안정성(Pro 핵심) — `ProjectStore` autosave는 Core라 iOS도 호출만 하면 됨 |
| P2 | 노이즈감소 apply 액션 iOS | |
| P2 | ProRes/GIF/스틸 export iOS | Pro 출력은 Mac 우선 허용 가능 |

## 검증 한계

- 정적 grep 기반(런타임 미검증). iOS는 이 머신에 iOS 26.5 플랫폼 미설치로 빌드/실행 검증 불가([로드맵](MOVIECUT_PRO_ROADMAP_20260622.md) 참조). Phase 1 iOS 작업은 iOS 플랫폼 환경에서 빌드·E2E 필요.
- "✅"는 코드 경로 존재를 뜻하며 DoD(preview+export 반영)와 다르다 — 각 항목 실측은 Mac 패턴(골든/E2E)을 iOS로 확장.
