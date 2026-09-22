# QAUTO-06 미디어 호환 코퍼스 — 첫 기준 기록 (2026-09-22)

> 러너: `scripts/run_qauto06_media_corpus.sh`(계약 사전등록·fail-closed[무결과 라인=행/크래시로 FAILED]·디스크 가드 preflight·QAUTO-01 레코더).
> 계약: 각 코퍼스 항목은 **성공(UITEST_DONE+error=none+산출물+비디오 스트림+길이 2.0s±0.2) 또는 명시적 unsupported(분류된 오류 표면)** 둘 중 하나로 끝나야 한다. 행/크래시/결과 라인 부재는 결코 "unsupported"가 아니다.
> 픽스처: 런타임 ffmpeg lavfi 결정론 생성(provenance class=GENERATED — 커밋 픽스처 아님).

## 기준 수치 (2026-09-22, HEAD 410cb02)

| 항목 | 형태 | 판정 |
|---|---|---|
| h264_4k_30 | 3840x2160@30 + 스테레오 48kHz | **성공** dur=2.000s |
| h264_1080_60 | 1920x1080@60 + 스테레오 48kHz | **성공** dur=2.000s |
| hevc_1080_30 | HEVC **hvc1** 1920x1080@30 + 48kHz | **성공** dur=2.000s |
| silent_1080_30 | 무음(오디오 트랙 없음) | **성공** dur=2.000s |
| mono_44k1_1080 | 모노 44.1kHz(혼합 샘플레이트 축) | **성공** dur=2.000s |
| portrait_9x16 | 1080x1920@30 세로형 | **성공** dur=2.000s |

판정 레코드: `qauto-qauto06_media_corpus-*.json`(app commit+harness sha 바인딩 — 최종 형태 PASS·이전 실행들 아래). 반복성: h264/무음/모노/세로 다리는 3회 실행에서 동일(초안 2회는 오디오 lavfi 구문 오류·hev1 경계 발견 각각으로 종료 — 아래 기록).

## 코퍼스가 발견한 호환 경계 — hev1 태그 HEVC (등록: BUG-CORPUS-01)

- **측정 사실**: libx265 기본(**hev1** 태그) HEVC 소스는 임포트 성공(clips=1) 후 **Mac 프리셋 export에서 "작업이 중단됨"으로 명시적 거부**(wall 0.985s). 커밋 HEVC 10bit 픽스처(bt2020pq·hvc1)와 **hvc1 태그로 재생성한 동일 소스는 모두 성공**(각 1.378s/1.428s) — 원인은 코덱이 아니라 **mp4 코덱 태그(hev1 vs hvc1)**.
- **왜 중요한가**: iPhone 실녹화는 hvc1(영향 없음). hev1은 일부 서드파티 인코더·Android 계열 출력 — 사용자에게 "영상이 안 돼요"로 나타날 수 있는 경계.
- **계약 준수**: 명시적 오류 표면(무음 실패 아님)으로 코퍼스 PASS 유지.
- **후보 처방(등록만 — 구현 별도 승인)**: 임포트 시점 codec-tag 사전 검증(hev1 감지 시 경고 또는 reader 경로 리라이트) — `BUG-CORPUS-01`로 백로그 등록.

## 잔여(QAUTO-06)

- project save 중 ENOSPC fault injection 확대(하니스 leg — diskfull 게이트 확장 형태).
- 장편 active soak(30/60분 렌더·출력 반복 — GREEN 디스크·wall-clock 자산, 루프 회차 배치).
- 코퍼스 확장 후보: HEVC 60fps·ProRes 소스·웹M(명시적 unsupported 확인)·HDR 10bit 라이브(커밋 fixture 경유).
