# QAUTO-03 출력 무결성 게이트 — 첫 기준 수치 기록 (2026-09-21)

> 원장: `CAPCUT_FEATURE_BACKLOG.md` §0.5.1 QAUTO-03(2026-09-12 승인 — 검증 레인 3순위).
> 러너: `scripts/run_export_integrity_gate.sh`(임계값 사전등록·fail-closed 가드·QAUTO-01 레코더 연결).
> 실측: 2회 연속 PASS(재현성 — 두 실행의 전 판정·수치 동일).

## 계약 (사전등록)

- **시나리오**: 실앱 하니스(MovieCutMac Debug)로 동일 프로젝트(임포트 + 색보정 — 커스텀 컴포지터 경로)를 **2회 독립 export**. 소스 픽스처 `solid_red_tone_320x240_2s_30fps.mp4`(h264+aac 2.000s — 영상·오디오 양 트랙).
- **R1 디코딩 동일성**: 3 프로브 프레임(head=0/mid=dur/2/tail=dur−0.1)의 md5(png)와 오디오 전체 트랙 md5(s16le PCM)가 rep1↔rep2 동일. **비트스트림 byte equality는 주장하지 않음**(컨테이너 타임스탬프는 달라도 됨 — 크기는 관찰값으로만 기록).
- **R2 스트림 계약**: rep 간 전 필드 동일 + 사전등록 기대치(h264+aac·컨테이너 길이 2.0s±0.1). fps·해상도·pix_fmt·회전은 첫 기준값으로 기록.
- **R3 A/V 싱크 드리프트**: |video.duration − audio.duration| ≤ 0.010s(각 export).
- **fail-closed**: 프로브 필드 공백·빈 입력 sentinel sha256(e3b0c4…)은 ERROR(통과 아님). 디스크 가드 BLOCK/STOP 시 시작 거부(QAUTO-07).

## 첫 기준 수치 (2026-09-21, HEAD d31e7ba)

| 축 | rep1 | rep2 | 판정 |
|---|---|---|---|
| 스트림 계약 | h264 1920x1080 30/1 yuv420p + aac 48000Hz 2ch, rot=none | 동일 | ✅ |
| 컨테이너 길이 | 2.000000s | 2.000000s | ✅ (2.0±0.1) |
| 프레임 md5 head/mid/tail | — | rep1=rep2 전 지점 동일 | ✅ |
| 오디오 PCM md5 | — | rep1=rep2 동일 | ✅ |
| A/V 드리프트 | 0.0s | 0.0s | ✅ (≤0.010) |
| 파일 크기(관찰) | 41,699 bytes | 41,699 bytes | (미단정) |

- 재현성: 2회 실행 전 판정 동일(PASS)·수치 완전 일치. 판정 레코드: `qauto03-20260921074240-46370`·`qauto03-20260921074559-46961`(`.build-check/history/qauto-qauto03_export_integrity-*.json` — app commit+harness sha 바인딩).
- **해석**: 색보정 컴포지터 경로의 export는 동일 입력·동일 빌드에서 디코딩 수준까지 완전 결정론적(프레임 3지점+오디오 PCM 전체). 크기까지 우연히 동일했으나 이는 계약이 아님.

## 축 패밀리 (기존 축과 통합)

| 축 | 러너 | 상태 |
|---|---|---|
| 반복 export 결정론 | `run_export_integrity_gate.sh` | **본 게이트 — 2회 PASS(2026-09-21)** |
| 디스크 풀(ENOSPC) 미드플라이트 | `run_diskfull_gate.sh` | 2/2 PASS(2026-09-04, STAB 3-A) |
| 취소(미드플라이트) | Mac e2e cancel 게이트 + iOS `ExportCancelMidFlight` CI | 완결(2026-09-03 취소 E2E·iOS 3776f9c) |

## 경위·유의

- 초안은 무음 픽스처(bars)를 썼다가 **스스로의 fail-closed 가드가 빈 오디오 프로브를 잡아 ERROR 종료** — 오디오 포함 픽스처로 교체 후 측정(공허한 통과가 아닌 증거).
- 재측정 트리거(QAUTO-01 규율 준용): export 파이프라인·코덱 설정 변경, toolchain 교체, 드리프트 관측 시. 상시 재실행은 아니며 verify_gate의 다른 축과 독립.
- DoD "기존 ENOSPC/취소 축과 통합"은 패밀리 표+레코드 내 포인터로 충족(각 축 러너를 본 게이트가 재실행하지는 않음 — 중복 측정 회피).
