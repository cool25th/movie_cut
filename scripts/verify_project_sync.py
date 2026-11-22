#!/usr/bin/env python3
"""Verify MovieCut.xcodeproj/project.pbxproj stays in sync with disk & project.yml.

Checks:
1. Every `.swift` file under each Xcode target source root (`App/MovieCutMac`,
   `App/MovieCutiOS`, `App/MovieCutMacTests`, `App/MovieCutiOSTests`,
   `App/MovieCutMacUITests`, `Tests/MovieCutCoreTests`) is referenced in
   `MovieCut.xcodeproj/project.pbxproj` AND included in its target's
   `PBXSourcesBuildPhase`.
2. Every `.swift` `PBXFileReference` in `project.pbxproj` resolves to an
   existing file on disk (no ghost references after file deletion/renaming).
3. Key settings in `project.yml` (`MOVIECUT_MAC_BUNDLE_ID`,
   `MOVIECUT_IOS_BUNDLE_ID`, `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`)
   match `project.pbxproj`.

Uses macOS `plutil -convert json` so `.pbxproj` parsing is exact.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PBXPROJ = REPO_ROOT / "MovieCut.xcodeproj" / "project.pbxproj"
PROJECT_YML = REPO_ROOT / "project.yml"

TARGET_SOURCE_ROOTS: dict[str, Path] = {
    "MovieCutMac": Path("App/MovieCutMac"),
    "MovieCutiOS": Path("App/MovieCutiOS"),
    "MovieCutMacTests": Path("App/MovieCutMacTests"),
    "MovieCutiOSTests": Path("App/MovieCutiOSTests"),
    "MovieCutMacUITests": Path("App/MovieCutMacUITests"),
    "MovieCutCoreTests": Path("Tests/MovieCutCoreTests"),
}

SYNCED_SETTINGS = (
    "MOVIECUT_MAC_BUNDLE_ID",
    "MOVIECUT_IOS_BUNDLE_ID",
    "MARKETING_VERSION",
    "CURRENT_PROJECT_VERSION",
)


def load_pbxproj() -> dict:
    proc = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", str(PBXPROJ)],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(proc.stdout)


def resolve_file_ref_paths(pbx: dict) -> dict[str, Path]:
    """Walk PBXGroup hierarchy from mainGroup to map fileRef ID -> repo-relative Path."""
    objects = pbx["objects"]
    root_obj = objects[pbx["rootObject"]]
    main_group_id = root_obj["mainGroup"]

    resolved: dict[str, Path] = {}

    def walk(node_id: str, prefix: Path) -> None:
        node = objects.get(node_id)
        if not node:
            return
        isa = node.get("isa")
        node_path = node.get("path")
        source_tree = node.get("sourceTree", "<group>")

        if source_tree == "SOURCE_ROOT":
            current = Path(node_path) if node_path else Path(".")
        elif source_tree == "<group>":
            current = (prefix / node_path) if node_path else prefix
        else:
            # BUILT_PRODUCTS_DIR, SDKROOT, etc. — not repo source files.
            return

        if isa == "PBXFileReference":
            resolved[node_id] = Path(os.path.normpath(str(current)))
        elif isa in ("PBXGroup", "PBXVariantGroup"):
            for child_id in node.get("children", []):
                walk(child_id, current)

    walk(main_group_id, Path("."))
    return resolved


def parse_project_yml_base_settings() -> dict[str, str]:
    """Extract base settings from project.yml without requiring PyYAML."""
    text = PROJECT_YML.read_text(encoding="utf-8")
    values: dict[str, str] = {}
    for key in SYNCED_SETTINGS:
        m = re.search(rf"^\s+{re.escape(key)}:\s*\"?([^\s\"#]+)\"?\s*$", text, re.MULTILINE)
        if m:
            values[key] = m.group(1)
    return values


def main() -> int:
    if not PBXPROJ.exists():
        print(f"ERROR: missing {PBXPROJ}", file=sys.stderr)
        return 1

    pbx = load_pbxproj()
    objects = pbx["objects"]
    file_ref_paths = resolve_file_ref_paths(pbx)

    errors: list[str] = []

    # 1. Verify no ghost `.swift` file references in pbxproj.
    swift_refs_on_disk: set[Path] = set()
    for ref_id, rel_path in sorted(file_ref_paths.items(), key=lambda kv: str(kv[1])):
        obj = objects[ref_id]
        if obj.get("lastKnownFileType") != "sourcecode.swift" and rel_path.suffix != ".swift":
            continue
        full_path = REPO_ROOT / rel_path
        if not full_path.exists():
            errors.append(f"GHOST pbxproj fileRef ({ref_id}): {rel_path} does not exist on disk")
        else:
            swift_refs_on_disk.add(rel_path)

    # 2. Build target -> set of compiled `.swift` paths from PBXSourcesBuildPhase.
    target_compiled_swift: dict[str, set[Path]] = {}
    for obj in objects.values():
        if obj.get("isa") != "PBXNativeTarget":
            continue
        name = obj.get("name", "")
        compiled: set[Path] = set()
        for phase_id in obj.get("buildPhases", []):
            phase = objects.get(phase_id, {})
            if phase.get("isa") != "PBXSourcesBuildPhase":
                continue
            for build_file_id in phase.get("files", []):
                build_file = objects.get(build_file_id, {})
                ref_id = build_file.get("fileRef")
                if ref_id and ref_id in file_ref_paths:
                    rel_path = file_ref_paths[ref_id]
                    if rel_path.suffix == ".swift":
                        compiled.add(rel_path)
        target_compiled_swift[name] = compiled

    # 3. Verify every `.swift` file on disk under each target root is in pbxproj & compiled.
    for target_name, root_rel in TARGET_SOURCE_ROOTS.items():
        root_abs = REPO_ROOT / root_rel
        if not root_abs.exists():
            errors.append(f"MISSING target source directory: {root_rel}")
            continue
        if target_name not in target_compiled_swift:
            errors.append(f"MISSING PBXNativeTarget in pbxproj: {target_name}")
            continue

        disk_swift = {
            p.relative_to(REPO_ROOT)
            for p in root_abs.rglob("*.swift")
            if p.is_file()
        }
        compiled = target_compiled_swift[target_name]

        missing_from_target = sorted(disk_swift - compiled)
        for rel in missing_from_target:
            if rel in swift_refs_on_disk:
                errors.append(
                    f"NOT COMPILED in target {target_name}: {rel} (referenced in pbxproj but missing from PBXSourcesBuildPhase)"
                )
            else:
                errors.append(
                    f"MISSING from pbxproj ({target_name}): {rel}"
                )

    # 4. Verify key project.yml settings match project-level XCBuildConfiguration.
    if PROJECT_YML.exists():
        yml_settings = parse_project_yml_base_settings()
        root_obj = objects[pbx["rootObject"]]
        cfg_list = objects.get(root_obj.get("buildConfigurationList", ""), {})
        for cfg_id in cfg_list.get("buildConfigurations", []):
            cfg = objects.get(cfg_id, {})
            cfg_name = cfg.get("name", cfg_id)
            build_settings = cfg.get("buildSettings", {})
            for key, expected in yml_settings.items():
                actual = str(build_settings.get(key, ""))
                if actual != expected:
                    errors.append(
                        f"SETTING DRIFT ({cfg_name}): {key} is {actual!r} in pbxproj vs {expected!r} in project.yml"
                    )

    if errors:
        print(f"verify_project_sync: FAIL ({len(errors)} issue(s))", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    total_targets = len(TARGET_SOURCE_ROOTS)
    total_compiled = sum(len(target_compiled_swift.get(t, ())) for t in TARGET_SOURCE_ROOTS)
    print(
        f"verify_project_sync: PASS ({total_compiled} Swift sources across {total_targets} Xcode targets + project.yml settings in sync)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
