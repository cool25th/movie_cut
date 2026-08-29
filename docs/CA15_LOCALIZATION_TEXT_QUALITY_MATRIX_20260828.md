# CA-15 현지화·텍스트 품질 감사 매트릭스 (2026-08-28)

> 근거: 백로그 §0.5.1 CA-14/15 · `COMPETITIVE_ANALYSIS_20260822.md` Part 4.6.
> 방법: 코드 근거(파일:라인) + **실측 프로브**(`Tests/MovieCutCoreTests/MultilingualTextRenderTests.swift` 4종 —
> 실제 `TextOverlayPixelProcessor` 경로로 렌더해 잉크 커버리지 단언, 폰트 가용 가정이 아닌 픽셀 증거).
> 다국어 자막 강점 주장의 전제를 축별로 판정한다.

## 축별 판정

| # | 축 | 현황(근거) | 판정 |
|---|---|---|---|
| 1 | UI 문자열 ko/en | 양 카탈로그 en+ko 전량 + CI 키·번역값 이중 검사(CA-24, `verify_localization_keys.py` 차단) | ✅ 충족 |
| 2 | CJK 자막 렌더링 | CoreText 공유 경로(프리뷰=출력)가 폰트 캐스케이드로 한글 렌더 — **실측 프로브 PASS**(잉크 커버리지·라틴 대비 밴드) | ✅ 충족(실측) |
| 3 | Emoji·결합문자 | 🎬🎉 클립·NFD 분해 한글(가+◌̌) 렌더 — **실측 프로브 PASS**(커버리지) | ✅ 충족(실측) |
| 4 | RTL 자막 | 아랍어 "مرحبا بالعالم" CoreText 바이디 경로 렌더 — **실측 프로브 PASS**. 혼합 방향 정렬 세부는 별도 스펙 없이 CT 기본(자연 기준 방향) | ✅ 충족(실측)·혼합방향 세부는 관찰 |
| 5 | 줄바꿈(CJK 포함) | `CTFramesetterSuggestFrameSizeWithConstraints` 제한폭(`TextOverlayPixelProcessor.swift:156`) — 장문 CJK **실측 프로브 PASS**(잉크 증가=줄바꿈·캔버스 내) | ✅ 충족(실측) |
| 6 | 세로 텍스트 | 전역 검색 0건 — 기능 부재 | ➖ 범위 외(v1 비목표·기록) |
| 7 | 숫자·시간 locale | 타임코드 `String(format:"%02d:…")`·`%.0f%%`는 C-포맷(로케일 중립·결정적) — `PreviewPanel.swift:859`·257. 홈 화면 수정일 `DateFormatter`는 시스템 로케일 추종(사용자 대면 날짜의 올바른 현지화) — `HomeView.swift:487` | ✅ 충족 |
| 8 | 파일명 유니코드 | `lastPathComponent` 통과 저장(ProjectStore.swift:160 등) — 정규화 없음. macOS NFD 일관 환경에선 왕복 안전·NFC 혼입 파일은 별도 이름으로 공존(충돌 처리 없음) | ⚠ 관찰(결함 아님 — 교차 출처 파일명 혼용 시 기록용) |
| 9 | 비라틴 키보드 단축키 | SwiftUI `.keyboardShortcut("n", modifiers:.command)`(`MovieCutMacApp.swift:66`) — 라틴 자모 단축키는 가상 키코드로 매핑돼 한국어 등 비라틴 입력 소스에서 동작 | ✅ 충족(플랫폼 표준 동작) |
| 10 | 텍스트 측정(자막 폭·박스) | 제안 크기+제한폭 계산이 전부 CoreText(`TextOverlayPixelProcessor.swift:151-167`) — 문자폭 추정 자체 코드 없음(자체 계산 결함 여지 원천 차단) | ✅ 충족 |

## 신규 등록 결함

없음 — 4종 실측 프로브 전부 PASS, 코드 경로 점검에서 등급 올릴 결함 미발견. 축 6(세로 텍스트)은
기능 부재의 정직 기록이지 결함이 아니며, 축 8(파일명 정규화)은 관찰 항목으로 남긴다.

## 부산물

- `MultilingualTextRenderTests` 4종이 상시 게이트에 편입됨 — 다국어 렌더 회귀(폰트 캐스케이드
  깨짐·줄바꿈 변경·바이디 경로 수정)가 커밋 게이트에서 잡힌다. 커버리지 방식 단언이라 플랫폼
  폰트 세트 변화에 강하다(어떤 캐스케이드 폰트가 선택되든 잉크만 보면 됨).

## 결론

Part 4.6 감사 축 10종 중 **7종 충족(4종 실측)·1종 범위 외·2종 관찰(결함 아님)** — 신규 결함 0건.
"다국어 자막 강점" 주장의 텍스트 품질 전제는 현재 구조(CoreText 공유 경로 + 카탈로그 이중 검사)로
성립하며, 측정 증거가 이 문서에 고정됐다.
