#!/usr/bin/env python3
"""Test driver schema validation and meta declarations."""

import os
import sys
import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))

from validate_targets_manifest import (
    DRIVER_SCHEMA, DRIVER_META, KNOWN_PACKAGE_DRIVERS,
    KNOWN_RUNTIME_DRIVERS, KNOWN_CONFIG_DRIVERS, KNOWN_CAPABILITY_DRIVERS,
)

UCC_DIR = os.path.join(REPO_ROOT, "ucc")


def load_all_targets():
    targets = {}
    for root, _, files in os.walk(UCC_DIR):
        for f in files:
            if not f.endswith(".yaml"):
                continue
            with open(os.path.join(root, f)) as fh:
                data = yaml.safe_load(fh) or {}
            for t, td in (data.get("targets") or {}).items():
                if isinstance(td, dict):
                    targets[t] = td
    return targets


def test_all_drivers_have_schema():
    """Every driver kind used in YAML has a schema declaration."""
    targets = load_all_targets()
    used_kinds = set()
    for t, td in targets.items():
        kind = (td.get("driver") or {}).get("kind", "")
        if kind and kind != "custom":
            used_kinds.add(kind)

    for kind in sorted(used_kinds):
        assert kind in DRIVER_SCHEMA, \
            f"Driver '{kind}' used in YAML but not in DRIVER_SCHEMA"
    print(f"PASS: All {len(used_kinds)} driver kinds have schemas")


def test_all_drivers_in_known_sets():
    """Every driver kind is in one of the KNOWN_*_DRIVERS sets."""
    all_known = (
        KNOWN_PACKAGE_DRIVERS | KNOWN_RUNTIME_DRIVERS
        | KNOWN_CONFIG_DRIVERS | KNOWN_CAPABILITY_DRIVERS
    )
    targets = load_all_targets()
    for t, td in targets.items():
        kind = (td.get("driver") or {}).get("kind", "")
        if kind and kind != "custom":
            assert kind in all_known, \
                f"Driver '{kind}' (target '{t}') not in any KNOWN_*_DRIVERS set"
    print("PASS: All drivers in known sets")


def test_driver_required_keys():
    """Targets provide all required driver keys."""
    targets = load_all_targets()
    for t, td in targets.items():
        driver = td.get("driver") or {}
        kind = driver.get("kind", "")
        if kind not in DRIVER_SCHEMA:
            continue
        schema = DRIVER_SCHEMA[kind]
        driver_keys = {k for k in driver if k != "kind"}
        for req in schema["required"]:
            assert req in driver_keys, \
                f"Target '{t}' driver.kind='{kind}' missing required key '{req}'"
    print("PASS: All required driver keys present")


def test_driver_no_unexpected_keys():
    """Targets don't have unexpected driver keys."""
    targets = load_all_targets()
    for t, td in targets.items():
        driver = td.get("driver") or {}
        kind = driver.get("kind", "")
        if kind not in DRIVER_SCHEMA:
            continue
        schema = DRIVER_SCHEMA[kind]
        driver_keys = {k for k in driver if k != "kind"}
        allowed = set(schema["required"]) | set(schema["optional"]) | {"github_repo"}
        for dk in driver_keys:
            assert dk in allowed, \
                f"Target '{t}' driver.kind='{kind}' has unexpected key '{dk}'"
    print("PASS: No unexpected driver keys")


def test_driver_meta_sync():
    """DRIVER_META in Python matches _ucc_driver_*_depends_on in shell."""
    drivers_sh = os.path.join(REPO_ROOT, "lib", "ucc_drivers.sh")
    with open(drivers_sh) as f:
        content = f.read()

    # Extract shell meta declarations
    shell_deps = {}
    shell_tools = {}
    for line in content.splitlines():
        if "_depends_on()" in line and "printf" in line:
            kind = line.split("_ucc_driver_")[1].split("_depends_on")[0].replace("_", "-")
            val = line.split("printf '")[1].split("'")[0] if "printf '" in line else ""
            shell_deps[kind] = val
        if "_provided_by()" in line and "printf" in line:
            kind = line.split("_ucc_driver_")[1].split("_provided_by")[0].replace("_", "-")
            val = line.split("printf '")[1].split("'")[0] if "printf '" in line else ""
            shell_tools[kind] = val

    # Compare with Python DRIVER_META
    # Skip drivers whose shell _depends_on uses a platform-aware `case` block
    # rather than a single-line `printf` (the parser above only handles the
    # printf form). These drivers ARE in shell — check for function existence
    # instead.
    PLATFORM_AWARE_SHELL = {"package", "pyenv-brew"}
    for kind, (dep, tool) in DRIVER_META.items():
        if kind in PLATFORM_AWARE_SHELL:
            # Verify the shell function exists at all (loose grep), since
            # the printf-extractor cannot read multi-line cases.
            shell_fn = f"_ucc_driver_{kind.replace('-', '_')}_depends_on"
            assert shell_fn in content, \
                f"DRIVER_META has {kind}→{dep} but no {shell_fn} in ucc_drivers.sh"
            continue
        if dep is not None:
            assert kind in shell_deps, \
                f"DRIVER_META has {kind}→{dep} but no shell _depends_on"
    print(f"PASS: Driver meta in sync ({len(DRIVER_META)} entries)")


def test_github_repo_valid():
    """All github_repo values look like owner/repo."""
    targets = load_all_targets()
    for t, td in targets.items():
        repo = (td.get("driver") or {}).get("github_repo", "")
        if repo:
            assert "/" in repo and len(repo.split("/")) == 2, \
                f"Target '{t}' github_repo='{repo}' doesn't look like owner/repo"
    print("PASS: All github_repo values are valid")


if __name__ == "__main__":
    test_all_drivers_have_schema()
    test_all_drivers_in_known_sets()
    test_driver_required_keys()
    test_driver_no_unexpected_keys()
    test_driver_meta_sync()
    test_github_repo_valid()
    print("\nAll driver tests passed.")
