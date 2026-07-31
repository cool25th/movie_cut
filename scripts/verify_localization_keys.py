#!/usr/bin/env python3
"""Reconcile the localization keys used in Swift code against a string catalog.

Mechanical replacement for hand-counting `NSLocalizedString` keys. It lexes the
Swift sources (comment-aware, escape-aware, raw/multiline string aware), pulls
the key out of every `NSLocalizedString(...)` call, and diffs that set against
the keys declared in `Localizable.xcstrings`.

Reported figures (all derived from the scan, never hard-coded):
  * count of distinct keys used in code
  * count of keys in the catalog
  * keys used in code but missing from the catalog
  * catalog keys not referenced by code, split into
      - "indirect": the key text exists as a Swift string literal somewhere
        (dynamic `NSLocalizedString(variable)` call sites and SwiftUI's implicit
        `LocalizedStringKey` literals land here), and
      - "orphan": the key text appears nowhere as a literal.
  * which used keys are Korean (Hangul in the key itself)
  * supplementary catalog health: entries whose `en` value is Korean, entries
    with no localizations at all

Exhaustiveness is self-checked: every `NSLocalizedString` identifier found by
the lexer is accounted for as either a literal-key call or a dynamic call, and
the totals are printed. A key built with string interpolation is a hard error
because such a key can never match a catalog entry.

This script is read-only. It never writes to the catalog or the sources.
It performs no network access and shells out to nothing.

Usage:
    python3 scripts/verify_localization_keys.py
    python3 scripts/verify_localization_keys.py \\
        --catalog App/MovieCutMac/Localizable.xcstrings \\
        --source-root App/MovieCutMac \\
        [--json] [--fail-on-korean] [--quiet]

Exit codes:
    0  reconciled: no keys missing from the catalog
    1  reconciliation failure (missing keys, interpolated key, or, with
       --fail-on-korean, a Korean key still used in code)
    2  usage / IO / catalog parse error
"""
from __future__ import annotations

import argparse
import bisect
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CATALOG = Path("App/MovieCutMac/Localizable.xcstrings")
DEFAULT_SOURCE_ROOTS = [Path("App/MovieCutMac")]
LOCALIZED_FUNCTION = "NSLocalizedString"

# Hangul blocks. Korean keys are the defect this reconciliation exists to find,
# so detection covers jamo and the extended blocks, not just the syllable range.
HANGUL_RANGES = (
    (0x1100, 0x11FF),  # Hangul Jamo
    (0x3130, 0x318F),  # Hangul Compatibility Jamo
    (0xA960, 0xA97F),  # Hangul Jamo Extended-A
    (0xAC00, 0xD7A3),  # Hangul Syllables
    (0xD7B0, 0xD7FF),  # Hangul Jamo Extended-B
)

SIMPLE_ESCAPES = {
    "n": "\n",
    "t": "\t",
    "r": "\r",
    "0": "\0",
    "\\": "\\",
    '"': '"',
    "'": "'",
}


def has_hangul(text: str) -> bool:
    return any(any(lo <= ord(ch) <= hi for lo, hi in HANGUL_RANGES) for ch in text)


@dataclass(frozen=True)
class ParsedLiteral:
    """A Swift string literal recovered by the lexer."""

    value: str
    kind: str  # "quoted" | "raw" | "multiline" | "multiline-raw"
    interpolated: bool
    end: int  # offset just past the closing delimiter


@dataclass(frozen=True)
class Site:
    """One source location."""

    path: str
    line: int

    def __str__(self) -> str:  # deterministic, grep-friendly
        return f"{self.path}:{self.line}"


@dataclass
class ScanResult:
    files: list[str] = field(default_factory=list)
    # key -> sites, for NSLocalizedString calls whose first argument is a literal
    direct_keys: dict[str, list[Site]] = field(default_factory=dict)
    # NSLocalizedString calls whose first argument is not a literal
    dynamic_sites: list[tuple[Site, str]] = field(default_factory=list)
    # NSLocalizedString calls whose key literal contains interpolation
    interpolated_sites: list[tuple[Site, str]] = field(default_factory=list)
    # every non-interpolated string literal value seen anywhere in the sources,
    # mapped to the sites it appears at (SwiftUI's implicit LocalizedStringKey
    # literals are only visible through this pool)
    literal_sites: dict[str, list[Site]] = field(default_factory=dict)
    literal_count: int = 0
    multiline_literal_count: int = 0
    raw_literal_count: int = 0
    call_count: int = 0


def line_starts(text: str) -> list[int]:
    starts = [0]
    for index, ch in enumerate(text):
        if ch == "\n":
            starts.append(index + 1)
    return starts


def line_of(starts: list[int], offset: int) -> int:
    return bisect.bisect_right(starts, offset)


def _strip_multiline_indent(body: str) -> str:
    """Apply Swift's multiline-literal indentation stripping.

    The indentation of the closing delimiter line is removed from every line.
    Only used for literal-pool membership, never for key extraction.
    """
    lines = body.split("\n")
    if len(lines) < 2:
        return body
    # First line after the opening delimiter and the closing delimiter line are
    # both structural in Swift multiline literals.
    closing = lines[-1]
    indent = closing[: len(closing) - len(closing.lstrip(" \t"))]
    inner = lines[1:-1]
    if indent:
        inner = [ln[len(indent):] if ln.startswith(indent) else ln.lstrip(" \t") for ln in inner]
    return "\n".join(inner)


def parse_literal(text: str, index: int) -> ParsedLiteral | None:
    """Parse a Swift string literal that starts at `text[index]`.

    Handles single-quoted, triple-quoted (multiline), and raw variants prefixed
    with one or more `#`.
    Returns None when `index` is not the start of a string literal.
    """
    hashes = 0
    cursor = index
    while cursor < len(text) and text[cursor] == "#":
        hashes += 1
        cursor += 1
    if cursor >= len(text) or text[cursor] != '"':
        return None
    pounds = "#" * hashes
    multiline = text.startswith('"""', cursor)
    opener = '"""' if multiline else '"'
    closer = opener + pounds
    escape_prefix = "\\" + pounds
    cursor += len(opener)

    out: list[str] = []
    interpolated = False
    while cursor < len(text):
        if text.startswith(closer, cursor):
            body = "".join(out)
            if multiline:
                body = _strip_multiline_indent(body)
            kind = ("multiline-raw" if hashes else "multiline") if multiline else ("raw" if hashes else "quoted")
            return ParsedLiteral(body, kind, interpolated, cursor + len(closer))
        if text.startswith(escape_prefix, cursor):
            after = cursor + len(escape_prefix)
            if after < len(text) and text[after] == "(":
                interpolated = True
                depth = 0
                probe = after
                while probe < len(text):
                    if text[probe] == "(":
                        depth += 1
                    elif text[probe] == ")":
                        depth -= 1
                        if depth == 0:
                            probe += 1
                            break
                    elif text[probe] == '"':
                        nested = parse_literal(text, probe)
                        if nested is not None:
                            probe = nested.end
                            continue
                    probe += 1
                out.append("\\(...)")
                cursor = probe
                continue
            if after < len(text):
                ch = text[after]
                if ch == "u" and text.startswith("u{", after):
                    close = text.find("}", after)
                    if close != -1:
                        try:
                            out.append(chr(int(text[after + 2:close], 16)))
                        except ValueError:
                            out.append(text[cursor:close + 1])
                        cursor = close + 1
                        continue
                if ch in SIMPLE_ESCAPES:
                    out.append(SIMPLE_ESCAPES[ch])
                    cursor = after + 1
                    continue
                if ch == "\n" and multiline:  # line continuation
                    cursor = after + 1
                    continue
                out.append(text[cursor:after + 1])
                cursor = after + 1
                continue
        if not multiline and text[cursor] == "\n":
            # Unterminated single-line literal; stop rather than swallow the file.
            return ParsedLiteral("".join(out), "raw" if hashes else "quoted", interpolated, cursor)
        out.append(text[cursor])
        cursor += 1
    return ParsedLiteral("".join(out), "raw" if hashes else "quoted", interpolated, cursor)


def _skip_trivia(text: str, index: int) -> int:
    """Advance past whitespace and comments."""
    while index < len(text):
        ch = text[index]
        if ch in " \t\r\n":
            index += 1
            continue
        if text.startswith("//", index):
            newline = text.find("\n", index)
            index = len(text) if newline == -1 else newline + 1
            continue
        if text.startswith("/*", index):
            depth = 1
            index += 2
            while index < len(text) and depth:
                if text.startswith("/*", index):
                    depth += 1
                    index += 2
                elif text.startswith("*/", index):
                    depth -= 1
                    index += 2
                else:
                    index += 1
            continue
        return index
    return index


def _is_ident_char(ch: str) -> bool:
    return ch.isalnum() or ch == "_" or ord(ch) > 127


def scan_file(path: Path, rel: str, result: ScanResult) -> None:
    scan_text(path.read_text(encoding="utf-8"), rel, result)


def scan_text(text: str, rel: str, result: ScanResult) -> None:
    starts = line_starts(text)

    def record_literal(literal: ParsedLiteral, site: Site) -> None:
        result.literal_count += 1
        if literal.kind.startswith("multiline"):
            result.multiline_literal_count += 1
        if "raw" in literal.kind:
            result.raw_literal_count += 1
        if not literal.interpolated:
            result.literal_sites.setdefault(literal.value, []).append(site)

    index = 0
    length = len(text)
    while index < length:
        ch = text[index]
        if text.startswith("//", index) or text.startswith("/*", index):
            index = _skip_trivia(text, index)
            continue
        if ch == '"' or (ch == "#" and parse_literal(text, index) is not None):
            literal = parse_literal(text, index)
            assert literal is not None
            record_literal(literal, Site(rel, line_of(starts, index)))
            index = literal.end
            continue
        if _is_ident_char(ch) and not ch.isdigit():
            start = index
            while index < length and _is_ident_char(text[index]):
                index += 1
            identifier = text[start:index]
            if identifier != LOCALIZED_FUNCTION:
                continue
            if start > 0 and text[start - 1] == ".":
                continue  # member access, not the Foundation macro
            site = Site(rel, line_of(starts, start))
            after = _skip_trivia(text, index)
            if after >= length or text[after] != "(":
                result.dynamic_sites.append((site, "<no call parentheses>"))
                result.call_count += 1
                continue
            result.call_count += 1
            arg = _skip_trivia(text, after + 1)
            literal = parse_literal(text, arg)
            if literal is None:
                snippet = text[arg:arg + 60].split("\n", 1)[0].strip()
                result.dynamic_sites.append((site, snippet))
                continue
            record_literal(literal, site)
            if literal.interpolated:
                result.interpolated_sites.append((site, literal.value))
            else:
                result.direct_keys.setdefault(literal.value, []).append(site)
            index = literal.end
            continue
        index += 1


def scan_sources(roots: list[Path], repo_root: Path) -> ScanResult:
    result = ScanResult()
    seen: set[Path] = set()
    for root in roots:
        absolute = root if root.is_absolute() else repo_root / root
        if not absolute.exists():
            raise FileNotFoundError(f"source root not found: {root}")
        files = sorted(absolute.rglob("*.swift")) if absolute.is_dir() else [absolute]
        for swift in files:
            resolved = swift.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)
            try:
                rel = str(resolved.relative_to(repo_root))
            except ValueError:
                rel = str(resolved)
            result.files.append(rel)
            scan_file(resolved, rel, result)
    result.files.sort()
    return result


@dataclass
class Catalog:
    path: str
    source_language: str
    version: str
    keys: list[str]
    korean_source_values: dict[str, str]  # key -> en value containing Hangul
    entries_without_localizations: list[str]


def load_catalog(path: Path, repo_root: Path) -> Catalog:
    absolute = path if path.is_absolute() else repo_root / path
    document = json.loads(absolute.read_text(encoding="utf-8"))
    strings = document.get("strings")
    if not isinstance(strings, dict):
        raise ValueError(f"{path}: no 'strings' object")
    source_language = str(document.get("sourceLanguage", "?"))
    korean_source: dict[str, str] = {}
    empty: list[str] = []
    for key, entry in strings.items():
        localizations = entry.get("localizations") if isinstance(entry, dict) else None
        if not localizations:
            empty.append(key)
            continue
        unit = localizations.get(source_language, {}).get("stringUnit", {})
        value = unit.get("value")
        if isinstance(value, str) and has_hangul(value):
            korean_source[key] = value
    try:
        rel = str(absolute.resolve().relative_to(repo_root))
    except ValueError:
        rel = str(absolute)
    return Catalog(
        path=rel,
        source_language=source_language,
        version=str(document.get("version", "?")),
        keys=sorted(strings.keys()),
        korean_source_values=korean_source,
        entries_without_localizations=sorted(empty),
    )


def build_report(scan: ScanResult, catalog: Catalog) -> dict:
    direct = set(scan.direct_keys)
    literal_pool = set(scan.literal_sites)
    catalog_keys = set(catalog.keys)
    missing = sorted(direct - catalog_keys)
    unreferenced = sorted(catalog_keys - direct)
    indirect = sorted(k for k in unreferenced if k in literal_pool)
    orphan = sorted(k for k in unreferenced if k not in literal_pool)
    korean_used = sorted(k for k in direct if has_hangul(k))
    korean_catalog = sorted(k for k in catalog_keys if has_hangul(k))
    # Korean literals that are NOT NSLocalizedString keys. A literal that also
    # exists as a catalog key is a localization key reaching the catalog through
    # some other route (SwiftUI's implicit LocalizedStringKey, or one of the
    # dynamic call sites below), so requirement 1's "Korean key" sweep has to
    # include it. The rest are plain (unlocalized) Korean literals.
    korean_literals_not_keys = sorted(
        key for key in literal_pool if has_hangul(key) and key not in direct
    )
    korean_literals_in_catalog = [k for k in korean_literals_not_keys if k in catalog_keys]
    korean_literals_outside_catalog = [k for k in korean_literals_not_keys if k not in catalog_keys]
    return {
        "catalog": {
            "path": catalog.path,
            "sourceLanguage": catalog.source_language,
            "version": catalog.version,
            "key_count": len(catalog_keys),
            "entries_without_localizations": len(catalog.entries_without_localizations),
        },
        "sources": {
            "files_scanned": len(scan.files),
            "string_literals_seen": scan.literal_count,
            "multiline_literals": scan.multiline_literal_count,
            "raw_literals": scan.raw_literal_count,
            f"{LOCALIZED_FUNCTION}_call_sites": scan.call_count,
            "call_sites_with_literal_key": scan.call_count
            - len(scan.dynamic_sites)
            - len(scan.interpolated_sites),
            "call_sites_with_dynamic_key": len(scan.dynamic_sites),
            "call_sites_with_interpolated_key": len(scan.interpolated_sites),
            "distinct_keys_used": len(direct),
        },
        "counts": {
            "keys_used_in_code": len(direct),
            "keys_in_catalog": len(catalog_keys),
            "missing_from_catalog": len(missing),
            "catalog_keys_unused_by_code": len(unreferenced),
            "catalog_keys_unused_indirect_literal": len(indirect),
            "catalog_keys_unused_orphan": len(orphan),
            "korean_keys_used_in_code": len(korean_used),
            "korean_keys_in_catalog": len(korean_catalog),
            "korean_literals_that_are_catalog_keys_but_not_nslocalizedstring_keys":
                len(korean_literals_in_catalog),
            "korean_literals_outside_catalog": len(korean_literals_outside_catalog),
            "korean_key_candidates_all_routes":
                len(korean_used) + len(korean_literals_in_catalog) + len(korean_literals_outside_catalog),
            "catalog_entries_with_korean_source_value": len(catalog.korean_source_values),
        },
        "missing_from_catalog": [
            {"key": key, "korean": has_hangul(key), "sites": [str(s) for s in scan.direct_keys[key]]}
            for key in missing
        ],
        "catalog_keys_unused_by_code": {"indirect_literal": indirect, "orphan": orphan},
        "korean_keys_used_in_code": [
            {
                "key": key,
                "in_catalog": key in catalog_keys,
                "sites": [str(s) for s in scan.direct_keys[key]],
            }
            for key in korean_used
        ],
        "korean_keys_in_catalog": korean_catalog,
        "korean_literals_not_nslocalizedstring_keys": {
            "in_catalog": [
                {"literal": key, "sites": [str(s) for s in scan.literal_sites[key]]}
                for key in korean_literals_in_catalog
            ],
            "outside_catalog": [
                {"literal": key, "sites": [str(s) for s in scan.literal_sites[key]]}
                for key in korean_literals_outside_catalog
            ],
        },
        "catalog_entries_with_korean_source_value": [
            {"key": key, "value": value}
            for key, value in sorted(catalog.korean_source_values.items())
        ],
        "dynamic_key_call_sites": [
            {"site": str(site), "snippet": snippet} for site, snippet in
            sorted(scan.dynamic_sites, key=lambda pair: (pair[0].path, pair[0].line))
        ],
        "interpolated_key_call_sites": [
            {"site": str(site), "key": key} for site, key in
            sorted(scan.interpolated_sites, key=lambda pair: (pair[0].path, pair[0].line))
        ],
        "files_scanned": scan.files,
    }


def print_report(report: dict, scan: ScanResult, show_files: bool) -> None:
    cat = report["catalog"]
    src = report["sources"]
    counts = report["counts"]
    print("== localization key reconciliation ==")
    print(f"catalog : {cat['path']} (sourceLanguage={cat['sourceLanguage']}, version={cat['version']})")
    print(f"sources : {src['files_scanned']} .swift files")
    print()
    print("[counts]")
    print(f"  keys used in code                          : {counts['keys_used_in_code']}")
    print(f"  keys in catalog                            : {counts['keys_in_catalog']}")
    print(f"  keys missing from catalog                  : {counts['missing_from_catalog']}")
    print(f"  catalog keys unused by code                : {counts['catalog_keys_unused_by_code']}")
    print(f"    - key text present as a Swift literal    : {counts['catalog_keys_unused_indirect_literal']}")
    print(f"    - key text absent from code (orphan)     : {counts['catalog_keys_unused_orphan']}")
    print(f"  Korean keys used in code                   : {counts['korean_keys_used_in_code']}")
    print(f"  Korean keys in catalog                     : {counts['korean_keys_in_catalog']}")
    print("  Korean catalog keys reached without "
          f"{LOCALIZED_FUNCTION} : "
          f"{counts['korean_literals_that_are_catalog_keys_but_not_nslocalizedstring_keys']}")
    print(f"  Korean literals outside the catalog        : {counts['korean_literals_outside_catalog']}")
    print(f"  Korean key candidates, all routes          : {counts['korean_key_candidates_all_routes']}")
    print(f"  catalog entries with Korean source value   : {counts['catalog_entries_with_korean_source_value']}")
    print()
    print("[scan accounting]")
    print(f"  {LOCALIZED_FUNCTION} call sites                 : {src[f'{LOCALIZED_FUNCTION}_call_sites']}")
    print(f"    with a literal key                       : {src['call_sites_with_literal_key']}")
    print(f"    with a dynamic (non-literal) key         : {src['call_sites_with_dynamic_key']}")
    print(f"    with an interpolated key (invalid)       : {src['call_sites_with_interpolated_key']}")
    print(f"  string literals lexed                      : {src['string_literals_seen']}"
          f" (multiline {src['multiline_literals']}, raw {src['raw_literals']})")
    print()

    def section(title: str, lines: list[str]) -> None:
        print(f"[{title}] {len(lines)}")
        for line in lines:
            print(f"  {line}")
        if not lines:
            print("  (none)")
        print()

    section(
        "keys missing from catalog",
        [
            f"{'KO ' if item['korean'] else '   '}{item['key']!r}  <- {', '.join(item['sites'])}"
            for item in report["missing_from_catalog"]
        ],
    )
    section(
        "Korean keys used in code",
        [
            f"{'in-catalog ' if item['in_catalog'] else 'NOT-IN-CAT '}{item['key']!r}"
            f"  <- {', '.join(item['sites'])}"
            for item in report["korean_keys_used_in_code"]
        ],
    )
    section(
        f"Korean literals that are catalog keys but not {LOCALIZED_FUNCTION} keys"
        " (implicit LocalizedStringKey / dynamic key route)",
        [
            f"{item['literal']!r}  <- {', '.join(item['sites'])}"
            for item in report["korean_literals_not_nslocalizedstring_keys"]["in_catalog"]
        ],
    )
    section(
        "Korean literals with no catalog entry (not localized through this catalog)",
        [
            f"{item['literal']!r}  <- {', '.join(item['sites'])}"
            for item in report["korean_literals_not_nslocalizedstring_keys"]["outside_catalog"]
        ],
    )
    section(
        "catalog entries whose source-language value is Korean",
        [f"{item['key']!r} -> {item['value']!r}" for item in report["catalog_entries_with_korean_source_value"]],
    )
    section(
        "dynamic key call sites (key comes from a variable)",
        [f"{item['site']}  {item['snippet']}" for item in report["dynamic_key_call_sites"]],
    )
    if report["interpolated_key_call_sites"]:
        section(
            "interpolated key call sites (cannot match a catalog entry)",
            [f"{item['site']}  {item['key']!r}" for item in report["interpolated_key_call_sites"]],
        )
    section(
        "catalog keys unused by code - orphan (no literal anywhere)",
        [repr(key) for key in report["catalog_keys_unused_by_code"]["orphan"]],
    )
    section(
        "catalog keys unused by code - key text present as a Swift literal",
        [repr(key) for key in report["catalog_keys_unused_by_code"]["indirect_literal"]],
    )
    if show_files:
        section("files scanned", report["files_scanned"])


SELF_TEST_SOURCE = '\n'.join([
    'import SwiftUI',
    '// NSLocalizedString("commented out", comment: "")',
    '/* block /* nested */ NSLocalizedString("block commented", comment: "") */',
    'let mention = "NSLocalizedString(\\"inside a literal\\")"',
    'let plain = NSLocalizedString("plain key", comment: "")',
    'let wrapped = NSLocalizedString(',
    '    "wrapped key",',
    '    comment: "multi-line call"',
    ')',
    'let escaped = NSLocalizedString("line\\nbreak \\"quoted\\" back\\\\slash", comment: "")',
    'let korean = NSLocalizedString("한국어 키", comment: "")',
    'let raw = NSLocalizedString(#"raw \\n key"#, comment: "")',
    'let dynamicKey = NSLocalizedString(title, comment: "")',
    'let interpolated = NSLocalizedString("count \\(n)", comment: "")',
    'let implicit = Text("implicit swiftui key")',
    'let block = """',
    '    multiline body',
    '    """',
    'let afterMultiline = NSLocalizedString("after multiline", comment: "")',
])


def run_self_test() -> int:
    """Lex a synthetic Swift source and assert the extraction is exact.

    Guards the lexer rules the reconciliation depends on: comments and string
    contents never yield keys, multi-line calls and escapes are decoded, raw and
    multiline literals do not derail the scan, dynamic and interpolated keys are
    separated out.
    """
    result = ScanResult()
    scan_text(SELF_TEST_SOURCE, "SelfTest.swift", result)
    keys = {key: [str(s) for s in sites] for key, sites in result.direct_keys.items()}
    checks: list[tuple[str, bool, str]] = []

    def check(name: str, actual: object, expected: object) -> None:
        checks.append((name, actual == expected, f"expected {expected!r}, got {actual!r}"))

    check("direct key count", len(keys), 6)
    check("plain key", "plain key" in keys, True)
    check("multi-line call key", "wrapped key" in keys, True)
    check("escape decoding", 'line\nbreak "quoted" back\\slash' in keys, True)
    check("korean key", "한국어 키" in keys, True)
    check("raw literal key keeps backslash", "raw \\n key" in keys, True)
    check("key after multiline literal", "after multiline" in keys, True)
    check("commented-out call ignored", "commented out" in keys, False)
    check("block-commented call ignored", "block commented" in keys, False)
    check("mention inside a literal ignored", "inside a literal" in keys, False)
    check("dynamic call sites", [str(site) for site, _ in result.dynamic_sites], ["SelfTest.swift:13"])
    check("interpolated call sites", [str(site) for site, _ in result.interpolated_sites], ["SelfTest.swift:14"])
    check("call accounting", result.call_count, 8)
    check(
        "call accounting balances",
        len(result.direct_keys) + len(result.dynamic_sites) + len(result.interpolated_sites),
        8,
    )
    check("implicit swiftui literal in pool", "implicit swiftui key" in result.literal_sites, True)
    check("multiline literal in pool", "multiline body" in result.literal_sites, True)
    check("hangul detector on jamo", has_hangul("\u3131"), True)
    check("hangul detector on ascii", has_hangul("Timeline zoom"), False)

    failed = [(name, detail) for name, ok, detail in checks if not ok]
    for name, ok, detail in checks:
        print(f"  {'ok  ' if ok else 'FAIL'} {name}" + ("" if ok else f" - {detail}"))
    print(f"self-test: {len(checks) - len(failed)}/{len(checks)} checks passed")
    return 1 if failed else 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Reconcile NSLocalizedString keys in Swift sources against a string catalog.",
    )
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument(
        "--source-root",
        type=Path,
        action="append",
        dest="source_roots",
        help=f"Swift source root to scan (repeatable, default: {DEFAULT_SOURCE_ROOTS[0]})",
    )
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    parser.add_argument("--json", action="store_true", help="emit the report as JSON")
    parser.add_argument("--list-files", action="store_true", help="list every scanned file")
    parser.add_argument(
        "--fail-on-korean",
        action="store_true",
        help="also exit non-zero while any Korean key is still used in code",
    )
    parser.add_argument("--quiet", action="store_true", help="print only the verdict line")
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="lex a synthetic Swift source and assert the extraction rules, then exit",
    )
    args = parser.parse_args(argv)

    if args.self_test:
        return run_self_test()

    repo_root = args.repo_root.resolve()
    roots = args.source_roots or DEFAULT_SOURCE_ROOTS
    try:
        scan = scan_sources(roots, repo_root)
        catalog = load_catalog(args.catalog, repo_root)
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    report = build_report(scan, catalog)

    failures: list[str] = []
    if report["counts"]["missing_from_catalog"]:
        failures.append(f"{report['counts']['missing_from_catalog']} key(s) missing from catalog")
    if report["sources"]["call_sites_with_interpolated_key"]:
        failures.append(
            f"{report['sources']['call_sites_with_interpolated_key']} interpolated key call site(s)"
        )
    if args.fail_on_korean and report["counts"]["korean_key_candidates_all_routes"]:
        counts = report["counts"]
        failures.append(
            f"{counts['korean_key_candidates_all_routes']} Korean key candidate(s) in code "
            f"({counts['korean_keys_used_in_code']} via {LOCALIZED_FUNCTION}, "
            f"{counts['korean_literals_that_are_catalog_keys_but_not_nslocalizedstring_keys']} via catalog-matched "
            f"literal, {counts['korean_literals_outside_catalog']} literal(s) with no catalog entry)"
        )

    if failures:
        verdict = "VERDICT: FAIL - " + "; ".join(failures)
    else:
        verdict = (
            "VERDICT: PASS - "
            f"{report['counts']['keys_used_in_code']} code keys all present in "
            f"{report['counts']['keys_in_catalog']} catalog keys"
            + (
                f" (note: {report['counts']['korean_keys_used_in_code']} Korean key(s) still used in code)"
                if report["counts"]["korean_keys_used_in_code"]
                else ""
            )
        )
    report["verdict"] = "FAIL" if failures else "PASS"
    report["failures"] = failures

    if args.json:
        # Keep stdout pure JSON so the report can be piped; verdict goes to stderr.
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=False))
        print(verdict, file=sys.stderr)
    else:
        if not args.quiet:
            print_report(report, scan, args.list_files)
        print(verdict)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
