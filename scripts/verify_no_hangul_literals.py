#!/usr/bin/env python3
"""L10N-01 (review 2026-08-26, expanded 2026-11-22): block hardcoded Hangul
string literals in BOTH iOS and Mac production app sources. The catalog's
source language is English; a Korean literal in a Text/Button bypasses the
catalog entirely and shows Korean in EVERY environment. Korean in COMMENTS
(`//` and `/* ... */`) is ignored via comment-aware lexing. DEBUG-only UI test
harnesses (`UITestHarness.swift`, `IOSUITestHarness.swift`) are excluded.

Usage: python3 scripts/verify_no_hangul_literals.py [extra dirs...]
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_TARGETS = [ROOT / "App" / "MovieCutiOS", ROOT / "App" / "MovieCutMac"]
TARGETS = DEFAULT_TARGETS + [Path(a).resolve() for a in sys.argv[1:]]
EXCLUDED_FILENAMES = {"UITestHarness.swift", "IOSUITestHarness.swift"}

HANGUL_IN_TEXT = re.compile(r"[\uAC00-\uD7A3]")


def extract_string_literals(source: str) -> list[tuple[int, str]]:
    """Comment-aware scanner returning (1-based line, literal) for quoted strings."""
    results: list[tuple[int, str]] = []
    i = 0
    n = len(source)
    line = 1
    while i < n:
        ch = source[i]
        if ch == "\n":
            line += 1
            i += 1
            continue
        # Line comment //
        if ch == "/" and i + 1 < n and source[i + 1] == "/":
            nl = source.find("\n", i + 2)
            if nl == -1:
                break
            line += 1
            i = nl + 1
            continue
        # Block comment /* ... */ (Swift supports nesting)
        if ch == "/" and i + 1 < n and source[i + 1] == "*":
            depth = 1
            i += 2
            while i < n and depth > 0:
                if source[i] == "\n":
                    line += 1
                    i += 1
                elif source[i] == "/" and i + 1 < n and source[i + 1] == "*":
                    depth += 1
                    i += 2
                elif source[i] == "*" and i + 1 < n and source[i + 1] == "/":
                    depth -= 1
                    i += 2
                else:
                    i += 1
            continue
        # Multiline string """..."""
        if source.startswith('"""', i):
            start_line = line
            end = source.find('"""', i + 3)
            if end == -1:
                break
            body = source[i + 3 : end]
            line += body.count("\n")
            results.append((start_line, f'"""{body}"""'))
            i = end + 3
            continue
        # Single-line string "..."
        if ch == '"':
            start_line = line
            j = i + 1
            while j < n and source[j] != "\n":
                if source[j] == "\\":
                    j += 2
                    continue
                if source[j] == '"':
                    results.append((start_line, source[i : j + 1]))
                    j += 1
                    break
                j += 1
            i = j
            continue
        i += 1
    return results


violations: list[str] = []
for base in TARGETS:
    if not base.exists():
        continue
    for path in sorted(base.rglob("*.swift")):
        if "Tests" in path.parts or "UITests" in path.parts:
            continue
        if path.name in EXCLUDED_FILENAMES:
            continue
        text = path.read_text(encoding="utf-8")
        for lineno, literal in extract_string_literals(text):
            if HANGUL_IN_TEXT.search(literal):
                violations.append(f"{path.relative_to(ROOT)}:{lineno}: {literal}")

if violations:
    print("Hardcoded Hangul string literals found (use catalog keys instead):")
    for violation in violations:
        print(f"  {violation}")
    sys.exit(1)

print("no Hangul literals in Mac or iOS production app sources")
