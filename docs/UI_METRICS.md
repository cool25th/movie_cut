# UI Metrics — action counts and regression goldens (U-08)

> `EditorSession.commandCount` (= `undoStack.count`) counts every command
> dispatched this session. Each user-facing action — button click, menu item,
> drag-commit — routes through `dispatch`, so the count approximates the
> interaction step count for a workflow. Lower is better.

## Representative flow action counts

Measured via the Mac DEBUG harness (`MOVIECUT_UITEST=1`) — the harness
drives the REAL ViewModel command paths (no stubs), so the counts reflect
actual product interactions.

| Flow | Commands | CapCut target | Notes |
|---|---|---|---|
| Import media → add to timeline | 2 | ≤2 | `ImportMediaCommand` + `AddClipCommand` |
| Import → add text → add grade | 4–5 | ≤4 | + `CreateTrackCommand(.text)` + `AddClipCommand` + grade cmd |
| Import 2 clips → transition → export | 4–5 | ≤4 | 2×(import+add) + transition cmd + export (engine, not command) |

## Regression goldens (AC②)

Four editor-surface goldens committed under `Tests/UIEvidence/`:

| State | Golden | Harness flags |
|---|---|---|
| `import_only` | `golden_import_only.png` | `MOVIECUT_UITEST_IMPORT=<mp4>` |
| `populated_editor` | `golden_populated_editor.png` | + `MOVIECUT_UITEST_TEXT_TEMPLATE_NAME=Title` |
| `with_color_grade` | `golden_with_color_grade.png` | + `MOVIECUT_UITEST_GRADE=1 MOVIECUT_UITEST_INSPECTOR_TAB=Adjustment` |
| `with_mask` | `golden_with_mask.png` | + `MOVIECUT_UITEST_MASK=1 MOVIECUT_UITEST_INSPECTOR_TAB=Mask` |

Run `scripts/ui_regression.sh` to capture all states and compare via dHash
(threshold 4). `--update-golden` refreshes the committed evidence.

## Usage

```bash
# Action count from the harness (add to any harness scenario):
#   let count = await viewModel.session.commandCount
#   report("action_count commands=\(count)")

# Regression gate:
scripts/ui_regression.sh

# Golden refresh (intentional UI change only):
scripts/ui_regression.sh --update-golden
```
