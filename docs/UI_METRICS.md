# MovieCut UI Metrics / Regression Evidence

> Status: U-08 Inc 1~2 infrastructure. Generated artifacts live in `artifacts/ui/` and are not source-of-truth. Reviewed UI goldens live in `Tests/UIEvidence/` and are committed.

## Commands

Capture a deterministic populated editor window:

```bash
scripts/ui_capture.sh
```

Run screenshot regression against committed goldens:

```bash
scripts/ui_regression.sh
```

Refresh goldens intentionally after reviewing the generated capture:

```bash
scripts/ui_regression.sh --update-golden
```

## Current surfaces

| Surface | Golden | Artifact | Metric |
|---|---|---|---|
| Populated editor | `Tests/UIEvidence/golden_populated_editor.png` | `artifacts/ui/moviecut_populated_editor_raw.png`, `artifacts/ui/moviecut_populated_editor_normalized.png` | dHash Hamming distance, threshold 4 |

The populated editor capture launches the Debug app with the existing DEBUG harness, imports `Tests/Fixtures/solid_red_tone_320x240_2s_30fps.mp4`, and adds a Title text template so the capture includes real media, preview, inspector, and timeline state.

## Evidence policy

- `Tests/UIEvidence/*.png`: reviewed committed baselines.
- `artifacts/ui/`: generated captures, normalized images, logs, reports, and throwaway DerivedData.
- Static/source contracts may lock script paths, but they are not U-08 completion proof. Completion proof requires `scripts/ui_regression.sh` to capture and compare a real image.

## U-08 remaining work

- [진행중] Expand from the first populated editor surface to the full four target surfaces: browser, preview+inspector, timeline populated, grading panel.
- [진행중] Inc 3 discovery metric: record the representative flow click count (clip add → transition apply → export start) via XCUITest or harness log and compare against `UI_DESIGN_PRINCIPLES.md` discoverability target.
