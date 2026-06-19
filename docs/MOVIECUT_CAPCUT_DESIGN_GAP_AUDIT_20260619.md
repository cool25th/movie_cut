# MovieCut ↔ CapCut side-by-side design gap audit

Date: 2026-06-19
Scope: macOS editor UI, presentation-layer only
Baseline commit: `d7a703f refactor(moviecut): align ia menu positions with capcut`

## Evidence used

- CapCut reference editor: `/tmp/moviecut-ui-evidence/current-loop/resume-20260619-004321/capcut_editor_clean.png`
  - Note: reference is a real CapCut editor window, but some timeline media are missing/relinked, so clip content is not a perfect visual-content baseline. It is still valid for IA/menu-position, density, panel zoning, and toolbar hierarchy.
- MovieCut current IA empty capture: `/tmp/moviecut-ui-evidence/current-loop/ia-menu-position-pass/moviecut_ia_menu_position_empty.png`
  - Captured after the IA/menu-position pass.
- Side-by-side composite: `/tmp/moviecut-ui-evidence/current-loop/design-gap-audit-20260619/capcut_vs_moviecut_current_empty_side_by_side.png`
- Prior MovieCut populated visual baseline: `/tmp/moviecut-ui-evidence/current-loop/resume-20260619-004321/moviecut_loop6_full_populated_text_selected.png`
  - Note: this predates the IA/menu-position pass, so use it only for visual-content density and selected-state references, not for top-toolbar ownership.

## Executive summary

The IA/menu-position pass fixed the largest structural mismatch: MovieCut no longer puts Split/Delete/Add Marker in the macOS top toolbar, preview transport is bottom-docked, and the timeline header now owns edit/marker/quick/zoom command clusters.

Remaining gaps are now mostly product-polish gaps rather than missing major surfaces:

1. Left browser still reads more like a utility sidebar plus a large import card than CapCut's content/template browser.
2. Inspector is functionally complete but visually too ledger-like and metadata-heavy, especially in empty/no-selection state.
3. Preview empty-state scaffold is strong but too decorative/placeholder-like compared with CapCut's direct content canvas.
4. Timeline rows are clean but too spreadsheet-like; clip/media affordances and selected-state richness need polish.
5. Toolbar and cluster density is improved, but MovieCut still has more visible chrome/buttons than CapCut in the same width.

## Area-by-area gap audit

### R1. Top toolbar / project chrome

What improved:
- Top toolbar ownership is now closer to CapCut: project/status, undo/redo, canvas/view/project controls, sync/export.
- Split/Delete/Add Marker are absent from the top toolbar and moved to timeline-local ownership.
- Export remains a clear top-right action.

Remaining gaps:
- MovieCut top toolbar still looks more macOS-toolbar-heavy than CapCut's compact title/action strip.
- Several icons in the right toolbar region appear as separate round/outlined controls; CapCut groups small view/export controls with tighter spacing and lower visual weight.
- MovieCut has visible window chrome and many utility affordances competing with the project title, while CapCut's central title/project name feels calmer.

Priority:
- P2. Do not undo the IA pass. Polish only spacing, grouping, and visual weight.

Recommended polish:
- Compress secondary top-right controls into lower-emphasis groups.
- Keep Export visually dominant but make neighboring view/project controls quieter.
- Reduce heavy circular outlines for non-primary controls where possible.

### R2. Left browser / content source panel

What improved:
- MovieCut has CapCut-like vertical category rail: Media, Audio, Text, Captions, Sticker, FX, Transitions, Filter, Adjust/Smart.
- Import/search affordances are present and discoverable.

Remaining gaps:
- CapCut's browser is a working asset grid immediately: categories/folders on the left, asset cards in a compact grid, thumbnails at high density.
- MovieCut empty browser is dominated by one large import card. This is good onboarding but weak as an editor browser once the app is open.
- MovieCut left rail labels are stacked vertically in compact badges; useful, but visually heavier and more segmented than CapCut's icon row/rail rhythm.
- Search bar and import card consume too much vertical attention for an empty editor. CapCut puts import/source controls at the top, then gives most space to asset/template browsing.
- Captions/Adjustment category parity is visually present in MovieCut, but the browser content for those modes needs product-grade surfaces to avoid feeling like placeholder tabs.

Priority:
- P0 for next polish loop. This is the biggest visible difference in the current side-by-side.

Recommended polish:
- Convert empty Media view from a single large drop card into a CapCut-like browser surface:
  - compact import/source row at top,
  - smaller empty drop tile,
  - reserved grid area for recent/imported assets,
  - sample skeleton cards or clear drop targets that match the final asset-card rhythm.
- Tighten left category rail spacing and reduce badge heaviness.
- Add/verify Captions and Adjust panels as first-class browser modes, or deliberately hide them until content exists.
- Make asset cards, template cards, effects, filters, transitions share one visual language.

### R3. Preview / canvas

What improved:
- Preview transport is now bottom-docked, matching CapCut's canvas-to-timeline flow.
- Canvas is visually central and uses a dark matte/editor surface.
- Empty import CTA is clear.

Remaining gaps:
- MovieCut empty preview contains a large decorative perspective/grid scaffold. It gives a nice branded empty state, but it is less like CapCut's editor canvas, which prioritizes actual media/canvas and keeps empty panels quieter.
- The centered import modal/card plus the left import card duplicates the same onboarding action in two large places.
- Preview control strip is functional but broader and more segmented than CapCut's compact transport strip.
- Current/Duration labels are separated to left/right, which is readable but gives a dashboard feel. CapCut's time/transport region feels more integrated.

Priority:
- P1. Important, but after the left browser because IA is now correct and controls are in the right zone.

Recommended polish:
- Reduce empty preview scaffold intensity; make it more like a quiet canvas matte with a compact import CTA.
- Avoid duplicating two dominant import cards; make either left browser or preview the primary onboarding target depending on state.
- Compact bottom transport into one tighter center-weighted strip: timecode, play controls, canvas badge, zoom/safe/volume with lower chrome.
- Validate selected text/video states after this pass, not just empty state.

### R4. Right inspector

What improved:
- Inspector is context-aware and no longer exposes unrelated editing content by default.
- Empty/no-selection project summary is useful and clean.
- Export summary is user-facing, not governance/debug text.

Remaining gaps:
- CapCut's right panel is usually a contextual property editor; MovieCut empty state is a dashboard with Project, Canvas, Timeline, Export Summary cards. Useful, but visually more administrative than creative.
- Row/card borders and repeated labels make the inspector feel ledger-like.
- Export Summary occupies a lot of no-selection visual weight even when the user has not entered export flow.
- Inspector title area is simple but lacks CapCut's tab/section hierarchy rhythm for selected clips.

Priority:
- P1/P2. High impact when clips are selected; lower impact in empty state.

Recommended polish:
- In no-selection state, reduce Export Summary prominence or collapse it behind a smaller project/export chip.
- Move toward flatter grouped rows with fewer card outlines.
- For selected video/text/audio states, verify and polish tab rhythm, row spacing, slider/value layout, and selected-state hierarchy.
- Keep Project/Canvas/Timeline summaries useful but visually quieter.

### R5. Timeline / edit command center

What improved:
- Timeline now correctly owns edit commands.
- Header has explicit Edit / Quick Tools / Markers / Zoom clusters.
- Tracks and rows are visible, with Video/Audio/Text separation and main video indication.

Remaining gaps:
- CapCut timeline is clip-first: colored clips, thumbnails/waveforms, selected outlines, and playhead dominate.
- MovieCut empty timeline is track-grid-first and spreadsheet-like; it shows rows well but not the editing affordance richness.
- Cluster labels improve understandability but may be slightly too textual/developer-like compared with CapCut's compact icon toolbar.
- The zoom cluster at far right is usable, but it visually competes with the edit toolbar row because it stretches wide.
- Track headers are readable but dense and boxy.

Priority:
- P0/P1 once populated-state capture is re-established. Timeline is the main editor surface.

Recommended polish:
- Run a populated-state review after IA pass and compare selected clip states.
- Improve clip surfaces: thumbnails/waveform/text-strip density, selected outline, status labels, and handles.
- Consider reducing cluster label prominence once discoverability is sufficient; keep accessibility labels.
- Make timeline header clusters visually lighter so clips and playhead remain the focus.
- Tune track header height/contrast and reduce grid heaviness.

### R6. Global density / hierarchy / product feel

What improved:
- Dark-shell visual metric target was met before IA pass.
- IA ownership is now more coherent.
- The app now has complete surfaces for browser, preview, inspector, and timeline.

Remaining gaps:
- MovieCut still has more visible borders, cards, labels, and large controls than CapCut.
- Empty state is visually polished but too "onboarding dashboard" compared with a production editor canvas.
- Many controls are correct but compete equally; primary/secondary hierarchy needs another polish pass.
- Current screenshots are not yet matched state-to-state: CapCut reference is populated; MovieCut current capture is empty. A populated current MovieCut capture is needed before making final design claims.

Priority:
- P0 verification task, not necessarily code task.

Recommended polish:
- Rebuild a current populated MovieCut state after IA pass: video + audio + text selected.
- Capture CapCut and MovieCut in matching states where possible.
- Re-run visual metrics only after state matching; otherwise use side-by-side design review as the primary signal.

## Next polish priority stack

### P0 — Left browser + timeline populated-state review

Why:
- Largest visible side-by-side mismatch is the left content browser and the empty/timeline composition.
- These are the places users scan first to understand whether the app feels like a real editor.

Scope:
- Left browser empty/media state compacting.
- Asset/template/effects card rhythm unification.
- Timeline populated-state capture and visual tuning.

Acceptance criteria:
- Empty state no longer shows two equally dominant import CTAs.
- Left browser has a clear content-grid rhythm even before/after import.
- Populated timeline reads clip-first, not grid-first.
- `git diff --check`, `swift build`, `swift test --filter StaticContract`, `xcodebuild ... build` pass.
- New side-by-side screenshot stored under `/tmp/moviecut-ui-evidence/current-loop/`.

### P1 — Preview + inspector hierarchy polish

Why:
- IA is fixed, but preview/inspector still carry a dashboard/card feel.

Scope:
- Compact bottom transport strip.
- Quieter empty preview matte/CTA.
- Inspector no-selection summary de-emphasis.
- Selected clip inspector row/slider rhythm review.

Acceptance criteria:
- Preview canvas remains visually central with less duplicated onboarding.
- Inspector no-selection is useful but lower-noise.
- Selected video/text/audio inspector states remain immediately understandable.

### P2 — Top chrome and micro-density polish

Why:
- Top toolbar is structurally correct, but still visually heavier than CapCut.

Scope:
- Reduce secondary toolbar chrome.
- Tighten spacing around view/project controls.
- Keep Export primary.

Acceptance criteria:
- Top toolbar reads as project/view/export chrome, not a general command shelf.
- No reintroduction of Split/Delete/Add Marker to top toolbar.

### P3 — Documentation and verification cleanup

Why:
- Docs contain stale state markers from older passes.

Scope:
- Update `CAPCUT_UI_PARITY_REQUIREMENTS.md` current-state snapshot.
- Mark completed hover preview/project status/visual metric/IA pass consistently.
- Add this audit to handoff references.

Acceptance criteria:
- No stale ❌ entries for already-completed R1-02/R2-04/visual metric state.
- Remaining backlog is explicit and prioritized.

## Recommended next implementation prompt

Implement P0: left browser + timeline populated-state polish.

Constraints:
- Presentation-layer only.
- Prefer `MediaLibraryPanel.swift`, `TimelineView.swift`, and shared tokens in `InspectorShared.swift`.
- Do not touch render/export/playback/session/Core model behavior.
- Preserve IA/menu-position contract from `IAMenuPositionStaticContractTests.swift`.
- Verify with build/static contracts/xcodebuild and a current populated screenshot.

Main goals:
1. Make left browser feel like a CapCut-style content browser instead of a large import utility panel.
2. Make populated timeline read clip-first with stronger selected/clip/media affordances and lower grid/header noise.
3. Keep accessibility and existing ViewModel wiring intact.
