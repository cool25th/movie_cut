#!/usr/bin/env python3
"""Region-based CapCut vs MovieCut visual parity metrics.

Compares two *window-content* screenshots (CapCut reference and the current
MovieCut window) by splitting each into the five editor regions and computing
coarse style metrics per region: brightness, contrast, edge density, dark fill,
grayscale histogram intersection, and an aggregate coarse visual similarity.

This intentionally avoids the misleading "empty black screen" comparison:
both inputs MUST be captured in a populated state (timeline with video, audio,
and text clips). Comparing two near-black empty editors yields ~0.97 similarity
and hides the real gap. See docs/CAPCUT_UI_SHOWCASE_HANDOFF.md section 4.

Dependencies: numpy + Pillow only (no OpenCV / SciPy).

Usage:
    python3 scripts/capcut_parity_metrics.py \
        --capcut /tmp/moviecut-ui-evidence/capcut_reference_window.png \
        --moviecut /tmp/moviecut-ui-evidence/moviecut_current_window.png \
        --out /tmp/moviecut-ui-evidence/side_by_side_metrics_populated.json \
        --check
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image

# Each region is (x0, y0, x1, y1) as fractions of the window-content crop.
# Approximates the 5-region editor IA: top bar / left browser / center
# preview / right inspector / bottom timeline. Override with --layout <json>.
DEFAULT_LAYOUT: dict[str, tuple[float, float, float, float]] = {
    "full": (0.00, 0.00, 1.00, 1.00),
    "top_bar": (0.00, 0.00, 1.00, 0.06),
    "left_browser": (0.00, 0.06, 0.22, 0.80),
    "preview_center": (0.22, 0.06, 0.74, 0.80),
    "right_inspector": (0.74, 0.06, 1.00, 0.80),
    "timeline": (0.00, 0.80, 1.00, 1.00),
}

SUBREGIONS = ["top_bar", "left_browser", "preview_center", "right_inspector", "timeline"]

# Every region is squashed to this size so edge density and histograms compare
# at identical dimensions regardless of source window resolution.
NORM_SIZE = 256

# Grayscale value below which a pixel counts as "dark fill". CapCut's chrome is
# near-black; MovieCut's earlier bright panels scored low here.
DARK_FILL_THRESHOLD = 48.0

# Sobel gradient magnitude above which a pixel counts as an edge.
EDGE_THRESHOLD = 50.0

HIST_BINS = 32

# Per-region coarse similarity weights (must sum to 1.0). Dark fill, histogram,
# and brightness carry the dark-shell style signal; contrast/edge are secondary.
WEIGHTS = {
    "brightness": 0.25,
    "contrast": 0.10,
    "edge": 0.10,
    "dark_fill": 0.30,
    "histogram": 0.25,
}

# Pass thresholds for --check (from the handoff doc, section 4).
TARGET_MEAN_SIMILARITY = 0.75
TARGET_DARK_FILL_DELTA = 0.15


def load_gray(path: Path) -> np.ndarray:
    img = Image.open(path).convert("RGB")
    arr = np.asarray(img, dtype=np.float64)
    # Rec. 601 luma.
    return 0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2]


def crop_region(gray: np.ndarray, bounds: tuple[float, float, float, float]) -> np.ndarray:
    h, w = gray.shape
    x0, y0, x1, y1 = bounds
    cx0, cx1 = int(round(x0 * w)), int(round(x1 * w))
    cy0, cy1 = int(round(y0 * h)), int(round(y1 * h))
    cx1 = max(cx1, cx0 + 1)
    cy1 = max(cy1, cy0 + 1)
    return gray[cy0:cy1, cx0:cx1]


def normalize(region: np.ndarray) -> np.ndarray:
    img = Image.fromarray(region.astype(np.uint8))
    img = img.resize((NORM_SIZE, NORM_SIZE), Image.BILINEAR)
    return np.asarray(img, dtype=np.float64)


def edge_density(region: np.ndarray) -> float:
    gx = region[1:-1, 2:] - region[1:-1, :-2]
    gy = region[2:, 1:-1] - region[:-2, 1:-1]
    mag = np.sqrt(gx ** 2 + gy ** 2)
    return float(np.mean(mag > EDGE_THRESHOLD))


def dark_fill(region: np.ndarray) -> float:
    return float(np.mean(region < DARK_FILL_THRESHOLD))


def gray_histogram(region: np.ndarray) -> np.ndarray:
    hist, _ = np.histogram(region, bins=HIST_BINS, range=(0.0, 255.0))
    total = hist.sum()
    if total == 0:
        return np.zeros(HIST_BINS, dtype=np.float64)
    return hist.astype(np.float64) / total


def region_metrics(cap: np.ndarray, mov: np.ndarray) -> dict[str, float]:
    cap_n = normalize(cap)
    mov_n = normalize(mov)

    b_cap, b_mov = float(np.mean(cap_n)), float(np.mean(mov_n))
    c_cap, c_mov = float(np.std(cap_n)), float(np.std(mov_n))
    e_cap, e_mov = edge_density(cap_n), edge_density(mov_n)
    d_cap, d_mov = dark_fill(cap_n), dark_fill(mov_n)
    hist_inter = float(np.minimum(gray_histogram(cap_n), gray_histogram(mov_n)).sum())

    sims = {
        "brightness": 1.0 - min(1.0, abs(b_cap - b_mov) / 128.0),
        "contrast": 1.0 - min(1.0, abs(c_cap - c_mov) / 96.0),
        "edge": 1.0 - min(1.0, abs(e_cap - e_mov) / 0.05),
        "dark_fill": 1.0 - min(1.0, abs(d_cap - d_mov)),
        "histogram": hist_inter,
    }
    coarse = sum(WEIGHTS[k] * sims[k] for k in WEIGHTS)

    return {
        "brightness_capcut": round(b_cap, 2),
        "brightness_moviecut": round(b_mov, 2),
        "brightness_delta": round(abs(b_cap - b_mov), 2),
        "contrast_capcut": round(c_cap, 2),
        "contrast_moviecut": round(c_mov, 2),
        "edge_density_capcut": round(e_cap, 4),
        "edge_density_moviecut": round(e_mov, 4),
        "edge_density_delta": round(abs(e_cap - e_mov), 4),
        "dark_fill_capcut": round(d_cap, 4),
        "dark_fill_moviecut": round(d_mov, 4),
        "dark_fill_delta": round(abs(d_cap - d_mov), 4),
        "histogram_intersection": round(hist_inter, 4),
        "coarse_visual_similarity": round(coarse, 4),
    }


def load_layout(path: Path | None) -> dict[str, tuple[float, float, float, float]]:
    if path is None:
        return DEFAULT_LAYOUT
    raw = json.loads(path.read_text())
    return {k: tuple(v) for k, v in raw.items()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--capcut", required=True, type=Path, help="CapCut reference window-content PNG")
    parser.add_argument("--moviecut", required=True, type=Path, help="MovieCut current window-content PNG")
    parser.add_argument("--out", type=Path, default=None, help="Write metrics JSON here")
    parser.add_argument("--layout", type=Path, default=None, help="Optional region-bounds JSON override")
    parser.add_argument("--check", action="store_true", help="Exit nonzero if parity targets are unmet")
    args = parser.parse_args()

    for label, path in (("capcut", args.capcut), ("moviecut", args.moviecut)):
        if not path.exists():
            print(f"error: {label} image not found: {path}", file=sys.stderr)
            return 2

    layout = load_layout(args.layout)
    cap_gray = load_gray(args.capcut)
    mov_gray = load_gray(args.moviecut)

    results: dict[str, Any] = {}
    for name, bounds in layout.items():
        results[name] = region_metrics(crop_region(cap_gray, bounds), crop_region(mov_gray, bounds))

    sub = [results[r] for r in SUBREGIONS if r in results]
    mean_sim = round(sum(r["coarse_visual_similarity"] for r in sub) / len(sub), 4) if sub else 0.0
    worst_dark = max((r["dark_fill_delta"] for r in sub), default=0.0)
    results["_aggregate"] = {
        "mean_coarse_visual_similarity": mean_sim,
        "worst_region_dark_fill_delta": round(worst_dark, 4),
        "capcut_image": str(args.capcut),
        "moviecut_image": str(args.moviecut),
        "note": "Populated-state region metrics. Both inputs must show a filled timeline; empty editors score falsely high.",
    }

    print(f"{'region':<16} {'sim':>6}  {'dark_cap':>8} {'dark_mov':>8}  {'bri_cap':>7} {'bri_mov':>7}")
    for name in ["full", *SUBREGIONS]:
        if name not in results:
            continue
        m = results[name]
        print(
            f"{name:<16} {m['coarse_visual_similarity']:>6.3f}  "
            f"{m['dark_fill_capcut']:>8.3f} {m['dark_fill_moviecut']:>8.3f}  "
            f"{m['brightness_capcut']:>7.1f} {m['brightness_moviecut']:>7.1f}"
        )
    print(f"\nmean subregion similarity: {mean_sim}  (target >= {TARGET_MEAN_SIMILARITY})")
    print(f"worst region dark_fill delta: {round(worst_dark, 4)}  (target <= {TARGET_DARK_FILL_DELTA})")

    if args.out is not None:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(results, indent=2))
        print(f"wrote {args.out}")

    if args.check:
        ok = mean_sim >= TARGET_MEAN_SIMILARITY and worst_dark <= TARGET_DARK_FILL_DELTA
        if not ok:
            print("\nPARITY CHECK FAILED", file=sys.stderr)
            return 1
        print("\nPARITY CHECK PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
