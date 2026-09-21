#!/usr/bin/env bash
# QAUTO provenance hardening (28th-cycle): GENERATED fixture provenance
# class — separate from the COMMITTED fixture lock by design (mixing
# content-addressed bytes with derivation records is forbidden).
#
# Identity is TWO-LAYER (27th-cycle feedback; 28th-cycle hardening applied):
#   fixture_id     logical identity (stable across regenerations)
#   generation_id  domain-separated, versioned canonical hash:
#                    SHA256("MOVIECUT_GENERATED_FIXTURE_V1\0"
#                           + fixture_id + generator_id + generator_version
#                           + generator_source_commit + generation_parameters_hash
#                           + input_count + ordered input_sha256…, all NUL-sep)
#                  = WHY this output exists (the generation contract).
#                  generator_id/version MUST be inside the hash: several
#                  generators can share one commit.
#   output_sha256  WHAT was actually produced (the evidence)
# Grammar contract (registration refuses anything else):
#   fixture_id / generator_id : [A-Za-z0-9._/-]+  (NUL impossible)
#   generator_version         : printable ASCII, NUL forbidden
#   generator_source_commit   : canonical lowercase git SHA
#   all sha256 fields         : lowercase hex, exactly 64 chars
# Canonicalization: UTF-8, NUL-separated fields in a fixed order.
# Input order: generator-DECLARED order — never sorted (A,B != B,A).
#
# Events are a separate vocabulary — the committed update_id semantics are
# NOT reused (an update is A->B state; a generated fixture change is a
# derivation):
#   GENERATE    first registration of a fixture_id (one per lock lifetime)
#   REGENERATE  same contract re-run (same generation_id) — deterministic
#               confirmation when the output matches
#   REBASELINE  operator-only provenance-world reset (--reason required,
#               epoch + 1, previous_epoch recorded)
#   REPAIR      journal witness for a provenance-restoration event (must
#               carry provenance_epoch; proof mechanism = LATER, the event
#               vocabulary is fixed here)
# regenerate != rebaseline: a generator code change alone is NEVER a
# rebaseline — the lineage continues unless the operator resets it.
# Event mutation semantics (28th-cycle):
#             generation_id   output        epoch
#   GENERATE  new             new           stays
#   REGENERATE  must equal    must equal    stays (read-only: journal only)
#   REBASELINE  may change    may change    +1 (operator --reason required)
#   REPAIR      re-derived    original      stays in principle (narrow scope)
#
# Invariants (audit/verify):
#   GEN-01 generation_id recomputes from the recorded fields
#   GEN-02 output_sha256 matches the actual file bytes (missing = fail)
#   GEN-03 generator_source_commit exists in Git
#   GEN-04 every input verifies (committed-lock chain or direct bytes)
#   GEN-05 input ordering canonical (ordered pair sequence, no duplicate ids)
#   GEN-06 one generation_id -> ONE output within the current chain
#          (epoch-aware: a REBASELINE resets the mapping)
# Determinism state (per fixture, three values — never a bare boolean):
#   DETERMINISTIC                  proven chain reproduces one output
#   NONDETERMINISTIC_GENERATION    same generation_id produced 2+ outputs
#   UNVERIFIABLE_GENERATION        cannot re-verify at all (source commit
#                                  gone / output missing / input chain broken)
#   NONDETERMINISTIC must NOT be converted by REBASELINE — fix the cause and
#   mint a NEW generation identity; UNVERIFIABLE may rebaseline only with an
#   explicit operator --reason.
# Asymmetric contract: same generation_id + different output = violation;
#   different generation_id + same output = ALLOWED (coincidence is legal).
# REGENERATE is a VERIFICATION event, not a mutation: a deterministic
# confirmation writes the immutable journal ONLY — the lock is untouched.
# A nondeterministic observation also leaves the lock untouched (exit 2).
# REPAIR scope is NARROW: re-deriving a LOST record from Git + generator
# source + input/output hashes. A generator that now produces different
# output is NOT repairable — it is NONDETERMINISTIC_GENERATION.
#
# Usage:
#   check_generated_fixtures.sh --init <gen-lock.json> <spec.json>
#   check_generated_fixtures.sh --regenerate <gen-lock.json> <spec.json>
#   check_generated_fixtures.sh --rebaseline <gen-lock.json> <fixture_id> --reason "…"
#   check_generated_fixtures.sh <gen-lock.json> [<output-file>…]     # verify
#   check_generated_fixtures.sh --audit [--human] <gen-lock.json>
set -euo pipefail
SCRIPT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

MODE="verify"
HUMAN=0
REASON=""
case "${1:-}" in
  --init) MODE="init"; shift ;;
  --regenerate) MODE="regenerate"; shift ;;
  --rebaseline) MODE="rebaseline"; shift ;;
  --audit) MODE="audit"; shift
            case "${1:-}" in
              --human) HUMAN=1; shift ;;
            esac ;;
esac
LOCK="${1:?gen-lock file required}"
shift

# Git operations target the repo that OWNS the lock (same rule as the
# committed pin checker — LOCK_ROOT falls back to the script root).
LOCK_ROOT="$(cd "$(dirname "$LOCK")/../.." 2>/dev/null && pwd || echo "$SCRIPT_ROOT")"
git -C "$LOCK_ROOT" rev-parse --git-dir >/dev/null 2>&1 || LOCK_ROOT="$SCRIPT_ROOT"
JOURNAL="$(dirname "$LOCK")/generated-lock-updates.jsonl"
COMMITTED_LOCK="$(dirname "$LOCK")/dataset-lock.json"

git() { # rev-parse echo trap: a caller MUST get rc==0 verification
  local r
  r="$(command git -C "$LOCK_ROOT" "$@")" || return 1
  printf '%s' "$r"
}

case "$MODE" in
verify|audit)
  [ -e "$LOCK" ] || { echo "BASELINE_MISSING — gen-lock absent: $LOCK" >&2; exit 1; }
  [ -e "$COMMITTED_LOCK" ] || { echo "COMMITTED_LOCK_MISSING — $COMMITTED_LOCK (GEN-04 needs the committed chain)" >&2; exit 1; }
  OUT_FILES=""
  while [ "$#" -gt 0 ]; do OUT_FILES="$OUT_FILES $1"; shift; done
  GENLOCK="$LOCK" JOURNAL="$JOURNAL" COMMITTED_LOCK="$COMMITTED_LOCK" \
  GENROOT="$LOCK_ROOT" OUT_FILES="$OUT_FILES" HUMAN="$HUMAN" MODE="$MODE" \
  SCRIPT_ROOT="$SCRIPT_ROOT" \
  python3 - <<'PY'
import datetime, json, os, subprocess, sys

GENROOT = os.environ["GENROOT"]
SCRIPT_ROOT = os.environ["SCRIPT_ROOT"]
genlock = json.load(open(os.environ["GENLOCK"]))
committed = json.load(open(os.environ["COMMITTED_LOCK"]))
com_by_fid = {v.get("fixture_id"): (p, v) for p, v in committed.get("fixtures", {}).items()}
com_by_path = committed.get("fixtures", {})

def git(*a):
    r = subprocess.run(["git", "-C", GENROOT, *a], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""

def git_ok(*a):
    # cat-file -e prints NOTHING on success — existence checks must read the
    # rc, never the stdout (empty-output trap).
    r = subprocess.run(["git", "-C", GENROOT, *a], capture_output=True)
    return r.returncode == 0

def sha_file(p):
    import hashlib
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def params_hash(parameters):
    import hashlib
    c = json.dumps(parameters, sort_keys=True, ensure_ascii=False,
                   separators=(",", ":"))
    return hashlib.sha256(c.encode("utf-8")).hexdigest()

def generation_id(fid, generator_id, gen_version, source_commit, phash, input_shas):
    # domain-separated + versioned canonical form (28th-cycle feedback):
    # generator_id/version are INSIDE the hash (several generators can share
    # one commit); input_count guards the list boundary; order is the
    # generator-DECLARED order, never sorted.
    import hashlib
    payload = "\0".join(["MOVIECUT_GENERATED_FIXTURE_V1", fid, generator_id,
                         gen_version, source_commit, phash,
                         str(len(input_shas))] + list(input_shas))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()

journal = []
jpath = os.environ["JOURNAL"]
if os.path.exists(jpath):
    for line in open(jpath):
        line = line.strip()
        if line:
            try:
                journal.append(json.loads(line))
            except Exception:
                journal.append({})

fixtures = genlock.get("fixtures", {})
violations = []
nondeterministic = False
same_output_diff_genid = 0
pending_states = {}

def viol(fid, inv, detail):
    violations.append({"fixture_id": fid, "invariant": inv, "detail": detail})

def determinism_state(fid, e):
    # three-state (28th-cycle feedback): UNVERIFIABLE = re-verification is
    # impossible AT ALL (missing evidence classes), distinct from "produced
    # something different" (NONDETERMINISTIC).
    out_rel = e.get("output_path", "")
    out_abs = out_rel if out_rel and os.path.isabs(out_rel) else (
        os.path.join(GENROOT, out_rel) if out_rel else "")
    if not out_rel or not os.path.isfile(out_abs):
        return "UNVERIFIABLE_GENERATION"
    sc = e.get("generator_source_commit", "")
    if sc and not git_ok("cat-file", "-e", f"{sc}^{{commit}}"):
        return "UNVERIFIABLE_GENERATION"
    return None  # verdict pending the invariant sweep below

out_files = [p for p in os.environ.get("OUT_FILES", "").split() if p]

# ---- per-fixture invariants (GEN-01..05) --------------------------------
for fid, e in sorted(fixtures.items()):
    state = None
    if e.get("provenance_class") != "GENERATED_FIXTURE":
        viol(fid, "provenance_class", "entry lacks GENERATED_FIXTURE class")
        continue
    phash = e.get("generation_parameters_hash", "")
    pairs = e.get("inputs", [])
    pair_ids = [p.get("fixture_id", "") for p in pairs]
    pair_shas = [p.get("sha256", "") for p in pairs]
    expect_gid = generation_id(fid, e.get("generator_id", ""),
                               e.get("generator_version", ""),
                               e.get("generator_source_commit", ""),
                               phash, pair_shas)
    # GEN-01
    if e.get("generation_id") != expect_gid:
        viol(fid, "GEN-01_generation_id_recompute",
             f"recorded {str(e.get('generation_id'))[:12]} != recomputed {expect_gid[:12]}")
    # GEN-02 (only when the caller named this output for byte checking —
    # otherwise the audit-level journal checks below still apply)
    out_rel = e.get("output_path", "")
    wanted = out_rel in out_files or not out_files
    if wanted:
        out_abs = out_rel if out_rel and os.path.isabs(out_rel) else (
            os.path.join(GENROOT, out_rel) if out_rel else "")
        if out_rel and os.path.isfile(out_abs):
            actual = sha_file(out_abs)
            if actual != e.get("output_sha256"):
                viol(fid, "GEN-02_output_bytes",
                     f"file {actual[:12]} != recorded {str(e.get('output_sha256'))[:12]}")
        else:
            viol(fid, "GEN-02_output_bytes", f"output file missing: {out_rel}")
    # GEN-03
    sc = e.get("generator_source_commit", "")
    if sc and not git_ok("cat-file", "-e", f"{sc}^{{commit}}"):
        viol(fid, "GEN-03_source_commit_exists", f"commit {sc} not found in Git")
    # GEN-04 — committed-lock chain first, then the pair's own sha witness
    for p in pairs:
        ifid, rec_sha = p.get("fixture_id", ""), p.get("sha256", "")
        hit = com_by_path.get(ifid) or (com_by_fid.get(ifid) or (None, None))[1]
        if hit is not None:
            if hit.get("sha256") != rec_sha:
                viol(fid, "GEN-04_input_provenance",
                     f"input {ifid} sha != committed lock sha ({rec_sha[:12]} vs {str(hit.get('sha256'))[:12]})")
        # not in the committed lock: the recorded sha is itself the witness
    # GEN-05 — ordered pair sequence: duplicate ids are the only alignment
    # hazard left, and the sequence order is the generator-DECLARED order
    if len(pair_ids) != len(set(pair_ids)):
        viol(fid, "GEN-05_input_order_canonical", "duplicate input fixture_id in ordered pair sequence")
    state = determinism_state(fid, e)
    if state:
        pending_states[fid] = state

# ---- GEN-06 (epoch-aware, lock + journal) -------------------------------
for fid, e in sorted(fixtures.items()):
    # mapping resets at the last REBASELINE of this fixture
    reb = [j for j in journal if j.get("fixture_id") == fid
           and j.get("event") == "REBASELINE"]
    cut = reb[-1]["provenance_epoch"] if reb and reb[-1].get("provenance_epoch") is not None else None
    gid = e.get("generation_id")
    outs = {e.get("output_sha256")}
    for j in journal:
        if j.get("fixture_id") != fid or j.get("generation_id") != gid:
            continue
        if cut is not None and (j.get("provenance_epoch") or 0) < cut:
            continue  # pre-rebaseline world — different provenance chain
        o = j.get("output_sha256") or j.get("observed_output_sha256")
        if o:
            outs.add(o)
    outs.discard(None)
    if len(outs) > 1:
        nondeterministic = True
        viol(fid, "GEN-06_one_output_per_generation_id",
             f"generation_id {str(gid)[:12]} maps to {len(outs)} outputs in the current chain — "
             f"NONDETERMINISTIC_GENERATION")

# asymmetric contract: different gen_id + same output is ALLOWED — counted,
# reported, never a violation
seen = {}
for fid, e in fixtures.items():
    seen.setdefault(e.get("output_sha256"), set()).add(e.get("generation_id"))
same_output_diff_genid = sum(1 for o, g in seen.items() if o and len(g) > 1)

gen06_fids = {v["fixture_id"] for v in violations
              if v["invariant"] == "GEN-06_one_output_per_generation_id"}
def overall_state(fid):
    if fid in gen06_fids:
        return "NONDETERMINISTIC_GENERATION"
    return pending_states.get(fid) or "DETERMINISTIC"
fixture_states = {fid: overall_state(fid) for fid in fixtures}

report = {
    "schema_version": 1,
    "ts": datetime.datetime.now().isoformat(timespec="seconds"),
    "kind": "generated_fixture_audit" if os.environ["MODE"] == "audit" else "generated_fixture_verify",
    "lock": os.path.relpath(os.path.abspath(os.environ["GENLOCK"]), GENROOT),
    "provenance_class": "GENERATED_FIXTURE",
    "fixtures": {fid: {
        "fixture_id": fid,
        "provenance_epoch": e.get("provenance_epoch", 1),
        "generation_id": e.get("generation_id"),
        "output_sha256": e.get("output_sha256"),
        "generator_id": e.get("generator_id"),
        "generator_version": e.get("generator_version"),
        "generator_source_commit": e.get("generator_source_commit"),
        "determinism_state": fixture_states.get(fid, "DETERMINISTIC"),
    } for fid, e in sorted(fixtures.items())},
    "totals": {
        "fixtures": len(fixtures),
        "journal_events": len(journal),
        "events": {ev: sum(1 for j in journal if j.get("event") == ev)
                   for ev in ("GENERATE", "REGENERATE", "REBASELINE", "REPAIR")},
    },
    "invariants": {"checked": 6, "violations": violations},
    "invariants_status": "PASS" if not violations else "VIOLATION",
    "nondeterministic_generation": nondeterministic,
    "same_output_diff_generation_id_allowed": same_output_diff_genid,
}
resets = [j for j in journal if j.get("event") == "REBASELINE"]
report["overall_continuity_status"] = "RESET_CONTINUOUS" if resets else "CONTINUOUS"
import hashlib as _hl
report["audit_id"] = _hl.sha256(json.dumps(
    {k: v for k, v in report.items() if k not in ("audit_id", "audit_sha256")},
    sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:16]
report["audit_sha256"] = _hl.sha256(json.dumps(
    {k: v for k, v in report.items() if k != "audit_sha256"},
    sort_keys=True, ensure_ascii=False).encode()).hexdigest()

if os.environ["MODE"] == "audit":
    outdir = os.path.join(SCRIPT_ROOT, ".build-check/history/audit")
    os.makedirs(outdir, exist_ok=True)
    out = os.path.join(outdir, f"audit-{report['audit_id']}.json")
    with open(out, "w") as f:
        json.dump(report, f, indent=2)
        f.write("\n")

if os.environ.get("HUMAN") == "1" and os.environ["MODE"] == "audit":
    print(f"generated-fixture audit — {report['ts']} (audit_id: {report['audit_id']}, record: {out})")
    for fid, fx in sorted(report["fixtures"].items()):
        print(f"  {fid}: epoch {fx['provenance_epoch']} / gen_id {str(fx['generation_id'])[:12]} / "
              f"output {str(fx['output_sha256'])[:12]} / gen {fx['generator_id']}@{fx['generator_version']}")
    t = report["totals"]
    print(f"  총계: fixtures {t['fixtures']}·events {t['events']}")
    print(f"  invariants(GEN-01~06): {report['invariants_status']}"
          + (f" — {len(report['invariants']['violations'])}건 위반" if violations else "")
          + (" · NONDETERMINISTIC_GENERATION" if nondeterministic else ""))
else:
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if os.environ["MODE"] == "audit":
        print(f"# record: {out}", file=sys.stderr)

if violations:
    raise SystemExit(1)
raise SystemExit(0)
PY
  ;;

init|regenerate)
  SPEC="${1:?spec.json required}"
  [ -f "$SPEC" ] || { echo "HASH_ERROR $SPEC (spec not found)" >&2; exit 1; }
  [ -e "$LOCK" ] || { echo "BASELINE_MISSING — gen-lock absent: $LOCK (bootstrap it first)" >&2; exit 1; }
  [ -e "$COMMITTED_LOCK" ] || { echo "COMMITTED_LOCK_MISSING — $COMMITTED_LOCK" >&2; exit 1; }
  GENLOCK="$LOCK" SPEC="$SPEC" JOURNAL="$JOURNAL" COMMITTED_LOCK="$COMMITTED_LOCK" \
  GENROOT="$LOCK_ROOT" MODE="$MODE" \
  python3 - <<'PY'
import datetime, hashlib, json, os, subprocess, sys

GENROOT = os.environ["GENROOT"]
spec = json.load(open(os.environ["SPEC"]))
genlock = json.load(open(os.environ["GENLOCK"]))
committed = json.load(open(os.environ["COMMITTED_LOCK"]))
com_by_fid = {v.get("fixture_id"): v for v in committed.get("fixtures", {}).values()}
com_by_path = committed.get("fixtures", {})

def git(*a):
    r = subprocess.run(["git", "-C", GENROOT, *a], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""

def git_ok(*a):
    # cat-file -e prints NOTHING on success — read the rc, not stdout.
    r = subprocess.run(["git", "-C", GENROOT, *a], capture_output=True)
    return r.returncode == 0

def sha_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

fid = spec.get("fixture_id")
if not fid:
    print("SPEC_INVALID — fixture_id required"); raise SystemExit(1)
for k in ("generator_id", "generator_version", "generation_parameters", "inputs", "output_file"):
    if k not in spec:
        print(f"SPEC_INVALID — {k} required"); raise SystemExit(1)

# Grammar contract (28th-cycle feedback): NUL can never appear in identity
# fields, so the NUL-separated canonical form has no separator ambiguity.
import re
GR_ID = re.compile(r"^[A-Za-z0-9._/-]+$")
GR_SHA = re.compile(r"^[0-9a-f]{64}$")
if not GR_ID.match(fid):
    print(f"GRAMMAR_VIOLATION — fixture_id must match [A-Za-z0-9._/-]+: {fid}"); raise SystemExit(1)
if not GR_ID.match(str(spec["generator_id"])):
    print("GRAMMAR_VIOLATION — generator_id must match [A-Za-z0-9._/-]+"); raise SystemExit(1)
gen_version = str(spec["generator_version"])
if not gen_version or not gen_version.isprintable() or "\0" in gen_version:
    print("GRAMMAR_VIOLATION — generator_version must be printable ASCII without NUL"); raise SystemExit(1)
for p in spec["inputs"]:
    i_fid = p.get("fixture_id") or p.get("path") or ""
    if not GR_ID.match(i_fid):
        print(f"GRAMMAR_VIOLATION — input fixture_id must match [A-Za-z0-9._/-]+: {i_fid}"); raise SystemExit(1)
    if p.get("sha256") and not GR_SHA.match(p["sha256"]):
        print(f"GRAMMAR_VIOLATION — input sha256 must be lowercase hex[64]"); raise SystemExit(1)

out_rel = spec["output_file"]
out_abs = out_rel if os.path.isabs(out_rel) else os.path.join(GENROOT, out_rel)
if not os.path.isfile(out_abs):
    print(f"OUTPUT_MISSING — {out_rel}: run the generator first, registration records actual bytes only"); raise SystemExit(1)

# GEN-04 at registration: inputs must verify NOW (committed chain or bytes).
# Locked as an ORDERED PAIR SEQUENCE — no parallel arrays to keep aligned;
# order is the generator-DECLARED order and is never sorted.
input_pairs = []
for inp in spec["inputs"]:
    i_fid = inp.get("fixture_id") or inp.get("path") or ""
    i_path = inp.get("path", "")
    i_abs = i_path if os.path.isabs(i_path) else os.path.join(GENROOT, i_path)
    if not i_path or not os.path.isfile(i_abs):
        print(f"INPUT_MISSING — {i_path}"); raise SystemExit(1)
    actual = sha_file(i_abs)
    hit = com_by_path.get(i_path) or com_by_fid.get(i_fid)
    if hit is not None:
        if hit.get("sha256") != actual:
            print(f"INPUT_CHAIN_BROKEN — {i_path} bytes do not match the committed lock sha"); raise SystemExit(1)
    claimed = inp.get("sha256")
    if claimed and claimed != actual:
        print(f"INPUT_SHA_MISMATCH — {i_path} spec claims {claimed[:12]}, bytes are {actual[:12]}"); raise SystemExit(1)
    input_pairs.append({"fixture_id": i_fid, "path": i_path, "sha256": actual})

phash = hashlib.sha256(json.dumps(spec["generation_parameters"], sort_keys=True,
                                  ensure_ascii=False, separators=(",", ":"))
                       .encode("utf-8")).hexdigest()
source_commit = spec.get("generator_source_commit", "") or git("rev-parse", "--short", "HEAD")
if not source_commit:
    print("SOURCE_COMMIT_UNAVAILABLE"); raise SystemExit(1)
if source_commit != source_commit.lower():
    print(f"GRAMMAR_VIOLATION — generator_source_commit must be canonical lowercase: {source_commit}"); raise SystemExit(1)
if not git_ok("cat-file", "-e", f"{source_commit}^{{commit}}"):
    print(f"GEN-03_SOURCE_COMMIT_MISSING — {source_commit} not in Git"); raise SystemExit(1)
# Domain-separated, versioned canonical form — generator_id/version are
# INSIDE the hash (several generators can share one commit); input_count
# guards the list boundary; order is the generator-DECLARED order.
gid = hashlib.sha256("\0".join(
    ["MOVIECUT_GENERATED_FIXTURE_V1", fid, str(spec["generator_id"]), gen_version,
     source_commit, phash, str(len(input_pairs))]
    + [p["sha256"] for p in input_pairs]).encode("utf-8")).hexdigest()
out_sha = sha_file(out_abs)
now = datetime.datetime.now().isoformat(timespec="seconds")
fixtures = genlock.setdefault("fixtures", {})

def append_event(event, extra):
    line = {"ts": now, "kind": "generated_fixture_event", "event": event,
            "fixture_id": fid, "generation_id": gid, "output_sha256": out_sha,
            "provenance_epoch": extra.get("provenance_epoch", 1)}
    line.update(extra)
    with open(os.environ["JOURNAL"], "a") as f:
        f.write(json.dumps(line, ensure_ascii=False) + "\n")

entry = fixtures.get(fid)
if os.environ["MODE"] == "init":
    if entry is not None:
        print(f"GENERATE_REFUSED — {fid} already registered (use --regenerate)"); raise SystemExit(1)
    entry = {
        "fixture_id": fid,
        "provenance_class": "GENERATED_FIXTURE",
        "generator_id": spec["generator_id"],
        "generator_version": gen_version,
        "generator_source_commit": source_commit,
        "generation_parameters_hash": phash,
        "inputs": input_pairs,
        "output_path": out_rel,
        "output_sha256": out_sha,
        "generation_id": gid,
        "provenance_epoch": 1,
        "generated_at": now,
        "update_history": [],
    }
    entry["update_history"].append({"ts": now, "event": "GENERATE",
        "generation_id": gid, "output_sha256": out_sha,
        "provenance_epoch": 1, "update_seq": 1})
    fixtures[fid] = entry
    append_event("GENERATE", {"update_seq": 1})
    genlock["updated_at"] = now
    with open(os.environ["GENLOCK"], "w") as f:
        json.dump(genlock, f, indent=2, ensure_ascii=False); f.write("\n")
    print(f"GENERATED registered: {fid} (generation_id {gid[:12]}, output {out_sha[:12]}, epoch 1)")
else:
    if entry is None:
        print(f"REGENERATE_REFUSED — {fid} not registered (use --init)"); raise SystemExit(1)
    prev_epoch = int(entry.get("provenance_epoch", 1))
    seq = len(entry.get("update_history", [])) + 1
    if entry.get("generation_id") != gid:
        # generation CONTRACT changed (generator commit/params/inputs) —
        # that is a new derivation identity, never a silent overwrite.
        print(f"CONTRACT_CHANGED — generation_id differs "
              f"(recorded {str(entry.get('generation_id'))[:12]} vs spec {gid[:12]}). "
              f"Register under --init as a new chain or --rebaseline as an operator reset."); raise SystemExit(1)
    # REGENERATE is a VERIFICATION event, not a mutation (28th-cycle
    # feedback): the immutable journal gets the observation, the lock is
    # NEVER rewritten here — a verifier that edits the lock is a mutator.
    if entry.get("output_sha256") == out_sha:
        append_event("REGENERATE", {"update_seq": seq,
            "result": "DETERMINISTIC_CONFIRMATION", "provenance_epoch": prev_epoch})
        print(f"REGENERATE confirmed: {fid} — same contract, identical output ({out_sha[:12]}); lock untouched")
    else:
        # same generation_id, different bytes = NONDETERMINISTIC_GENERATION:
        # record the observation, fail closed — lock untouched, and the fix
        # is a NEW generation identity after the cause is resolved, never a
        # REBASELINE over the divergence.
        append_event("REGENERATE", {"update_seq": seq,
            "result": "NONDETERMINISTIC_GENERATION", "provenance_epoch": prev_epoch,
            "observed_output_sha256": out_sha})
        print(f"NONDETERMINISTIC_GENERATION — {fid}: generation_id {gid[:12]} produced "
              f"{out_sha[:12]} (lock has {str(entry.get('output_sha256'))[:12]}). "
              f"Observation recorded; lock untouched — resolve the cause and mint a "
              f"new generation identity (REBASELINE is not an escape hatch)."); raise SystemExit(2)
PY
  ;;

rebaseline)
  FID=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --reason) REASON="${2:-}"; shift 2 ;;
      *) FID="$1"; shift ;;
    esac
  done
  [ -n "$FID" ] || { echo "REBASELINE REFUSED — fixture_id required" >&2; exit 1; }
  [ -n "$REASON" ] || { echo "REBASELINE REFUSED — --reason is required (operator acknowledgment)" >&2; exit 1; }
  [ -e "$LOCK" ] || { echo "BASELINE_MISSING — gen-lock absent: $LOCK" >&2; exit 1; }
  GENLOCK="$LOCK" FID="$FID" JOURNAL="$JOURNAL" GENROOT="$LOCK_ROOT" REASON="$REASON" \
  python3 - <<'PY'
import datetime, hashlib, json, os

genlock = json.load(open(os.environ["GENLOCK"]))
fid = os.environ["FID"]
entry = genlock.get("fixtures", {}).get(fid)
if entry is None:
    print(f"REBASELINE REFUSED — {fid} is not in the gen-lock"); raise SystemExit(1)
def sha_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()
out_abs = entry.get("output_path", "")
out_abs = out_abs if os.path.isabs(out_abs) else os.path.join(os.environ["GENROOT"], out_abs)
if not os.path.isfile(out_abs):
    print(f"REBASELINE REFUSED — output missing: {entry.get('output_path')}"); raise SystemExit(1)
new_sha = sha_file(out_abs)
now = datetime.datetime.now().isoformat(timespec="seconds")
prev_epoch = int(entry.get("provenance_epoch", 1))
epoch = prev_epoch + 1
seq = len(entry.get("update_history", [])) + 1
line = {"ts": now, "kind": "generated_fixture_event", "event": "REBASELINE",
        "fixture_id": fid, "generation_id": entry.get("generation_id"),
        "output_sha256": new_sha, "provenance_epoch": epoch,
        "previous_epoch": prev_epoch,
        "reason": os.environ["REASON"],
        "operator_acknowledgment": True,
        "note": "new provenance chain starts here — prior chain kept via this event"}
with open(os.environ["JOURNAL"], "a") as f:
    f.write(json.dumps(line, ensure_ascii=False) + "\n")
entry["output_sha256"] = new_sha
entry["provenance_epoch"] = epoch
entry["generated_at"] = now
entry.setdefault("update_history", []).append({"ts": now, "event": "REBASELINE",
    "generation_id": entry.get("generation_id"), "output_sha256": new_sha,
    "provenance_epoch": epoch, "previous_epoch": prev_epoch,
    "update_seq": seq, "reason": os.environ["REASON"]})
genlock["updated_at"] = now
with open(os.environ["GENLOCK"], "w") as f:
    json.dump(genlock, f, indent=2, ensure_ascii=False); f.write("\n")
print(f"rebaselined generated fixture: {fid} (epoch {epoch}, REBASELINE event appended)")
PY
  echo "NOTE: commit the gen-lock and journal together (same review unit)." >&2
  exit 0
  ;;
esac
