# MovieCut vs CapCut 갭 분석 V13 — 배선 격차 재설정 — 2026-07-29

> **[상태: 대체됨 — 역사 기록]** V13의 G-ID/U-ID 격차 항목은 `.kiro/specs/capcut-parity-and-bugfix/` 스펙(2026-07-31)의 요구사항으로 재설계·실행됐다. 현역 격차 판정은 그 스펙의 `requirements.md`와 `docs/README.md`를 본다. 이 파일은 역사 기록으로 제자리에 둔다.
>
> 작성일: 2026-07-29 / 브랜치: `main` (기준 커밋: `0ecdc6f`)
> 기준선: V12 `docs/archive/GAP_ANALYSIS_V12_FUNC_UI_20260706.md` (기준 커밋 `89e3795`) — **델타 62 커밋**
> 판정 기준: `docs/CAPCUT_BENCHMARK_STANDARD.md` v1.6 (B-ID)
> 원천 스펙: `docs/CAPCUT_SURPASS_SPEC_20260703.md`
> 이 감사의 실측: 빌드 3종 + 전체 테스트 1회 + repo-wide grep 실사. **코드 수정 없음.**

---

## 0. 한 줄 요약

V12는 "기능이 없다"(이미지 파이프라인 부재)를 P0로 잡았고 그것은 상환됐다. **V13이 발견한 격차는 성격이 다르다: 기능이 Core에 구현돼 있는데 화면에 연결되지 않은 것이 주류다.** 미배선 Core 서브시스템 **1,279줄**(협업·AI편집·보컬분리·스타일전이·버전히스토리)이 App에서 **호출 0회**이고, 워드 캡션 타이밍·프록시·현지화는 데이터/래핑까지만 있고 소비 지점이 없다. 동시에 7/28 핵심 편집 수리가 드러낸 사실 — **메인 Preview가 프로젝트 합성을 쓰지 않고 있었다** — 은 V1~V12의 `=` 판정 상당수가 동작 확인 없이 내려졌음을 뜻한다. 따라서 V13은 우선순위를 **"구현량 추가"에서 "이미 만든 것을 화면에 잇기 + 판정을 동작으로 재확인"** 으로 재설정한다.

---

## 1. 검증된 기준선 (2026-07-29 실측)

| 검증 | 명령 | 결과 |
|------|------|------|
| Core 빌드 | `swift build` | ✅ 성공 |
| 전체 테스트 | `swift test` | ✅ 984 tests / 162 suites 통과, 18.6s |
| Mac 앱 빌드 | `xcodebuild -scheme MovieCutMac` | ✅ BUILD SUCCEEDED |
| **iOS 앱 빌드** | `xcodebuild -scheme MovieCutiOS` | ❌ **불가** — `iOS 26.5 is not installed` |
| 린트 | `swiftlint lint` | ⚠️ 1,022건 (error 414 / warning 608), 비블로킹 |

**⚠️ 984개 통과를 기능 증거로 읽지 말 것.** 테스트 파일 137개 중 **85개(62%)가 StaticContract**(소스 문자열 존재 검사)이고 부정 단언이 248건이다. 통과 수치의 상당 부분은 동작 신호가 아니다. (`docs/STATIC_CONTRACT_TRIAGE_20260728.md`)

---

## 2. V12 이후 판정 변화

### 2-1. 상환된 것

| 항목 | V12 판정 | 현재 | 근거 |
|------|---------|------|------|
| G-15 이미지 클립 파이프라인 | ❌ P0 (사진 재생/export 불가) | ✅ | `ImageVideoRenderService`가 PlaybackEngine·ExportEngine·PreviewPanel 3곳에 배선됨 |
| G-16 타임라인 스크럽 | 🟡 | ✅ | `TimelineView.swift:475 scrubTimeline(atLocalX:phase:)` |
| G-17 클립 복사/붙여넣기 | ✅ | ✅ | `CopyClipCommand` / `PasteClipsCommand` |
| G-04 필름스트립 | ✅ | ✅ | `FilmstripPlanning` / `ThumbnailGenerator` / `TimelineFilmstripStore` |
| Track.isLocked 미배선 (V*의 dead field 전례) | ❌ | ✅ 해소 | Core 3회 / App 2파일 배선 확인 |

### 2-2. 새로 드러난 것 — 판정 신뢰도 자체의 문제

7/28 핵심 편집 수리(`docs/CAPCUT_CORE_EDITING_REPAIR_HANDOFF_20260727.md`)가 확인한 사실:

- **메인 Preview가 프로젝트 합성 경로를 쓰지 않고 선택 원본 asset을 직접 재생하고 있었다** (`b398563`에서 수리).
- magnetic compaction이 모든 트랙에 무차별 적용됐다 (`1fa836c`).
- 배속/ramp의 timeline↔source 시간 일관성이 깨져 있었다 (`269d50a`, `dfde012`, `1d8882a`, `0115e6c`).

즉 **"타임라인에서 본 것과 export 결과가 다른"** 상태였고, 그 동안 V1~V12는 B-F2/B-F4에 `=` 판정을 내리고 있었다. **이것이 이번 감사의 가장 중요한 발견이다: 격차 목록보다 판정 방법이 문제였다.**

→ **P0 부채로 기록**: `=` 판정이 붙은 모든 B-ID는 preview+export 동시 증거로 재확인이 필요하다. 본 문서 §6에 재확인 큐를 둔다.

---

## 3. 격차 3분류

### 3-A. 능가 (⬆ — 지킬 것)

| B-ID | 내용 | 근거 |
|------|------|------|
| B-F4.5 | 스코프(파형/벡터/히스토그램) — CapCut 부재 | `ScopeAnalyzer` |
| B-F4.6 | ProRes / 10-bit HDR export — CapCut 부재 | `MOVIECUT_UITEST_EXPORT_PRORES` / `_HDR` 게이트 |
| B-F5.4 | 5밴드 실 EQ — CapCut 데스크톱 멀티밴드 EQ 부재 | `MOVIECUT_UITEST_EQ_PRESET` |
| B-F6.4 | 온디바이스 처리 — CapCut은 클라우드 업로드 필수 | Vision/Speech 온디바이스 |
| B-U8 | 로그인 불필요·무제한·오프라인 — CapCut은 로그인+페이월 | 구조적 |

### 3-B. 배선 격차 (**V13 신규 분류** — Core에 있으나 화면에 없음)

가장 비용 대비 효과가 큰 구간이다. **새로 만들 필요가 없고 이어주기만 하면 된다.**

| 항목 | Core | App | 실측 |
|------|------|-----|------|
| **B-F3.3 워드 캡션(karaoke)** | 4파일 (`SubtitleGenerator`, `TranscriptionTypes`, `SpeechTranscriptionProvider`, `TextClipContent`) | **0파일** | 워드 타이밍을 STT가 뽑아 모델에 저장하지만 렌더/편집 UI가 소비하지 않음 |
| **B-I7 프록시 소비** | `ProxyInfo` + `ThumbnailGenerator` + `MediaLibraryPanel` | PlaybackEngine·ExportEngine **0회** | 프록시가 생성만 되고 재생에 쓰이지 않음 |
| **B-U6 현지화** | — | `NSLocalizedString` 8파일 | **`.lproj` / `Localizable.strings` / `.xcstrings` 파일 0개** — 래핑만 됐고 번역 카탈로그가 없어 실질 영어 전용 |

### 3-C. 미배선 서브시스템 — **1,279줄, App 호출 0회**

| 파일 | 줄수 | 대응 B-ID |
|------|------|----------|
| `Cloud/CollaborationService.swift` | 546 | (CapCut 대비 항목 아님 — 자체 로드맵) |
| `AI/ClaudeEditingProvider.swift` | 265 | B-F6.2 AI Auto-Edit |
| `Analysis/StyleTransferProvider.swift` | 174 | B-F4.2 필터 |
| `Audio/VocalSeparationService.swift` | 121 | **B-F5.2 보컬 분리** |
| `AI/AIEditingProvider.swift` | 103 | B-F6.2 |
| `Cloud/VersionHistory.swift` | 70 | (자체 로드맵) |

`VocalSeparationService`는 V12 이전부터 dead code 전례로 지목됐고 **여전히 죽어 있다.** `Analysis/BackgroundRemovalProvider`도 App 호출 0회지만, 배경 제거 기능 자체는 `InspectorEffectsSection.swift:351` 토글 + `CustomVideoCompositor.swift:528 applyPersonSegmentation` 경로로 동작한다 — **프로바이더만 죽은 위양성**이므로 삭제 후보로 분류한다.

### 3-D. 열위 (⬇/❌ — 실제로 만들어야 하는 것)

| B-ID | CapCut | MovieCut 실측 | 판정 |
|------|--------|--------------|------|
| **B-L2 홈 화면** | 프로젝트 목록(썸네일)·새 프로젝트·템플릿 진입 | **0파일** — `WindowGroup`이 곧장 편집기 | ❌ |
| **B-F4.4 블렌딩 모드** | Multiply/Screen/Overlay/Soft Light 속성 드롭다운 | 사용자 노출 **0** — `CISoftLightBlendMode` 등은 필터 내부 구현명일 뿐 | ❌ |
| **B-F2.3 컴파운드 클립** | 중첩 시퀀스 | **0파일** | ❌ |
| **B-I8 프리뷰 품질 선택** | Performance Priority / 360p·540p 수동 | **0파일** | ❌ |
| **B-F3.2 자막 export** | SRT·VTT·ASS | SRT만 (`WebVTT`/`AdvancedSubStation` 0파일) | ⬇ |
| **B-F4.2/4.3 볼륨** | 필터·이펙트·전환 수백 종 | **전환 12 / 이펙트 18 / 텍스트템플릿 14 / 스티커 22 / SFX 12** | ⬇ (전략상 큐레이션) |
| **B-F5.1 음악 라이브러리** | 상용 내장 | SFX 12개만 | ⬇ |
| **B-F2.4 속도 커브 프리셋** | 6종 프리셋 UI | `SpeedCurvePreset` 0파일 — 램프 엔진은 있으나 프리셋 UI 없음 | ⬇ |

---

## 4. 플랫폼 격차 (B-ID 밖 — 그러나 가장 큼)

**iOS 8,706줄이 이 호스트에서 컴파일조차 되지 않는다.** CapCut의 주 사용처가 모바일임을 감안하면 이것은 기능 격차 이전의 문제다.

| 항목 | 상태 |
|------|------|
| iOS 빌드 | ❌ iOS 26.5 플랫폼 미설치 |
| iOS 테스트 타겟 | ❌ 없음 (`project.yml`에 `MovieCutiOSUITests` 0건) |
| iOS harness | ❌ 없음 (`MOVIECUT_UITEST` iOS 소스에 0건) |
| iOS two-source 전환 | ❌ `TransitionPixelProcessor` 호출 0회 |
| iOS chroma/segmentation | ⬇ shared processor 미위임 (inline 재구현) |
| CI iOS 단계 | `continue-on-error` — 사실상 무검증 |

상세 및 착수 프롬프트: `docs/NEXT_SESSION_WORKORDER_20260729.md` Track 2 (W4~W7).

---

## 5. 채점 시트 (B-ID, V13 갱신)

> V12(2026-07-06) 스냅샷 대비 갱신. 변화만 굵게.

| 영역 | ⬆ | = | ⬇ | ❌ | V12 대비 변화 |
|---|---|---|---|---|---|
| B-F1 미디어 | 1 | **5** | 1 (F1.4 실기기) | — | **F1.2/F1.3 = 도달** (G-15 상환) |
| B-F2 타임라인 | — | 5 | 1 (F2.4 커브 프리셋 UI) | F2.3 컴파운드 | `=` 5건은 **preview+export 재확인 필요**(§2-2) |
| B-F3 텍스트·자막 | 후보 F3.1 | 2 | 2 (F3.2 VTT/ASS, F3.4 볼륨) | **F3.3 워드 캡션** | F3.3을 **배선 격차로 재분류**(데이터는 있음) |
| B-F4 색·효과 | F4.5 / F4.6 | 2 | F4.1(UI) / F4.2 / F4.3 | **F4.4 블렌딩** | 변화 없음 |
| B-F5 오디오 | F5.4 | 2 | F5.1 | F5.2 보컬분리 | F5.2 = **dead code 121줄로 확인** |
| B-F6 AI | F6.4 | 1 | F6.2 | F6.3 | F6.2 = **미배선 368줄로 확인** |
| B-L 화면 | — | 4 | 2 (L3/L7) | **L2 홈** | 변화 없음 |
| B-I 동작 | — | 3 | 3 (I1/I4/**I7 프록시 소비 0회 확인**) | I8 | I7 근거 확정 |
| B-U 사용성 | U8 | 3 | 2 (U3/U5) | **U6 현지화** | U6 = **번역 카탈로그 0개로 확인**(래핑만 존재) |

---

## 6. P0 부채 — 판정 재확인 큐

§2-2에 따라, 다음은 **새 기능이 아니라 기존 `=` 판정의 동작 재확인**이다.

| 순위 | 대상 | 확인 방법 |
|---|---|---|
| 1 | B-F2.1 split/trim/move/delete/ripple | preview 캡처와 export 프레임을 **같은 timestamp에서** 비교 |
| 2 | B-F2.4 속도/램프/역재생/freeze | 동일 |
| 3 | B-F4.1 색보정 체인 | 골든 픽셀 (`GoldenPixelHarness` 패턴) |
| 4 | B-I6 undo 무결성 | 파괴적 작업 후 undo 왕복 |

`scripts/verify_preview_export_parity.py`에 **duration 비교가 없다**(frame MAD만) — 재확인 전에 보강 필요. `docs/NEXT_SESSION_WORKORDER_20260729.md` W7과 동일 항목.

---

## 7. 권장 실행 순서

| 슬롯 | 작업 | 근거 |
|---|---|---|
| **1** | **배선 격차 3건**(3-B): 워드 캡션 렌더, 프록시 소비, 현지화 카탈로그 | **이미 만든 것을 잇는 것** — 신규 구현 대비 비용 최소, 체감 최대 |
| 2 | 미배선 1,279줄 처리 결정(3-C): 배선 vs 삭제 | 죽은 채로 두면 유지비만 발생. `VocalSeparationService`는 B-F5.2 격차와 직결 |
| 3 | 판정 재확인 큐(§6) | 격차 목록의 신뢰도 복구 |
| 4 | **B-L2 홈 화면**(U-01) | 유일한 구조적 IA 부재 — 프로젝트 관리 동선 자체가 없음 |
| 5 | B-F4.4 블렌딩 모드 | 확정 격차, 오버레이 합성의 기본기 |
| 병행 | StaticContract 정리 / 린트 베이스라인 | `docs/NEXT_SESSION_WORKORDER_20260729.md` W2/W3 |
| 차단됨 | iOS 파리티 W4~W7 | **사용자 조치 필요**: iOS 26.5 플랫폼 설치 |

---

## 8. 실사 증거 요약

- 빌드/테스트: `swift build` ✅ / `swift test` 984 pass 18.6s / Mac `xcodebuild` ✅ / iOS ❌ 플랫폼 미설치
- 배선 격차: `wordTiming` Core 4파일·App 0 / `proxy` PlaybackEngine·ExportEngine 각 0회 / `.lproj`·`.xcstrings` 0개
- 미배선 서브시스템: 6파일 1,279줄, App 호출 0회 (`CollaborationService` 546, `ClaudeEditingProvider` 265, `StyleTransferProvider` 174, `VocalSeparationService` 121, `AIEditingProvider` 103, `VersionHistory` 70)
- 부재 확정: 홈 화면·컴파운드 클립·프리뷰 품질·VTT/ASS·속도 커브 프리셋 각 **0파일**
- 블렌딩: `blendMode` 매치 2건이 전부 `CISoftLightBlendMode`/`CIOverlayBlendMode` 내부 필터명 — 사용자 노출 없음
- 볼륨: 전환 12 / 이펙트 18 / 텍스트템플릿 14 / 스티커 22 / SFX 12
- 위양성 처리: `BackgroundRemovalProvider`는 App 0회지만 기능은 `InspectorEffectsSection.swift:351` + `CustomVideoCompositor.swift:528` 경로로 동작 — 프로바이더만 삭제 후보
- 검증 부채: StaticContract 85/137 파일(62%), 부정 단언 248건
