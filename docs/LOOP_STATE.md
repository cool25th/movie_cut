상태: RUN
현재 증분: 다음 = **프리뷰 색공간 발산 수정**(사용자 결정 A 채택, 2026-08-16). 상세 명세·증거·DoD는 docs/SESSION_HANDOFF_CURRENT.md 세션 2의 "발견·미수정 결함" 항목 참조. 요약: untagged BT.601 SD 비디오가 프리뷰 커스텀 컴포지터 경로에서 색조 회전(레드 (254,0,0) → 프리뷰 (247,36,0), MAD ≈ 10.25). 매트릭스(601/709) 수준 조사 필요 — `AVPlayerItemVideoOutput`에 sRGB 태그 강제 시도는 조합 행업으로 폐기 전례(§7 함정 참조). **완료 판정 = 스크립트의 비디오판 크롭 파리티 시나리오 재활성화 후 PASS + 기존 13개 시나리오 무회귀 + verify_gate 4단계 PASS.**
이전 완료: Inc 0/Inc 1(G-23 Inc 2 전체) 2026-08-16 세션 2 커밋(b4de271, 73f653f — 게이트 1,153 tests, 파리티 13/13, crop_rect MAD 0.70). 색공간 수정 이후 예정: EXECUTION_PLAN §3 Inc 2(EditorViewModel 분해) → Inc 3(G-02 Inc5 HSL).
마지막 커밋: cac2416
갱신: 2026-08-16 23:40
