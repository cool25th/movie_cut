#!/usr/bin/env python3
"""L10N-01 (review 2026-08-26): block hardcoded Hangul string literals in
the iOS app sources. The catalog's source language is English; a Korean
literal in a Text/Button bypasses the catalog entirely and shows Korean in
EVERY environment (the effect-inspector defect: 31 literals, Korean even on
English devices). Korean in COMMENTS is fine — only quoted literals fail.

Usage: python3 scripts/verify_no_hangul_literals.py [extra dirs...]
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGETS = [ROOT / "App" / "MovieCutiOS", *[Path(a).resolve() for a in sys.argv[1:]]]

# Hangul syllables inside a double-quoted literal (single-line literals only;
# the iOS app has no multi-line Korean literals).
HANGUL_IN_QUOTES = re.compile(r'"[^"\n]*[\uAC00-\uD7A3][^"\n]*"')

violations: list[str] = []
for base in TARGETS:
    for path in sorted(base.rglob("*.swift")):
        if "Tests" in path.parts or "UITests" in path.parts:
            continue
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            for match in HANGUL_IN_QUOTES.findall(line):
                violations.append(f"{path.relative_to(ROOT)}:{lineno}: {match}")

if violations:
    print("Hardcoded Hangul string literals found (use catalog keys instead):")
    for violation in violations:
        print(f"  {violation}")
    sys.exit(1)

print("no Hangul literals in iOS app sources")
