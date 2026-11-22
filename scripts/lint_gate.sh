#!/usr/bin/env bash
# High-signal lint gate (req 15.5 / task 8.4).
#
# Enforces a small ALLOW-LIST of rules whose ERROR severity signals a real
# correctness / crash risk, not style:
#
#   force_cast        (as!)  — crash on unexpected type
#   force_try         (try!) — crash on thrown error
#   shorthand_operator       — style only, but errors are few and trivial to fix
#
# Also detects SwiftLint runtime crashes (e.g. missing sourcekitdInProc.framework
# on CLT-only macOS hosts without Xcode.app) so the gate can NEVER silently pass
# on a broken SwiftLint invocation:
#   - In CI (`CI=true`) or with `--require-swiftlint`, a SwiftLint crash is a
#     hard failure.
#   - Locally without Xcode, falls back to a comment/string-aware Python scanner
#     enforcing `force_cast` and `force_try` across Sources/, App/, Tests/ and
#     prints an explicit warning that full SwiftLint requires Xcode.
#
# Optional force_unwrapping ratchet:
#   Set `FORCE_UNWRAP_MAX=<n>` (or `--max-force-unwrap <n>`) to fail when
#   SwiftLint reports more than <n> `force_unwrapping` findings.
#
# Usage:
#   scripts/lint_gate.sh                        # enforces the allow-list (CI-blocking)
#   scripts/lint_gate.sh --report               # report counts only, never fail
#   scripts/lint_gate.sh --require-swiftlint    # fail if SwiftLint cannot load sourcekitd
#   scripts/lint_gate.sh --max-force-unwrap N   # fail if force_unwrapping exceeds N
#
# Exit code 0 = no allow-list violations; 1 = violations or broken gate.
set -uo pipefail

cd "$(dirname "$0")/.."

REPORT_ONLY=0
REQUIRE_SWIFTLINT=0
FORCE_UNWRAP_MAX="${FORCE_UNWRAP_MAX:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --report)
      REPORT_ONLY=1
      ;;
    --require-swiftlint)
      REQUIRE_SWIFTLINT=1
      ;;
    --max-force-unwrap)
      shift
      FORCE_UNWRAP_MAX="${1:-}"
      ;;
    *)
      echo "lint_gate: unknown option: $1" >&2
      exit 2
      ;;
  esac
  shift
done

if [ "${CI:-}" = "true" ] || [ "${GITHUB_ACTIONS:-}" = "true" ]; then
  REQUIRE_SWIFTLINT=1
fi

run_clt_fallback_check() {
  python3 - "$REPORT_ONLY" <<'PY'
import re
import sys
from pathlib import Path

report_only = sys.argv[1] == "1"
roots = [Path("Sources"), Path("App"), Path("Tests")]
# Match `as!` or `try!` tokens in Swift code (outside comments/strings).
pattern = re.compile(r"\b(as!|try!)(?=\s|\(|\[|$)")
disable_next_re = re.compile(r"swiftlint:disable:next\s+([^\n]+)")
disable_this_re = re.compile(r"swiftlint:disable:this\s+([^\n]+)")
disable_block_re = re.compile(r"swiftlint:disable(?!:next|:this)\s+([^\n]+)")
enable_block_re = re.compile(r"swiftlint:enable\s+([^\n]+)")


def strip_strings_and_comments(source: str):
    """Yield (line_no, code_only_line, comment_text) preserving line numbers."""
    n = len(source)
    i = 0
    line_no = 1
    code_buf: list[str] = []
    comment_buf: list[str] = []
    block_comment_depth = 0

    def flush():
        nonlocal code_buf, comment_buf
        res = (line_no, "".join(code_buf), "".join(comment_buf))
        code_buf = []
        comment_buf = []
        return res

    while i < n:
        ch = source[i]
        nxt = source[i + 1] if i + 1 < n else ""

        if block_comment_depth > 0:
            if ch == "/" and nxt == "*":
                block_comment_depth += 1
                comment_buf.append("/*")
                i += 2
            elif ch == "*" and nxt == "/":
                block_comment_depth -= 1
                comment_buf.append("*/")
                i += 2
            elif ch == "\n":
                yield flush()
                line_no += 1
                i += 1
            else:
                comment_buf.append(ch)
                i += 1
            continue

        # Line comment
        if ch == "/" and nxt == "/":
            end = source.find("\n", i)
            if end == -1:
                comment_buf.append(source[i:])
                i = n
            else:
                comment_buf.append(source[i:end])
                yield flush()
                line_no += 1
                i = end + 1
            continue

        # Block comment start
        if ch == "/" and nxt == "*":
            block_comment_depth = 1
            comment_buf.append("/*")
            i += 2
            continue

        # Raw / multiline / normal string literals (skip contents so prose `try!`/`as!` isn't flagged)
        if ch == "#" or ch == '"':
            hashes = 0
            j = i
            while j < n and source[j] == "#":
                hashes += 1
                j += 1
            if j < n and source[j] == '"':
                is_multiline = source[j:j + 3] == '"""'
                delim = ('"""' if is_multiline else '"') + ("#" * hashes)
                i = j + (3 if is_multiline else 1)
                code_buf.append(" ")
                while i < n:
                    if source.startswith(delim, i):
                        i += len(delim)
                        break
                    if source[i] == "\\" and hashes == 0 and i + 1 < n:
                        if source[i + 1] == "\n":
                            yield flush()
                            line_no += 1
                        i += 2
                        continue
                    if source[i] == "\n":
                        yield flush()
                        line_no += 1
                    i += 1
                continue
            elif hashes > 0:
                code_buf.append(ch)
                i += 1
                continue

        if ch == "\n":
            yield flush()
            line_no += 1
            i += 1
            continue

        code_buf.append(ch)
        i += 1

    if code_buf or comment_buf:
        yield flush()


def rule_matches(disabled: set[str], rule: str) -> bool:
    return "all" in disabled or rule in disabled


hits: list[str] = []
scanned = 0
for root in roots:
    if not root.exists():
        continue
    for path in sorted(root.rglob("*.swift")):
        scanned += 1
        text = path.read_text(encoding="utf-8")
        disabled_block: set[str] = set()
        disable_next: set[str] = set()
        for line_no, code, comment in strip_strings_and_comments(text):
            active_this: set[str] = set(disable_next)
            disable_next = set()
            if comment:
                m_this = disable_this_re.search(comment)
                if m_this:
                    active_this.update(m_this.group(1).split())
                m_next = disable_next_re.search(comment)
                if m_next:
                    disable_next.update(m_next.group(1).split())
                m_dis = disable_block_re.search(comment)
                if m_dis:
                    disabled_block.update(m_dis.group(1).split())
                m_en = enable_block_re.search(comment)
                if m_en:
                    for tok in m_en.group(1).split():
                        if tok == "all":
                            disabled_block.clear()
                        else:
                            disabled_block.discard(tok)
            for m in pattern.finditer(code):
                token = m.group(1)
                rule = "force_cast" if token == "as!" else "force_try"
                if rule_matches(disabled_block, rule) or rule_matches(active_this, rule):
                    continue
                hits.append(f"{path}:{line_no}: error: {token} violation ({rule})")

if not hits:
    print(f"lint_gate: CLT fallback PASS (0 force_cast/force_try violations across {scanned} Swift files; full SwiftLint requires Xcode)")
    sys.exit(0)

print(f"lint_gate: FAIL ({len(hits)} violation(s) via CLT fallback for force_cast,force_try)")
for h in hits:
    print(h)
sys.exit(0 if report_only else 1)
PY
}

if ! command -v swiftlint &> /dev/null; then
  echo "lint_gate: SwiftLint not installed (brew install swiftlint)." >&2
  if [ "$REQUIRE_SWIFTLINT" -eq 1 ]; then
    exit 1
  fi
  echo "lint_gate: WARNING — falling back to CLT force_cast/force_try scanner." >&2
  run_clt_fallback_check
  exit $?
fi

ALLOW_LIST="force_cast,force_try,shorthand_operator"

# --quiet suppresses per-file progress; capture exit status without aborting.
OUTPUT=$(swiftlint lint --quiet --force-exclude . 2>&1)
SWIFTLINT_RC=$?

# SwiftLint returns 0 (clean) or 2 (lint violations found). Any crash (e.g.
# missing sourcekitdInProc on CLT-only macOS -> SIGILL/SIGTRAP/Fatal error)
# MUST NOT be mistaken for 0 violations.
if printf '%s\n' "$OUTPUT" | grep -qE "Fatal error:|sourcekitdInProc|Library not loaded|Trace/BPT trap|Illegal instruction" \
   || { [ "$SWIFTLINT_RC" -ne 0 ] && [ "$SWIFTLINT_RC" -ne 2 ]; }; then
  echo "lint_gate: SwiftLint failed to execute (exit code ${SWIFTLINT_RC})." >&2
  printf '%s\n' "$OUTPUT" | head -n 5 >&2
  if [ "$REQUIRE_SWIFTLINT" -eq 1 ]; then
    echo "lint_gate: FAIL — SwiftLint is required in CI / --require-swiftlint mode." >&2
    exit 1
  fi
  echo "lint_gate: WARNING — Xcode/sourcekitd unavailable; running CLT force_cast/force_try fallback." >&2
  run_clt_fallback_check
  exit $?
fi

# Filter to only the allow-listed rules + error severity.
HITS=$(printf '%s\n' "$OUTPUT" | grep -E ": (error): .*\((${ALLOW_LIST//,/|})\)$" || true)
FORCE_UNWRAP_COUNT=$(printf '%s\n' "$OUTPUT" | grep -cE "\((force_unwrapping)\)$" || true)

FAILED=0
if [ -n "$HITS" ]; then
  COUNT=$(printf '%s\n' "$HITS" | wc -l | tr -d ' ')
  echo "lint_gate: FAIL ($COUNT allow-list violation(s) for rules: ${ALLOW_LIST})"
  printf '%s\n' "$HITS"
  echo ""
  echo "These are correctness-risk rules. Fix them (replace as!/try! with safe"
  echo "unwraps, or add a typed fixture), or document a baseline exception."
  FAILED=1
fi

if [ -n "$FORCE_UNWRAP_MAX" ] && [ "$FORCE_UNWRAP_COUNT" -gt "$FORCE_UNWRAP_MAX" ]; then
  echo "lint_gate: FAIL (force_unwrapping count ${FORCE_UNWRAP_COUNT} exceeds ceiling ${FORCE_UNWRAP_MAX})"
  FAILED=1
fi

if [ "$FAILED" -eq 0 ]; then
  echo "lint_gate: PASS (0 allow-list violations: ${ALLOW_LIST}; force_unwrapping=${FORCE_UNWRAP_COUNT})"
  exit 0
fi

if [ "$REPORT_ONLY" -eq 1 ]; then
  echo "lint_gate: --report mode, not failing the build."
  exit 0
fi
exit 1
