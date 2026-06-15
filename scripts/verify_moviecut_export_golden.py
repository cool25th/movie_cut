#!/usr/bin/env python3
"""Validate MovieCut single-fixture export golden evidence.

This verifier intentionally accepts only the narrow 2026-06-12 single-fixture
preflight evidence shape. It prevents a generated artifact from being promoted
as ExportEngine E2E, full-suite, device, or release-ready evidence unless those
claims are backed by separate artifacts.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

REQUIRED_TOP_LEVEL_FIELDS = {
    "fixture_id",
    "export_artifact_path",
    "hash_or_pixel_checksum",
    "expected_spec",
    "failure_bucket",
}
REQUIRED_EXPECTED_SPEC_FIELDS = {
    "runner",
    "resolution",
    "duration_seconds",
    "fps",
    "frames",
    "video_track_count",
    "claim_boundary",
}
FORBIDDEN_CLAIMS = {
    "MovieCut ExportEngine end-to-end verified",
    "full-suite",
    "iOS device",
    "release-ready",
    "all export combinations",
}
ACCEPTED_EVIDENCE_LABEL = "Single fixture preflight artifact accepted"
OPEN_RISK_LABEL = "product ExportEngine path artifact missing"
NEXT_OWNER_LABEL = "ExportEngine artifact owner"
EXPECTED_SCOPE = "actual_export_single_fixture_preflight"
RESOLUTION_PATTERN = re.compile(r"^[1-9][0-9]*x[1-9][0-9]*$")
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
FRAME_PATTERN = re.compile(r"^BGRA\(([0-9]{1,3}),([0-9]{1,3}),([0-9]{1,3}),([0-9]{1,3})\)$")
EXPECTED_FIXTURE_PREFIX = "actual_export_golden_single_fixture/"
EXPECTED_ARTIFACT_SUFFIX = ".mp4"
EXPECTED_MANIFEST_SUFFIX = ".json"
EXPECTED_ARTIFACT_BASENAME_PREFIX = "moviecut-export-golden-2026-06-12-"
EXPECTED_EVIDENCE_DIRECTORY_NAME = "qa-evidence"
EXPECTED_EVIDENCE_DATE_UTC = "2026-06-12"
FIXTURE_ID_PARTS = 3
FIXTURE_OWNER_PART_INDEX = 1


def expected_manifest_stem(manifest_path: Path) -> str:
    return manifest_path.expanduser().resolve(strict=False).stem


def manifest_owner(manifest_path: Path) -> str:
    name = manifest_path.expanduser().resolve(strict=False).name
    if not name.startswith(EXPECTED_ARTIFACT_BASENAME_PREFIX):
        return ""
    remainder = name[len(EXPECTED_ARTIFACT_BASENAME_PREFIX) :]
    if "." in remainder:
        remainder = remainder.rsplit(".", 1)[0]
    return remainder


def fixture_owner(fixture_id: str) -> str:
    parts = fixture_id.split("/")
    if len(parts) != FIXTURE_ID_PARTS:
        return ""
    return parts[FIXTURE_OWNER_PART_INDEX]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_mp4_file_type_box(path: Path) -> bool:
    with path.open("rb") as file:
        header = file.read(12)
    return len(header) >= 12 and header[4:8] == b"ftyp"


def missing_required_mp4_atoms(path: Path) -> list[str]:
    """Return required atom markers missing from the small preflight MP4.

    This intentionally stays lightweight: the verifier is not a full MP4 parser,
    but it should reject synthetic byte blobs that only spoof the `ftyp` header
    while lacking the expected video payload/index atoms for this evidence type.
    """
    data = path.read_bytes()
    required_atoms = (b"ftyp", b"mdat", b"moov", b"avc1")
    return [atom.decode("ascii") for atom in required_atoms if data.find(atom) < 0]


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def file_mtime_date_failure(path: Path, label: str) -> str | None:
    try:
        modified_date_utc = datetime.fromtimestamp(
            path.expanduser().resolve(strict=False).stat().st_mtime,
            timezone.utc,
        ).date().isoformat()
    except OSError as error:
        return f"{label} mtime could not be read: {error}"
    if modified_date_utc != EXPECTED_EVIDENCE_DATE_UTC:
        return (
            f"{label} mtime UTC date must be {EXPECTED_EVIDENCE_DATE_UTC} "
            f"to prevent stale renamed evidence reuse, got {modified_date_utc}"
        )
    return None


def load_manifest(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as file:
        data = json.load(file)
    if not isinstance(data, dict):
        raise ValueError("manifest root must be a JSON object")
    return data


def valid_bgra_frames(frames: Any) -> bool:
    if not isinstance(frames, list) or not frames:
        return False
    for frame in frames:
        match = FRAME_PATTERN.match(str(frame))
        if not match:
            return False
        channels = [int(value) for value in match.groups()]
        if any(channel < 0 or channel > 255 for channel in channels):
            return False
    return True


def verify(manifest_path: Path) -> tuple[bool, dict[str, Any]]:
    failures: list[str] = []
    data = load_manifest(manifest_path)

    missing = sorted(REQUIRED_TOP_LEVEL_FIELDS - data.keys())
    require(not missing, f"missing top-level fields: {missing}", failures)

    fixture_id = str(data.get("fixture_id") or "")
    require(
        fixture_id.startswith(EXPECTED_FIXTURE_PREFIX),
        f"fixture_id must start with {EXPECTED_FIXTURE_PREFIX}",
        failures,
    )
    owner_from_manifest = manifest_owner(manifest_path)
    owner_from_fixture = fixture_owner(fixture_id)
    require(bool(owner_from_fixture), "fixture_id must have three slash-separated parts including owner", failures)
    require(
        bool(owner_from_manifest) and owner_from_fixture == owner_from_manifest,
        "fixture_id owner must match evidence manifest owner to prevent cross-owner claim reuse",
        failures,
    )

    expected_spec = data.get("expected_spec")
    require(isinstance(expected_spec, dict), "expected_spec must be an object", failures)
    if isinstance(expected_spec, dict):
        spec_missing = sorted(REQUIRED_EXPECTED_SPEC_FIELDS - expected_spec.keys())
        require(not spec_missing, f"missing expected_spec fields: {spec_missing}", failures)
        runner = str(expected_spec.get("runner", ""))
        claim_boundary = str(expected_spec.get("claim_boundary", ""))
        resolution = expected_spec.get("resolution")
        duration_seconds = expected_spec.get("duration_seconds")
        fps = expected_spec.get("fps")
        frames = expected_spec.get("frames")
        video_track_count = expected_spec.get("video_track_count")
        require(
            "single fixture preflight" in runner.lower(),
            "expected_spec.runner must explicitly say single fixture preflight",
            failures,
        )
        require(
            isinstance(resolution, str) and bool(RESOLUTION_PATTERN.match(resolution)),
            "expected_spec.resolution must be formatted as <positive-width>x<positive-height>",
            failures,
        )
        require(
            isinstance(duration_seconds, (int, float)) and duration_seconds > 0,
            "expected_spec.duration_seconds must be a positive number",
            failures,
        )
        require(isinstance(fps, int) and fps > 0, "expected_spec.fps must be a positive integer", failures)
        require(isinstance(frames, list) and bool(frames), "expected_spec.frames must be a non-empty list", failures)
        require(valid_bgra_frames(frames), "expected_spec.frames must be BGRA(r,g,b,a) values in 0...255", failures)
        if isinstance(duration_seconds, (int, float)) and isinstance(fps, int) and fps > 0 and isinstance(frames, list):
            expected_frame_count = max(1, round(duration_seconds * fps))
            require(
                len(frames) == expected_frame_count,
                f"expected_spec.frames count must equal round(duration_seconds * fps)={expected_frame_count}",
                failures,
            )
        require(
            isinstance(video_track_count, int) and video_track_count >= 1,
            "expected_spec.video_track_count must be >= 1",
            failures,
        )
        require(
            "not MovieCut full export engine" in claim_boundary
            and "full-suite" in claim_boundary
            and "iOS device" in claim_boundary
            and "release-ready" in claim_boundary,
            "expected_spec.claim_boundary must block ExportEngine/full-suite/device/release-ready claims",
            failures,
        )

    require(data.get("failure_bucket") is None, "failure_bucket must be null for verified wording", failures)
    require(data.get("qa_scope") == EXPECTED_SCOPE, f"qa_scope must be {EXPECTED_SCOPE}", failures)

    cannot_claim = data.get("cannot_claim")
    require(isinstance(cannot_claim, list), "cannot_claim must be a list", failures)
    if isinstance(cannot_claim, list):
        missing_forbidden = sorted(FORBIDDEN_CLAIMS - set(map(str, cannot_claim)))
        require(not missing_forbidden, f"cannot_claim missing forbidden claims: {missing_forbidden}", failures)

    artifact_value = data.get("export_artifact_path")
    artifact_path = Path(str(artifact_value)).expanduser() if artifact_value else Path()
    manifest_resolved = manifest_path.expanduser().resolve(strict=False)
    manifest_dir = manifest_resolved.parent
    require(
        manifest_resolved.parent.name == EXPECTED_EVIDENCE_DIRECTORY_NAME,
        f"manifest must be stored in a {EXPECTED_EVIDENCE_DIRECTORY_NAME} directory",
        failures,
    )
    require(
        manifest_resolved.name.startswith(EXPECTED_ARTIFACT_BASENAME_PREFIX),
        f"manifest basename must start with {EXPECTED_ARTIFACT_BASENAME_PREFIX}",
        failures,
    )
    require(
        manifest_resolved.suffix.lower() == EXPECTED_MANIFEST_SUFFIX,
        f"manifest suffix must be {EXPECTED_MANIFEST_SUFFIX} to prevent extensionless copied evidence reuse",
        failures,
    )
    manifest_mtime_failure = file_mtime_date_failure(manifest_path, "manifest")
    require(manifest_mtime_failure is None, manifest_mtime_failure or "", failures)
    require(bool(artifact_value), "export_artifact_path is required", failures)
    require(artifact_path.suffix.lower() == EXPECTED_ARTIFACT_SUFFIX, "export_artifact_path must point to an .mp4 artifact", failures)
    require(
        artifact_path.name.startswith(EXPECTED_ARTIFACT_BASENAME_PREFIX),
        f"export_artifact_path basename must start with {EXPECTED_ARTIFACT_BASENAME_PREFIX}",
        failures,
    )
    require(
        artifact_path.stem == expected_manifest_stem(manifest_path),
        "export artifact stem must match manifest stem to prevent cross-artifact claim reuse",
        failures,
    )
    if artifact_value:
        try:
            artifact_resolved = artifact_path.resolve(strict=False)
            require(
                artifact_resolved.parent == manifest_dir,
                "export artifact must be stored next to the manifest in the qa-evidence directory",
                failures,
            )
        except OSError as error:
            failures.append(f"failed to resolve export_artifact_path: {error}")
    require(artifact_path.exists(), f"export artifact does not exist: {artifact_path}", failures)
    require(artifact_path.is_file(), f"export artifact is not a file: {artifact_path}", failures)
    if artifact_path.exists():
        artifact_mtime_failure = file_mtime_date_failure(artifact_path, "export artifact")
        require(artifact_mtime_failure is None, artifact_mtime_failure or "", failures)

    hash_block = data.get("hash_or_pixel_checksum")
    require(isinstance(hash_block, dict), "hash_or_pixel_checksum must be an object", failures)
    actual_sha = None
    actual_size = None
    if artifact_path.exists() and artifact_path.is_file():
        require(is_mp4_file_type_box(artifact_path), "export artifact must contain an MP4 ftyp box header", failures)
        missing_atoms = missing_required_mp4_atoms(artifact_path)
        require(
            not missing_atoms,
            f"export artifact missing required MP4 atom markers for preflight video evidence: {missing_atoms}",
            failures,
        )
        actual_sha = sha256(artifact_path)
        actual_size = artifact_path.stat().st_size
    if isinstance(hash_block, dict):
        manifest_sha = hash_block.get("sha256")
        manifest_size = hash_block.get("file_size_bytes")
        require(
            isinstance(manifest_sha, str) and bool(SHA256_PATTERN.match(manifest_sha)),
            "hash_or_pixel_checksum.sha256 must be a lowercase 64-character hex digest",
            failures,
        )
        require(
            isinstance(manifest_size, int) and manifest_size > 0,
            "hash_or_pixel_checksum.file_size_bytes must be a positive integer",
            failures,
        )
        require(manifest_sha == actual_sha, "sha256 does not match artifact bytes", failures)
        require(manifest_size == actual_size, "file_size_bytes does not match artifact bytes", failures)

    can_claim = str(data.get("can_claim") or "")
    require(
        "actual_export_golden_single_fixture" in can_claim and "hash" in can_claim.lower(),
        "can_claim must stay scoped to actual_export_golden_single_fixture and hash/read-back evidence",
        failures,
    )
    forbidden_terms_in_can_claim = sorted(
        claim for claim in FORBIDDEN_CLAIMS if claim.lower() in can_claim.lower()
    )
    require(
        not forbidden_terms_in_can_claim,
        f"can_claim must not include forbidden blocked claims: {forbidden_terms_in_can_claim}",
        failures,
    )

    claim_boundary = {
        "accepted_evidence": ACCEPTED_EVIDENCE_LABEL if not failures else None,
        "blocked_claims": sorted(FORBIDDEN_CLAIMS),
        "can_count_as_export_engine_e2e": False,
    }
    retro_row = {
        "project": "MovieCut",
        "accepted_evidence": claim_boundary["accepted_evidence"],
        "blocked_claim": ", ".join(claim_boundary["blocked_claims"]),
        "open_risk": OPEN_RISK_LABEL,
        "next_owner": NEXT_OWNER_LABEL,
    }

    summary = {
        "manifest": str(manifest_path),
        "fixture_id": data.get("fixture_id"),
        "manifest_owner": manifest_owner(manifest_path),
        "fixture_owner": fixture_owner(str(data.get("fixture_id") or "")),
        "artifact": str(artifact_path),
        "artifact_stem_matches_manifest": artifact_path.stem == expected_manifest_stem(manifest_path),
        "sha256": actual_sha,
        "file_size_bytes": actual_size,
        "qa_scope": data.get("qa_scope"),
        "failure_bucket": data.get("failure_bucket"),
        "expected_evidence_date_utc": EXPECTED_EVIDENCE_DATE_UTC,
        "file_provenance_guard_count": 2,
        "forbidden_claim_guard_count": len(FORBIDDEN_CLAIMS),
        "claim_boundary": claim_boundary,
        "retro_row": retro_row,
        "failures": failures,
    }
    return not failures, summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path, help="Path to MovieCut export golden evidence JSON")
    args = parser.parse_args()

    ok, summary = verify(args.manifest)
    print(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
