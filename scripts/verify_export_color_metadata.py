#!/usr/bin/env python3
"""Verify the color-space metadata of an exported MovieCut file against the v1
SDR Rec.709 render contract.

The v1 pipeline is SDR Rec.709 end to end (`RenderColorConfiguration`), and
`ExportPlanner` tags SDR outputs with Rec.709 primaries/transfer/matrix. This
script reads those tags back out of an exported file with ffprobe and asserts
they match the contract. It is the machine-checked counterpart to the unit tests
in HDRProfileGatingTests: those verify the planner PRODUCES the right settings,
this verifies the FILE on disk actually carries them (catching an encoder that
silently strips or rewrites color properties).

Exit code 0 = pass, 1 = mismatch/missing. Designed for CI (fast, no GUI).

Usage:
    verify_export_color_metadata.py <exported-file> [--allow-hdr]
    verify_export_color_metadata.py <exported-file> --expect-primaries ITU_R_709_2
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from typing import Any

# The v1 contract. These are the AVFoundation string values that
# ExportPlanner writes and that ffprobe surfaces.
V1_PRIMARIES = "ITU_R_709_2"
V1_TRANSFER = "ITU_R_709_2"
V1_MATRIX = "ITU_R_709_2"

# ffprobe's string forms for the wide-gamut/HDR spaces the v1 gate rejects.
HDR_TRANSFERS = {"SMPTE_ST_2084", "ARIB_STD_B67"}  # PQ, HLG
WIDE_PRIMARIES = {"DCI_P3", "Display_P3", "ITU_R_2020"}


def ffprobe_color_metadata(path: str) -> dict[str, str | None]:
    """Return the color metadata for the first video stream, keys lowercased.

    Returns a dict with possibly-None values for: primaries, transfer, matrix,
    bit_depth, pix_fmt. Missing tags become None rather than raising.
    """
    cmd = [
        "ffprobe",
        "-v", "error",
        "-select_streams", "v:0",
        "-show_entries",
        "stream=color_primaries,color_transfer,color_space,bits_per_raw_sample,pix_fmt",
        "-of", "json",
        path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ffprobe failed (exit {result.returncode}): {result.stderr.strip()}")
    streams = json.loads(result.stdout).get("streams", [])
    if not streams:
        raise RuntimeError("no video stream found")
    s = streams[0]
    return {
        "primaries": s.get("color_primaries"),
        "transfer": s.get("color_transfer"),
        "matrix": s.get("color_space"),
        "bit_depth": s.get("bits_per_raw_sample"),
        "pix_fmt": s.get("pix_fmt"),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("file", help="exported movie file to inspect")
    parser.add_argument("--allow-hdr", action="store_true",
                        help="do not fail on HDR/wide-gamut tags (default: reject, v1 is SDR Rec.709)")
    parser.add_argument("--expect-primaries", default=V1_PRIMARIES,
                        help=f"required color primaries (default: {V1_PRIMARIES})")
    parser.add_argument("--expect-transfer", default=V1_TRANSFER,
                        help=f"required transfer function (default: {V1_TRANSFER})")
    parser.add_argument("--expect-matrix", default=V1_MATRIX,
                        help=f"required YCbCr matrix (default: {V1_MATRIX})")
    args = parser.parse_args()

    try:
        meta = ffprobe_color_metadata(args.file)
    except (RuntimeError, json.JSONDecodeError) as exc:
        print(f"FAIL: could not read color metadata: {exc}", file=sys.stderr)
        return 1

    print(f"file: {args.file}")
    for key, value in meta.items():
        print(f"  {key:12} {value}")

    problems: list[str] = []

    # 1. The v1 SDR contract: primaries/transfer/matrix must be Rec.709.
    if meta["primaries"] != args.expect_primaries:
        problems.append(f"primaries: expected {args.expect_primaries}, got {meta['primaries']}")
    if meta["transfer"] != args.expect_transfer:
        problems.append(f"transfer: expected {args.expect_transfer}, got {meta['transfer']}")
    if meta["matrix"] != args.expect_matrix:
        problems.append(f"matrix: expected {args.expect_matrix}, got {meta['matrix']}")

    # 2. Unless explicitly allowed, reject HDR/wide-gamut outright — the v1
    #    pipeline cannot produce those correctly (8-bit SDR compositor), so a
    #    file carrying those tags is mislabeled. This is the "false label"
    #    guard from the render-reliability plan.
    if not args.allow_hdr:
        if meta["transfer"] in HDR_TRANSFERS:
            problems.append(f"HDR transfer function present ({meta['transfer']}) in an SDR-only build — output is mislabeled")
        if meta["primaries"] in WIDE_PRIMARIES:
            problems.append(f"wide-gamut primaries present ({meta['primaries']}) in an SDR-only build — output is mislabeled")

    if problems:
        print("FAIL: color metadata does not match the v1 SDR Rec.709 contract:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1

    print("PASS: color metadata matches the v1 SDR Rec.709 contract.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
