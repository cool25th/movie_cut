# CA-12 경쟁사 A/B 벤치마크 하니스 + 기준 수치 최초 기록 (2026-08-27)

> 근거: `docs/COMPETITIVE_ANALYSIS_20260822.md` Part 5 (벤치마크 하니스 설계) · 백로그 §0.5.1 CA-12.
> 완료 기준: "하니스 + 기준 수치 최초 기록" — 이 문서가 그 기록이다.
> 측정 원칙: VERIFICATION_STANDARD §1 (자가보고 수치 배제 — 전 수치가 실측 명령 출력).

---

## 1. 하니스 구성 (Part 5 §1~§4 대응)

| 구성요소 | 파일 | 역할 |
|---|---|---|
| 품질 메트릭 모듈 | `scripts/ab_benchmark_metrics.py` | `single`(단일 영상 절대 지표)·`pair`(참조 대비 지표)·`blind`(사람 블라인드 프로토콜)·`self-test`(결정적 원시 검증 15종) |
| fixture 세트 생성 | `scripts/make_ab_fixtures.sh` | 12 대표 fixture 결정적 생성 + `manifest.json`(SHA-256·지오메트리·코덱·지속) — 스크립트 내 핀 테이블이 세트 버전 관리 |
| 종단 러너 | `scripts/run_ca12_ab_benchmark.sh` | 조건 필드 수집→앱 빌드(Debug·샌드박스 OFF)→fixture별 실앱 구동(RSS 폴링·와치독)→메트릭 수집→`baseline.json` |
| 앱 하니스 게이트 | `App/MovieCutMac/UITestHarness.swift` | 신규 `MOVIECUT_UITEST_CHROMA_KEY=1`(실제 커맨드 경로 크로마키) + `export_wall_s=`(§1.4 앱 전체 vs encode 구간 분리, 일반·파리티 양 경로) + 파리티 경로 DUCKING/CHROMA_KEY 미러링 |

**A/B의 의미**: A측(MovieCut)은 이 하니스가 자동 실측한다. B측(경쟁사)은 사람이 동일 fixture로
경쟁 앱에서 출력해 `artifacts/ab_benchmark/competitor/<fixture_id>.mp4` 로 놓고
`--blind`로 랜덤화 블라인드 투표를 만들어 사람이 평가한다(§5). 메트릭 표는 양측 동일 정의로
각각 계산해 병치 비교한다.

## 2. 조건 필드 (§1.4 — 모든 수치는 이 조건과 함께 읽힌다)

`baseline.json`의 `conditions` 블록이 실행마다 기록된다. 첫 기준 수치의 조건:

| 필드 | 값 |
|---|---|
| 기기 / 칩 / RAM | Mac16,10 / Apple M4 / 17.2 GB |
| OS / 빌드 | 26.6.2 / 25G83 |
| 앱 커밋 | 6ca0d59 (Debug, 샌드박스 OFF, CODE_SIGNING_ALLOWED=NO) |
| 전원 / 열 | AC / 경고 없음(pmset) |
| 저장(출력) | /dev/disk3s5 (내장) — **⑩ 외장 미연결**: 외장 축은 조건 필드로만 기록, 외장 연결 시 재실측 |
| 기동 | fixture마다 신규 프로세스+컨테이너 = cold |
| 반복 | 1 (`REPS=n`으로 반복 실행·중앙값/p95 확장) |
| 측정 샘플링 | single 9프레임(등간)·pair fixture별 타임스탬프(§4 표) |
| 캔버스 | 전 fixture 기본 캔버스 **1920x1080** 으로 통일(§6 발견 ③) |

측정 정의(§1.4 준수): RTF = `export_wall_s / 출력 길이`(하니스 내부 격리 시계 — 임포트·구성 제외).
앱 전체 벽시계는 러너가 프로세스 수명으로 측정. peak RSS는 실행 중 `ps` 폴링 최댓값.

## 3. 지표 정의 (Part 5 §2 — PSNR 단독 금지 준수)

**single(출력 파일 절대 지표)**: 코덱/프로파일/픽셀포맷/색 태그·**chroma subsampling**(pix_fmt
유도: yuv420p→4:2:0)·실제 비트레이트(size×8/duration, ffprobe 보고치 병기)·키프레임 간격
중앙값/최대(패킷 키플래그)·**CFR/VFR 판정**(프레젠테이션 순 정렬 pts 델타 지터 ≤1ms)·
highlight clipping(최대채널 ≥250 비율)·shadow crush(최소채널 ≤5 비율)·**banding proxy**
(점유 루마 레벨 범위 내 결측 레벨 비율 — 포스터화 검출, 평탄 프레임 0)·
loudness/true-peak(ebur128)·A/V 시작·지속 오프셋.

**pair(무손실 참조 대비)**: 참조 = 파리티 하니스의 **프리뷰 PNG 덤프**(무손실 — 확립 관례와
동일한 타임스탬프 정합+스케일/패드 규칙). 시험 = 출력 mp4 동일 시점 프레임.
전역/프레임별 **PSNR**·**block SSIM**(8x8 비중첩, Rec.601 luma, Wang 상수)·채널별 MAD
p95/max·**ΔE(CIE76**, sRGB→XYZ→Lab, 4px 스트라이드)·비교 프레임 수.

**blind(사람 병행)**: 시드 지정 랜덤화(품목별 X/Y 셔플·원본명 은닉 복사본)·투표용
ballot.md·응답 CSV 템플릿·채점(`--tally` → 승수·tie·결정 대상 점유율). 판정 문구는
Part 5 원문대로 **비열등(not-inferiority)** 이지 승률 경쟁이 아님을 결과 JSON에 명시.

정확성 검증: `self-test` 15종(동일→PSNR ∞/SSIM 1·균일 +10→20.412dB 해석값·흑백 ΔE=100·
램프/포스터라인 banding 0/>0.9·시드 결정론·yuv 파싱 등) — PASS.

## 4. 12 대표 fixture 세트 (Part 5 §3, 버전 = 핀된 SHA-256)

| # | id | 미디어(해상도@fps·길이) | SHA-256(앞16) | 앱 시나리오(하니스 게이트) | pair 샘플 시점 |
|---|---|---|---|---|---|
| ① | ab01_single_1080p30 | 1920x1080@30·10s | 2c52262a660fde26 | 없음(패스스루) | 1.0,3.5,6.0,8.5 |
| ② | ab02_4k60_hevc | 3840x2160@60·6s | 8721fdbfced49bb1 | 없음(패스스루) | 0.5,2.0,4.5 |
| ③ | ab03_hdr_10bit | 320x240·2s(BT.2020+PQ) | 08f9a9100dd87e91 | 없음(패스스루) | 0.5,1.5 |
| ④ | ab04_interview_30min | 640x360@30·30분(**축소 스케일**) | 0a60a6787ba72e8b | TEXT_AT=0.5(자막) | 1,450,900,1350,1750 |
| ⑤ | ab05_shorts_overlays | 720x1280@30·1s ×2임포트 | 3ce2018e913f97aa | TEXT_AT=0.5(다중 오버레이) | 0.3,0.7 |
| ⑥ | ab06_ramp_opticalflow | 320x240@30·2s | b7a9cb2e4209256a | SPEED_RAMP=1+OPTICAL_FLOW=1 | 0.3,0.7 |
| ⑦ | ab07_mask_chromakey | 320x240@30·4s(그린스크린) | d47ff2a2b88ab9c9 | MASK=1+CHROMA_KEY=1 | 0.5,1.5,2.5,3.5 |
| ⑧ | ab08_color_grade | 1920x1080@30·1s | 27323f996091f455 | COLOR=1+GRADE=1 | 0.5 |
| ⑨ | ab09_ducking_master | 320x240·2s(+BGM/voice wav) | 1aab9104827ceb8d | DUCKING_BGM/VOICE/APPLY=1 | 0.5,1.5 |
| ⑩ | ab10_external_disk | ① 미디어 재사용 | 2c52262a660fde26 | 없음 — 저장장치 축(§2) | ①과 동일 |
| ⑪ | ab11_vfr_screenrec | 320x240·~5s(VFR) | bede888f6f2ebb37 | 없음(패스스루) | 0.5,2.5,4.5 |
| ⑫ | ab12_two_hour | 320x240@24·2시간(**축소 스케일**) | a439b9129d32c67e | 없음(패스스루) | 1,1800,3600,5400,7100 |

장편 2종(④⑫)은 디스크·세션 예산으로 축소 해상도로 생성했다(§1.4 "fixture 규모 명시 필수" 준수 —
규모는 매니페스트가 기계적으로 고정). 커밋된 fixture(③⑤⑥⑧⑨⑪·덕킹 wav)는 Tests/Fixtures에서
재사용한다. 재생성·검증: `bash scripts/make_ab_fixtures.sh`(핀 불일치 시 실패).

## 5. 첫 기준 수치 (A측 = MovieCut, 2026-08-27 실측)

원본: `artifacts/ab_benchmark/run_20260827_092242/baseline.json` (아래는 요약 전사).

| id | 앱 전체 s | export s | RTF | peakRSS MB | 비트레이트 kbps | 키프레임 s | CFR | LUFS | PSNR dB | SSIM | MAD p95 | ΔE mean | 프레임 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ab01 | 7.16 | 4.37 | 0.437 | 118 | 8,791 | 0.97 | T | −70.0 | 29.46 | 0.9869 | 4.46 | 1.85 | 4 |
| ab02 | 2.66 | 1.43 | 0.238 | 131 | 6,318 | 0.97 | T | — | 29.69 | 0.9847 | 4.62 | 2.06 | 3 |
| ab03 | 1.58 | 0.55 | 0.275 | 103 | 3,758 | 0.97 | T | — | 15.15 | 0.9365 | 15.84 | 10.98 | 2 |
| ab04 | 539.11 | 538.06 | 0.299 | **1,387** | 10,622 | 0.97 | T | −70.0 | 22.53 | 0.9812 | 10.40 | 2.27 | 5 |
| ab05 | 2.08 | 0.57 | 0.283 | 113 | 101 | 0.97 | T | — | 34.21 | 0.9874 | 3.97 | 1.71 | 2 |
| ab06 | 1.57 | 0.56 | 0.396 | 109 | 109 | 0.97 | T | — | 50.71 | 0.9873 | 0.30 | 0.16 | 2 |
| ab07 | 2.59 | 0.95 | 0.237 | 114 | 29 | 0.97 | T | — | 33.77 | 0.9994 | 0.22 | 0.08 | 4 |
| ab08 | 1.57 | 0.37 | 0.368 | 107 | 36 | 0.97 | T | — | 31.93 | 0.9984 | 10.10 | 4.44 | 1 |
| ab09 | 624.94† | — | — | 101 | — | — | — | — | — | — | — | — | — |
| ab10 | 4.70 | 2.57 | 0.257 | 126 | 8,792 | 0.97 | T | −70.0 | 29.46 | 0.9869 | 4.46 | 1.85 | 4 |
| ab11 | 2.14 | 1.17 | 0.235 | 107 | 209 | 0.97 | T | — | 7.38 | 0.9164 | 144.96 | 68.56 | 3 |
| ab12 | 2,509.52 | 2,506.05 | 0.348 | **5,054** | 8,365 | 0.97 | T | −70.0 | 16.93 | 0.9308 | 29.37 | 11.28 | 5 |

† ab09는 하니스 파킹으로 종료 — §6 발견 4. LUFS −70.0은 정현파 오디오의 실측값(신호 특성).
ab12 부가: **A/V 시작·지속 오프셋 모두 0.000s**(2시간 무드리프트 싱크)·하이라이트 클리핑
54.5%(testsrc2 백색 영역 특성)·banding 0.017. 출력 7.5GB(1080p 캔버스 2시간)는 메트릭 기록 후
프루닝(러너가 자동 — 재생성은 `run_ca12_ab_benchmark.sh ab12`).
모든 출력 h264/4:2:0/1920x1080(기본 캔버스)·하이라이트 클리핑/섀도 크러시는 ab12 외 전
fixture 0.0%·banding proxy 0.0(합성 소스 특성).

## 6. 발견 (하니스가 포획 — 후속 큐 등록 근거)

1. **HDR 태그 소스의 preview↔export 픽셀 발산(ab03)**: PSNR 15.1dB·MAD p95 15.8. 기존
   파리티 비교기(`verify_preview_export_parity.py`)로 교차확인 — **동일 FAIL(MAD 11.26, 허용 2.0)**.
   BT.2020+PQ 소스가 프리뷰와 출력에서 다르게 해석된다. CA-04는 출력 태그(ffprobe)만 확인했고
   픽셀 파리티는 미측정이었다. → 결함 후보 등록(§8).
2. **VFR의 시각 매칭 한계(ab11)**: PSNR 7.4dB·MAD p95 145 — VFR→CFR 재표본화로 같은
   타임스탬프의 프레임 위상이 양측 다르다. 교차확인 동일 FAIL(MAD 77.97). 이는 품질 열화라기보다
   **측정 정의의 한계**로 기록한다(VFR 품질 비교는 블라인드+절대 지표로).
3. **기본 캔버스 1080p 통일**: 전 fixture가 1920x1080 캔버스로 출력된다(소스 4K는 다운스케일,
   320x240는 업스케일). ②의 4K 네이티브 출력 비교는 캔버스를 소스 해상도로 설정하는 후속 실행
   필요(`MOVIECUT_UITEST_EXPORT_RESOLUTION=p4K` + 캔버스 설정 경로 확인).
4. **덕킹×파리티 경로 조합 파킹(ab09 — 결정론 재현)**: 파리티 하니스에서 DUCKING 게이트
   적용 직후 태스크가 재개되지 않는 파킹(0% CPU·메인 스레드 런루프 유휴·체크포인트
   `scenarios_applied`에서 영구 정지). **2회 재현 동일**(180초 와치독 kill로도 같은 지점).
   일반 경로(비-파리티) 덕킹 E2E는 run_e2e_export.sh에서 통과 중 — 파리티 경로 한정 조합
   결함. CHROMA_KEY 게이트는 ab07에서 정상 통과(크로마키 무관). 등록: 백로그 §1.13
   BUG-CA12-01.
5. **ab12(2시간) 장편 완주**: export 2,506s(RTF 0.348)·peak RSS 5,054MB·**A/V 싱크 Δ0.000s**.
   2시간 출력이 기본 캔버스(1080p)에서 7.5GB가 되는 비용 구조를 실측으로 기록.
6. **소스↔캔버스 스케일 불일치가 pair 지표를 지배**: 원생 1080p 소스(ab01/02/08)는
   PSNR 29~32dB인 반면, 업스케일 소스(ab03/04/12 — 320~640px→1080p 캔버스)는 15~23dB,
   VFR(ab11)은 7dB. 업스케일 픽셀 차이(프리뷰/출력 보간 경로 차이 포함)가 인코딩 손실보다
   크게 작동한다. 해석 규칙: **pair 지표는 동일 스케일 fixture 간에만 비교**하고, 스케일이
   다른 비교는 절대 지표+블라인드로 판정한다.

## 7. 블라인드 프로토콜 사용법 (사람 블라인드 병행)

```
# A측 출력은 러너가 자동으로 artifacts/ab_benchmark/moviecut/<id>.mp4 에 유지
# (1GB 초과 출력 — ab04·ab12 — 은 프루닝되므로 해당 fixture 재실행으로 스테이징)
bash scripts/run_ca12_ab_benchmark.sh
# B측: 동일 fixture로 경쟁 앱에서 수동 출력 → artifacts/ab_benchmark/competitor/<id>.mp4
bash scripts/run_ca12_ab_benchmark.sh --blind     # 랜덤화 투표 생성(시드 기록)
# 사람이 ballot.md 보고 responses.csv 채움 → 채점
python3 scripts/ab_benchmark_metrics.py blind \
  --tally artifacts/ab_benchmark/blind/responses.csv \
  --key  artifacts/ab_benchmark/blind/blind_key.json \
  --out  artifacts/ab_benchmark/blind
```

## 8. 후속 (등록·제안)

- **BUG-CA12-01 등록(§6 발견 4)**: 파리티 경로×덕킹 조합의 태스크 파킹 — 결정론 재현
  명령 `WATCHDOG_S=180 bash scripts/run_ca12_ab_benchmark.sh ab09`. 최소화·수정은 별도 증분.
- **BUG-CA12-02 후보(§6 발견 1)**: HDR(BT.2020+PQ) 태그 소스의 preview↔export 픽셀 발산
  (기존 비교기 교차 FAIL MAD 11.26 vs 허용 2.0) — 백로그 결함행 등록.
- 4K 네이티브 캔버스 실행(발견 ③)·외장 디스크 연결 시 ⑩ 재실측·REPS 반복 실행의
  중앙값/p95 확장.
- 경쟁사 B측 출력 확보 시 §7 절차로 블라인드 평가 실시 — 결과가 "블라인드 비열등"의
  Perceptual 등급(VERIFICATION_STANDARD §2 ③) 근거가 된다.
