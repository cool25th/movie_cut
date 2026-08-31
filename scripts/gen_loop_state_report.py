#!/usr/bin/env python3
"""STAB-08: generate a measured gate-status table from recorded history.

Inputs — JSON files under .build-check/history/, each written by a recorder
at the END of the corresponding gate run:

  gate-<epoch>.json     {ts, steps: {name: OK|FAIL}, overall: GATE_PASS|GATE_FAIL}
  w-smoke-<epoch>.json  {ts, workflows: {name: PASS|FAIL}, steps_ok, steps_total}
  parity-<epoch>.json   {ts, scenarios: {name: PASS|FAIL}, worst_mad}

Output: a compact markdown table on stdout; --write renders it to
docs/LOOP_STATE_REPORT.md. The table reflects the LAST 3 runs of each gate —
the structural answer to the external review #9 contradiction (a narrative
LOOP_STATE claiming W 5/5 while the measured run said 4/5): the report is
generated ONLY from recorded artifacts, never hand-edited.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HISTORY = os.path.join(ROOT, ".build-check", "history")


def load_series(prefix: str, limit: int = 3) -> list[dict]:
    files = sorted(glob.glob(os.path.join(HISTORY, f"{prefix}-*.json")))
    out = []
    for path in files[-limit:]:
        try:
            with open(path) as f:
                out.append(json.load(f))
        except (OSError, json.JSONDecodeError):
            continue
    return out


def fmt_ts(ts) -> str:
    try:
        return datetime.fromisoformat(ts).strftime("%m-%d %H:%M")
    except (TypeError, ValueError):
        return "?"


def summarize(verdicts: list[str]) -> str:
    ok = sum(1 for v in verdicts if v in ("OK", "PASS", "GATE_PASS"))
    return f"{ok}/{len(verdicts)}" if verdicts else "—"


def render() -> str:
    lines = ["# LOOP STATE REPORT (generated — do not hand-edit)", ""]
    lines.append("_Generated: " + datetime.now().isoformat(timespec="seconds")
                 + " from `.build-check/history/` (last 3 runs per gate)._")

    gate = load_series("gate")
    lines.append("## verify_gate (5-step)")
    lines.append("| run | steps | overall |")
    lines.append("|---|---|---|")
    for entry in gate:
        steps = entry.get("steps", {})
        step_txt = " ".join(f"{name}:{v}" for name, v in steps.items())
        lines.append(f"| {fmt_ts(entry.get('ts'))} | {step_txt or '—'} | {entry.get('overall', '?')} |")
    if not gate:
        lines.append("| (no recorded runs) | | |")
    lines.append("")

    smoke = load_series("w-smoke")
    lines.append("## W smoke (representative workflows)")
    lines.append("| run | workflows | steps | verdict |")
    lines.append("|---|---|---|---|")
    for entry in smoke:
        flows = entry.get("workflows", {})
        verdicts = list(flows.values())
        overall = "PASS" if verdicts and all(v == "PASS" for v in verdicts) else "FAIL"
        lines.append(f"| {fmt_ts(entry.get('ts'))} | {summarize(verdicts)} | "
                     f"{entry.get('steps_ok', '?')}/{entry.get('steps_total', '?')} | {overall} |")
    if not smoke:
        lines.append("| (no recorded runs) | | | |")
    lines.append("")

    parity = load_series("parity")
    lines.append("## Core editing parity (preview ↔ export)")
    lines.append("| run | scenarios | failing | worst MAD |")
    lines.append("|---|---|---|---|")
    for entry in parity:
        scenarios = entry.get("scenarios", {})
        failing = [name for name, v in scenarios.items() if v != "PASS"]
        worst = entry.get("worst_mad")
        worst_txt = f"{worst:.2f}" if isinstance(worst, (int, float)) else "—"
        lines.append(f"| {fmt_ts(entry.get('ts'))} | {summarize(list(scenarios.values()))} | "
                     f"{', '.join(failing) or '—'} | {worst_txt} |")
    if not parity:
        lines.append("| (no recorded runs) | | | |")
    lines.append("")
    lines.append("_Known registered flakes appear here by name until their root "
                 "(BUG-CA12-01 class) is fixed — the table shows what WAS measured, "
                 "not what we wish were true._")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true",
                        help="render to docs/LOOP_STATE_REPORT.md instead of stdout")
    parser.add_argument("--check-reproducible", action="store_true",
                        help="render twice and fail if the tables differ (the "
                             "STAB-08 reproducibility DoD; the timestamp line "
                             "is excluded)")
    args = parser.parse_args()

    if args.check_reproducible:
        import copy
        def strip_ts(text: str) -> str:
            return re.sub(r"_Generated:.*?_", "_Generated:_", text, count=1)
        first = strip_ts(render())
        second = strip_ts(render())
        if first != second:
            print("REPRODUCIBILITY FAIL: two renders differ", file=sys.stderr)
            return 1
        print("REPRODUCIBLE: two renders identical")
        return 0

    text = render()
    if args.write:
        target = os.path.join(ROOT, "docs", "LOOP_STATE_REPORT.md")
        with open(target, "w") as f:
            f.write(text)
        print(f"wrote {os.path.relpath(target, ROOT)}")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
