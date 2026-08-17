# macOS 비디오 에디터 — 커스텀 컴포지터 라우팅 결함 검증·수정, T2 성능 측정 및 모션 트래킹 결정성 게이트 자문 요청

당신은 **Swift·AVFoundation·CoreImage·Vision 기반 macOS/iOS 비디오 편집기의 재생·출력 렌더 파이프라인 아키텍트**입니다.

아래 세 문제는 하나의 렌더 라우팅·측정 클러스터로 연결되어 있습니다.

- **문제 A:** 배경제거 사용 시 커스텀 컴포지터 프리뷰 트리거 누락 의심
- **문제 B:** T2 스트레스 타임라인에서 커스텀 컴포지터 프로브 `n=0`
- **문제 C:** 모션 트래킹을 결정론적으로 실행하는 테스트 하니스 게이트 부재

코드 저장소에는 접근할 수 없으므로, 제공되지 않은 파일명·타입·구현을 사실처럼 만들지 마세요. 정보가 부족한 경우에는 단정하지 말고 다음을 명확히 구분해 답해 주세요.

- 확인된 사실
- 관측 결과
- 유력 가설
- 대안 가설
- 코드에서 확인해야 할 지점
- 확인 결과에 따른 분기별 해결안

---

## 1. 프로젝트 맥락

### 1.1 기본 환경

- Swift 6 / SwiftUI / AppKit
- 최소 지원 macOS 15 이상
- AVPlayer 기반 프리뷰
- AVAssetExportSession 기반 출력
- AVFoundation / CoreImage / Vision 사용
- 프로젝트는 완전 오프라인
- 직접 코덱 구현은 하지 않음
- 프리뷰 구조는 `AVMutableComposition` + `AVMutableVideoComposition`
- 편집 변경 시 프리뷰용 composition과 video composition을 재빌드
- 커스텀 컴포지터는 조건부로 부착

---

### 1.2 렌더 경로 용어

이 요청에서는 프리뷰·출력 렌더 경로를 다음처럼 구분합니다.

#### 1. custom-compositor 경로

- `AVMutableVideoComposition.customVideoCompositorClass`가 설정됨
- `CustomVideoCompositor.startRequest(_:)`가 호출됨
- CoreImage·Vision 기반 사용자 정의 픽셀 처리가 수행됨

#### 2. built-in-compositor 경로

- `AVMutableVideoComposition`은 사용하지만 `customVideoCompositorClass`는 설정하지 않음
- AVFoundation 내장 컴포지터가 처리
- 공간 변환, 불투명도, 기본 크롭·램프 등 내장 명령 범위 안에서 동작할 수 있음

#### 3. preprocessed-source 경로

- 광학플로우 등의 처리가 사전 렌더된 대체 미디어에 이미 반영됨
- 재생 시점에는 해당 기능을 위한 실시간 픽셀 처리가 필요하지 않음
- 플레이어는 처리 완료된 미디어를 일반 소스처럼 재생

#### 4. time-mapping-only 경로

- composition track의 시간 매핑으로 재생 속도만 변경
- 별도의 프레임 생성·픽셀 효과가 없음
- 예: `scaleTimeRange` 기반 일정 배속 또는 일부 속도 변경

> 이 문서에서 기존의 “plain 경로”라는 표현은 사용하지 않습니다.  
> 필요 시 “built-in-compositor 경로” 또는 “time-mapping-only 경로”로 구분합니다.

---

### 1.3 현재 커스텀 컴포지터 부착 트리거

현재 트리거 개념은 다음과 같습니다.

```swift
let usesCustomVideoCompositor = videoClipInstructions.contains { c in
    c.colorCorrection != nil || c.colorGrade != nil
    || c.chromaKey != nil || c.chromaKeyColor != nil
    || c.mask != nil || !c.effects.isEmpty
    || c.blendMode != .normal || c.cropRect != nil
} || !transitionEffects.isEmpty || !textOverlayClipEffects.isEmpty
```

현재 목록에는 다음 항목이 없습니다.

- `isBackgroundRemoved`
- optical-flow slow motion
- speed ramp

단, optical-flow와 speed ramp가 커스텀 컴포지터를 필요로 하는지는 아직 확정하지 않았습니다.

- speed ramp는 composition track의 time mapping만 사용할 수 있음
- optical flow는 사전 렌더 미디어로 교체될 수 있음
- 반대로 실시간 프레임 생성을 커스텀 컴포지터에서 수행한다면 트리거가 필요함

따라서 기능 이름만 보고 판단하지 말고, **해당 기능이 실제로 어느 처리 경로에서 실행되는지**를 기준으로 판정해 주세요.

---

### 1.4 배경제거 처리 구조

- 배경제거 픽셀 처리는 현재 커스텀 컴포지터 내부에만 존재
- 주요 처리 경로:

```text
applyPersonSegmentation
→ VNSequenceRequestHandler
→ PersonSegmentationCompositor
```

- 커스텀 컴포지터 트리거가 발동하지 않으면 프리뷰에서 배경제거가 적용되지 않을 가능성이 높음
- 과거 `cropRect`가 트리거에서 누락되어 출력에는 반영되지만 프리뷰에서는 무시된 유사 결함이 있었음
- 해당 과거 결함은 트리거 조건 한 줄 추가로 해결됨

단, 현재 배경제거 결함은 아직 실증되지 않았습니다.  
`isBackgroundRemoved` 누락은 **유력 원인 가설**이지 확정 원인이 아닙니다.

---

### 1.5 프리뷰·출력·플랫폼별 배선 계약

프리뷰와 출력의 트리거 구현은 별도 함수일 수 있으며, 다음 4분면의 동일 여부는 아직 완전히 검증되지 않았습니다.

| 플랫폼 | 프리뷰 | 출력 |
|---|---|---|
| macOS | 일부 미검증 | 일부 미검증 |
| iOS | 일부 미검증 | 일부 미검증 |

신규 시각 속성은 각 경로에서 다음 네 단계가 연결되어야 합니다.

1. Core 모델
2. 재생·출력 instruction metadata
3. macOS·iOS 컴포지터의 `applyClipEffects`
4. preview/export 엔진의 compositor routing trigger

각 4분면에서 아래 항목을 확인해야 합니다.

1. 모델에 효과 속성이 존재하는가
2. 재생·출력 instruction metadata로 전달되는가
3. 필요한 경우 커스텀 컴포지터가 부착되는가
4. `applyClipEffects` 또는 대응 처리 함수가 호출되는가
5. 실제 결과 프레임에 효과가 반영되는가

---

### 1.6 프리뷰↔출력 픽셀 패리티 계약

기본 계약은 다음과 같습니다.

- 같은 프로젝트 → 같은 시각 결과
- 프리뷰↔출력 픽셀 MAD ≤ 2.0
- 16개 파리티 시나리오 보유
- 색관리는 sRGB SDR 고정
- `RenderColorConfiguration` 사용
- 컴포지터 소스 해석도 다음과 같이 working color space를 명시

```swift
CIImage(
    cvPixelBuffer: pixelBuffer,
    options: [.colorSpace: workingSpace]
)
```

단, 배경제거 프리뷰와 출력이 서로 다른 Vision segmentation quality level을 사용하는지 확인이 필요합니다.

예:

- 프리뷰: `.balanced`
- 출력: `.accurate`

서로 다른 품질 모드를 의도적으로 사용한다면 전체 픽셀 MAD ≤ 2.0 계약과 충돌할 수 있습니다. 이 경우 다음 중 어떤 계약이 적절한지 판정해 주세요.

#### 계약 A — 완전 픽셀 패리티

- 파리티 테스트에서는 프리뷰와 출력이 동일한 segmentation quality를 사용
- MAD ≤ 2.0 적용
- 일반 사용자 프리뷰에서만 별도의 속도 우선 모드를 허용

#### 계약 B — 의도적 품질 비대칭

- 프리뷰는 속도 우선, 출력은 정밀 모드
- 배경제거를 전체 픽셀 동일 계약의 명시적 예외로 정의
- 대신 다음과 같은 의미 기반 패리티를 사용
  - segmentation mask IoU
  - 경계 F-score
  - 배경 잔존률
  - 전경 손실률
  - 합성 경계 품질

동일 품질 모드인 경우에는 기본 픽셀 MAD 계약을 그대로 적용해 주세요.

---

### 1.7 성능 측정 프로브

신규 `CompositorRenderProbe`가 커스텀 컴포지터 렌더 요청당 벽시계 시간을 누적합니다.

현재 실측:

- 멀티레이어·자막 타임라인: p50 1.28ms / p95 2.19ms
- 컬러 체인: p50 3.94ms / p95 4.27ms

단, 다음 항목은 아직 명확히 문서화되지 않았습니다.

- 측정 시작 위치
- 측정 종료 위치
- `startRequest(_:)` 진입부터 `finish(...)` 직전까지인지
- CoreImage GPU 작업 완료를 기다리는지
- CPU enqueue 시간만 포함하는지
- Vision 처리 시간이 포함되는지
- 취소·실패 요청을 포함하는지
- warm-up 프레임을 제외하는지
- 요청이 병렬로 들어올 때 집계가 thread-safe한지
- 측정 표본 수 `n`
- 테스트 영상 해상도·코덱·FPS
- 테스트 Mac 모델
- macOS 버전
- Release/Debug 구성
- 전원 연결 상태
- thermal state
- 백그라운드 작업 상태

위 정보가 없으면 현재 수치의 의미를 단정하지 말고, 필수 측정 메타데이터와 올바른 프로브 경계를 제안해 주세요.

---

## 2. 문제 A — 배경제거 프리뷰 라우팅 결함 의심

### 2.1 현재 관측

- `isBackgroundRemoved`가 커스텀 컴포지터 트리거 목록에 없음
- 배경제거 픽셀 렌더링은 커스텀 컴포지터 내부에만 존재
- 배경제거만 사용하는 프로젝트에서 프리뷰가 built-in-compositor 경로로 갈 가능성이 있음
- 프리뷰에서 배경제거가 누락되고 출력에만 반영되는 과거 `cropRect` 결함과 유사함

---

### 2.2 아직 확정되지 않은 사항

다음은 코드 또는 실앱 계측으로 확인해야 합니다.

- `AVPlayerItem.videoComposition`에 실제로 custom compositor class가 없는지
- `AVPlayerItem.customVideoCompositor`가 `nil`인지
- `CustomVideoCompositor.startRequest(_:)`가 호출되지 않는지
- `isBackgroundRemoved`가 instruction metadata에 전달되는지
- 배경제거 효과의 활성 구간과 테스트 PTS가 일치하는지
- 출력 경로에도 동일 트리거 누락이 있는지
- macOS와 iOS의 트리거 구현이 같은지
- 프로브 env가 정상적으로 무장됐는지
- 커스텀 컴포지터 요청이 생성된 후 취소된 것은 아닌지
- 다른 효과가 우연히 커스텀 컴포지터를 트리거하고 있지 않은지

---

### 2.3 필수 결함 검증 대조군

다음 네 시나리오를 같은 입력 영상·같은 PTS·같은 프로젝트 설정으로 비교하는 절차를 설계해 주세요.

| 시나리오 | 예상 custom compositor 요청 | 확인 목적 |
|---|---:|---|
| 효과 없음 | 0 | 프로브·하니스 음성 대조군 |
| 이미 트리거되는 컬러 효과 1개 | 1개 이상 | 프로브·컴포지터 양성 대조군 |
| 배경제거만 적용 — 수정 전 | 현재 가설상 0 | 누락 결함 재현 |
| 배경제거만 적용 — 수정 후 | 1개 이상 | 수정 효과 확인 |

보유 인프라:

- 실제 앱을 실행하는 UI 테스트 하니스
- 프리뷰 프레임 PNG 덤프
- 출력 MP4 생성
- 특정 PTS의 프레임 추출·비교
- 골든 테스트
- 프리뷰↔출력 파리티 테스트
- 환경변수 기반 프로브 무장

단순히 `preview_render_n`만 보지 말고 다음을 단계별로 관찰하도록 설계해 주세요.

1. 효과 플래그가 Core 모델에 존재
2. instruction metadata에 전달
3. `videoComposition`이 player item에 부착
4. `customVideoCompositorClass` 설정 여부
5. custom compositor 인스턴스 생성 여부
6. `startRequest(_:)` 호출 여부
7. 효과 활성 PTS의 프레임 요청 여부
8. `applyPersonSegmentation` 호출 여부
9. 프리뷰 프레임의 시각적 결과
10. 출력 프레임의 시각적 결과

---

### 2.4 반드시 비교할 해결 옵션

#### 옵션 A1 — 국소 패치

트리거에 다음 조건을 추가합니다.

```swift
|| c.isBackgroundRemoved
```

평가 항목:

- 예상 코드 변경 위치
- 변경 규모
- 스키마 변경 여부
- 즉시 결함 복구 가능성
- macOS/iOS·preview/export에 각각 추가해야 하는지
- 기존 골든·파리티 회귀 위험
- 성능 영향
- 다음 신규 효과에서 동일 누락이 재발할 가능성

#### 옵션 A2 — 공유 render-route resolver 도입

예시 개념:

```swift
enum VisualProcessingRoute {
    case builtInCompatible
    case customCompositor
    case preRenderedSource
    case timeMappingOnly
}
```

또는:

```swift
var requiresCustomVideoCompositor: Bool
```

요구사항:

- preview/export/macOS/iOS가 같은 판정 로직을 공유
- 스키마 변경 없이 computed property 또는 resolver로 구현할 수 있는지 검토
- 모든 시각 속성을 한 곳에서 분류
- 신규 속성 추가 시 exhaustive test가 실패하도록 설계
- preprocessed source와 time mapping을 불필요하게 custom compositor로 보내지 않음

평가 항목:

- 예상 변경 위치·규모
- 기존 트리거 함수 제거·위임 범위
- 순환 의존성 가능성
- 스키마·마이그레이션 영향
- 테스트 전략
- 재발 방지 수준
- 리팩터링 도중 회귀 위험

#### 옵션 A3 — 항상 custom compositor 부착

평가 항목:

- 조건 누락을 원천 제거하는 장점
- 효과 없는 프로젝트까지 렌더 경로가 바뀌는 영향
- 자연 크기 처리
- preferred transform·orientation
- pass-through 구간
- 색공간 해석
- 프레임 타이밍
- 성능·메모리
- 배터리·발열
- built-in compositor와의 결과 차이
- 기존 plain 프로젝트의 골든·파리티 회귀 범위

이 옵션을 기본안으로 권장하려면 기존 효과 없는 프로젝트에 대해 다음 무회귀 근거를 요구해 주세요.

- 픽셀 패리티
- 자연 크기
- orientation
- 시간 정확성
- 색관리
- 프리뷰 성능
- 출력 성능
- 메모리
- seek 지연

---

### 2.5 optical-flow와 speed ramp 판별

다음 기준으로 각 기능을 분류해 주세요.

- custom per-frame pixel operation
- pre-rendered source substitution
- time-mapping-only
- built-in compositor compatible

각 분류에 따라 다음을 답해 주세요.

1. 커스텀 컴포지터 트리거가 필요한가
2. instruction metadata 전달이 필요한가
3. 프리뷰와 출력이 같은 경로를 써야 하는가
4. 사전 처리 미디어의 캐시·무효화가 필요한가
5. 원본 미디어와 대체 미디어의 타이밍 패리티를 어떻게 검증할 것인가
6. 트리거를 추가했을 때 불필요한 이중 처리가 생길 수 있는가

---

## 3. 문제 B — T2 측정에서 `preview_render_n=0`

### 3.1 현재 관측

- T2를 실행하면 `CompositorRenderProbe`의 request count가 0
- 1순위 가설은 배경제거 트리거 누락
- 그러나 `n=0`만으로 원인이 확정되지는 않음

다음 대안 원인을 포함해 진단 순서를 제시해 주세요.

- `customVideoCompositorClass` 미설정
- player item에 `videoComposition` 미부착
- 커스텀 컴포지터 인스턴스 미생성
- 테스트 PTS에서 효과 비활성
- 플레이어가 실제 프레임 요청을 하지 않음
- offscreen·hidden view로 display link가 진행되지 않음
- 테스트 재생 시간이 너무 짧음
- probe env 미무장
- 요청이 생성 후 즉시 취소됨
- 프로브 집계의 동시성 오류
- 측정 종료 시점이 너무 빨라 flush 전에 결과를 읽음
- T2 미디어가 preprocessed-source 경로로만 구성됨
- 다른 렌더 경로에서 프레임이 공급되지만 현재 프로브가 해당 계층을 관측하지 못함

---

### 3.2 T2 벤치마크 분리

현재 T2를 다음 두 벤치마크로 분리할 계획입니다.

#### T2-R — Preview Render Stress

구성:

- 사전 처리된 optical-flow 0.5× 소스
- 실시간 또는 프리뷰용 배경제거
- 사전 생성된 모션 트래킹 키프레임
- 모션 트래킹 결과가 위치·크기·마스크 등에 실제로 적용되는 구간

측정 대상:

- custom compositor 요청 처리 p50/p95/p99
- request count
- success/failure/cancel count
- 프레임 공급률
- dropped frame
- late frame
- display cadence
- seek-to-first-frame
- 편집 명령 후 first updated frame
- process memory peak
- thermal state
- 출력이 아니라 실제 프리뷰 재생의 사용자 체감

#### T2-M — Motion Tracking Analysis

구성:

- 고정 테스트 영상
- 고정 초기 rect
- 고정 시작·종료 PTS
- 고정 프레임 샘플링 정책
- 실제 `MotionTrackingProvider` 실행

측정 대상:

- 분석 RTF
- 총 처리 시간
- 프레임별 처리 p50/p95/p99
- 메모리 피크
- 생성 키프레임 수
- median IoU
- p10 IoU
- 최종 프레임 IoU
- 추적 실패율
- 최대 연속 실패 프레임
- 가림 후 재획득 성능
- 동일 호스트 반복 편차

다음을 평가해 주세요.

1. T2-R과 T2-M 분리가 타당한가
2. Vision 트래킹이 일반 재생 중 계속 실행되지 않고 사전에 키프레임을 생성하는 구조라면, 분석 비용을 프리뷰 렌더 비용에서 분리해야 하는가
3. T2-R에는 Vision 추론 자체가 아니라 생성된 키프레임 평가 비용만 포함하는 것이 맞는가
4. 배경제거는 프리뷰 중 실시간 Vision 처리인지, 캐시된 마스크를 사용하는지에 따라 T2-R 정의가 어떻게 달라져야 하는가
5. 모션 트래킹 게이트가 완성되기 전 `T2-R0`, 완성 후 `T2-R1`로 단계화하는 것이 적절한가

예시:

```text
T2-R0
- optical-flow 사전 처리 소스
- 배경제거
- 모션 트래킹 제외

T2-R1
- optical-flow 사전 처리 소스
- 배경제거
- 사전 생성된 모션 트래킹 키프레임 포함
```

---

### 3.3 프리뷰 측정 옵션 비교

다음 후보를 비교해 주세요.

1. `CustomVideoCompositor.startRequest` → `finish` 구간
2. `AVPlayerItemVideoOutput`의 frame availability·PTS 관측
3. `copyPixelBuffer` 호출 시간
4. `NSView` 또는 `NSWindow` display link 기반 frame cadence
5. Core Animation FPS·hitch
6. `os_signpost` 기반 edit/seek → first updated frame
7. Instruments 또는 `xctrace`
8. 별도 `AVAssetReader` 기반 오프라인 처리 벤치마크
9. 필요 시 `CIRenderTask` 또는 GPU completion을 이용한 비동기 렌더 완료 계측
10. 플레이어 timebase와 실제 표시 프레임 PTS 비교

각 후보별로 다음을 구분해 주세요.

- 무엇을 실제로 측정하는가
- 디코딩 비용 포함 여부
- built-in compositor 비용 포함 여부
- custom compositor 비용 포함 여부
- CoreImage CPU 작업 포함 여부
- GPU enqueue만 측정하는지
- GPU 완료까지 포함하는지
- Vision 처리 포함 여부
- 화면 표시 비용 포함 여부
- 프레임 준비 시간과 버퍼 취득 시간을 구분할 수 있는지
- probe 자체가 재생을 교란하는지
- CI 자동화 가능성
- 반복 실행 안정성
- 구현 난이도
- 최소 지원 macOS 15에 적합한지

특히 다음을 비판적으로 검토해 주세요.

> `AVPlayerItemVideoOutput.copyPixelBuffer(forItemTime:)` 호출 시간을 end-to-end 프리뷰 렌더 시간으로 간주해도 되는가?

프레임이 이미 비동기적으로 준비된 상태에서 단순 버퍼 취득만 빠르게 완료될 수 있으므로, 호출 시간과 실제 디코딩·컴포지팅·표시 비용을 혼동하지 않는 측정 설계를 제안해 주세요.

또한 `AVPlayerItemVideoOutput` 추가 시 다음도 확인해 주세요.

- `suppressesPlayerRendering` 설정
- 기존 `AVPlayerLayer` 표시 경로 변화 여부
- pixel buffer polling이 재생에 주는 영향
- `hasNewPixelBuffer`와 display link의 올바른 조합
- offscreen UI 테스트에서 프레임 진행을 보장하는 방법

---

### 3.4 컴포지터 프로브 의미 검증

현재 `CompositorRenderProbe`가 무엇을 측정하는지 다음 관점에서 검토해 주세요.

- 시작점이 `startRequest(_:)` 진입인지
- 종료점이 `finish(withComposedVideoFrame:)` 호출 직전인지
- Core Image의 실제 렌더 완료를 기다리는지
- CPU command encoding 시간만 포함하는지
- GPU completion까지 포함하는지
- pixel buffer allocation 시간이 포함되는지
- Vision segmentation 시간이 포함되는지
- 취소 요청을 별도로 집계하는지
- 실패 요청을 별도로 집계하는지
- warm-up 프레임을 제외하는지
- 첫 프레임만 유난히 느린 현상을 별도 기록하는지
- 병렬 요청의 중복 시간 때문에 합산값이 과장되는지
- thread-safe한 누적·percentile 계산인지
- 측정 종료 시 모든 요청이 flush되었는지

성공·실패·취소 요청을 다음처럼 분리하는 것이 필요한지도 평가해 주세요.

```text
render_success_n
render_failed_n
render_cancelled_n
render_p50_ms
render_p95_ms
render_p99_ms
first_frame_ms
warmup_excluded_n
```

---

### 3.5 메모리 측정

메모리는 최소한 다음을 구분해 주세요.

- process physical footprint
- resident size 또는 RSS
- peak absolute value
- 테스트 시작 대비 peak delta
- `IOSurface`
- pixel buffer pool
- decoded frame queue
- CoreImage cache
- Vision request·mask buffer
- temporary render target
- GPU 관련 진단 지표
- autorelease pool 영향
- 프록시·사전 렌더 미디어 캐시
- 테스트 종료 후 메모리 회수 여부

단일 RSS 숫자만으로 결론 내리지 말고, CI에서 자동 수집 가능한 지표와 Instruments에서 수동 확인할 지표를 나누어 주세요.

---

## 4. 문제 C — 모션 트래킹 하니스 게이트 부재

### 4.1 현재 모션 트래킹 흐름

`MotionTrackingProvider`는 다음 흐름으로 동작합니다.

```text
사용자가 초기 rect 지정
→ Vision 트래킹 실행
→ 시점별 bounding rect 생성
→ 편집 모델에 키프레임 생성
→ 프리뷰·출력에서 키프레임 적용
```

현재 고정 초기 rect와 고정 영상을 사용해 이 경로를 결정론적으로 실행하는 UI 테스트 하니스 env gate가 없습니다.

---

### 4.2 기존 하니스 패턴

기존 UI 테스트 하니스는 다음 패턴을 사용합니다.

```text
MOVIECUT_UITEST_*=1
```

예:

```text
MOVIECUT_UITEST_KARAOKE=1
```

해당 gate는 단순 모델 직접 변경이 아니라 실제 앱에서 실제 편집 커맨드 경로를 실행합니다.

---

### 4.3 신규 게이트 요구사항

다음과 같은 신규 게이트를 설계해 주세요.

```text
MOVIECUT_UITEST_MOTION_TRACKING=1
```

필요 조건:

- 번들된 고정 테스트 영상
- 테스트 영상 해시 검증
- 고정 초기 rect
- 고정 시작 PTS
- 고정 종료 PTS
- 고정 프레임 샘플링 정책
- 영상 orientation 처리 명시
- `preferredTransform` 처리 명시
- Vision normalized rect와 렌더 좌표계 변환 고정
- 가능하면 Vision request revision 명시
- tracking level 명시
- 실제 `MotionTrackingProvider` 사용
- 실제 편집 command 실행
- 생성된 키프레임을 프로젝트 모델에 적용
- 프로젝트 저장
- 프로젝트 재오픈
- 재오픈 후 키프레임 유지 확인
- 프리뷰에서 결과 적용 확인
- 출력에서 결과 적용 확인
- sleep 기반 대기가 아닌 명시적 completion 신호
- timeout과 실패 원인 기록
- 일반 사용자 실행에서는 gate가 절대 활성화되지 않음
- 테스트 종료 후 생성 파일·상태 정리

다음과 같은 실행 순서를 포함해 주세요.

```text
앱 실행
→ 테스트 프로젝트 생성 또는 로드
→ 고정 미디어 삽입
→ 고정 PTS로 이동
→ 고정 초기 rect 주입
→ 실제 모션 트래킹 커맨드 실행
→ provider 완료 이벤트 대기
→ 키프레임 수·PTS·좌표 수집
→ 프로젝트 저장
→ 프로젝트 재오픈
→ 키프레임 직렬화 유지 확인
→ 프리뷰 특정 PTS PNG 덤프
→ 출력 생성
→ 프리뷰·출력 결과 검증
→ T2-M 성능 결과 기록
```

---

### 4.4 하니스 설계 옵션

다음 옵션을 2~3개로 비교해 주세요.

#### 옵션 C1 — UI 테스트 env gate에서 전체 실제 경로 실행

- 앱 시작 시 env 확인
- 테스트 프로젝트·고정 영상 준비
- 실제 커맨드와 provider 실행
- 완료 이벤트를 UI 테스트에 노출

#### 옵션 C2 — 내부 테스트 오케스트레이터

- 앱 내부에 테스트 전용 coordinator를 둠
- env gate가 coordinator를 활성화
- 실제 command·provider·persistence 경로는 그대로 사용
- UI 테스트는 coordinator 상태만 관찰

#### 옵션 C3 — provider 통합 테스트 + 얇은 UI smoke test 분리

- `MotionTrackingProvider`와 command·persistence는 통합 테스트에서 검증
- UI 테스트는 기능 진입·완료·결과 반영만 확인
- T2-M은 별도 host performance test로 실행

각 옵션별로 다음을 비교해 주세요.

- 실제 사용자 경로 충실도
- 결정성
- CI 안정성
- 실행 시간
- 실패 진단 가능성
- App Store 빌드 노출 위험
- 테스트 코드와 제품 코드의 결합도
- 스키마 영향
- 유지보수 비용

---

### 4.5 결정성 통제 항목

다음 항목을 반드시 통제하거나 기록해야 하는지 평가해 주세요.

- 테스트 영상 파일 해시
- 해상도
- 코덱
- FPS
- VFR/CFR 여부
- 시작 PTS
- 종료 PTS
- 샘플링 PTS 목록
- 초기 rect
- normalized rect 좌표계
- top-left/bottom-left 원점
- 영상 rotation
- preferred transform
- crop·scale 적용 순서
- Vision request revision
- tracking level
- Vision confidence threshold
- request handler 재사용 정책
- 장면 전환 처리
- 추적 실패 시 중단·재시도 정책
- 키프레임 간 보간 방식
- macOS 버전
- 기기 모델
- 동일 호스트 반복 횟수

---

### 4.6 골든 검증 설계

정확히 고정할 항목과 허용오차로 검증할 항목을 나누어 주세요.

#### 정확히 고정할 후보

- 테스트 영상 해시
- 초기 rect
- 분석 시작·종료 PTS
- 샘플링 PTS 목록
- 키프레임 타임스탬프
- 생성 키프레임 수
- 직렬화 구조
- effect·tracking 플래그
- command 완료 상태
- 프로젝트 저장·재오픈 후 키프레임 수
- NaN·무한대 없음
- 필수 필드 존재 여부

#### 허용오차로 검증할 후보

- 각 bounding box 좌표
- confidence
- IoU
- 최종 위치
- 가림 후 재획득 시점
- 프레임별 중심점 이동
- 박스 크기 변화
- 동일 호스트 반복 실행 편차

다음 형태의 품질 게이트를 설계해 주세요.

```text
- 예상 샘플 PTS의 100% 또는 사전 정의된 비율 이상에 키프레임 존재
- median IoU ≥ 기준값
- p10 IoU ≥ 하한값
- 최종 프레임 IoU ≥ 기준값
- 최대 연속 실패 프레임 ≤ N
- 화면 범위 밖 rect 0건 또는 허용 정책 명시
- NaN·무한대 0건
- 동일 호스트 반복 실행의 좌표 편차 ≤ 허용값
- 프로젝트 저장·재오픈 후 키프레임 손실 0건
```

현재 구현의 첫 실행 결과를 그대로 골든으로 복사하는 방식과, 사람이 주석한 ground truth를 사용하는 방식을 비교해 주세요.

최소한 다음 세 종류의 기준 파일을 구분하는 것이 필요한지도 평가해 주세요.

1. **행동 골든**
   - 키프레임 개수
   - PTS
   - command·persistence 결과

2. **품질 ground truth**
   - 사람이 주석한 bounding box
   - IoU 평가 기준

3. **렌더 골든**
   - 특정 PTS의 프리뷰·출력 이미지
   - 트래킹 결과가 실제 시각 효과에 적용됐는지 확인

---

### 4.7 권장 테스트 계층

다음 계층 분리가 적절한지 평가해 주세요.

1. `MotionTrackingProvider` 단위·통합 테스트
2. 실제 앱 커맨드 경로 UI 테스트
3. 키프레임 저장·마이그레이션·재오픈 테스트
4. 키프레임 렌더 프리뷰↔출력 파리티 테스트
5. 분석 성능 T2-M 테스트
6. 렌더 성능 T2-R 테스트

각 계층에서 중복 검증해야 할 항목과 한 계층에서만 검증할 항목을 구분해 주세요.

---

## 5. 공통 제약조건

- 기존 16개 프리뷰↔출력 파리티 시나리오 무회귀
- 기본 픽셀 MAD ≤ 2.0
- segmentation quality가 의도적으로 다르면 별도 의미 기반 패리티 정의
- 스키마 변경은 최후 수단
- 스키마 변경 시 버전 마이그레이션·구버전 프로젝트 테스트 필수
- 측정은 실제 지원 Mac 호스트에서만 인정
- 시뮬레이터 수치와 추정치 금지
- 성능 측정은 Release 구성
- 테스트 하드웨어·OS·전원·발열 상태 기록
- warm-up 횟수 기록
- 반복 횟수 기록
- 표본 수 기록
- 성공·실패·취소 compositor request 분리 집계
- 테스트 env gate는 일반 사용자 실행에서 활성화되지 않아야 함
- 테스트 전용 코드가 App Store 사용자 기능으로 노출되지 않아야 함
- 1증분 = 1커밋
- 각 커밋은 하나의 독립적으로 검증 가능한 목적만 포함
- 각 커밋 전 다음 4단계 게이트 통과 필수
  1. `swift build`
  2. `swift test` 전체
  3. `xcodebuild` macOS
  4. `xcodebuild` iOS

항상 custom compositor를 부착하는 대안은 별도 실험으로 평가하고, 즉시 기본 아키텍처로 권장하려면 기존 효과 없는 프로젝트에 대한 파리티·성능·자연 크기·orientation·색관리 무회귀 근거를 요구해 주세요.

---

## 6. 요청 산출물 형식

먼저 **10줄 이내의 실행 요약**을 제시한 뒤, 다음 순서와 형식으로 답해 주세요.

---

### 6.1 사실·가설 표

| 항목 | 확인된 사실 | 관측 결과 | 유력 가설 | 대안 가설 | 추가로 필요한 증거 |
|---|---|---|---|---|---|

사실과 가설을 혼합하지 마세요.

---

### 6.2 문제 A — 배경제거 프리뷰 라우팅

다음 순서로 작성해 주세요.

1. 원인 판정 절차
2. 대조군별 예상 결과
3. 해결 옵션 A1/A2/A3 비교표
4. 권장안과 근거
5. 구현·검증 체크리스트
6. macOS/iOS × preview/export 라우팅 매트릭스
7. optical-flow·speed ramp 처리 경로 판정 기준
8. 회귀 가능성
9. 회귀 차단 테스트
10. 완료 판정 기준

옵션 비교표 형식:

| 옵션 | 접근 방식 | 예상 변경 범위 | 스키마 영향 | 파리티 위험 | 성능 영향 | 재발 방지 | 권장도 |
|---|---|---|---|---|---|---|---|

---

### 6.3 문제 B — T2와 성능 측정

다음 순서로 작성해 주세요.

1. `n=0` 진단 트리
2. 문제 A 수정이 T2 측정을 자연 해소하는 조건
3. 문제 A 수정 후에도 `n=0`일 때의 다음 진단
4. T2-R/T2-M 분리 평가
5. `T2-R0`/`T2-R1` 단계화 평가
6. 측정 도구 비교표
7. 권장 측정 스택
8. 각 지표의 정확한 의미
9. GPU 완료 포함 여부 판정 방법
10. CI 자동 게이트와 수동 Instruments 분석 구분
11. 메모리 측정 항목
12. 완료 판정 기준

측정 도구 비교표 형식:

| 측정 방법 | 실제 측정 대상 | 디코딩 포함 | 컴포지팅 포함 | GPU 완료 포함 | 표시 비용 포함 | CI 자동화 | 난이도 | 주의점 |
|---|---|---:|---:|---:|---:|---:|---:|---|

---

### 6.4 문제 C — 모션 트래킹 하니스

다음 순서로 작성해 주세요.

1. 하니스 gate 설계 옵션 2~3개
2. 옵션 비교표
3. 권장안과 근거
4. 실제 앱 커맨드 실행 순서
5. completion·timeout 설계
6. Vision 결정성 통제 항목
7. 좌표계·orientation 처리
8. 행동 골든·품질 ground truth·렌더 골든 분리
9. IoU·실패율 검증 설계
10. 저장·재오픈 검증
11. 분석 성능과 렌더 성능 분리
12. 완료 판정 기준

옵션 비교표 형식:

| 옵션 | 사용자 경로 충실도 | 결정성 | CI 안정성 | 진단성 | 코드 결합도 | 유지비용 | 권장도 |
|---|---:|---:|---:|---:|---:|---:|---:|

---

### 6.5 권장 코드 구조

구체적 저장소 파일명은 추측하지 말고, 논리적 책임 단위로 다음을 제안해 주세요.

- shared render-route resolver
- preview composition builder
- export composition builder
- platform compositor adapter
- effect instruction metadata
- compositor probe
- motion tracking test orchestrator
- golden fixture loader
- performance result recorder

각 책임이 어디에 있어야 하며 어떤 의존 방향을 가져야 하는지 설명해 주세요.

---

### 6.6 최종 실행 순서

다음 형식으로 제시해 주세요.

| 순서 | 증분·커밋 범위 | 변경 내용 | 선행 조건 | 완료 게이트 | 롤백 기준 |
|---:|---|---|---|---|---|

권장 순서는 최소한 다음 흐름을 평가해 주세요.

1. 기존 대조군과 프로브 정상 동작 검증
2. 배경제거 단독 결함 재현
3. `isBackgroundRemoved` 최소 트리거 패치
4. 4분면 파리티·골든 회귀
5. shared render-route resolver 도입
6. T2-R0 측정
7. 모션 트래킹 하니스 도입
8. T2-M 측정
9. T2-R1 측정
10. 항상 custom compositor 부착 방식의 별도 실험

---

### 6.7 최종 판정

마지막에는 다음 질문에 명확히 답해 주세요.

1. 현재 정보만으로 배경제거 프리뷰 결함 가능성은 높은가
2. 최소 패치와 구조적 수정 중 어떤 순서가 적절한가
3. optical-flow와 speed ramp에 트리거를 추가해야 하는 판별 기준은 무엇인가
4. 문제 A 수정이 T2 `n=0`을 해결할 가능성은 어느 정도인가
5. `copyPixelBuffer` 호출 시간은 무엇을 측정하며 무엇을 측정하지 못하는가
6. T2-R과 T2-M은 분리해야 하는가
7. 모션 트래킹 골든에서 정확 일치와 허용오차를 어떻게 나눠야 하는가
8. 항상 custom compositor 부착은 기본안인가, 실험안인가
9. 가장 먼저 실행할 독립 커밋은 무엇인가
10. 세 문제의 최종 권장 처리 순서는 무엇인가
