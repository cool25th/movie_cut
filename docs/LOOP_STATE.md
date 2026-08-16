상태: RUN
현재 증분: 완료 = **프리뷰 색공간 발산 수정**(G-29 전도부, 2026-08-17 세션) — AVPlayer 디코드 ICC 태그("Composite NTSC")로 컴포지터 프리뷰에만 색조 회전(레드 (254,0,0)→(247,36,0), MAD 10.25)이 발생하던 것을 `RenderColorConfiguration.sourceImage(from:)`로 양쪽 컴포지터(Mac·iOS)의 소스 해석을 작업 공간에 고정해 폐쇄. 실증: 파리티 `crop_rect_video` 신설 MAD **0.50 PASS** + 전체 14/14 무회귀 + verify_gate 1,155 tests PASS. 다음 = **EXECUTION_PLAN §3 Inc 2(EditorViewModel 분해 1호 경계 — timeline editing)**.
이전 완료: 색공간 수정 직전 = G-23 Inc 2 전체(2026-08-16 세션 2, 커밋 b4de271·73f653f — 게이트 1,153 tests, 파리티 13/13, crop_rect MAD 0.70).
마지막 커밋: c2c2341
갱신: 2026-08-17 02:47
