#!/usr/bin/env bash
# CA-22 2차 gate — auto proxy generation: settings toggle, in-flight cancel,
# and resume, all through the REAL app import path (Mac harness, Debug build,
# sandbox OFF).
#
# Legs (each a fresh cold app launch → fresh project):
#   A. mode=off  → import → NOTHING scheduled (assets=0, cancelled=0)
#   B. mode=on   → import → proxy generated (assets=1, missing=0)
#   C. mode=on + cancel (long fixture so the cancel lands mid-encode)
#                → cancelled>=1, assets=0, missing=1
#   D. mode=on + cancel + resume → the cancelled generation is restarted and
#                completes (assets=1, cancelled>=1)
#
# Fixture: the small legs reuse the committed 3s bars clip; the cancel legs
# generate a deterministic 90s 1080p30 clip at runtime (same pattern as the
# latency baseline's 10-minute fixture — nothing large is committed).
#
# Usage: bash scripts/run_ca22_proxy_gate.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v ffmpeg >/dev/null || { echo "ffmpeg required" >&2; exit 1; }

WORK="$(mktemp -d /tmp/ca22.XXXXXX)"
trap 'rm -rf "$WORK"; pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true' EXIT

FIXTURE="$ROOT/Tests/Fixtures/bars_320x240_3s_30fps.mp4"
[ -f "$FIXTURE" ] || { echo "missing fixture: run scripts/make_fixtures.sh" >&2; exit 1; }

LONG="$WORK/ca22_long_1920x1080_90s.mp4"
echo "[ca22] generating 90s cancel-window fixture…"
ffmpeg -v error -y \
  -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=90" \
  -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p "$LONG"

echo "[ca22] building MovieCutMac (Debug, sandbox OFF)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO build >/dev/null
products="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')" || true
APP_BIN="$products/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found" >&2; exit 1; }

# run_leg <name> <fixture> [extra env...]
run_leg() {
  local name="$1"; shift
  local fixture="$1"; shift
  local dir="$WORK/$name"
  mkdir -p "$dir"
  local result="$dir/result.txt"
  rm -f "$result"
  pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true; sleep 1
  # shellcheck disable=SC2086
  env MOVIECUT_UITEST=1 \
    MOVIECUT_UITEST_AUTO_PROXY=1 \
    MOVIECUT_UITEST_IMPORT="$fixture" \
    MOVIECUT_UITEST_RESULT="$result" \
    MOVIECUT_UITEST_QUIT=1 \
    $* \
    "$APP_BIN" >/dev/null 2>&1 &
  local pid=$!
  ( sleep 360; kill "$pid" 2>/dev/null || true ) &
  local wd=$!
  for _ in $(seq 1 720); do [ -s "$result" ] && grep -q "UITEST_DONE" "$result" 2>/dev/null && break; sleep 0.5; done
  wait "$pid" 2>/dev/null || true
  kill "$wd" 2>/dev/null || true
  cat "$result" 2>/dev/null | tail -1 || true
}

field() { # <text> <key>
  # `|| echo` keeps a missing key from returning non-zero — under `set -e`
  # that would kill the caller (same trap class as check()'s return below).
  printf '%s' "$1" | grep -oE "$2=[^ ]+" | head -1 | cut -d= -f2 || echo ""
}

FAIL=0
check() { # <name> <actual> <expected-op> <expected>
  local name="$1" actual="$2" op="$3" expected="$4" verdict
  verdict=FAIL
  case "$op" in
    eq) [ "$actual" = "$expected" ] && verdict=PASS ;;
    ge) [ -n "$actual" ] && [ "$actual" -ge "$expected" ] 2>/dev/null && verdict=PASS ;;
  esac
  printf '%-38s %s (got %s, want %s %s)\n' "$name" "$verdict" "${actual:-missing}" "$op" "$expected"
  [ "$verdict" = FAIL ] && FAIL=1
  # A passing check's `&& FAIL=1` chain evaluates to 1; without an explicit
  # `return 0` the function itself returns non-zero and `set -e` exits the
  # script right after the FIRST passing assertion.
  return 0
}

echo "[ca22] leg A: mode=off — nothing scheduled"
A="$(run_leg A "$FIXTURE" MOVIECUT_UITEST_AUTO_PROXY_MODE=off)"
check "A assets-with-proxy" "$(field "$A" auto_proxy_assets)" eq 0
check "A cancelled" "$(field "$A" auto_proxy_cancelled)" eq 0

echo "[ca22] leg B: mode=on — generated in background"
B="$(run_leg B "$FIXTURE" MOVIECUT_UITEST_AUTO_PROXY_MODE=on)"
check "B idle" "$(field "$B" auto_proxy_idle)" eq 1
check "B assets-with-proxy" "$(field "$B" auto_proxy_assets)" eq 1
check "B missing" "$(field "$B" auto_proxy_missing)" eq 0

echo "[ca22] leg C: cancel mid-encode (90s fixture)"
C="$(run_leg C "$LONG" MOVIECUT_UITEST_AUTO_PROXY_MODE=on MOVIECUT_UITEST_AUTO_PROXY_CANCEL=1)"
check "C cancelled>=1" "$(field "$C" auto_proxy_cancelled)" ge 1
check "C assets-with-proxy" "$(field "$C" auto_proxy_assets)" eq 0
check "C missing" "$(field "$C" auto_proxy_missing)" eq 1

echo "[ca22] leg D: cancel then resume — restarts and completes"
D="$(run_leg D "$LONG" MOVIECUT_UITEST_AUTO_PROXY_MODE=on MOVIECUT_UITEST_AUTO_PROXY_CANCEL=1 MOVIECUT_UITEST_AUTO_PROXY_RESUME=1)"
check "D cancelled>=1" "$(field "$D" auto_proxy_cancelled)" ge 1
check "D assets-with-proxy" "$(field "$D" auto_proxy_assets)" eq 1
check "D missing" "$(field "$D" auto_proxy_missing)" eq 0

if [ "$FAIL" -eq 0 ]; then
  echo "CA22 PROXY GATE: PASS"
else
  echo "CA22 PROXY GATE: FAIL" >&2
  exit 1
fi
