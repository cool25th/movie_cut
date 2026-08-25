상태: RUN
현재 증분: 진행 중 = **리뷰-20260826 반영 — P0 출력 정확성 → P1 생존성 → 게이트 강화** (외부 리뷰 8건 전부 코드 대조 확정, 백로그 §1.12 등록). 완료: GATE-01 · BUG-08(게이트 제거+iOS includeIdentitySource 누락 판명, 이색 픽스처 실측) · BUG-IOS-08(효과 pt 전달+3경로 orientedForDisplay, 플랜+출력 양다리 upright) · G-15 AC5+AC6(ImageVideoRenderService Core 이동, PNG/HEIC/EXIF+사진전용 export E2E) · **BUG-IOS-09 전환** — 2슬롯 교차+백타이밍+makeTransitionEffects 포팅, 전환 없는 트랙 단일 레이아웃 유지, 플랜 프레임 블렌드 실측(IOSTransitionPipelineTests 3종). 다음: BUG-IOS-10 오디오 믹스 → Phase 2 생존성. iOS 38/38·Mac 44/44.
다음 증분(우선순위): **Phase 1 — P0 출력 정확성(공유 렌더 계획 기준)**: ①픽스처 확장(solid_blue·HEIC/EXIF) → ②BUG-08 멀티트랙(이색 픽스처·Mac+iOS 동시) → ③BUG-IOS-08 회전(비대칭 픽스처) → ④G-15 AC6 이미지 파이프라인 → ⑤BUG-IOS-09 전환 → ⑥BUG-IOS-10 오디오 믹스. 이후 Phase 2 생존성(SURV-01·autosave flush·RACE-01·STICKER-01·L10N-01·G-27 하니스) → Phase 3 Mac 테스트 CI 차단 승격·전략 문서 범위 경계 명문화. **대기(사용자)**: G-27 실기기 2종(잠금 해제)·MACUI-01(TCC/재부팅)·PARITY-TOL-01(승인)·RENDER-02 태그된 라이터(별도 증분).
**기존 결함 기록**: 자체 측정 게이트 5/5(1,413)·Mac 유닛 42/42. 코어 파리티 12/17 FAIL은 PARITY-TOL-01 대기(재표본 variance, 절대 픽셀 검증 완료). 실기기 검증 미실행. **병렬 세션 경합 주의**: pbxproj 손상 2회·VM/iOS-xcstrings 커밋 누락 각 1회·LOOP_STATE 덮어쓰기 1회 — 커밋 직전 git status/diff --stat 확인 절차 유지.
**범위 외 발견(후속 관찰)**: `layerActiveTracks` 보조 블렌드 트랙 캔버스 핏 부재(BUG-06 잔존 가능성)·회전+전환 조합 — iOS 회전 경로는 BUG-IOS-08로 등록(2026-08-26, §1.12).
대기 결정 사항: **PARITY-TOL-01**(허용치 vs 픽스처 ≥720p 재생성 — 권고 (a))·G-27 실기기 2종 연결+잠금 해제·MACUI-01 사용자 TCC/재부팅·CA-07 가격(사용자 전용)·CA-11·CA-13·CA-16(P2).
마지막 커밋: (이 세션 증분·docs 커밋 — git log 참조)
갱신: 2026-08-26
