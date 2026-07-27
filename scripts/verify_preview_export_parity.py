#!/usr/bin/env python3
"""Pixel-diff comparator for Step 1 Preview↔Export parity.

Compares a Preview frame PNG (dumped by the `MOVIECUT_UITEST_PARITY` harness
via `PlaybackEngine.snapshotFrame(at:)`) against the same timestamp extracted
from the exported mp4 by ffmpeg. Reports per-channel mean absolute difference
(MAD) and a pass/fail verdict against a configurable tolerance.

This is the non-skippable parity gate required by
`docs/CAPCUT_CORE_EDITING_REPAIR_HANDOFF_20260727.md` Step 1: the Preview must
render the same frame the Exporter renders at a given composition timestamp.

Usage:
    python3 scripts/verify_preview_export_parity.py \\
        --preview-dir <dir with preview_t<t>.png> \\
        --export-mp4   <exported.mp4> \\
        --times        0.5,1.5,2.5 \\
        [--tolerance 8.0] [--size 320x240]
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def run_text(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True, check=True)


def run_bytes(cmd: list[str]) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(cmd, capture_output=True, check=True)


def extract_export_frame(mp4: Path, time: float, out_png: Path, size: str) -> None:
    """Extract a single frame from the exported mp4 at `time`, scaled to `size`."""
    # Scale + center-pad so the comparator sees the same canvas region the
    # preview rendered. force_original_aspect_ratio=decrease keeps aspect.
    vf = (
        f"scale={size.replace('x', ':')}:force_original_aspect_ratio=decrease,"
        f"pad={size.replace('x', ':')}:(ow-iw)/2:(oh-ih)/2:black"
    )
    run_text([
        "ffmpeg", "-v", "error", "-y",
        "-ss", f"{time:.3f}",
        "-i", str(mp4),
        "-frames:v", "1",
        "-vf", vf,
        str(out_png),
    ])


def read_pixels(png: Path, force_size: str | None = None) -> tuple[int, int, list[tuple[int, int, int, int]]]:
    """Return (width, height, [RGBA per pixel]) for a PNG. Uses ffmpeg to dump
    raw RGBA so we don't require PIL/numpy in the test environment. If
    `force_size` (WxH) is given, the image is scaled+padded to that size first
    so preview (canvas-resolution) and export (source-resolution) frames are
    compared on the same grid."""
    extract_cmd = ["ffmpeg", "-v", "error", "-i", str(png)]
    if force_size:
        vf = (
            f"scale={force_size.replace('x', ':')}:force_original_aspect_ratio=decrease,"
            f"pad={force_size.replace('x', ':')}:(ow-iw)/2:(oh-ih)/2:black"
        )
        extract_cmd += ["-vf", vf]
    extract_cmd += ["-f", "rawvideo", "-pix_fmt", "rgba", "-"]
    proc = run_bytes(extract_cmd)
    raw = proc.stdout  # type: ignore[attr-defined]
    if force_size:
        w, h = (int(x) for x in force_size.split("x"))
    else:
        probe = run_text([
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height", "-of", "csv=p=0",
            str(png),
        ]).stdout.strip()  # type: ignore[attr-defined]
        w_s, h_s = probe.split(",")
        w, h = int(w_s), int(h_s)
    expected = w * h * 4
    if len(raw) < expected:
        raise ValueError(f"{png}: too few bytes ({len(raw)} < {expected})")
    pixels = []
    data = raw[:expected]
    for i in range(0, expected, 4):
        pixels.append((data[i], data[i + 1], data[i + 2], data[i + 3]))
    return w, h, pixels


def mad(a: list[tuple[int, int, int, int]],
        b: list[tuple[int, int, int, int]]) -> tuple[float, float, float, float, float]:
    """Mean absolute difference per channel + overall. 0.0 == identical."""
    n = min(len(a), len(b))
    if n == 0:
        return (255.0, 255.0, 255.0, 255.0, 255.0)
    sums = [0.0, 0.0, 0.0, 0.0]
    for pa, pb in zip(a[:n], b[:n]):
        for c in range(4):
            sums[c] += abs(pa[c] - pb[c])
    r, g, bl, al = (s / n for s in sums)
    overall = (r + g + bl) / 3.0  # ignore alpha for the overall verdict
    return (r, g, bl, al, overall)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--preview-dir", required=True, type=Path,
                    help="dir containing preview_t<t>.png dumps")
    ap.add_argument("--export-mp4", required=True, type=Path,
                    help="exported mp4 to extract comparison frames from")
    ap.add_argument("--times", required=True,
                    help="comma-separated seconds, e.g. 0.5,1.5,2.5")
    ap.add_argument("--tolerance", type=float, default=8.0,
                    help="max acceptable overall MAD (default 8.0/255)")
    ap.add_argument("--size", default="320x240",
                    help="canvas size for export frame extraction (WxH)")
    ap.add_argument("--work-dir", type=Path, default=None,
                    help="scratch dir for extracted export frames")
    args = ap.parse_args()

    if not args.export_mp4.is_file():
        print(f"FAIL: export mp4 missing: {args.export_mp4}", file=sys.stderr)
        return 2

    work = args.work_dir or Path("/tmp/moviecut-parity-workdir")
    work.mkdir(parents=True, exist_ok=True)

    times = [float(t) for t in args.times.split(",") if t.strip()]
    if not times:
        print("FAIL: no times provided", file=sys.stderr)
        return 2

    worst = 0.0
    failed = False
    print(f"Preview dir: {args.preview_dir}")
    print(f"Export mp4 : {args.export_mp4}")
    print(f"Tolerance  : overall MAD <= {args.tolerance:.2f}")
    print("-" * 60)
    for t in times:
        preview_png = args.preview_dir / f"preview_t{t:.3f}.png"
        if not preview_png.is_file():
            print(f"  t={t:.3f}s  SKIP (no preview dump {preview_png.name})")
            failed = True
            continue
        export_png = work / f"export_t{t:.3f}.png"
        extract_export_frame(args.export_mp4, t, export_png, args.size)

        pw, ph, ppix = read_pixels(preview_png, force_size=args.size)
        ew, eh, epix = read_pixels(export_png, force_size=args.size)
        # Both are now forced to args.size; sanity-check.
        if (pw, ph) != (ew, eh) or (pw, ph) != tuple(int(x) for x in args.size.split("x")):
            print(f"  t={t:.3f}s  FAIL size mismatch after normalize: "
                  f"preview {pw}x{ph} export {ew}x{eh} (target {args.size})")
            failed = True
            continue

        r, g, b, a, overall = mad(ppix, epix)
        worst = max(worst, overall)
        ok = overall <= args.tolerance
        verdict = "OK  " if ok else "FAIL"
        print(f"  t={t:.3f}s  {verdict}  overall_MAD={overall:.2f}  "
              f"(R={r:.1f} G={g:.1f} B={b:.1f} A={a:.1f})")
        if not ok:
            failed = True

    print("-" * 60)
    print(f"Worst overall MAD: {worst:.2f}  (tolerance {args.tolerance:.2f})")
    if failed:
        print("RESULT: FAIL")
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
