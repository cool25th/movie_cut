#!/usr/bin/env bash
# High-signal lint gate (req 15.5 / task 8.4).
#
# The full SwiftLint run carries 692 findings (measured 2026-07-31 after the
# identifier_name relaxation), too many to gate CI on without blocking every
# PR. This script instead enforces a small ALLOW-LIST of rules whose ERROR
# severity signals a real correctness / crash risk, not style:
#
#   force_cast        (as!)  — crash on unexpected type
#   force_try         (try!) — crash on thrown error
#   shorthand_operator       — style only, but errors are few and trivial to fix
#
# force_unwrapping is deliberately NOT in the gate: it is an opt-in rule with
# 241 existing findings, so gating on it is not convertible today (recorded in
# .kiro/specs/capcut-parity-and-bugfix/verification-debt-8.md §4).
#
# Usage:
#   scripts/lint_gate.sh            # enforces the allow-list (CI-blocking)
#   scripts/lint_gate.sh --report   # report counts only, never fail
#
# Exit code 0 = no allow-list violations; 1 = violations present.
set -uo pipefail

cd "$(dirname "$0")/.."

REPORT_ONLY=0
[ "${1:-}" = "--report" ] && REPORT_ONLY=1

if ! command -v swiftlint &> /dev/null; then
  echo "lint_gate: SwiftLint not installed (brew install swiftlint)."
  # Missing tool is a hard fail in CI so the gate cannot silently pass.
  exit 1
fi

ALLOW_LIST="force_cast,force_try,shorthand_operator"

# --quiet suppresses per-file progress; we only want violations.
OUTPUT=$(swiftlint lint --quiet --force-exclude . 2>&1)
# Filter to only the allow-listed rules + error severity.
HITS=$(printf '%s\n' "$OUTPUT" | grep -E ": (error): .*\((${ALLOW_LIST//,/|})\)$" || true)

if [ -z "$HITS" ]; then
  echo "lint_gate: PASS (0 allow-list violations: ${ALLOW_LIST})"
  exit 0
fi

COUNT=$(printf '%s\n' "$HITS" | wc -l | tr -d ' ')
echo "lint_gate: FAIL ($COUNT allow-list violation(s) for rules: ${ALLOW_LIST})"
printf '%s\n' "$HITS"
echo ""
echo "These are correctness-risk rules. Fix them (replace as!/try! with safe"
echo "unwraps, or add a typed fixture), or document a baseline exception."
if [ "$REPORT_ONLY" -eq 1 ]; then
  echo "lint_gate: --report mode, not failing the build."
  exit 0
fi
exit 1
