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
  done < <(grep -oE '`[A-Za-z0-9_.][A-Za-z0-9_./-]*/`?' "$file" 2>/dev/null | sed 's/^`//')

  while IFS= read -r ref; do
    check_link "$ref" "$file"
  done < <(grep -oE '\]\([A-Za-z0-9_][^)#?[:space:]]*\)' "$file" 2>/dev/null | sed 's/^](//; s/)$//')
done

if [ "$fail" -ne 0 ]; then
  echo "DOC PATH CHECK: FAIL ($checked path refs verified)" >&2
  exit 1
fi
echo "DOC PATH CHECK: OK ($checked path refs verified)"
