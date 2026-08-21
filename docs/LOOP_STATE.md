상태: RUN(2단계 계획 승인됨 2026-08-20)
현재 증분: 완료 = **Motion Tracking Recovery v1 + safety hotfix** — PR #12(`1af95b8`)로 완전 가림 후 재획득을 구현하고, PR #13(`cd173cf`)으로 Codex P2 2건(appearance matcher 부재 시 fail-closed·recovery timeout 선검사)을 보강. Issue #11은 측정 근거를 기록한 뒤 `completed`로 종료.
검증 증거: normal fixture mean/min IoU **0.7995/0.7041**, fail rate **0.0000**; occlusion `reacquire_at=2.033s`, latency **0.633s**, sustained post-emergence IoU **0.7543**. 동일 binary/process Release attribution: RTF **0.9670→0.9388(-2.92%)**, p95 **85.34→79.15ms(-7.25%)**. PR #12 CI #79 및 PR #13 CI #81 모두 `build-and-test / ios-tests / lint` green. PR #13 최종 Codex review: major issue 없음.
이전 완료(최근): G-28 effect cost 실측/브라우저·background single-flight, G-26 master chain 직렬화/제품 배선/Inspector preset UI, G-24 stabilization warp 종단 통합, G-03 adjustment layer, G-27 simulator E2E, W representative-work gate, latency enforce, G-25 audio graph 전환.
공식 잔여 게이트: **G-27 iOS 실기기 3종(최소/중간/최신) 검증**. 하니스/가이드는 준비 완료이며 물리 iPhone 연결이 필요. 3종 PASS 전에는 Phase 1의 공식 실기기 조건을 완료로 선언하지 않음.
자율 다음 작업: **2단계 완료 판정 + 잔여 gap 재스캔**. 과거 LOOP_STATE의 다음 후보였던 `마스터 체인 인스펙터 UI`와 `G-28 measureAllBuiltIns 백그라운드 이관`은 현재 main에 이미 구현/회귀 잠금까지 존재하므로 재작업 금지. 방향 문서 §3·§9와 `EXECUTION_PLAN_PHASE2_20260819.md`를 현재 코드에 재대조한 뒤 다음 원자 증분을 확정한다. 3단계 HDR 공개는 단계 게이트 판정 전 선행 착수하지 않는다.
기존 결함 기록 갱신: motion tracking full-occlusion loss recovery 결함 폐쇄. recovery 중 appearance verification 없는 후보 수용 및 late candidate timeout 우회 P2도 PR #13으로 폐쇄. snapshotFrame 중복 프레임은 하니스 문서화 상태 유지.
대기 결정 사항: **접근 정규화 승인**만 유지. `모션 트래킹 재검출 시드` 대기 항목은 #11 완료로 제거.
제품 코드 기준점(PR #13 merge): cd173cf8cb1b2821fa1182ca762e5fa0ef3928f5
문서 상태 동기화: PR #14
갱신: 2026-08-22 00:32 KST
