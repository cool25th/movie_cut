# CapCut 8.9.0 벤치마크 출력 획득 — 등록·프로브 기록·수동 키트 (2026-09-23)

CA-32 / OC-03 계약의 첫 경쟁 축. MovieCut 기준선(CA-12)·ffmpeg-reference와
동일 fixture·동일 pair-metric으로 CapCut 데스크톱 출력을 비교한다.

## 상태

- **후보 등록 완료**: `capcut-8.9.0` — `qa/baselines/benchmark-candidates.json`
  (`CapCut Desktop`, `8.9.0 (com.lemon.lvoverseas)`)
- **출력 규약**: `artifacts/ab_benchmark/candidates/capcut-8.9.0/<fixture_id>.mp4`
- **측정**: 출력 확보 후 `bash scripts/run_benchmark_candidates.sh --measure capcut-8.9.0`
  (원 커맨드 — 없는 fixture는 SKIP, 레지스트리에 시각 append)

## 환경 확인 (2026-09-23 프로브)

- /Applications/CapCut.app 설치됨 — 버전 8.9.0, bundle `com.lemon.lvoverseas`,
  URL scheme `capcut://`. **CLI/헤드리스 내보내기 없음**.
- System Events 접근성 스크립팅 작동(TCC 허용 상태): 프로세스 창 열거·홈
  화면 요소(홈/템플릿/공간/디자인 스튜디오/`HomePageStartProjectName`) 관측.
- `open -a CapCut <fixture>` 실행 → 홈 창 + **무명 모달**(810x500, AXGroup +
  버튼 2개, **AX 텍스트 전무**) — 맹목 클릭이 안전하지 않음.
- 전체 화면 캡처 당시 데스크톱을 다른 작업이 점유 중 → 좌표 클릭 기반
  자동화는 보류. **결론: 수동 10분 획득이 더 빠르고 안전.**
  (무인 시간대에 GUI 재시도는 열려 있는 옵션 — 모달 정체 확인 후)

## 수동 획득 절차 (약 10분)

입력 소스: `artifacts/ab_benchmark/candidates/capcut-8.9.0/_inputs/`
(= fixtures와 동일 파일 3종. ab10은 ab01 출력 복사)

공통: 새 프로젝트 → 입력 파일을 타임라인에 드래그 → **원본 그대로**
(자르기/자동 개선/스마트 프리셋 제안은 전부 취소) → 우상단 내보내기:

| 설정 | 값 |
|---|---|
| 해상도 | 1080p (1920x1080, 16:9) |
| 프레임 레이트 | 30 (ab02는 60) |
| 코덱 | H.264 |
| 비트레이트 | 기본(권장) 그대로 |
| 오디오 | AAC |

저장 위치를 위 폴더로 지정, 파일명 정확히:

1. `ab01_1080p30_10s.mp4` → **`ab01_single_1080p30.mp4`**
2. `ab02_2160p60_hevc_6s.mov` → **`ab02_4k60_hevc.mp4`**
   (4K60 HEVC → 1080p 스케일. HEVC 10bit 처리 동작/경고 기록)
3. `ab07_greenscreen_320x240_4s.mp4` → **`ab07_mask_chromakey.mp4`**
   (320x240 → 1080p 업스케일. 크로마키 적용 없음)
4. `cp ab01_single_1080p30.mp4 ab10_external_disk.mp4`
   (ab10 = ab01 동일 입력 — reference 축과 동일 취급)

### 기록 요망 (비교 문서에 들어갈 관찰)

- 각 내보내기 소요(진행창 표시) — RTF 산출용
- 로그인/계정 강제 여부, 워터마크·Pro 배지 표시 여부
- 기본 비트레이트 표시값, 내보내기 창 스크린샷 1장
- ab02 HEVC 10bit 경고/변환 동작

## 비교 기준(현재 확정치)

ffmpeg-reference 축(2026-09-23, 동일 pair 계약 · 9포인트 샘플):

| fixture | PSNR(dB) | SSIM mean | 비고 |
|---|---|---|---|
| ab01_single_1080p30 | 38.90 | 0.9947 | 1080p30 10s 기본 |
| ab02_4k60_hevc | 30.58 | 0.9943 | 4K60 HEVC→1080p |
| ab07_mask_chromakey | 46.26 | 0.9997 | 320x240→1080p |
| ab10_external_disk | 38.90 | 0.9947 | =ab01 |

MovieCut 기준선(CA-12, 2026-08-27 — RTF·RSS 포함 전체 수치는
`CA12_AB_BENCHMARK_20260827.md` 참조). CapCut 출력이 확보되면 같은 표에
CapCut 열이 붙고, 소스 대비 품질 열화치(재압축·스케일 정책 차이)가
3축으로 비교된다.
