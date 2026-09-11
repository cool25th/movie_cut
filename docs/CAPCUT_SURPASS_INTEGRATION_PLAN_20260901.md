# `feat/capcut-surpass-7gaps` 선별 통합 계획

작성일: 2026-09-01  
대상: `feat/g25-inc8-app-wiring`  
소스: `feat/capcut-surpass-7gaps` (`646298e02f4819ff074132b2c21ffeba47ebb8b9`)

## 결론

`movie_cut-capcut-surpass` 폴더는 독립 프로젝트가 아니라 같은 저장소의 추가 Git worktree다. 작업 트리는 깨끗하며 폴더를 제거해도 `feat/capcut-surpass-7gaps` 브랜치와 22개 고유 커밋은 본 저장소에 보존된다.

브랜치 전체 병합이나 일괄 cherry-pick은 하지 않는다. 두 브랜치는 공통 조상 `f8c67b1` 이후 대상 383개, 소스 22개 커밋으로 갈라졌다. 가상 병합에서는 23개 파일이 양쪽에서 변경됐고, 그중 15개 파일에서 51개 내용 충돌과 4개 delete/modify 충돌이 예상된다. 현재 대상 작업 트리에도 export/compositor 관련 WIP가 있으므로 기능별로 현재 아키텍처에 다시 이식한다.

2026-09-01에 보조 worktree는 `git worktree remove`로 제거했다. 제거 후에도 소스 브랜치가 위 tip을 가리키는 것을 확인했으며, 필요하면 같은 브랜치로 worktree를 다시 만들 수 있다.

## 먼저 지킬 조건

1. 현재 작업 트리의 사용자 WIP를 버리거나 임의로 stash하지 않는다.
2. 현재 WIP가 독립 커밋으로 정리된 뒤 `codex/integrate-capcut-surpass` 같은 통합 브랜치를 최신 대상에서 만든다.
3. 각 기능은 한 커밋으로 이식하고, 해당 기능의 필터 테스트를 통과시킨 뒤 다음 기능으로 간다.
4. 소스 브랜치는 최종 통합 및 원격 백업이 끝날 때까지 삭제하지 않는다.
5. 소스 브랜치의 문서상 “완료” 표기는 현재 코드의 테스트/측정으로 재검증한 뒤에만 현재 문서에 반영한다.

## 단계별 실행

### 1단계 — 저위험 잔존 격차

1. **보컬 분리 UI 호스팅** (`cc68964`)
   - 현재 `InspectorVocalSection.swift` 구현은 있지만 선택된 오디오 클립의 Inspector에서 호출되지 않는다.
   - 현재 `InspectorPanel.selectedClipInspectorSections`의 `.audio` 분기에 섹션을 추가한다.
   - `R401InspectorContextStaticContractTests`에 오디오 전용 노출과 비오디오 미노출 계약을 추가한다.

2. **AI Assistant의 AutoColor 실분석 배선** (`e9f6703`)
   - Effects 쪽 `autoColorSelectedClip`/`autoEnhanceSelectedClip`은 현재도 `AutoColorAnalyzer`를 사용하지만, AI Assistant가 호출하는 `autoEnhance`/`autoColorCorrect`는 별도 extension에서 고정 brightness/contrast/saturation 값을 적용한다.
   - 두 Assistant 진입점을 기존 실분석 함수로 통일하고, 썸네일이 없거나 분석이 실패할 때의 사용자 메시지와 undo 단위를 보존한다.
   - 두 UI 진입점이 실제 analyzer 경로를 호출하는 계약 테스트를 복원한다.

3. **자막 편집 중 word timing 보존** (`10af50b`)
   - 현재 최초 자막 생성은 word timing을 보존하지만 split/merge 및 정렬 재생성 경로는 timing을 떨어뜨린다.
   - `SubtitleGenerator`에 split/merge/alignment 순수 함수를 현재 모델에 맞춰 이식한다.
   - split은 경계 단어를 한쪽에 정확히 배정하고, merge는 시간순 정렬·중복 경계를 처리하며, alignment는 클립 로컬 시간으로 clamp한다.
   - `SubtitleWordTimingPreservationTests`를 현재 API에 맞춰 복원한다.

4. **Mac autosave coalescing** (`9304e8b`)
   - 현재 Mac은 편집마다 별도 `Task`를 만들며, iOS에는 이미 debounce가 있다.
   - 소스 패치를 그대로 가져오면 현재의 오류 노출 계약을 잃으므로, “마지막 snapshot 우선 + 직렬 저장 + 실패 표시 + `flushAutosave` 즉시 배출”로 다시 구현한다.
   - 연속 편집 1회 저장, 저장 중 추가 편집의 최신 값 보존, 디스크 오류 표시, 종료 전 flush를 테스트한다.

5. **undo 보강 테스트 선별 이식** (`233dee7`, `7b240d4`)
   - 현재 `UndoRoundTripTests`, `UndoIntegrityTests`, 카드 문서 명령 테스트와 겹치는 항목을 먼저 제외한다.
   - 현재 커버되지 않는 명령만 추가하고, 각 테스트는 “상태가 실제로 변경됨 → undo로 정확 복원 → redo로 정확 재적용”을 확인한다.

### 2단계 — 키프레임 커스텀 베지어

대상 커밋: `18e8b74`, `eb0eba5`

- 현재 Core의 `InterpolationMode`에는 `.custom`과 제어점 모델이 없고, 현재 UI의 그래프는 기존 interpolation을 시각화한다.
- `CubicBezierControl`을 스키마 호환 기본값과 함께 추가하고, x축 역산이 수렴하지 않을 때의 결정적 fallback을 둔다.
- 현재 `KeyframeGraphMath` 및 Inspector 구조에 핸들 편집을 통합한다. 오래된 `BezierCurveEditorView`를 그대로 복사하지 않는다.
- Core 수학, Codable 구버전 로드, preview/export 동일성, undo 단위, 키보드/VoiceOver 조작을 검증한다.

### 3단계 — 10-bit HDR 경로 재구현

대상 커밋: `ac589c2`, `cdb7053`, `7ae1055`

- 현재 ProRes master 경로는 존재하지만 HDR은 8-bit SDR 프레임을 HDR로 재태깅하지 않도록 feature flag로 차단돼 있다.
- 소스의 `TenBitVideoCompositor` 아이디어만 참고하고, 현재 compositor의 adjustment layer, canvas alpha/background, motion/stabilization, 오류 전파 변경을 유지한 채 Mac/iOS 공통 색 관리 계약을 먼저 정한다.
- persisted `ExportCodec`에 master 종류를 다시 섞지 않는다. 현재의 `VideoCompressionProfile`/`profileOverride` 구조를 유지한다.
- 기존 `scripts/run_e2e_export.sh`에 실제 `pix_fmt`, bit depth, primaries, transfer, matrix 검증을 강화한다. 별도 오래된 스크립트를 복제하지 않는다.
- SDR golden/parity가 그대로 통과하고, 실제 출력이 10-bit Rec.2020 + HLG/PQ임을 확인한 뒤에만 `FeatureFlag.hdrMaster`를 연다.
- 이 단계는 현재 수정 중인 `CustomVideoCompositor.swift`, `ExportEngine.swift`, iOS compositor 및 Xcode project WIP가 정리된 후 진행한다.

### 4단계 — 현재 아키텍처 기준 감사 후 폐기/보완

1. **thermal export** (`6a58b16`)
   - 현재는 critical에서 export를 사전 거부하고 serious에서는 OS throttling에 맡긴다.
   - 프레임별 sleep을 바로 이식하지 말고, serious 상태 장편 export의 완료율·시간·온도를 측정해 이득이 있을 때만 pacing을 추가한다.

2. **iOS PlaybackEngine 및 AVAudioMix 계열** (`74b69a1`, `244de25`, `a9341a3`, `fe7bbc4`, `d78c13c`, `827e10d`)
   - 과거 `IOSPlaybackEngine`은 의도적으로 제거됐으므로 되살리지 않는다. 현재 `PreviewView`와 export가 공유하는 `IOSExportEngine.makeRenderPlan`을 확장한다.
   - 효과 및 volume/fade는 현재 경로가 이미 대체했다.
   - proxy/thermal은 현재 plan이 `originalURL`만 소비하므로, preview 전용 source policy와 thermal observer를 현 구조에 추가한다. export는 항상 원본을 쓰도록 mode를 명시한다.
   - ducking/EQ는 현재 `AudioMixEntry`가 volume/fade만 처리하므로, placed-span 시간축과 현재 audio graph/DSP 계약에 맞춰 구현한다. 구형 `AudioMixBuilder`나 EQ tap을 복원하지 않는다.
   - 각 항목은 preview/export parity와 실제 오디오 측정 테스트를 추가한 뒤 완료로 판정한다.

3. **flatten 캐시 최적화** (`831578e`)
   - 현재 `FlattenedTimelineCache.update`는 변경 통지마다 안전하게 다시 계산한다.
   - 소스 브랜치의 digest는 effect, opacity, color, volume, canvas 등 모든 렌더 의미를 포함하지 않아 그대로 쓰면 stale snapshot을 재사용할 수 있다.
   - 원 패치는 폐기한다. 전체 렌더 의미를 포괄하는 fingerprint를 별도로 설계하고, fingerprint 계산 비용이 flatten보다 충분히 낮다는 반복 측정이 있을 때만 short-circuit를 다시 추진한다.

4. **문서 전용 및 브랜치 정리 변경**
   - `4418fc5`, `6ac0e97`의 오래된 성능/README 상태표는 이식하지 않는다.
   - 브랜치 전용 정리 커밋 `646298e`는 현재 구조에 적용하지 않는다.

## 소스 커밋 처리표

| 커밋 | 처리 |
|---|---|
| `cc68964` | 현재 Inspector 구조에 재이식 |
| `10af50b` | 현재 자막 API에 재이식 |
| `ac589c2`, `cdb7053`, `7ae1055` | 현재 export/compositor 구조로 재설계 |
| `6a58b16` | 측정 후 조건부 이식 |
| `831578e` | 불완전 digest 패치 폐기; 완전한 fingerprint를 새로 설계할 때만 재추진 |
| `233dee7`, `7b240d4` | 중복 제거 후 테스트만 선별 이식 |
| `9304e8b` | 오류 노출·flush를 보존하도록 재작성 |
| `18e8b74`, `eb0eba5` | 현재 keyframe graph에 재이식 |
| `e9f6703` | AI Assistant의 고정값 stub을 실분석 경로로 재배선 |
| `74b69a1`, `244de25`, `a9341a3`, `fe7bbc4`, `d78c13c`, `827e10d` | 구형 엔진은 폐기; 현 render-plan에 proxy/thermal·ducking/EQ의 미대체 의미만 재구현 |
| `4418fc5`, `6ac0e97`, `646298e` | 오래된 문서/브랜치 정리 — 제외 |

## 검증 게이트

각 단계의 필터 테스트 후 다음 순서로 승격한다.

1. `swift test` 전체 통과.
2. Mac 앱/테스트와 iOS 앱/테스트 빌드 통과.
3. `scripts/verify_gate.sh` 통과.
4. 렌더·오디오·HDR 변경은 `scripts/run_e2e_export.sh`와 preview/export parity 통과.
5. 성능 변경은 동일 fixture/동일 빌드로 전후 반복 측정하고 결과를 `PERF_BASELINE_20260622.md`에 기록.
6. `git range-diff`와 경로별 비교로 소스 22개 커밋의 “이식/대체/의도적 폐기”가 모두 처리됐는지 최종 감사.

## 완료 조건

- 위 처리표에 미판정 커밋이 없다.
- 현재 브랜치의 사용자 WIP가 손실되지 않았다.
- 모든 필수 게이트가 통과하고 문서 상태가 실제 코드와 일치한다.
- 통합 결과가 원격에 백업된 뒤에만 `feat/capcut-surpass-7gaps` 로컬 브랜치 삭제 여부를 별도로 결정한다.
