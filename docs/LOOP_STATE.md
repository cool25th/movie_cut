상태: RUN
현재 증분: 완료 = **CA 소형~중형 4건 + 루프 병렬 3건(2026-08-27)** — 병렬 세션: CA-01(오프라인 차단·캡처 — sandbox-exec 네트워크 거부 하 E2E 완주·소켓 0개·MC-02 ②③✅)·ENOSPC fail-closed 저장(49b7f87)·ui_regression 무음 PASS 폐쇄. 직렬 세션: **CA-08**(iOS 자막 스타일 6종 — Core SubtitleStylePresets 원탭 적용·인스펙터 칩·7ca8949)·**CA-17**(iOS 자막 export SRT/VTT — SubtitleDocument 공유·confirmationDialog→ShareLink·b03c62b)·**CA-19**(iOS 타임라인 스냅+가이드라인 — Mac 패리티·14pt 반경·fa11902)·**CA-22 1차**(프록시 자동 생성 — PlaybackSettings.autoGenerateProxyOnImport + 백그라운드 Task·a789b58). 부수: Mac trim snappedTime 빌드 오류 수정·iOS 커브 편집 UI(5e5e36b)·후속 관찰 2건 상환(6499efc). 게이트 5/5(Core 1,417).
다음 증분(우선순위): **CA-12**(경쟁사 A/B 벤치마크 하니스 — PSNR/SSIM+블라인드·중형) → CA-22 2차(프록시 설정 UI·취소·재개) → CA-14/15(소형). v1.6 체인·§1.12 리뷰 파생·후속 관찰 전부 소진. **대기(사용자)**: G-27 실기기 2종(잠금 해제)·MACUI-01+U-08 회귀 실측(TCC 접근성/재부팅)·PARITY-TOL-01(승인).
**기존 결함 기록**: 자체 측정 게이트 5/5(1,417)·Mac 유닛 48/48·iOS 48/48. 실기기 검증 미실행. **병렬 세션 경합 주의**: pbxproj 손상 2회·LOOP_STATE 덮어쓰기 1회·중단 회차 WIP 2회(프로토콜 0 해결·LI-003) — 커밋 직전 git status/diff --stat 확인 유지.
**범위 외 발견(후속 관찰)**: ui_regression 골든 의도 드리프트(AX 복구 시 갱신).
대기 결정 사항: **PARITY-TOL-01**(허용치 vs 픽스처 ≥720p 재생성 — 권고 (a))·G-27 실기기 2종 연결+잠금 해제·MACUI-01+U-08 회귀 실측(TCC 접근성/재부팅)·CA-07 가격(사용자 전용)·CA-11·CA-13·CA-16(P2).
마지막 커밋: 7ca8949
갱신: 2026-08-27 14:30
