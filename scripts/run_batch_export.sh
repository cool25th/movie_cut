#!/usr/bin/env bash
# OC-02 — headless batch export (헤드리스 배치 출력).
#
# The app's harness already runs full import→export passes unattended; this
# CLI productizes that path for PROJECT files: each `.moviecut` argument (or
# every *.moviecut under a directory argument) is loaded through the REAL
# launch path (MOVIECUT_BOOTSTRAP_PROJECT → openProject) and exported through
# the standard preset writer to <outdir>/<project-name>.mp4.
#
# Contract: every input produces either a verified artifact (file exists,
# non-empty, container duration > 0) or an EXPLICIT surfaced error (the
# harness result line carries error != none). A hang/crash/missing result
# line is a FAILURE (exit 1) — never "skipped". Batch summary at the end.
#
# Entirely local: the harness path never touches the network (CA-01).
#
# Usage: bash scripts/run_batch_export.sh <project.moviecut | dir> [outdir]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v ffprobe >/dev/null || { echo "ffprobe required" >&2; exit 2; }

if [ $# -lt 1 ]; then
  echo "usage: $0 <project.moviecut | dir> [outdir]" >&2
  exit 2
fi

if [ -x "$ROOT/scripts/disk_guard.sh" ]; then
  "$ROOT/scripts/disk_guard.sh" >/dev/null 2>&1 || {
    rc=$?
    echo "ERROR: disk guard refuses new work (rc=$rc) — aborting" >&2
    exit 2
  }
fi

# Collect inputs.
INPUTS=()
for arg in "$@"; do
  case "$arg" in
    *.moviecut) [ -s "$arg" ] && INPUTS+=("$(cd "$(dirname "$arg")" && pwd)/$(basename "$arg")") ;;
    *)
      # First non-.moviecut arg = output directory.
      if [ -z "${OUTDIR:-}" ]; then
        OUTDIR="$arg"
      fi
      ;;
  esac
done
# Directory arguments expand to their .moviecut contents.
EXPANDED=()
for input in "${INPUTS[@]}"; do EXPANDED+=("$input"); done
for arg in "$@"; do
  if [ -d "$arg" ]; then
    while IFS= read -r found; do EXPANDED+=("$found"); done < <(find "$arg" -maxdepth 1 -name "*.moviecut" -size +0 | sort)
  fi
done
[ ${#EXPANDED[@]} -ge 1 ] || { echo "no .moviecut inputs found" >&2; exit 2; }
OUTDIR="${OUTDIR:-$PWD/batch-exports}"
mkdir -p "$OUTDIR"

echo "Building MovieCutMac (Debug, sandbox OFF)..."
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO build >/dev/null
APP_BIN="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{sub(/\r/,"",$2); print $2; exit}')/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found" >&2; exit 2; }

WORK="$(mktemp -d /tmp/moviecut-batch.XXXXXX)"
trap 'rm -rf "$WORK"; pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true' EXIT

echo "=== headless batch export: ${#EXPANDED[@]} project(s) → $OUTDIR ==="
FAIL=0; OK=0; ERRORED=0
for project in "${EXPANDED[@]}"; do
  name="$(basename "$project" .moviecut)"
  out="$OUTDIR/$name.mp4"
  result="$WORK/$name.result.txt"
  rm -f "$out" "$result"
  env MOVIECUT_UITEST=1 \
    MOVIECUT_BOOTSTRAP_PROJECT="$project" \
    MOVIECUT_UITEST_EXPORT="$out" \
    MOVIECUT_UITEST_RESULT="$result" \
    MOVIECUT_UITEST_QUIT=1 \
    "$APP_BIN" >"$WORK/$name.log" 2>&1 &
  pid=$!
  ( sleep 300; kill "$pid" 2>/dev/null; true ) & wd=$!
  for _ in $(seq 1 600); do
    grep -q "UITEST_DONE" "$result" 2>/dev/null && break
    sleep 0.5
  done
  wait "$pid" 2>/dev/null || true
  kill "$wd" 2>/dev/null || true

  if ! grep -q "UITEST_DONE" "$result" 2>/dev/null; then
    echo "  FAIL  $name — no result line (hang/crash); log: $WORK/$name.log"
    FAIL=$((FAIL + 1))
    continue
  fi
  if ! grep -q "error=none" "$result" 2>/dev/null; then
    status="$(grep -oE 'error=.*' "$result" | head -1)"
    echo "  ERR   $name — explicit unsupported: $status"
    ERRORED=$((ERRORED + 1))
    continue
  fi
  if [ ! -s "$out" ]; then
    echo "  FAIL  $name — error=none but no artifact"
    FAIL=$((FAIL + 1))
    continue
  fi
  dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out" 2>/dev/null || echo 0)"
  ok="$(python3 -c "print(1 if float('$dur') > 0 else 0)" 2>/dev/null || echo 0)"
  if [ "$ok" = "1" ]; then
    echo "  OK    $name → $out (${dur}s)"
    OK=$((OK + 1))
  else
    echo "  FAIL  $name — artifact duration unparsable ($dur)"
    FAIL=$((FAIL + 1))
  fi
done

echo "=== batch summary: OK=$OK explicit-error=$ERRORED FAIL=$FAIL ==="
[ "$FAIL" -eq 0 ] || exit 1
