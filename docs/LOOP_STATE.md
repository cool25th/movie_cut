상태: RUN
현재 증분: 완료 = **BUG-07 해결 — 회전 메타데이터 3경로 평행 수정** — 비대칭(좌=적/우=청) 픽스처 실측으로 결함 확정(표시 크기 스케일만 적용·픽셀 옆으로 누움 — BUG-06 핏 수정과 상호작용). 수정: 평문 `rotationAwareFitTransform`(회전→핏 순 — `concatenating` self-먼저 적용 실증 판명)·프리뷰 동일 결합+`.sourceFrame` 앵커 pt 제거(이중 적용)+트랙 pt identity 통일·커스텀 컴포지터 `orientedForDisplay`(±90°/180° 매핑). 검증: 엑스포트·프리뷰 픽셀 실측 모두 상=적(R237)/하=청(B235) PASS · Mac 유닛 42/42(오리엔테이션 4종 신설) · **CA-04 매트릭스 PASS — BUG-07 REG 소멸·방향 어설션 승격** · verify_gate 1,413·5/5. CA-04 등록 결함 전량 소멸(BUG-06·07 해결).
다음 증분(우선순위): ① **RENDER-02**(P2) 범위 태깅 ② G-27 실기기 2종(사용자 잠금 해제 대기)·MACUI-01 복구(사용자 TCC/재부팅 조치 대기) ③ 잔여 소형(A11Y-01 iOS 인스펙터 a11y·UX-REC-01/02·iOS 회전 경로 확인 — RENDER-01 통합 후에도 pt 결합 가능성). **PARITY-TOL-01 승인 대기 유지**.
**기존 결함 기록**: 자체 측정 게이트 5/5(1,413)·Mac 유닛 42/42. 코어 파리티 12/17 FAIL은 PARITY-TOL-01 대기(재표본 variance, 절대 픽셀 검증 완료). 실기기 검증 미실행. **병렬 세션 경합 주의**: pbxproj 손상 2회·VM/iOS-xcstrings 커밋 누락 각 1회·LOOP_STATE 덮어쓰기 1회 — 커밋 직전 git status/diff --stat 확인 절차 유지.
**범위 외 발견(후속 관찰)**: `layerActiveTracks` 보조 블렌드 트랙 캔버스 핏 부재(BUG-06 잔존 가능성)·회전+전환 조합·iOS 회전 경로.
대기 결정 사항: **PARITY-TOL-01**(허용치 vs 픽스처 ≥720p 재생성 — 권고 (a))·G-27 실기기 2종 연결+잠금 해제·MACUI-01 사용자 TCC/재부팅·CA-07 가격(사용자 전용)·CA-11·CA-13·CA-16(P2).
마지막 커밋: (이 세션 증분·docs 커밋 — git log 참조)
갱신: 2026-08-25 14:50
