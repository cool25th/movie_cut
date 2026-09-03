#!/usr/bin/env bash
# Verifies that every repo-local path referenced by ACTIVE docs and agent
# command files actually exists (docs/archive/ is frozen history and is not
# checked — active ledgers must not point back into it as sources of truth).
#
# Resolution rules:
#   - Backtick-quoted paths (`docs/X.md`) are REPO-ROOT-relative and only
#     verified when rooted at a known repo directory — prose fragments like
#     `Commands/` inside wrapped directory trees are not path references.
#   - Markdown links [text](path) resolve relative to the FILE's directory
#     (GitHub semantics), falling back to repo-root.
#   - Build outputs (build/) and URLs/anchors are skipped.
#
# Usage: bash scripts/verify_doc_paths.sh   (from anywhere; resolves repo root)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

KNOWN_ROOTS="docs/ scripts/ Sources/ App/ Tests/ .claude/ .github/ MovieCut.xcodeproj"

fail=0
checked=0

is_known_root() {
  local ref="$1" root
  for root in $KNOWN_ROOTS; do
    case "$ref" in
      "$root"*) return 0 ;;
    esac
  done
  return 1
}

note_missing() {
  echo "MISSING: $1  (referenced in $2)" >&2
  fail=1
}

# CODEX-03 stale-allowlist: opening the backtick gate exposed 27
# pre-existing references to files that were archived or moved before the
# check could see them (they live in historical spec/handoff docs).
# Listed explicitly so NEW broken references still fail while these await
# doc cleanup — do not add to this list for new content.
known_stale_ref() {
  case "$1" in
    docs/CAPCUT_PARITY_SPEC.md|docs/USABILITY_BENCHMARK_STANDARD.md|\
    docs/PERF_BASELINE_20260622.md|docs/NEXT_SESSION_WORKORDER_20260729.md|\
    docs/STATIC_CONTRACT_TRIAGE_20260728.md|docs/CAPCUT_CORE_EDITING_REPAIR_HANDOFF_20260727.md|\
    docs/CAPCUT_UI_PARITY_REQUIREMENTS.md|docs/UIUX_HANDOFF.md|docs/CAPCUT_UI_SHOWCASE_HANDOFF.md|\
    docs/EXECUTION_PLAN_PHASE2_20260819.md|docs/UI_CAPTURE_DIAGNOSIS_PROMPT_20260817.md|\
    docs/MovieCut_Compositor_Validation_Prompt.md|\
    Sources/MovieCutCore/Models/CaptionStyle.swift|\
    Sources/MovieCutCore/Audio/VoiceEffectPreset.swift|\
    Sources/MovieCutCore/Export/FCPXMLExporter.swift|\
    Sources/MovieCutCore/CardNews/ScriptCardDistributor.swift|\
    App/MovieCutMac/Audio/VocalSeparationRenderer.swift|\
    App/MovieCutMac/Audio/VoiceEffectRenderer.swift|\
    App/MovieCutMac/Effects/EffectBrowserView.swift|\
    App/MovieCutMac/Media/ImageVideoRenderService.swift|\
    App/MovieCutMac/CardNews/BrandKitStore.swift|\
    App/MovieCutMac/Home/RecentProjectsStore.swift|\
    App/MovieCutMac/UIKitCommon/ToastCenter.swift|\
    App/MovieCutMac/Settings/AppPreferences.swift|\
    App/MovieCutMac/Library/BrowserCard.swift|\
    App/MovieCutMac/Palette/CommandRegistry.swift)
      return 0 ;;
  esac
  return 1
}

check_backtick() {
  local ref="$1" file="$2"
  case "$ref" in
    http://*|https://*|file://*|build/*|*\ *) return ;;
  esac
  # Only FILE references: directory trees in specs describe planned
  # increments (Sources/.../Plugins/, App/.../Palette/) that legitimately
  # do not exist yet, and `...` marks elisions.
  case "$ref" in
    *.md|*.swift|*.sh|*.py|*.yml|*.yaml|*.plist|*.json|*.xcstrings|*.xcodeproj|*.strings|*.txt|*.cube|*.wav|*.mp4) ;;
    *) return ;;
  esac
  case "$ref" in
    *...*) return ;;
  esac
  known_stale_ref "$ref" && return
  is_known_root "$ref" || return
  checked=$((checked + 1))
  [ -e "$ref" ] || note_missing "$ref" "$file"
}

check_link() {
  local ref="$1" file="$2" dir
  dir="$(dirname "$file")"
  case "$ref" in
    http://*|https://*|file://*|mailto:*|\#*|build/*) return ;;
  esac
  # Same-directory links (no slash) resolve against the file's own
  # directory — a broken same-dir .md link must fail the check too.
  checked=$((checked + 1))
  if [ ! -e "$dir/$ref" ] && [ ! -e "$ref" ]; then
    note_missing "$ref" "$file"
  fi
}

for file in docs/*.md .claude/commands/*.md; do
  [ -f "$file" ] || continue
  while IFS= read -r ref; do
    check_backtick "${ref%\`}" "$file"
  # CODEX-03: the old pattern required the match to END at a slash, so a
  # file reference like `docs/DOES_NOT_EXIST.md` was extracted as `docs/`
  # and then ignored (no recognized extension) — the backtick check never
  # validated what it was built for. Match through the closing backtick or
  # end of token instead.
  done < <(grep -oE '`[A-Za-z0-9_.][A-Za-z0-9_./-]*`?' "$file" 2>/dev/null | sed 's/^`//')

  while IFS= read -r ref; do
    check_link "$ref" "$file"
  done < <(grep -oE '\]\([A-Za-z0-9_][^)#?[:space:]]*\)' "$file" 2>/dev/null | sed 's/^](//; s/)$//')
done

if [ "$fail" -ne 0 ]; then
  echo "DOC PATH CHECK: FAIL ($checked path refs verified)" >&2
  exit 1
fi
echo "DOC PATH CHECK: OK ($checked path refs verified)"
