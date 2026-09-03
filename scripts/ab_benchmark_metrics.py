#!/usr/bin/env python3
"""CA-12 competitive A/B benchmark quality metrics (COMPETITIVE_ANALYSIS Part 5).

Computes the benchmark metric set that Part 5 §2 requires for every output
video — PSNR alone is explicitly banned as a single criterion, so this module
always reports the family together:

  single <video>
      Absolute per-video metrics: container/codec metadata, color tags,
      chroma subsampling (from pix_fmt), actual bitrate, keyframe interval
      stats, CFR/VFR verdict, highlight clipping / shadow crush / banding
      proxies on sampled frames, audio loudness + true peak (ebur128) and
      A/V start/duration sync deltas.

  pair --reference-dir <previews> --export <mp4> --times t1,t2,...
      Reference metrics against the harness's lossless preview PNG dumps at
      the same timestamps (the established parity convention): global and
      per-frame PSNR, block SSIM (8x8, luma), per-channel MAD p95/max,
      and CIE76 delta-E mean/p95/max on Rec.709->Lab.

  blind --a-dir <dir> --b-dir <dir> --out <dir> [--seed N]
      Human blind-comparison protocol (Part 5 §2 "사람 블라인드 병행"):
      emits a randomized ballot (markdown), a hidden key JSON, and a
      responses.csv template. `--tally` scores a filled response sheet.

  --self-test
      Deterministic synthetic checks of every metric primitive.

Dependencies: numpy + ffmpeg/ffprobe.
Frame sampling for `single` and `pair` is timestamp-based (default 9 evenly
spaced points); the sample count is recorded in every JSON output so numbers
are always read with their sampling conditions (§1.4 condition-field rule).
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import random
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

import numpy as np

# ----------------------------------------------------------------------------
# ffmpeg/ffprobe helpers
# ----------------------------------------------------------------------------


def run_text(cmd: list[str]) -> str:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"command failed ({proc.returncode}): {' '.join(cmd)}\n{proc.stderr}")
    return proc.stdout


def run_stderr(cmd: list[str]) -> str:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"command failed ({proc.returncode}): {' '.join(cmd)}\n{proc.stderr}")
    return proc.stderr


def ffprobe_json(path: Path) -> dict[str, Any]:
    return json.loads(run_text([
        "ffprobe", "-v", "error", "-print_format", "json",
        "-show_format", "-show_streams", str(path),
    ]))


def probe_duration_s(path: Path) -> float:
    info = ffprobe_json(path)
    raw = info.get("format", {}).get("duration")
    return float(raw) if raw else 0.0


def decode_rgb(path: Path, *, seek_s: float | None = None, scale_pad: str | None = None) -> np.ndarray:
    """Decode one frame (optionally at a timestamp) as HxWx3 uint8 RGB.

    `scale_pad` follows the parity comparator convention: scale with
    force_original_aspect_ratio=decrease then center-pad to the target canvas.
    """
    cmd = ["ffmpeg", "-v", "error"]
    if seek_s is not None:
        cmd += ["-ss", f"{seek_s:.3f}"]
    cmd += ["-i", str(path)]
    if scale_pad:
        w, h = scale_pad.split("x")
        cmd += ["-vf",
                f"scale={w}:{h}:force_original_aspect_ratio=decrease,"
                f"pad={w}:{h}:(ow-iw)/2:(oh-ih)/2:black"]
    cmd += ["-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    proc = subprocess.run(cmd, capture_output=True)
    if proc.returncode != 0 or not proc.stdout:
        raise RuntimeError(f"frame decode failed for {path} (seek={seek_s})")
    raw = np.frombuffer(proc.stdout, dtype=np.uint8)
    if raw.size % 3 != 0:
        raise RuntimeError(f"unexpected raw size {raw.size}")
    # Recover dimensions from the probe (single frame => stream dims).
    if scale_pad:
        w, h = (int(x) for x in scale_pad.split("x"))
    else:
        info = ffprobe_json(path)
        vstream = next(s for s in info["streams"] if s.get("codec_type") == "video")
        w, h = int(vstream["width"]), int(vstream["height"])
    frame = raw.reshape(h, w, 3)
    return frame


def sample_times(duration_s: float, count: int) -> list[float]:
    """Evenly spaced interior sample timestamps (never 0 or the exact end)."""
    if duration_s <= 0:
        return [0.0]
    span = duration_s * 0.95
    return [round(span * (i + 0.5) / count, 3) for i in range(count)]


# ----------------------------------------------------------------------------
# Pixel metric primitives (pure numpy — unit tested by --self-test)
# ----------------------------------------------------------------------------


def mad_per_channel(ref: np.ndarray, test: np.ndarray) -> list[float]:
    diff = np.abs(ref.astype(np.int16) - test.astype(np.int16))
    return [round(float(diff[..., c].mean()), 3) for c in range(3)]


def psnr_db(ref: np.ndarray, test: np.ndarray) -> float:
    mse = float(np.mean((ref.astype(np.float64) - test.astype(np.float64)) ** 2))
    if mse == 0:
        return math.inf
    return 10.0 * math.log10(255.0 ** 2 / mse)


def luma(frame: np.ndarray) -> np.ndarray:
    # Rec. 601 luma, same family as the parity comparator / fixture tooling.
    f = frame.astype(np.float64)
    return 0.299 * f[..., 0] + 0.587 * f[..., 1] + 0.114 * f[..., 2]


def ssim_mean(ref: np.ndarray, test: np.ndarray) -> float:
    """Block SSIM (non-overlapping 8x8 windows, Rec.601 luma, Wang constants).

    Non-overlapping blocks are the standard fast variant of the original
    sliding-window formulation; the same variant is applied to both inputs so
    comparisons are internally consistent. Frames are cropped to 8-multiples.
    """
    a = luma(ref)
    b = luma(test)
    h, w = a.shape
    h8, w8 = h - (h % 8), w - (w % 8)
    a = a[:h8, :w8]
    b = b[:h8, :w8]
    ra = a.reshape(h8 // 8, 8, w8 // 8, 8)
    rb = b.reshape(h8 // 8, 8, w8 // 8, 8)
    c1 = (0.01 * 255) ** 2
    c2 = (0.03 * 255) ** 2
    mu_a = ra.mean(axis=(1, 3))
    mu_b = rb.mean(axis=(1, 3))
    var_a = ra.var(axis=(1, 3))
    var_b = rb.var(axis=(1, 3))
    cov = ((ra - mu_a[:, None, :, None]) * (rb - mu_b[:, None, :, None])).mean(axis=(1, 3))
    ssim_map = ((2 * mu_a * mu_b + c1) * (2 * cov + c2)) / \
               ((mu_a ** 2 + mu_b ** 2 + c1) * (var_a + var_b + c2))
    return float(ssim_map.mean())


# sRGB/Rec.709 D65 -> XYZ, then CIE L*a*b* (D65 reference white).
_SRGB_TO_XYZ = np.array([
    [0.4124564, 0.3575761, 0.1804375],
    [0.2126729, 0.7151522, 0.0721750],
    [0.0193339, 0.1191920, 0.9503041],
])
_D65_WHITE = np.array([0.95047, 1.0, 1.08883])


def delta_e76(ref: np.ndarray, test: np.ndarray, *, stride: int = 4) -> np.ndarray:
    """CIE76 delta-E per sampled pixel (stride subsampling bounds cost)."""
    def to_lab(frame: np.ndarray) -> np.ndarray:
        rgb = frame.astype(np.float64)[::stride, ::stride] / 255.0
        linear = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
        xyz = linear @ _SRGB_TO_XYZ.T / _D65_WHITE
        eps = 216 / 24389
        kappa = 24389 / 27
        f = np.where(xyz > eps, np.cbrt(xyz), (kappa * xyz + 16) / 116)
        lab = np.empty_like(f)
        lab[..., 0] = 116 * f[..., 1] - 16
        lab[..., 1] = 500 * (f[..., 0] - f[..., 1])
        lab[..., 2] = 200 * (f[..., 1] - f[..., 2])
        return lab

    la, lb = to_lab(ref), to_lab(test)
    return np.sqrt(np.sum((la - lb) ** 2, axis=-1))


def highlight_clip_pct(frame: np.ndarray) -> float:
    return float(np.mean(frame.max(axis=-1) >= 250) * 100.0)


def shadow_crush_pct(frame: np.ndarray) -> float:
    return float(np.mean(frame.min(axis=-1) <= 5) * 100.0)


def banding_proxy(frame: np.ndarray) -> float:
    """Missing occupied luma levels inside the occupied span, 0..1.

    A smooth gradient occupies nearly every 8-bit level between its darkest
    and brightest occupied level; posterized (banded) content leaves gaps.
    Flat frames (span < 2 levels) are defined as 0 (no banding signal).
    """
    y = np.round(luma(frame)).astype(np.uint8).ravel()
    hist = np.bincount(y, minlength=256)
    occupied = np.nonzero(hist)[0]
    if occupied.size < 2:
        return 0.0
    span = int(occupied[-1] - occupied[0] + 1)
    return float(1.0 - occupied.size / span)


def percentile(values: list[float], q: float) -> float:
    if not values:
        return 0.0
    return float(np.percentile(np.asarray(values), q))


# ----------------------------------------------------------------------------
# single — absolute per-video metrics
# ----------------------------------------------------------------------------


def video_packet_stats(path: Path) -> dict[str, Any]:
    out = run_text([
        "ffprobe", "-v", "error", "-select_streams", "v",
        "-show_entries", "packet=pts_time,flags",
        "-of", "csv=p=0", str(path),
    ])
    pts: list[float] = []
    key_pts: list[float] = []
    for line in out.splitlines():
        parts = line.strip().split(",")
        if len(parts) < 2 or not parts[0]:
            continue
        try:
            t = float(parts[0])
        except ValueError:
            continue
        pts.append(t)
        if "K" in parts[1]:
            key_pts.append(t)
    # Presentation order: packets arrive in demux (decode) order, which B-frame
    # reordering makes non-monotonic — sort + dedupe before taking deltas.
    pts = sorted(set(pts))
    key_pts = sorted(set(key_pts))
    if not pts:
        return {"frame_packets": 0}
    deltas = [b - a for a, b in zip(pts, pts[1:]) if b > a]
    stats: dict[str, Any] = {
        "frame_packets": len(pts),
        "median_frame_delta_ms": round(1000 * float(np.median(deltas)), 3) if deltas else None,
        "frame_delta_jitter_ms": round(1000 * (max(deltas) - min(deltas)), 3) if deltas else None,
        "cfr": bool(deltas and (max(deltas) - min(deltas)) <= 0.001),
    }
    if len(key_pts) >= 2:
        kdel = [b - a for a, b in zip(key_pts, key_pts[1:]) if b > a]
        stats["keyframe_count"] = len(key_pts)
        stats["keyframe_interval_median_s"] = round(float(np.median(kdel)), 3)
        stats["keyframe_interval_max_s"] = round(max(kdel), 3)
    else:
        stats["keyframe_count"] = len(key_pts)
    return stats


def audio_metrics(path: Path) -> dict[str, Any]:
    stderr = run_stderr(["ffmpeg", "-v", "info", "-i", str(path),
                         "-af", "ebur128=peak=true", "-f", "null", "-"])
    lufs = re.search(r"I:\s+(-?[\d.]+)\s+LUFS", stderr)
    peak = re.search(r"Peak:\s+(-?[\d.]+)\s+dBFS", stderr)
    return {
        "integrated_lufs": float(lufs.group(1)) if lufs else None,
        "true_peak_dbfs": float(peak.group(1)) if peak else None,
    }


def av_sync(info: dict[str, Any]) -> dict[str, Any]:
    def stream(kind: str) -> dict[str, Any] | None:
        return next((s for s in info.get("streams", []) if s.get("codec_type") == kind), None)

    v, a = stream("video"), stream("audio")
    if not v or not a:
        return {"has_audio": bool(a), "av_start_delta_s": None, "av_duration_delta_s": None}

    def fnum(x: Any) -> float | None:
        try:
            return float(x)
        except (TypeError, ValueError):
            return None

    v_start, a_start = fnum(v.get("start_time")), fnum(a.get("start_time"))
    v_dur, a_dur = fnum(v.get("duration")), fnum(a.get("duration"))
    return {
        "has_audio": True,
        "av_start_delta_s": round(a_start - v_start, 6) if (v_start is not None and a_start is not None) else None,
        "av_duration_delta_s": round(a_dur - v_dur, 6) if (v_dur is not None and a_dur is not None) else None,
    }


def chroma_subsampling(pix_fmt: str) -> str:
    m = re.match(r"yuv(\d)(\d)(\d)", pix_fmt or "")
    if not m:
        return pix_fmt or "unknown"
    j, a, b = m.groups()
    return f"{j}:{a}:{b}"


def cmd_single(args: argparse.Namespace) -> int:
    path = Path(args.video)
    info = ffprobe_json(path)
    vstream = next(s for s in info["streams"] if s.get("codec_type") == "video")
    duration = float(info["format"].get("duration") or 0.0)
    size_bytes = int(info["format"].get("size") or path.stat().st_size)
    reported_bitrate = int(info["format"]["bit_rate"]) if info["format"].get("bit_rate") else None
    computed_bitrate = round(size_bytes * 8 / duration / 1000, 1) if duration > 0 else None

    times = sample_times(duration, args.samples)
    clips, crushes, bandings = [], [], []
    for t in times:
        try:
            frame = decode_rgb(path, seek_s=t)
        except RuntimeError:
            continue
        clips.append(highlight_clip_pct(frame))
        crushes.append(shadow_crush_pct(frame))
        bandings.append(banding_proxy(frame))

    result: dict[str, Any] = {
        "video": str(path),
        "container": info["format"].get("format_name"),
        "codec": vstream.get("codec_name"),
        "codec_profile": vstream.get("profile"),
        "pix_fmt": vstream.get("pix_fmt"),
        "chroma_subsampling": chroma_subsampling(vstream.get("pix_fmt", "")),
        "width": vstream.get("width"),
        "height": vstream.get("height"),
        "r_frame_rate": vstream.get("r_frame_rate"),
        "color": {
            "primaries": vstream.get("color_primaries"),
            "transfer": vstream.get("color_transfer"),
            "space": vstream.get("color_space"),
        },
        "duration_s": round(duration, 3),
        "size_bytes": size_bytes,
        "bitrate_kbps_reported": reported_bitrate and round(reported_bitrate / 1000, 1),
        "bitrate_kbps_computed": computed_bitrate,
        "sampled_frames": len(clips),
        "sample_times_s": times,
        "highlight_clip_pct_mean": round(float(np.mean(clips)), 3) if clips else None,
        "shadow_crush_pct_mean": round(float(np.mean(crushes)), 3) if crushes else None,
        "banding_proxy_mean": round(float(np.mean(bandings)), 4) if bandings else None,
    }
    result.update(video_packet_stats(path))
    result.update(av_sync(info))
    audio = next((s for s in info["streams"] if s.get("codec_type") == "audio"), None)
    if audio:
        loud = audio_metrics(path)
        result["integrated_lufs"] = loud["integrated_lufs"]
        result["true_peak_dbfs"] = loud["true_peak_dbfs"]
    else:
        result["integrated_lufs"] = None
        result["true_peak_dbfs"] = None

    _emit(result, args.out)
    return 0


# ----------------------------------------------------------------------------
# pair — reference (lossless preview PNG) vs export metrics
# ----------------------------------------------------------------------------


def cmd_pair(args: argparse.Namespace) -> int:
    ref_dir = Path(args.reference_dir)
    export = Path(args.export)
    times = [float(t) for t in args.times.split(",") if t.strip()]
    if not times:
        print("pair: --times is required (comma-separated)", file=sys.stderr)
        return 2

    # Canvas size from the first reference PNG's export-side probe: the
    # parity convention scales+pads the export frame to the preview canvas.
    first_ref = ref_dir / f"preview_t{times[0]:.3f}.png"
    info = ffprobe_json(export)
    vstream = next(s for s in info["streams"] if s.get("codec_type") == "video")
    scale_pad = f"{vstream['width']}x{vstream['height']}"

    per_frame: list[dict[str, Any]] = []
    mse_accum = 0.0
    pix_accum = 0
    all_mads: list[float] = []
    all_de: list[np.ndarray] = []
    ssims: list[float] = []
    for t in times:
        ref_png = ref_dir / f"preview_t{t:.3f}.png"
        if not ref_png.exists():
            continue
        ref = decode_rgb(ref_png)
        try:
            test = decode_rgb(export, seek_s=t, scale_pad=scale_pad)
        except RuntimeError:
            continue
        mse_accum += float(np.sum((ref.astype(np.float64) - test.astype(np.float64)) ** 2))
        pix_accum += ref.size
        all_mads.extend(mad_per_channel(ref, test))
        all_de.append(delta_e76(ref, test).ravel())
        frame_psnr = psnr_db(ref, test)
        frame_ssim = ssim_mean(ref, test)
        ssims.append(frame_ssim)
        per_frame.append({
            "t_s": t,
            "psnr_db": round(frame_psnr, 3) if math.isfinite(frame_psnr) else "inf",
            "ssim": round(frame_ssim, 6),
            "mad_per_channel": mad_per_channel(ref, test),
        })

    if not per_frame:
        print("pair: no comparable frames found", file=sys.stderr)
        return 1

    mse_global = mse_accum / pix_accum if pix_accum else 0.0
    psnr_global = math.inf if mse_global == 0 else 10 * math.log10(255 ** 2 / mse_global)
    de = np.concatenate(all_de)
    result = {
        "reference_dir": str(ref_dir),
        "export": str(export),
        "canvas": scale_pad,
        "frames_compared": len(per_frame),
        "psnr_global_db": round(psnr_global, 3) if math.isfinite(psnr_global) else "inf",
        "ssim_mean": round(float(np.mean(ssims)), 6),
        "ssim_min": round(float(np.min(ssims)), 6),
        "mad_p95": round(percentile(all_mads, 95), 3),
        "mad_max": round(max(all_mads), 3),
        "delta_e_mean": round(float(de.mean()), 3),
        "delta_e_p95": round(percentile(list(de), 95), 3),
        "delta_e_max": round(float(de.max()), 3),
        "per_frame": per_frame,
    }
    _emit(result, args.out)
    return 0


# ----------------------------------------------------------------------------
# blind — human blind-comparison protocol
# ----------------------------------------------------------------------------


def cmd_blind(args: argparse.Namespace) -> int:
    if args.tally:
        if not args.key:
            print("blind --tally requires --key", file=sys.stderr)
            return 2
        return blind_tally(Path(args.tally), Path(args.key), Path(args.out or "."))

    if not args.a_dir or not args.b_dir or not args.out:
        print("blind: --a-dir, --b-dir and --out are required without --tally", file=sys.stderr)
        return 2
    a_dir, b_dir = Path(args.a_dir), Path(args.b_dir)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    fixture_ids = sorted({p.stem for p in a_dir.glob("*.mp4")}
                         & {p.stem for p in b_dir.glob("*.mp4")})
    if not fixture_ids:
        print(f"blind: no matching fixture stems between {a_dir} and {b_dir}", file=sys.stderr)
        return 1

    rng = random.Random(args.seed)
    mapping: dict[str, dict[str, str]] = {}
    rows: list[str] = ["| # | fixture | X | Y |", "|---|---------|---|---|"]
    for i, fid in enumerate(fixture_ids, start=1):
        x_is_a = rng.random() < 0.5
        mapping[fid] = {"X": "A" if x_is_a else "B", "Y": "B" if x_is_a else "A"}
        # CODEX-10: the ballot's X column must point at <fid>_X.mp4 (what the
        # materialization step actually produced) — the mapping table is the
        # ONLY place X/Y decode to A/B. Swapping the file names here made an
        # evaluator's X vote tally as the opposite editor whenever x_is_a
        # was false.
        rows.append(f"| {i} | {fid} | {fid}_X.mp4 | {fid}_Y.mp4 |")

    # Materialize the shuffled copies so the viewer never sees original names.
    materialize: list[str] = []
    for fid, side in mapping.items():
        for label, origin in side.items():
            src = (a_dir if origin == "A" else b_dir) / f"{fid}.mp4"
            dst = out_dir / f"{fid}_{label}.mp4"
            if not dst.exists() or dst.stat().st_mtime < src.stat().st_mtime:
                run_text(["cp", str(src), str(dst)])
            materialize.append(str(dst))

    (out_dir / "blind_key.json").write_text(json.dumps({
        "seed": args.seed,
        "mapping": mapping,
        "note": "Do not open during evaluation. Used only by --tally.",
    }, indent=2))
    (out_dir / "responses.csv").write_text(
        "fixture,preferred,confidence(1-5),notes\n" +
        "".join(f"{fid},,\n" for fid in fixture_ids))
    ballot = [
        "# CA-12 blind A/B ballot",
        "",
        f"Seed: {args.seed} — sides are randomized per fixture.",
        "",
        "For each row, watch X (`<fixture>_X.mp4`) and Y (`<fixture>_Y.mp4`)",
        "(same fixture, two editors), then record the preferred side in",
        "responses.csv (X | Y | tie) plus a 1-5 confidence. Evaluate picture",
        "quality only (sharpness, artifacts, banding, color). Do not open",
        "blind_key.json before finishing.",
        "",
        *rows,
    ]
    (out_dir / "ballot.md").write_text("\n".join(ballot) + "\n")
    print(f"blind: {len(fixture_ids)} trials -> {out_dir} (ballot.md, responses.csv, blind_key.json)")
    return 0


def blind_tally(responses: Path, key: Path, out_dir: Path) -> int:
    key_data = json.loads(key.read_text())
    mapping = key_data["mapping"]
    wins = {"A": 0, "B": 0}
    ties = 0
    trials = 0
    with responses.open() as fh:
        for row in csv.DictReader(fh):
            fid = (row.get("fixture") or "").strip()
            pref = (row.get("preferred") or "").strip().upper()
            if fid not in mapping or not pref:
                continue
            trials += 1
            if pref == "TIE":
                ties += 1
            elif pref in ("X", "Y"):
                wins[mapping[fid][pref]] += 1
    decided = wins["A"] + wins["B"]
    result = {
        "trials": trials,
        "ties": ties,
        "wins_a": wins["A"],
        "wins_b": wins["B"],
        "a_share_of_decided": round(wins["A"] / decided, 4) if decided else None,
        "note": "Part 5 gate wording: blind 비열등 (not-inferiority), not a win-rate race.",
    }
    _emit(result, out_dir / "blind_result.json")
    return 0


# ----------------------------------------------------------------------------
# self-test
# ----------------------------------------------------------------------------


def cmd_self_test(_: argparse.Namespace) -> int:
    failures: list[str] = []

    def check(name: str, cond: bool) -> None:
        print(f"  {'PASS' if cond else 'FAIL'}  {name}")
        if not cond:
            failures.append(name)

    rng = np.random.default_rng(42)
    base = np.full((64, 64, 3), 128, dtype=np.uint8)
    offset = np.full((64, 64, 3), 138, dtype=np.uint8)

    # PSNR: identical -> inf; +-10 uniform -> MSE 100 -> 20.412 dB.
    check("psnr identical = inf", math.isinf(psnr_db(base, base)))
    expected = 10 * math.log10(255 ** 2 / 100)
    check("psnr uniform offset = 20.412 dB", abs(psnr_db(base, offset) - expected) < 1e-9)

    # SSIM: identical = 1; noise degrades; structured vs noise ordering.
    noisy = np.clip(base.astype(np.int16) + rng.integers(-25, 25, base.shape), 0, 255).astype(np.uint8)
    check("ssim identical = 1.0", abs(ssim_mean(base, base) - 1.0) < 1e-9)
    check("ssim noise < 1.0", ssim_mean(base, noisy) < 0.99)
    grad = np.tile(np.linspace(0, 255, 64, dtype=np.uint8)[:, None, None], (1, 64, 3))
    grad_noisy = np.clip(grad.astype(np.int16) + rng.integers(-4, 4, grad.shape), 0, 255).astype(np.uint8)
    check("ssim mild-noise > heavy-noise", ssim_mean(grad, grad_noisy) > ssim_mean(base, noisy))

    # delta-E: pure black vs pure white == 100 (CIE76, L 0 vs 100).
    black = np.zeros((8, 8, 3), dtype=np.uint8)
    white = np.full((8, 8, 3), 255, dtype=np.uint8)
    de = float(delta_e76(black, white).mean())
    check("delta_e black/white = 100.0", abs(de - 100.0) < 0.5)

    # Clipping / crush / banding on synthetic frames.
    hot = np.full((8, 8, 3), 255, dtype=np.uint8)
    check("highlight 100% on white", abs(highlight_clip_pct(hot) - 100.0) < 1e-9)
    dark = np.zeros((8, 8, 3), dtype=np.uint8)
    check("shadow crush 100% on black", abs(shadow_crush_pct(dark) - 100.0) < 1e-9)
    ramp = np.tile(np.linspace(0, 255, 256, dtype=np.uint8)[None, :, None], (8, 1, 3))
    check("banding 0 on full ramp", banding_proxy(ramp) == 0.0)
    posterized = (ramp // 32) * 32
    check("banding > 0.9 on posterized ramp", banding_proxy(posterized) > 0.9)

    # MAD per channel sanity.
    check("mad offset = 10", mad_per_channel(base, offset) == [10.0, 10.0, 10.0])

    # sample_times never hits 0 or the end.
    ts = sample_times(10.0, 5)
    check("sample_times interior", all(0 < t < 10 for t in ts) and len(ts) == 5)

    # Blind randomization determinism + true side swap.
    r1, r2 = random.Random(7), random.Random(7)
    m1 = {fid: (r1.random() < 0.5) for fid in range(20)}
    m2 = {fid: (r2.random() < 0.5) for fid in range(20)}
    check("blind seed determinism", m1 == m2)

    # Blind label/materialization/tally round trip (CODEX-10): the ballot's
    # X column must point at <fid>_X.mp4, the materialized files must match
    # the mapping's sides byte-for-byte, and an all-X ballot must tally to
    # whichever side the mapping says X is — covering BOTH x_is_a outcomes.
    import tempfile
    a_payload = b"A-SIDE-" + bytes(range(256)) * 4
    b_payload = b"B-SIDE-" + bytes(255 - i for i in range(256)) * 4
    x_is_a_seen = {True: 0, False: 0}
    label_ok = mat_ok = True
    with tempfile.TemporaryDirectory() as td:
        tdp = Path(td)
        for seed in range(12):
            a_dir, b_dir, out_dir = tdp / f"a{seed}", tdp / f"b{seed}", tdp / f"out{seed}"
            a_dir.mkdir(); b_dir.mkdir()
            fids = ("fx01", "fx02", "fx03", "fx04")
            for fid in fids:
                (a_dir / f"{fid}.mp4").write_bytes(a_payload)
                (b_dir / f"{fid}.mp4").write_bytes(b_payload)
            rc = cmd_blind(argparse.Namespace(
                tally=None, key=None, a_dir=str(a_dir), b_dir=str(b_dir),
                out=str(out_dir), seed=seed))
            if rc != 0:
                label_ok = mat_ok = False
                break
            key = json.loads((out_dir / "blind_key.json").read_text())
            ballot = (out_dir / "ballot.md").read_text()
            for fid in fids:
                side = key["mapping"][fid]
                x_is_a_seen[side["X"] == "A"] += 1
                if not re.search(rf"\| {fid}_X\.mp4 \| {fid}_Y\.mp4 \|", ballot):
                    label_ok = False
                expected_x = a_payload if side["X"] == "A" else b_payload
                expected_y = b_payload if side["X"] == "A" else a_payload
                if (out_dir / f"{fid}_X.mp4").read_bytes() != expected_x \
                        or (out_dir / f"{fid}_Y.mp4").read_bytes() != expected_y:
                    mat_ok = False
            # All-X ballots decode through the mapping: wins land on each
            # side exactly as often as X maps to it in this seed.
            (out_dir / "responses.csv").write_text(
                "fixture,preferred,confidence(1-5),notes\n" +
                "".join(f"{fid},X,3,\n" for fid in fids))
            blind_tally(out_dir / "responses.csv", out_dir / "blind_key.json", out_dir)
            result = json.loads((out_dir / "blind_result.json").read_text())
            want_a = sum(1 for fid in fids if key["mapping"][fid]["X"] == "A")
            if result["wins_a"] != want_a or result["wins_b"] != len(fids) - want_a:
                mat_ok = False
    check("blind ballot labels always <fid>_X/<fid>_Y", label_ok)
    check("blind materialization + tally match mapping (both x_is_a outcomes)",
          mat_ok and x_is_a_seen[True] > 0 and x_is_a_seen[False] > 0)

    # chroma subsampling parsing.
    check("chroma yuv420p -> 4:2:0", chroma_subsampling("yuv420p") == "4:2:0")
    check("chroma yuv444p -> 4:4:4", chroma_subsampling("yuv444p") == "4:4:4")

    print(f"self-test: {'PASS' if not failures else 'FAIL'} ({len(failures)} failure(s))")
    return 1 if failures else 0


# ----------------------------------------------------------------------------
# output helpers
# ----------------------------------------------------------------------------


def _emit(payload: dict[str, Any], out: str | None) -> None:
    text = json.dumps(payload, indent=2)
    if out:
        Path(out).parent.mkdir(parents=True, exist_ok=True)
        Path(out).write_text(text + "\n")
        print(f"wrote {out}")
    else:
        print(text)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    p_single = sub.add_parser("single", help="absolute metrics for one video")
    p_single.add_argument("video")
    p_single.add_argument("-o", "--out")
    p_single.add_argument("--samples", type=int, default=9)
    p_single.set_defaults(func=cmd_single)

    p_pair = sub.add_parser("pair", help="reference (preview PNGs) vs export metrics")
    p_pair.add_argument("--reference-dir", required=True)
    p_pair.add_argument("--export", required=True)
    p_pair.add_argument("--times", required=True)
    p_pair.add_argument("-o", "--out")
    p_pair.set_defaults(func=cmd_pair)

    p_blind = sub.add_parser("blind", help="human blind A/B protocol")
    p_blind.add_argument("--a-dir")
    p_blind.add_argument("--b-dir")
    p_blind.add_argument("--out")
    p_blind.add_argument("--seed", type=int, default=20260827)
    p_blind.add_argument("--tally", help="score a filled responses.csv")
    p_blind.add_argument("--key", help="blind_key.json for --tally")
    p_blind.set_defaults(func=cmd_blind)

    p_test = sub.add_parser("self-test", help="deterministic metric checks")
    p_test.set_defaults(func=cmd_self_test)

    args = parser.parse_args()
    if args.command == "blind" and args.tally and not args.key:
        print("blind --tally requires --key", file=sys.stderr)
        return 2
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
