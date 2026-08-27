상태: RUN
현재 증분: 완료 = **CA-12(경쟁사 A/B 벤치마크 하니스 + 기준 수치 최초 기록, 2026-08-27)** — `ab_benchmark_metrics.py`(single/pair/blind·self-test 15종 PASS — PSNR·SSIM·ΔE·banding·clipping·chroma·키프레임·VFR/CFR·A/V sync·loudness/true-peak) + `make_ab_fixtures.sh`(12 대표 fixture·SHA-256 핀=세트 버전 관리) + `run_ca12_ab_benchmark.sh`(§1.4 조건 필드·실앱 구동·RTF/RSS·와치독·baseline.json·블라인드 A측 스테이징) + 하니스 CHROMA_KEY 게이트·export_wall_s(앱 전체 vs encode 분리). **첫 기준 수치 11/12 fixture 실측**(`CA12_AB_BENCHMARK_20260827.md`): 30분 RTF 0.299·2시간 RTF 0.348(peakRSS 5,054MB·A/V Δ0.000s)·소형 0.24~0.44. 발견 등록 §1.13: **BUG-CA12-01**(파리티×덕킹 파킹 — 결정론 재현·⑨ 수치 공백)·**BUG-CA12-02**(HDR 태그 소스 preview↔export 발산 — 기존 비교기 교차 FAIL MAD 11.26). 부수: 디스크 100%(163MB) → 재생 가능 캐시 1.5GB 정리로 회복(purgeable 정산 후 27Gi — 세션 중 7.5GB ab12 출력 프루닝으로 13Gi 유지).
다음 증분(우선순위): **BUG-CA12-02 감사**(HDR 색 해석 경로 — P1 후보) → CA-22 2차(프록시 설정 UI·취소·재개) → CA-14/15(소형). **대기(사용자)**: G-27 실기기 2종(잠금 해제)·MACUI-01+U-08 회귀 실측(TCC 접근성/재부팅)·PARITY-TOL-01(승인)·**디스크 용량 회피 지속 관찰**(데이터 볼륨 만약 — 재생 가능 캐시 정리는 1회 수행됨).
**기존 결함 기록**: 자체 측정 게이트 5/5·Mac 유닛 48/48·iOS 48/48. 실기기 검증 미실행. **병렬 세션 경합 주의**: pbxproj 손상 2회·LOOP_STATE 덮어쓰기 1회·중단 회차 WIP 2회(프로토콜 0 해결·LI-003) — 커밋 직전 git status/diff --stat 확인 유지.
**범위 외 발견(후속 관찰)**: ui_regression 골든 의도 드리프트(AX 복구 시 갱신)·VFR timestamp 매칭 편차(측정 정의 한계 — CA12 문서 §6).
대기 결정 사항: **PARITY-TOL-01**(허용치 vs 픽스처 ≥720p 재생성 — 권고 (a))·G-27 실기기 2종 연결+잠금 해제·MACUI-01+U-08 회귀 실측(TCC 접근성/재부팅)·CA-07 가격(사용자 전용)·CA-11·CA-13·CA-16(P2).
마지막 커밋: 574d30a
갱신: 2026-08-27 19:30
