# 구현 계획 — CapCut 파리티 및 버그 수정

`design.md` §7의 순서를 실행 단위로 쪼갠 것이다. 각 작업은 코드를 쓰거나 검증을 실행하는 단위이며, 완료 판정은 실행 산출물로만 한다.

**모든 작업에 적용되는 규율** (`design.md` §1, §2)
- 새 StaticContract를 추가하지 않는다. 검증은 동작 테스트·골든 픽셀·하니스 실행으로 한다.
- 보고하는 모든 숫자는 그 세션에서 직접 실행한 명령의 출력이어야 한다.
- 신규 골든 테스트는 `assertRendererFunctional()`을 최상단에서 호출한다.
- 새 코드는 `EditorViewModel.swift`가 아니라 별도 파일 또는 별도 extension 파일에 둔다.
- 네트워크 entitlement를 추가하지 않는다.
- 검증하지 못한 항목은 "미검증"으로 분리해 보고한다.

---

## 0. 검증 인프라 실존 확인

- [x] 0.1 골든 픽셀 하니스가 이 호스트에서 실제로 도는지 확인
  - `GoldenPixel.assertRendererFunctional()`을 포함한 기존 골든 테스트를 실행해 sentinel이 통과하는지 확인
  - skip이 아니라 실제 실행됐음을 출력으로 확인
  - 실패하면 그 사실을 기록하고, 인프라 수리를 작업 8(요구사항 15) 범위로 승격
  - _Requirements: 4, 15_

- [x] 0.2 접근성 레이블을 읽는 XCUITest 경로가 이 호스트에서 완주하는지 확인
  - `App/MovieCutMacUITests/`의 기존 테스트를 실행
  - `CardEditorUITests`의 `waitForLabel` 헬퍼가 `XCUIElement.label`을 실제로 읽어오는지 확인
  - `MOVIECUT_UITEST_QUIT`을 켜면 접근성 핸드셰이크가 깨지는 제약(`UnsavedChangesGuardUITests` 주석)을 재확인
  - _Requirements: 1_

- [x] 0.3 기준선 3종 측정 후 기록
  - `swift build` / `swift test` / `xcodebuild -scheme MovieCutMac` 실행 출력을 그대로 기록
  - 이후 모든 작업이 이 수치와 비교된다. 문서의 과거 수치를 인용하지 않는다
  - _Requirements: 15_

---

## 1. 접근성 레이블 현지화 결함 수정 (요구사항 1)

- [x] 1.1 한국어 `NSLocalizedString` 키 전수 조사 및 대조 스크립트 작성
  - 키가 한국어인 호출부를 전수 수집 (`TimelineView.swift:788, 941, 950` 포함)
  - 코드 사용 키 집합 ↔ `Localizable.xcstrings` 키 집합을 대조하는 스크립트를 만든다. 손으로 세지 않는다
  - 대조 결과(사용 키 수 / 카탈로그 키 수 / 불일치 목록)를 출력으로 기록
  - _Requirements: 1.3, 1.4_

- [x] 1.2 한국어 키를 영어 키로 교체하고 카탈로그 재정렬
  - 호출부의 키를 영어로 바꾸고 `Localizable.xcstrings`의 키를 그에 맞춰 재정렬
  - 한국어(`ko`) 값은 기존 문구를 그대로 보존한다
  - 1.1의 대조 스크립트로 누락 0건 확인
  - _Requirements: 1.1, 1.2, 1.3_

- [x] 1.3 깨지는 StaticContract 처리
  - `R504MainVideoTrackStaticContractTests`, `R503TrackHeaderStaticContractTests`, `UIUXAccessibilityRegressionStaticContractTests`의 한국어 키 단언을 건별로 판정
  - 결함 고정 성격은 제거, 접근성 회귀 방지 목적은 XCUITest로 승격
  - 건별 판정과 근거 한 줄을 기록. 파일 단위 일괄 삭제 금지
  - _Requirements: 1.1, 15.1, 15.2_

- [x] 1.4 영어 로케일 접근성 레이블 검증 ✅
  - XCUITest로 영어 로케일에서 접근성 레이블에 한글이 0건임을 확인
  - `MOVIECUT_UITEST_QUIT`을 켜지 않는다 (접근성 핸드셰이크 제약)
  - 한국어 로케일 문구가 변하지 않았음을 함께 확인
  - **실행 결과:** `LocalizedAccessibilityLabelUITests` 3건 전부 통과 (27.2초)
    - `testEnglishLocaleTimelineSurfaceExposesNoHangul` ✅ (elements=300, labels=102, 한글 0건)
    - `testEnglishLocaleCardSurfaceExposesNoHangul` ✅ (elements=221, labels=40, 한글 0건)
    - `testKoreanLocaleKeepsCatalogKoreanCopy` ✅ (영어 leak 0건, hangulTexts=151)
  - **수정 내용:** `InspectorPanel.swift`의 `ProjectOverviewSummaryStrip` title 3건을 `NSLocalizedString`로 래핑. 카탈로그에 Canvas(캔버스), Clips(클립) 키 추가.
  - **미해결 잔여:** "Fit Timeline" 등 `timelineToolbarIconButton`의 title은 카탈로그에 키가 없어 한국어 로케일에서 영어로 표시됨. 단 카탈로그에 키 자체가 부재하므로 `isUntranslatedEnglish` 검사에 걸리지 않음. 향후 현지화 정리 항목으로 분리.
  - _Requirements: 1.1, 1.2_

---

## 2. 파리티 기준선 확립 (요구사항 2a) — 작업 5의 게이트

- [x] 2.1 하니스에 합성 길이 리포트 추가
  - `UITestHarness`가 preview 덤프와 함께 합성 duration을 출력하도록 한다
  - 기존 `parity_done` / `error=none` 키=값 리포트 형식을 따른다
  - **구현/실행 증거:** parity 합성이 준비된 직후 `playbackEngine.duration`을 캡처해 `duration=%.3f`, `currentProject.timeline.frameRate`를 `frame_rate=%.3f`로 기록한다. 실제 2x split 하니스 리포트에서 `duration=1.000 frame_rate=30.000 composition_error=none error=none` 확인.
  - _Requirements: 2.3_

- [x] 2.2 파리티 스크립트에 `--expect-duration` 추가
  - `scripts/verify_preview_export_parity.py`에 옵션을 추가하고, 주어지면 `probe_duration()` 결과와 1프레임(프로젝트 frameRate) 이내인지 확인
  - 옵션이 없으면 현행 동작을 유지해 기존 호출부가 회귀하지 않게 한다
  - **구현/실행 증거:** `--frame-rate`로 프로젝트 fps를 받아 허용 범위를 `1 / fps`로 계산한다. 옵션 미지정 PASS, 30fps에서 0.020초 차이 PASS, 0.040초 차이 FAIL을 확인했다. `run_core_editing_parity.sh`는 하니스의 `duration`/`frame_rate`를 파싱해 검증기에 전달한다.
  - **실행 안정화:** Xcode CLI 전용 DerivedData, LaunchServices `--env` 실행, 앱 샌드박스 컨테이너 내 fixture/산출물 staging을 사용해 entitlement 완화 없이 실제 앱 하니스를 실행한다.
  - _Requirements: 2.3_

- [x] 2.3 기존 7종 시나리오 실행 후 기준선 기록
  - `scripts/run_core_editing_parity.sh`를 그대로 실행. **커버리지를 늘리지 않는다**
  - 시나리오별 실측 MAD와 duration 결과를 표로 기록
  - 전환 시나리오의 헤드리스 제약(`buildComposition` 정지)을 제약으로 명시 기록하고 해결 대상에서 제외
  - **2026-07-31 1차 실행:** 5/7 PASS. split_2x(MAD 0.40, duration 1.000/1.000), speed_ramp(0.45, 1.400/1.383 — 30fps 1프레임 이내), bgm(0.45, 5.500/5.500), image_video_mixed(0.70, 7.000/7.000), normal_delete(0.45, 2.000/2.000). text_overlay와 filter_mask_subtitle은 `scenarios_applied` 직후 하니스가 종료되어 preview/export 측정 전 FAIL; 2.5에서 원인을 진단하고 수리했다.
  - **2026-07-31 최종 실행 (`/tmp/moviecut-parity-final.log`): 7/7 PASS.**

    | 시나리오 | MAD | preview duration | export duration | duration 판정 |
    |---|---:|---:|---:|---|
    | split_2x | 0.40 | 1.000s | 1.000s | PASS |
    | speed_ramp | 0.45 | 1.383s | 1.400s | PASS (차이 0.017s < 30fps 1프레임) |
    | text_overlay | 0.62 | 2.000s | 2.000s | PASS |
    | bgm | 0.45 | 5.500s | 5.500s | PASS |
    | filter_mask_subtitle | 0.62 | 2.000s | 2.000s | PASS |
    | image_video_mixed | 0.70 | 7.000s | 7.000s | PASS |
    | normal_delete | 0.45 | 2.000s | 2.000s | PASS |

  - 기존 전환 시나리오는 헤드리스 `buildComposition` 정지 제약 때문에 이 7종 기준선과 수리 범위에서 계속 제외한다.
  - _Requirements: 2.1, 2.2, 2.5_

- [x] 2.4 허용 오차 정책 확정
  - 최종 실측 MAD 범위는 0.40~0.70이고 최댓값은 image_video_mixed의 0.70이다.
  - 근거 없이 사용하던 전 시나리오 MAD 허용치 25.0을 **2.0**으로 낮췄다. 이는 실측 최댓값의 약 2.9배 여유를 두면서도 기존 25.0보다 12.5배 엄격하고 스크립트 기본값 8.0보다 4배 엄격하다.
  - 시나리오별 상향 예외는 없으며 7종 모두 2.0을 사용한다. 인코딩·스케일링의 작은 플랫폼 변동은 허용하되 의미 있는 preview/export 렌더 분기는 검출하는 정책이다.
  - _Requirements: 2.5_

- [x] 2.5 기준선이 red인 항목 처리
  - 최초 red 2건의 crash report(`MovieCutMac-2026-07-31-115247.ips`, `MovieCutMac-2026-07-31-115254.ips`)에서 parity 하니스의 빠른 mutation 중 SwiftUI/AppKit 레이아웃이 충돌하는 공통 원인을 확인했다. DEBUG parity 환경에서는 전체 편집기 surface와 toolbar/export sheet를 렌더하지 않는 blank surface로 최소화했다.
  - UI crash 제거 후 두 시나리오가 `rebuildPreviewComposition`에서 정지했다. 일반 텍스트 preview만 `AVVideoCompositionCoreAnimationTool`을 사용하고 export는 공유 `TextOverlayPixelProcessor` custom compositor를 사용하던 구현 분기가 원인이었다.
  - 작은 범위 수리로 일반 텍스트 preview를 export와 동일한 custom compositor 경로에 연결했다. sticker와 legacy Apple Color Emoji 경로는 회귀 위험을 피하기 위해 기존 Core Animation 경로를 유지했다.
  - custom compositor 첫 프레임이 nil이 되는 문제는 `snapshotFrame(at:)`에서 exact target seek 완료를 기다리고 item-time pixel buffer를 최대 2초 polling하도록 보완했다.
  - 관련 `TextOverlayPixelProcessorTests` 14건/2 suites PASS, 최종 7종 파리티 7/7 PASS(`RESULT: ALL PARITY SCENARIOS PASSED`)로 별도 대형 작업 승격 없이 종료했다.
  - _Requirements: 2.1, 2.2_

---

## 3. 미배선 서브시스템 정리 및 보컬 분리 배선 (요구사항 10, 9)

- [~] 3.1 삭제 전 참조 상태 grep 재측정
  - `ClaudeEditingProvider`, `StyleTransferProvider`, `CollaborationService`, `VersionHistory`, `AIEditingProvider`, `BackgroundRemovalProvider` 각각의 현재 App 참조 수를 측정
  - `requirements.md` 요구사항 10의 결정 표와 대조. 불일치가 있으면 표를 갱신하고 결정을 재검토
  - _Requirements: 10.1_

- [~] 3.2 `BackgroundRemovalProvider` 삭제 전 기능 무회귀 확인
  - 배경 제거 기능이 `PersonSegmentationCompositor` 경로로 여전히 동작함을 먼저 보인다
  - 위양성 판정 근거를 기록해 다음 감사에서 재등재되지 않게 한다
  - _Requirements: 10.4, 10.5_

- [~] 3.3 삭제 5건 실행
  - `ClaudeEditingProvider`(+`URLSessionClaudeTransport`), `StyleTransferProvider`, `CollaborationService`, `VersionHistory`, `BackgroundRemovalProvider` 제거
  - 그것만을 대상으로 하던 테스트를 함께 제거
  - 삭제 후 빌드와 전체 테스트 green 확인, 테스트 수 감소를 실측으로 기록
  - 삭제로 새 CapCut 격차가 생기지 않았음을 확인
  - _Requirements: 10.2, 10.5_

- [~] 3.4 `AIEditingProvider` 프로토콜 경유로 어시스턴트 UI 배선
  - `RuleBasedEditingProvider`가 기존 `AssistantCommandParser` → `AssistantIntent` 경로를 감싸도록 연결
  - 오프라인 규칙 기반 경로로 실제 편집 의도가 타임라인에 적용되는 것을 동작 테스트로 확인
  - 네트워크 entitlement를 요구하지 않음을 확인
  - _Requirements: 10.3, 10.4_

- [~] 3.5 `VocalSeparationRenderer` 구현 (App 계층)
  - `AVAudioFile` 읽기 → 블록 단위 `CenterChannelVocalSeparator` 처리 → 파일 기록
  - `NoiseReductionService` 배선 패턴을 따른다
  - 모노 입력은 명시적 오류로 실패시킨다 (무처리 통과 금지)
  - _Requirements: 9.1, 9.4_

- [~] 3.6 보컬 분리 UI + 명령 배선
  - Inspector에 보컬 제거 / 센터 분리 + 강도 조작을 추가
  - 기존 `SetClipSourceAssetCommand`로 소스를 교체해 단일 undo 단위로 만든다
  - _Requirements: 9.1, 9.3_

- [~] 3.7 보컬 분리 오디오 측정 검증
  - 센터 팬 / 사이드 팬 성분을 구분한 fixture 생성
  - 센터 에너지 감소와 사이드 유지를 수치로 확인. 문자열 검사로 대체 금지
  - preview와 export 양쪽에서 결과가 반영됨을 확인
  - _Requirements: 9.2, 9.5_

---

## 4. 독립 기능 3종 (요구사항 3, 5, 6)

- [~] 4.1 `SecurityScopedAccess`에 URL 수준 오버로드 추가
  - `resolveBookmark` / `beginScope` / `endScope`의 URL 오버로드를 추가하고 기존 `MediaAsset` 버전이 그것을 호출하도록 리팩터
  - bookmark 처리 경로를 복제하지 않는다 — 이 타입이 라이프사이클의 단일 소유자라는 성질을 유지
  - _Requirements: 3.5_

- [~] 4.2 `RecentProjectsStore` 구현
  - Application Support JSON. 항목: 프로젝트 URL의 security-scoped bookmark, 이름, 수정 시각, 길이, 썸네일 경로
  - upsert / 정렬 / 누락 파일 판정을 동작 테스트로 검증
  - _Requirements: 3.1, 3.3, 3.4, 3.5_

- [~] 4.3 `AppStage` 전이 로직을 테스트 가능한 타입으로 분리
  - 홈 표시 여부, dirty 시 전이 차단, 하니스 게이트(`MOVIECUT_UITEST` / `MOVIECUT_BOOTSTRAP_PROJECT`) 판정을 뷰에서 분리
  - 전이·게이트·dirty 분기를 **단위 테스트**로 덮는다. 하니스가 홈을 우회하므로 이것이 유일한 커버리지다
  - _Requirements: 3.2, 3.6, 3.7_

- [~] 4.4 `HomeView` 구현 및 `WindowGroup` 분기
  - 카드 그리드(썸네일·이름·수정 시각·길이), 새 프로젝트 / 열기, 누락 파일 구분 표시 + 제거 수단
  - 저장되지 않은 변경이 있을 때 편집기 → 홈 전환 시 저장 확인. `applicationShouldTerminate`의 3버튼 정책을 따른다
  - 썸네일은 기존 `ThumbnailGenerator`로 저장 시점에 기록
  - _Requirements: 3.1, 3.2, 3.4, 3.7_

- [~] 4.5 홈 경유 경로 검증
  - 게이트 환경변수를 켜지 않고 홈을 거쳐 편집기에 도달하는 XCUITest 1건 추가
  - 게이트를 켠 기존 E2E가 회귀하지 않음을 확인
  - 샌드박스에서 앱 완전 종료 후 재실행 → 최근 목록에서 프로젝트 열기 성공을 실행 증거로 확인
  - _Requirements: 3.5, 3.6_

- [~] 4.6 `PreviewQuality` 모델 + 프리뷰 렌더 해상도 적용
  - `PlaybackSettings`에 `previewQuality` 추가 (`String` raw value enum, 기본 `.full`, `decodeIfPresent ?? 기본값`)
  - `currentSchemaVersion`을 건드리지 않는다 (작업 6에서 일괄 처리)
  - `PlaybackEngine`의 렌더 해상도에만 적용. `ExportEngine`은 `project.canvas`를 쓰므로 export 해상도 불변임을 확인
  - _Requirements: 5.1, 5.2, 5.3_

- [~] 4.7 화질 저하 원인 표시 우선순위 구현
  - 우선순위: 열 강등 > 수동 프록시 > 수동 프리뷰 품질. 배지는 단일 표시
  - 동시에 걸린 원인 전체는 접근성 레이블 / 툴팁 문자열에 담는다. 아이콘을 겹쳐 그리지 않는다
  - 우선순위 결정을 Core 순수 함수로 두고 조합 케이스를 단위 테스트 (`ProxyBadgeState.resolve` 확장)
  - _Requirements: 5.4_

- [~] 4.8 WebVTT / ASS 자막 직렬화 구현
  - `SubtitleDocument.swift`에 `vttString(from:)` / `assString(from:)` 추가
  - WebVTT: `WEBVTT` 헤더 + `HH:MM:SS.mmm` / ASS: `[Script Info]`·`[V4+ Styles]`·`[Events]` + `H:MM:SS.cc`
  - **스코프: 텍스트와 타이밍만.** ASS는 단일 기본 스타일 하나만 쓰고 클립별 스타일 매핑과 `\k` 태그는 하지 않는다
  - `srtString`은 손대지 않는다
  - _Requirements: 6.1, 6.2, 6.3, 6.4_

- [~] 4.9 자막 export UI 확장 및 검증
  - `AutoSubtitlesView.exportSRT()`를 포맷 선택으로 확장. `NSSavePanel` 확장자가 선택에 따라 바뀌게 한다
  - 생성된 `.vtt` / `.ass`를 실제로 파싱해 타이밍이 타임라인 자막 클립과 일치함을 확인
  - 기존 SRT export 무회귀 확인
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

---

## 5. 렌더 기능 3종 (요구사항 4, 8, 7) — 작업 2 통과 후

- [~] 5.1 `BlendMode` 모델 추가
  - `Clip`에 `blendMode` 추가 (`String` raw value enum, 기본 `.normal`, `decodeIfPresent ?? 기본값`, 기본값이 아닐 때만 encode)
  - `currentSchemaVersion`을 건드리지 않는다 (작업 6에서 일괄 처리)
  - 필드가 없는 기존 프로젝트 JSON 픽스처가 로드되고 `.normal`로 해석됨을 테스트로 고정
  - _Requirements: 4.4_

- [~] 5.2 `BlendPixelProcessor` 구현 + 골든 픽셀 테스트
  - 두 `CIImage`와 모드를 받아 합성하는 Core 프로세서 신설
  - 모드별 골든 픽셀 테스트. 소프트웨어 렌더러 기준, 채널당 오차 2, `assertRendererFunctional()` 최상단 호출
  - _Requirements: 4.6, 4.8_

- [~] 5.3 macOS 합성 경로에 블렌딩 배선
  - `CustomVideoCompositor`의 다중 트랙 합성 지점에서 프로세서 호출
  - **`.normal`은 프로세서를 호출하지 않고 우회한다.** 도입 전후 export 프레임이 픽셀 동일함을 확인
  - 불투명도와 블렌딩이 함께 반영됨을 확인
  - preview와 export가 동일한 합성 결과를 만드는지 확인. 헤드리스 제약에 막히면 그 사실을 기록하고 골든으로 대체
  - iOS 배선은 하지 않는다 (작업 9로 이관)
  - _Requirements: 4.1, 4.2, 4.3, 4.5, 4.7_

- [~] 5.4 인스펙터에 블렌딩 모드 드롭다운 추가
  - `InspectorBasicSection`에 선택 UI 추가, 기존 `SetClipPropertyCommand`로 적용
  - _Requirements: 4.1_

- [~] 5.5 `ClipTrimMath`에 slip / slide 순수 함수 추가
  - slip: `sourceRange`만 이동, `timelineRange`와 전체 길이 유지
  - slide: `timelineRange` 이동 + 인접 클립 경계 조정, 자신의 `sourceRange`와 전체 길이 유지
  - 배속·램프 클립에서 timeline↔source 매핑을 반드시 경유. 새 시간 계산 체계를 만들지 않는다
  - 소스 경계 초과 요청은 클램프. 램프·배속·경계 케이스를 단위 테스트
  - _Requirements: 8.1, 8.2, 8.3, 8.5_

- [~] 5.6 slip / slide 명령 및 제스처 배선
  - 명령 2개 신규, 각각 단일 undo 단위. `CommandSupport`의 locked-track 가드 재사용
  - 타임라인 드래그 + modifier로 조작 연결
  - 조작 후 preview와 export 결과가 일치함을 작업 2의 게이트로 확인
  - _Requirements: 8.4, 8.6_

- [~] 5.7 컴파운드 Inc 1a — 모델·직렬화
  - `CompoundDefinition` 신설, `Project.compounds`와 `Clip.compoundId` 추가 (`decodeIfPresent ?? 기본값`)
  - **중첩 금지 검증**: 자식 클립이 `compoundId`를 가지면 생성 시 거부, 로드 시 명시적 오류
  - 깨진 참조(`compoundId`에 정의 없음)는 로드 시 명시적 오류
  - 저장·로드 왕복 무손실 + 컴파운드 없는 기존 프로젝트 로드를 픽스처로 고정
  - `currentSchemaVersion`을 건드리지 않는다 (작업 6에서 일괄 처리)
  - _Requirements: 7.6_

- [~] 5.8 컴파운드 Inc 1b — flatten 렌더 (단일 출처 캐시)
  - Core에 1단계 flatten 순수 함수 신설. 재귀하지 않는다 (중첩 금지가 전제)
  - **캐시를 한 곳에만 둔다.** 프로젝트 변경 시 1회 계산해 `FlattenedTimeline` 값 스냅샷을 만들고, `PlaybackEngine`과 `ExportEngine`은 그것을 **인자로 받는다.** 엔진 내부에 flatten 호출이나 자체 캐시를 두지 않는다
  - 프레임 루프에서 flatten을 호출하지 않는다
  - **두 엔진이 받은 `FlattenedTimeline`이 동일함을 테스트로 고정한다.** 이것이 파리티 주장의 근거다
  - _Requirements: 7.5_

- [~] 5.9 컴파운드 Inc 1c — 편집 UI
  - 생성 / 해제 명령 2개 신규, 각각 단일 undo 단위
  - 타임라인에 단일 클립으로 표시
  - 이동·트림·복사 시 내부 구성이 상대적으로 보존됨을 확인
  - 해제 시 원래 클립이 복원됨을 확인
  - 완료 보고에서 "컴파운드 클립 완성"으로 부르지 않는다 (내부 편집은 Inc 2)
  - _Requirements: 7.1, 7.2, 7.4, 7.7_

---

## 6. 스키마 통합 (단일 커밋)

- [~] 6.1 `currentSchemaVersion` 인상 및 항등 마이그레이터 등록
  - 작업 4.6 / 5.1 / 5.7이 모두 병합된 뒤 **한 번에** 처리한다
  - 합쳐진 필드 전체를 대상으로 버전을 한 단계 올리고 항등 마이그레이터 하나를 등록
  - 마이그레이션 체인이 `currentSchemaVersion`에 도달함을 테스트로 확인
  - 이전 버전 프로젝트 픽스처가 로드되고, 미래 버전(`schemaVersion` 초과) 픽스처가 명시적 오류를 내는지 확인
  - _Requirements: 4.4, 5.3, 7.6_

---

## 7. 파리티 커버리지 확장 (요구사항 2b)

- [~] 7.1 하니스에 비후행 클립 삭제 경로 추가
  - 현재 `deleteClip()`이 항상 선택된(마지막) 클립을 지우므로 실제 갭이 만들어지지 않는다
  - 비후행 클립을 삭제해 갭이 생기는 시나리오를 구동할 수 있게 한다
  - _Requirements: 2.1_

- [~] 7.2 편집 조작 파리티 시나리오 신규
  - trim / move / ripple / 역재생 / 프리즈 시나리오를 기존 `run_scenario` 함수로 추가
  - 워치독, 실패 시 작업 디렉토리 보존, 무음 skip 금지 규율을 유지
  - 각 시나리오에 `--expect-duration`을 적용
  - _Requirements: 2.1, 2.2, 2.3, 2.5_

- [~] 7.3 undo 왕복 검증 추가
  - 파괴적 편집 전 `Project` 스냅샷과 undo 후 스냅샷을 모델 수준에서 비교 (`Equatable`)
  - 픽셀 비교가 아니라 상태 비교로 구현
  - _Requirements: 2.4_

---

## 8. 검증 신뢰도 부채 정리 (요구사항 15)

- [~] 8.1 `docs/` 산문 단언 테스트 제거
  - 문서 산문을 단언하는 테스트를 제거한다. 문서 오타 수정이 테스트를 깨뜨리는 것은 의존 방향이 거꾸로다
  - 삭제 전 해당 문서가 아직 유효한지 확인. 죽은 문서면 함께 정리 대상으로 보고
  - 건별 근거 한 줄 기록. 착수 전후 지표를 실측으로 기록
  - _Requirements: 15.1, 15.4_

- [~] 8.2 부정 단언 전수 분류
  - 결함 고정(기능 부재를 잠금 → 제거)과 경계 방향(계층 침투 방지 → 주석 후 유지)으로 분류
  - 분류표와 근거를 제시. 애매한 건은 애매하다고 표시하고 유지 쪽으로 기울인다
  - **파일 단위 일괄 삭제 금지.** StaticContract 파일에 섞인 실제 동작 단언까지 사라질 수 있다
  - _Requirements: 15.2, 15.4_

- [~] 8.3 렌더 프로세서 문자열 단언을 골든 픽셀로 승격
  - 승격 대응표(어떤 문자열 단언 → 어떤 픽셀 테스트)를 만든다
  - 승격된 테스트가 실제로 실행됐음(skip이 아님)을 확인 가능한 증거로 남긴다
  - `assertRendererFunctional()` 경유 필수
  - _Requirements: 15.3, 15.4_

- [~] 8.4 린트 게이트 판단
  - 규칙별 분해를 실측하고, 오류에 대해 CI 차단으로 전환할 수 있는지 판단
  - 규칙을 완화하는 경우 이 코드베이스에서 정당한 이유를 기록한다. 그냥 끄지 않는다
  - 전환 불가면 이유를 기록
  - _Requirements: 15.5_

---

## 9. iOS 파리티 (요구사항 11–14) — 사용자 조치 대기

> **선행 조건: iOS 플랫폼 설치.** 미설치 상태에서는 이 절의 어떤 작업도 완료로 표시하지 않는다. 검증되지 않은 iOS 관련 주장을 기록하지 않는다. (요구사항 11의 수용 기준 6)

- [~] 9.1 iOS 플랫폼 설치 여부 확인 후 진행 판단
  - 시뮬레이터 목록과 iOS 스킴 빌드를 시도해 가능 여부를 확인
  - 불가하면 여기서 멈추고 그 사실을 보고한다. 이후 작업에 손대지 않는다
  - _Requirements: 11.1, 11.6_

- [~] 9.2 iOS 테스트 타깃 및 하니스 진입점 구축
  - `project.yml`에 iOS UI 테스트 타깃 추가. **`info:` 블록을 추가하지 않는다** — 손으로 관리되는 `Info.plist`를 덮어쓴다
  - xcodegen 실행 전후 `Info.plist` 해시를 비교해 덮어쓰기가 없었음을 증거로 남긴다
  - iOS 진입점에 하니스 훅 추가 (macOS의 `ContentView` `.task { runUITestHarnessIfRequested() }` 전례)
  - 하니스가 import → export를 실제로 구동하고, 생성된 미디어의 존재와 길이를 외부 도구로 확인
  - _Requirements: 11.1, 11.2, 11.3, 11.4_

- [~] 9.3 CI iOS 단계가 실패를 조용히 통과시키지 않게 수정
  - _Requirements: 11.5_

- [~] 9.4 iOS 합성기를 공유 프로세서로 전환 (크로마키 / 배경 제거)
  - `IOSCustomVideoCompositor`의 inline 크로마키·세그멘테이션을 Core 공유 프로세서 호출로 교체
  - inline 재구현을 제거해 같은 수식이 두 곳에 남지 않게 한다
  - iOS↔macOS export 비교: **고정 시뮬레이터 1종**에서 MAD 척도로 판정, 기종·OS를 기록. 골든 척도를 쓰지 않는다
  - edgeShrink / softness 파리티를 확인. 오차 초과는 수치와 원인 구분과 함께 파리티 격차로 보고
  - _Requirements: 12.1, 12.2, 12.3, 12.4_

- [~] 9.5 iOS two-source 전환 배선
  - `IOSCustomVideoCompositor`에 two-source instruction 경로를 추가하고 공유 `TransitionPixelProcessor`를 경유
  - 9.4와 **같은 파일을 고치므로 순차 진행**한다
  - 전환 구간 중간 프레임이 두 소스의 혼합인지, 전환 길이가 인접 클립 겹침과 일치하는지 확인
  - iOS↔macOS 전환 구간 프레임 비교 (9.4와 동일한 척도·기종 기록 규칙)
  - _Requirements: 13.1, 13.2, 13.3, 13.4_

- [~] 9.6 iOS 문자열 현지화 래핑
  - iOS의 사용자 노출 문자열 개수를 먼저 측정해 보고
  - 현지화 가능하도록 래핑한다. 카탈로그만 추가하면 효과가 없다
  - _Requirements: 14.1_

- [~] 9.7 iOS 현지화 카탈로그 추가 및 실행 확인
  - 카탈로그 생성 + 한국어 번역. macOS 카탈로그와 용어를 일치시킨다
  - 한국어 로케일로 시뮬레이터 실행해 번역이 실제로 표시됨을 확인
  - 영어 로케일에서 한글 0건 확인
  - _Requirements: 14.2, 14.3, 14.4, 14.5_

- [~] 9.8 iOS 블렌딩 배선 (작업 5에서 이관)
  - 9.4 완료로 iOS가 공유 프로세서를 경유하게 된 뒤, `IOSCustomVideoCompositor`에 블렌딩 호출을 추가
  - `.normal` 우회 규칙을 macOS와 동일하게 유지
  - _Requirements: 4.2, 4.7_

---

## 10. 문서 부채 정리 (요구사항 16)

- [~] 10.1 완료 항목을 근거와 함께 표시
  - `PRO_SPEC_GAP_WORKORDER_*`, `NEXT_SESSION_WORKORDER_*`, `REVIEW_FINDINGS_WORKORDER_*`, `GAP_ANALYSIS_V13_*`의 완료 항목을 완료로 표시하거나 문서를 폐기 표시
  - 각 표시에 근거(커밋 해시 또는 코드 위치)를 포함
  - 이미 해소된 항목(STT 온디바이스, 스키마 마이그레이션, 북마크, entitlements, 카라오케 공백, 프록시 소비, 속도 커브 프리셋, 열 강등, OSLog, 앱 아이콘)도 함께 정리
  - _Requirements: 16.1, 16.2_

- [~] 10.2 최신 판정 단일 진입점 정리
  - 어떤 문서가 최신인지 독자가 추측하지 않아도 되게 진입점을 만든다
  - 문서 산문을 단언하는 테스트를 새로 만들지 않는다
  - _Requirements: 16.3, 16.4_

- [~] 10.3 이 스펙의 미완 항목을 명시 기록
  - 요구사항 7 Inc 2(내부 편집 + 컴파운드 레벨 효과) 분리 상태
  - iOS 플랫폼 미설치로 막힌 항목
  - 헤드리스 제약으로 앱 레벨 검증이 불가했던 항목
  - 사용자에게 보이는 제약을 함께 기록
  - _Requirements: 16.1, 16.2_
