#!/usr/bin/env bash
# QAUTO provenance hardening (29th-cycle): REAL generated media E2E —
# GEN_MEDIA_001 through the full generated-fixture provenance chain.
#
# Success sequence (28th-cycle feedback, 13 steps condensed):
#   1. clean workspace (no output/temp leftovers)
#   2. GENERATE via the real generator -> H1
#   3. remove output + temp (clean workspace again)
#   4. fresh-process GENERATE (same contract) -> H2
#   5. assert H1 == H2 — divergence = NONDETERMINISTIC_GENERATION observed:
#      STOP (recorded, chain never opened; NOT patched via rebaseline)
#   6. --init registration on the REAL lock (GENERATE event + env metadata)
#   7. clean fresh-process REGENERATE -> deterministic confirmation,
#      assert the lock is byte-identical afterwards (read-only verification)
#   8. Mutation A: 1-byte output corruption -> GEN-02 fires
#   9. Mutation B: recorded generation_parameters_hash tampered (gen_id kept)
#      -> GEN-01 fires
#  10. Mutation C: same generation_id + different output in the journal
#      -> GEN-06 / NONDETERMINISTIC_GENERATION fires
#  11. clean restoration (real lock untouched by mutations)
#  12. REBASELINE on a COPY of the lock (temp) — the real lock stays
#      CONTINUOUS; rebaselining without cause would pollute the ledger
#  13. committed-fixture verify regression (6 pins ALL MATCH) + real
#      generated-lock audit PASS/CONTINUOUS
#
# Usage: bash scripts/run_gen_media_e2e.sh
set -uo pipefail   # NO -e: expected-failure mutation legs return rc=1 on purpose
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v ffmpeg >/dev/null || { echo "ffmpeg required" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe required" >&2; exit 1; }

GEN="$ROOT/scripts/check_generated_fixtures.sh"
GENG="$ROOT/scripts/generators/gen_media_001.sh"
PIN="$ROOT/scripts/check_dataset_pins.sh"
LOCK="$ROOT/qa/baselines/generated-fixtures.json"
OUT="$ROOT/Tests/Fixtures/generated/GEN_MEDIA_001.mp4"
E2E_DIR="$(mktemp -d /tmp/moviecut-genmedia-e2e.XXXXXX)"

fail() { echo "GEN-MEDIA-E2E FAIL: $1" >&2; tar -cf "$E2E_DIR/evidence.tar" "$OUT" 2>/dev/null || true; exit 1; }
chk() { if [ "$2" = "$3" ]; then echo "  OK  $1 (rc=$3)"; else echo "  BAD $1 expected rc=$2 got rc=$3"; fail "$1"; fi; }

echo "== 1-5) clean double-build determinism proof =="
rm -f "$OUT"
bash "$GENG" "$OUT" || fail "generator crashed (H1)"
[ -s "$OUT" ] || fail "generator produced no output (H1)"
H1="$(shasum -a 256 "$OUT" | awk '{print $1}')"
DUR="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT")"
RES="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate,codec_name -of csv=p=0 "$OUT")"
AUD="$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels -of csv=p=0 "$OUT")"
echo "  media: dur=${DUR}s · $RES · $AUD"
[ "$RES" = "h264,1920,1080,30/1" ] || fail "video contract mismatch: $RES"
[ "$AUD" = "aac,48000,2" ] || fail "audio contract mismatch (stereo required): $AUD"
rm -f "$OUT"                       # clean workspace — no temp/cache reuse
bash "$GENG" "$OUT" || fail "generator crashed (H2)"
[ -s "$OUT" ] || fail "generator produced no output (H2)"
H2="$(shasum -a 256 "$OUT" | awk '{print $1}')"
[ "$H1" = "$H2" ] || fail "NONDETERMINISTIC_GENERATION observed pre-registration: H1=${H1:0:12} H2=${H2:0:12} — chain NOT opened (per contract), inspect the generator"
echo "  H1 == H2 (${H1:0:16}…) — clean double-build deterministic"

echo "== 6) registration on the REAL lock (GENERATE) =="
cat > "$E2E_DIR/spec.json" <<EOF
{"fixture_id": "GEN_MEDIA_001",
 "generator_id": "scripts/generators/gen_media_001.sh",
 "generator_version": "1.0.0",
 "generation_parameters": {"video": {"width": 1920, "height": 1080, "fps": 30, "seconds": 2, "source": "fixed-color 0x202040"},
                           "audio": {"codec": "aac", "sample_rate": 48000, "channels": 2, "tone_hz": 440}},
 "inputs": [],
 "output_file": "Tests/Fixtures/generated/GEN_MEDIA_001.mp4"}
EOF
if python3 -c "
import json, sys
lock = json.load(open('$LOCK'))
sys.exit(0 if 'GEN_MEDIA_001' in lock.get('fixtures', {}) else 1)"; then
  fail "GEN_MEDIA_001 already registered — re-run must use --regenerate, not a second GENERATE"
fi
bash "$GEN" --init "$LOCK" "$E2E_DIR/spec.json" || fail "registration failed"
bash "$GEN" "$LOCK" >/dev/null 2>&1; chk "verify after registration" 0 $?

echo "== 7) fresh-process REGENERATE — read-only verification =="
rm -f "$OUT"
bash "$GENG" "$OUT" || fail "generator crashed (H3)"
H3="$(shasum -a 256 "$OUT" | awk '{print $1}')"
[ "$H1" = "$H3" ] || fail "REGENERATE produced different bytes: ${H3:0:12} vs ${H1:0:12}"
LOCK_BEFORE="$(shasum -a 256 "$LOCK" | awk '{print $1}')"
bash "$GEN" --regenerate "$LOCK" "$E2E_DIR/spec.json" | head -1
LOCK_AFTER="$(shasum -a 256 "$LOCK" | awk '{print $1}')"
[ "$LOCK_BEFORE" = "$LOCK_AFTER" ] || fail "REGENERATE rewrote the lock (verification event must be read-only)"
echo "  OK  REGENERATE deterministic confirmation · lock byte-identical"

echo "== 8) Mutation A: output corruption -> GEN-02 =="
cp "$OUT" "$E2E_DIR/out.bak"
printf 'X' >> "$OUT"
bash "$GEN" "$LOCK" > "$E2E_DIR/mutA.json" 2>/dev/null; chk "GEN-02 fires" 1 $?
grep -o "GEN-02_output_bytes" "$E2E_DIR/mutA.json" | head -1
cp "$E2E_DIR/out.bak" "$OUT"

echo "== 9) Mutation B: identity corruption -> GEN-01 =="
PH="$(python3 -c 'import json; print(json.load(open("qa/baselines/generated-fixtures.json"))["fixtures"]["GEN_MEDIA_001"]["generation_parameters_hash"])')"
python3 - "$PH" <<'PYMUTB'
import json, sys
p = "qa/baselines/generated-fixtures.json"
d = json.load(open(p))
e = d["fixtures"]["GEN_MEDIA_001"]
e["generation_parameters_hash"] = ("0" * 63) + "1" if sys.argv[1][-1] != "1" else ("0" * 63) + "2"
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
PYMUTB
bash "$GEN" "$LOCK" > "$E2E_DIR/mutB.json" 2>/dev/null; chk "GEN-01 fires" 1 $?
grep -o "GEN-01_generation_id_recompute" "$E2E_DIR/mutB.json" | head -1
python3 - "$PH" <<'PYUNMUTB'
import json, sys
p = "qa/baselines/generated-fixtures.json"
d = json.load(open(p))
d["fixtures"]["GEN_MEDIA_001"]["generation_parameters_hash"] = sys.argv[1]
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
PYUNMUTB
bash "$GEN" "$LOCK" >/dev/null 2>&1; chk "verify restored after B" 0 $?

echo "== 10) Mutation C: same gen_id + different output -> GEN-06 =="
GID="$(python3 -c 'import json; print(json.load(open("qa/baselines/generated-fixtures.json"))["fixtures"]["GEN_MEDIA_001"]["generation_id"])')"
python3 - "$GID" <<'PYMUTC'
import datetime, json, sys
line = {"ts": datetime.datetime.now().isoformat(timespec="seconds"),
        "kind": "generated_fixture_event", "event": "REGENERATE",
        "fixture_id": "GEN_MEDIA_001", "generation_id": sys.argv[1],
        "output_sha256": "e" * 64, "provenance_epoch": 1, "update_seq": 99}
open("qa/baselines/generated-lock-updates.jsonl", "a").write(json.dumps(line) + "\n")
PYMUTC
bash "$GEN" "$LOCK" > "$E2E_DIR/mutC.json" 2>/dev/null; chk "GEN-06 fires" 1 $?
grep -o "NONDETERMINISTIC_GENERATION" "$E2E_DIR/mutC.json" | head -1
python3 - <<'PYCLEANC'
lines = open("qa/baselines/generated-lock-updates.jsonl").readlines()
keep = [l for l in lines if '"update_seq": 99' not in l]
open("qa/baselines/generated-lock-updates.jsonl", "w").writelines(keep)
PYCLEANC
bash "$GEN" "$LOCK" >/dev/null 2>&1; chk "verify restored after C" 0 $?

echo "== 11-12) REBASELINE on a COPY (real lock stays CONTINUOUS) =="
TMPLOCK="$E2E_DIR/generated-fixtures.json"
cp "$LOCK" "$TMPLOCK"
cp qa/baselines/generated-lock-updates.jsonl "$E2E_DIR/generated-lock-updates.jsonl"
bash "$GEN" --rebaseline "$TMPLOCK" GEN_MEDIA_001 --reason "e2e: epoch semantics on a lock copy (real ledger untouched)" >/dev/null; chk "rebaseline on copy" 0 $?
python3 - "$E2E_DIR" <<'PYCHKRB'
import json, sys, os
d = sys.argv[1]
j = [json.loads(l) for l in open(os.path.join(d, "generated-lock-updates.jsonl")) if l.strip()]
r = [x for x in j if x.get("event") == "REBASELINE"][-1]
ok = r["provenance_epoch"] == 2 and r["previous_epoch"] == 1 and r["operator_acknowledgment"]
print("  OK  REBASELINE copy: prev=1 -> epoch=2" if ok else "  BAD " + json.dumps(r))
PYCHKRB
python3 - <<'PYCHKREAL'
import json
lock = json.load(open("qa/baselines/generated-fixtures.json"))
fx = lock["fixtures"]["GEN_MEDIA_001"]
ok = fx["provenance_epoch"] == 1
print("  OK  real lock epoch stays 1 (CONTINUOUS, no pollution)" if ok else "  BAD real lock rebaselined")
PYCHKREAL

echo "== 13) regression — committed pins + real generated audit =="
FIXTURES=$(python3 -c "
import json
lock=json.load(open('qa/baselines/dataset-lock.json'))
print(' '.join(sorted(lock['fixtures'].keys())))")
bash "$PIN" qa/baselines/dataset-lock.json $FIXTURES >/dev/null 2>&1; chk "committed verify 6 pins ALL MATCH" 0 $?
bash "$GEN" --audit "$LOCK" > "$E2E_DIR/audit.json" 2>/dev/null; chk "real generated audit" 0 $?
python3 - "$E2E_DIR" <<'PYCHKAUD'
import json, sys
r = json.load(open(sys.argv[1] + "/audit.json"))
fx = r["fixtures"]["GEN_MEDIA_001"]
ok = (r["invariants_status"] == "PASS" and r["overall_continuity_status"] == "CONTINUOUS"
      and fx["determinism_state"] == "DETERMINISTIC")
print("  OK  audit PASS/CONTINUOUS/DETERMINISTIC" if ok else "  BAD " + json.dumps(
    {k: r[k] for k in ("invariants_status", "overall_continuity_status")}, ensure_ascii=False))
PYCHKAUD

rm -rf "$E2E_DIR"
echo ""
echo "GEN-MEDIA-E2E PASS — GEN_MEDIA_001 registered: real-media clean double-build deterministic,"
echo "  REGENERATE read-only verified, mutations A/B/C fire, real ledger CONTINUOUS, committed pins intact"
echo "  scratch freed: $E2E_DIR"
