# 무인 작업 — 귀환 후 검토용: public API dead code

> **[보관 — 완료]** 이 문서는 `docs/archive/`에 있다. 현역이 아니며 갱신되지 않는다. 전체 문서 지도는 [docs/README.md](../README.md).
>
> - 상태: 후보 4종 + 2종을 `3c438aa`에서 삭제(Core 816줄 감소). 사용자 결정 완료.
> - 지금 볼 곳: 복원이 필요하면 `3c438aa`에서 되살릴 것.

> 작성일: 2026-07-29 (자율 작업 세팅 단계)
> 성격: **사용자 결정 필요.** 무인으로는 건드리지 않았음.

## 배경

`Package.swift`가 `MovieCutCore`를 외부 배포용 library product로 정의:

```swift
products: [ .library(name: "MovieCutCore", targets: ["MovieCutCore"]) ]
```

따라서 `Sources/MovieCutCore/`의 `public` 타입은 외부 소비자가 있을 수 있고,
사용자가 의도적으로 public API surface로 유지 중일 수 있다.
**repo 내부(Tests 포함)에서 0~1회 참조**더라도 무인 삭제는 위험하다고 판단해 제외했다.

## 후보 (전부 `public`, repo 내 자기 선언 1건뿐 — grep 독립 재검증 완료)

| # | 파일 | 줄수 | 타입 | 종류 | 참조수 | 비고 |
|---|------|------|------|------|--------|------|
| 1 | `Sources/MovieCutCore/Commands/AutoReframeCommand.swift` | 190 | `public struct AutoReframeCommand: EditorCommand` | struct | 1 | dispatch 안 됨 |
| 2 | `Sources/MovieCutCore/Commands/CrossfadeAudioCommand.swift` | 145 | `public struct CrossfadeAudioCommand: EditorCommand` | struct | 1 | dispatch 안 됨 |
| 3 | `Sources/MovieCutCore/Commands/ImportMultipleCommand.swift` | 182 | `public struct ImportMultipleCommand: EditorCommand` | struct | 1 | 단일형 `ImportMediaCommand`는 살아있음 |
| 4 | `Sources/MovieCutCore/Commands/SaveAsTemplateCommand.swift` | 113 | `public struct SaveAsTemplateCommand: EditorCommand` | struct | 1 | dispatch 안 됨 |
| 5 | `Sources/MovieCutCore/Export/SocialShareService.swift` | 147 | `public final class SocialShareService` (+ `public enum SocialShareTarget`) | class+enum | 1 (둘 다 동일 파일 내에서만 사용) | 파일 전체 dead cluster |
| 6 | `Sources/MovieCutCore/Media/MediaFolder.swift` | 39 | `public struct MediaFolder` | struct | 1 | project.yml/Package.swift 언급 0 |

**총 잠정 제거량**: ~816줄 (6개 파일).

## 검증 증거 (grep, 원본)

```
$ grep -rnw <TypeName> --include="*.swift" Sources App Tests
# 각각 선언 1건만 매칭 (AutoReframeCommand 예시)
Sources/MovieCutCore/Commands/AutoReframeCommand.swift:5:public struct AutoReframeCommand: EditorCommand, Sendable, Codable {
```

문자열 리터럴 dispatch(`"<TypeName>"`)도 전부 0건 확인.

## 결정 필요

- **(a) 제거**: MovieCutCore가 실제로 외부 배포되지 않는다면(internal 사용 전용) 이 6개는 안전하게 제거 가능. 약 816줄 감소.
- **(b) 유지**: 공개 API surface 의도라면 그대로. 단 `@available(*, deprecated)` 등으로 의도 표시 검토.
- **(c) 일부만**: 예: `MediaFolder`(39줄, 모델계)는 확실히 dead, `*Command` 4개는 API 의도 가능.

이 항목들은 `docs/archive/AUTONOMOUS_WORK_20260729.md` 큐에 넣지 않았음 (규칙: 무인 public API 제외).
