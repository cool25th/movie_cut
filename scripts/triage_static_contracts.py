#!/usr/bin/env python3
"""Classify MovieCut StaticContract tests into KEEP / REPLACE / DELETE / EXCLUDE.

StaticContract tests assert source-string presence rather than behavior. The
review (docs/README.md §6 rule #2) and the established triage policy
(docs/STATIC_CONTRACT_TRIAGE_20260728.md) call for shrinking this debt. This
script automates the classification with the heuristics the codebase audit
identified, so progress is measurable and re-runnable.

Buckets (per STATIC_CONTRACT_TRIAGE_20260728.md):
  EXCLUDE  — file matches "StaticContract" grep but does NOT read source
             (already a behavior test; "StaticContract" is only in a comment).
  KEEP     — legitimate source-level contract:
             - boundary-direction negatives (a UI slice must NOT reference a
               Core service symbol: ExportEngine/PlaybackEngine/EditorSession/
               dispatchCommand/session.dispatch/apply().
             - forbidden-term lists checked against shipping UI copy.
  DELETE   — fake signal: defect-locking negatives ("feature X is absent") or
             brittle exact-equality over enum cases / UI constants.
  REPLACE  — positive `contains` of a processor/method call standing in for
             "it is wired"; should become a behavior/golden test.

Usage:
    triage_static_contracts.py [--root REPO] [--out PATH]
Defaults: --root = repo root (script's parent's parent), --out = stdout.
Exit 0. The result is a markdown table suitable for committing.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

# Core service symbols — a negative check against these in a UI slice is a
# legitimate boundary contract (KEEP).
BOUNDARY_SYMBOLS = (
    "ExportEngine", "PlaybackEngine", "EditorSession", "dispatchCommand",
    "session.dispatch", "apply(", "ProjectStore", "RenderCache",
)

# Feature names that, when the subject of a NEGATIVE assertion, indicate a
# defect-lockout (the feature was removed and the test guards its absence).
# "absent feature must stay absent" is not a regression signal — DELETE.
DEFECT_LOCK_FEATURES = (
    "syncToCloud", "isCloudSyncing", "libraryTabBar", "Smart tools move here",
)


@dataclass
class Verdict:
    bucket: str          # KEEP / REPLACE / DELETE / EXCLUDE
    reason: str          # one-line justification
    sample_line: int | None  # a representative line number, if found


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text(encoding="utf-8", errors="replace")


def reads_source(text: str) -> bool:
    """A StaticContract test that actually reads source code."""
    return (
        "func source(" in text
        or "#filePath" in text
        or "String(contentsOfFile" in text
        or "String(contentsOf:" in text
    )


def find_line(text: str, needle: str) -> int | None:
    for i, line in enumerate(text.splitlines(), start=1):
        if needle in line:
            return i
    return None


def classify(text: str) -> Verdict:
    if not reads_source(text):
        return Verdict("EXCLUDE", "matches grep but does not read source (behavior test)", None)

    # Forbidden-term list: a `forbidden…Terms` (or similar) array checked
    # case-insensitively against shipping UI copy. Legitimate KEEP.
    if re.search(r"forbidden\w*[Tt]erms", text) and "caseInsensitive" in text:
        ln = find_line(text, "caseInsensitive") or find_line(text, "forbidden")
        return Verdict("KEEP", "forbidden-term list against shipping copy (legitimate contract)", ln)

    # Negative assertions: `!foo.contains(`, `!bar.range(of:…)==nil`, etc.
    # Match the negation prefix on a `.contains(`/`range(of:` call regardless of
    # the receiver variable name.
    neg_re = re.compile(r"!\s*[\w.]+\.contains\(|!\s*[\w.]+\.range\(of:\s*[^)]+\)\s*==\s*nil")
    neg_lines = [(i, line) for i, line in enumerate(text.splitlines(), start=1) if neg_re.search(line)]
    has_negative = bool(neg_lines)

    # Boundary-direction KEEP: the file references a Core service symbol as a
    # QUOTED STRING literal (e.g. in a forbidden-symbols array like R305). This
    # is the signature of "this UI slice must not call that Core service", a
    # legitimate architectural boundary contract.
    boundary_quoted = any(
        re.search(r'"[^"]*\b' + re.escape(sym) + r'\b[^"]*"', text)
        for sym in BOUNDARY_SYMBOLS
    )

    # Defect-lockout: a negative assertion whose target is a removed feature /
    # UI string, checked on the same line.
    defect_lines = [
        (i, line) for i, line in neg_lines
        if any(feat in line for feat in DEFECT_LOCK_FEATURES)
    ]

    if has_negative:
        # Explicit defect-lockout wins over boundary (a defect lockout is the
        # clearest fake signal even if the file also has boundary checks).
        if defect_lines:
            feat_line, feat_line_no = defect_lines[0][1], defect_lines[0][0]
            return Verdict("DELETE", "defect-locking negative (guards absence of a removed feature)", feat_line_no)
        if boundary_quoted:
            ln = next((find_line(text, f'"{sym}"') for sym in BOUNDARY_SYMBOLS if find_line(text, f'"{sym}"')), None)
            return Verdict("KEEP", "boundary-direction negative (quoted Core service symbol — UI/Core boundary)", ln)

        # Exact enum-case array equality is brittle — breaks on any reorder/add.
        if re.search(r"\[\s*[A-Z]\w+\.\w+(?:,\s*[A-Z]\w+\.\w+)+\s*\]", text):
            ln = find_line(text, ".")
            return Verdict("DELETE", "brittle exact enum-case array equality (breaks on reorder/add)", ln)

    # Positive contains of a processor/method call = REPLACE candidate.
    processor_signal = any(tok in text for tok in (
        "PixelProcessor.apply", "Compositor.apply", "PixelProcessor.",
        "ColorCorrectionPixelProcessor", "ColorGradePixelProcessor",
        "ChromaKeyPixelProcessor", "MaskPixelProcessor", "TextOverlayPixelProcessor",
        "VisualEffectPixelProcessor", "CanvasBackgroundPixelProcessor",
        "BlendPixelProcessor", "TransitionPixelProcessor",
        "PersonSegmentationCompositor", "ClipAnimationCompositor",
    ))
    if processor_signal:
        ln = next((find_line(text, tok) for tok in (
            "PixelProcessor", "Compositor", "ColorCorrectionPixelProcessor",
        ) if find_line(text, tok)), None)
        return Verdict("REPLACE", "positive processor/wiring presence → promote to golden/behavior", ln)

    # Remaining source-reading negatives/positives we can't confidently bucket
    # land in REPLACE (review them by hand).
    if has_negative:
        return Verdict("REPLACE", "source-string negative; needs hand review (boundary vs defect)", neg_lines[0][0])
    return Verdict("REPLACE", "source-string positive wiring; needs hand review", find_line(text, "contains"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=None, help="repo root (default: inferred from script location)")
    parser.add_argument("--out", default=None, help="output markdown path (default: stdout)")
    args = parser.parse_args()

    root = Path(args.root).resolve() if args.root else Path(__file__).resolve().parent.parent
    test_dirs = [
        root / "Tests" / "MovieCutCoreTests",
        root / "App" / "MovieCutMacTests",
        root / "App" / "MovieCutMacUITests",
    ]

    # The audit identifies StaticContract files by name suffix AND by content.
    files: list[Path] = []
    for d in test_dirs:
        if d.is_dir():
            files.extend(sorted(d.glob("*.swift")))
    sc_files = [f for f in files if "StaticContract" in f.name or "StaticContract" in read(f)]

    verdicts: dict[Path, Verdict] = {}
    for f in sc_files:
        verdicts[f] = classify(read(f))

    order = {"KEEP": 0, "REPLACE": 1, "DELETE": 2, "EXCLUDE": 3}
    by_bucket: dict[str, list[tuple[Path, Verdict]]] = {}
    for f, v in verdicts.items():
        by_bucket.setdefault(v.bucket, []).append((f, v))
    for b in by_bucket:
        by_bucket[b].sort(key=lambda fv: fv[0].name)

    def rel(p: Path) -> str:
        try:
            return str(p.relative_to(root))
        except ValueError:
            return str(p)

    lines: list[str] = []
    lines.append("# StaticContract Triage — auto-classified")
    lines.append("")
    lines.append(f"> Generated by `scripts/triage_static_contracts.py`. Re-run to refresh. ")
    lines.append(f"> Total files scanned: **{len(sc_files)}**. ")
    lines.append("")
    counts = {b: len(by_bucket.get(b, [])) for b in ("KEEP", "REPLACE", "DELETE", "EXCLUDE")}
    lines.append("## Counts")
    lines.append("")
    lines.append("| Bucket | Count | Meaning |")
    lines.append("|---|---:|---|")
    lines.append(f"| KEEP | {counts['KEEP']} | Legitimate source-level contract (boundary/forbidden) — leave as-is |")
    lines.append(f"| REPLACE | {counts['REPLACE']} | Source-string presence → promote to behavior/golden |")
    lines.append(f"| DELETE | {counts['DELETE']} | Fake signal (defect-lockout / brittle equality) — remove |")
    lines.append(f"| EXCLUDE | {counts['EXCLUDE']} | Matches grep but is already a behavior test |")
    lines.append("")
    for bucket in ("KEEP", "REPLACE", "DELETE", "EXCLUDE"):
        items = by_bucket.get(bucket, [])
        if not items:
            continue
        lines.append(f"## {bucket} ({len(items)})")
        lines.append("")
        lines.append("| File | Reason | Line |")
        lines.append("|---|---|---:|")
        for f, v in items:
            ln = str(v.sample_line) if v.sample_line else "—"
            lines.append(f"| `{rel(f)}` | {v.reason} | {ln} |")
        lines.append("")

    out = "\n".join(lines) + "\n"
    if args.out:
        Path(args.out).write_text(out, encoding="utf-8")
        print(f"wrote {args.out}: KEEP={counts['KEEP']} REPLACE={counts['REPLACE']} "
              f"DELETE={counts['DELETE']} EXCLUDE={counts['EXCLUDE']}", file=sys.stderr)
    else:
        sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
