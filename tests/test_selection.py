#!/usr/bin/env python3
"""Test target selection modes and UCC_TARGET_SET behavior."""

import os
import sys
import subprocess
import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QUERY_SCRIPT = os.path.join(REPO_ROOT, "tools", "validate_targets_manifest.py")
UCC_DIR = os.path.join(REPO_ROOT, "ucc")


def run_query(*args, env_extra=None):
    env = os.environ.copy()
    env.setdefault("HOST_PLATFORM", "macos")
    env.setdefault("HOST_PLATFORM_VARIANT", "macos")
    env.setdefault("HOST_PACKAGE_MANAGER", "brew")
    env.setdefault("HOST_OS_ID", "macos-15.4")
    env.setdefault("HOST_FINGERPRINT", "macos/15.4/arm64/brew")
    if env_extra:
        env.update(env_extra)
    result = subprocess.run(
        ["python3", QUERY_SCRIPT] + list(args) + [UCC_DIR],
        capture_output=True, text=True, env=env
    )
    return result.stdout.strip(), result.stderr.strip(), result.returncode


def get_all_targets():
    """Load all target names from YAML files."""
    targets = set()
    for root, _, files in os.walk(UCC_DIR):
        for f in files:
            if not f.endswith(".yaml"):
                continue
            with open(os.path.join(root, f)) as fh:
                data = yaml.safe_load(fh) or {}
            for t in (data.get("targets") or {}):
                targets.add(t)
    return targets


def test_single_target_includes_deps():
    """Selecting a single target includes its full dep chain."""
    stdout, _, rc = run_query("--dep-targets", "ariaflow")
    assert rc == 0
    deps = stdout.splitlines()
    assert "ariaflow" in deps, "Target itself must be in dep chain"
    assert "homebrew" in deps, "ariaflow depends on homebrew (via driver)"
    assert len(deps) >= 3, f"Expected at least 3 deps, got {len(deps)}: {deps}"
    print("PASS: Single target includes full dep chain")


def test_single_target_deps_ordered():
    """Dependencies come before the target in the dep chain."""
    stdout, _, _ = run_query("--dep-targets", "ariaflow")
    deps = stdout.splitlines()
    homebrew_pos = deps.index("homebrew")
    ariaflow_pos = deps.index("ariaflow")
    assert homebrew_pos < ariaflow_pos, \
        f"homebrew (pos {homebrew_pos}) should come before ariaflow (pos {ariaflow_pos})"
    print("PASS: Deps ordered correctly in single target chain")


def test_dep_components_covers_chain():
    """dep-components includes all components needed."""
    stdout, _, _ = run_query("--dep-components", "ariaflow")
    comps = stdout.splitlines()
    assert "software-bootstrap" in comps, "ariaflow needs software-bootstrap (homebrew)"
    assert "node-stack" in comps, "ariaflow is in node-stack"
    print("PASS: dep-components covers the chain")


def test_multiple_targets_merge():
    """Multiple targets merge their dep chains."""
    # Get individual chains
    a_stdout, _, _ = run_query("--dep-targets", "ariaflow")
    b_stdout, _, _ = run_query("--dep-targets", "cli-jq")

    a_deps = set(a_stdout.splitlines())
    b_deps = set(b_stdout.splitlines())
    merged = a_deps | b_deps

    assert "ariaflow" in merged
    assert "cli-jq" in merged
    assert "homebrew" in merged  # both need it
    print("PASS: Multiple targets merge dep chains")


def test_component_selection_includes_all_targets():
    """Selecting a component includes all its targets."""
    stdout, _, _ = run_query("--ordered-targets", "docker")
    targets = stdout.splitlines()
    assert "docker-desktop" in targets
    assert "docker-resources" in targets
    assert "docker-available" in targets
    assert "docker-settings-file" in targets
    assert len(targets) == 4, f"Docker has 4 targets, got {len(targets)}"
    print("PASS: Component selection includes all targets")


def test_disabled_targets_in_policy():
    """Targets in defaults/selection.yaml disabled: list."""
    with open(os.path.join(REPO_ROOT, "defaults", "selection.yaml")) as f:
        sel = yaml.safe_load(f) or {}
    disabled = sel.get("disabled", [])

    all_targets = get_all_targets()
    for t in disabled:
        assert t in all_targets, f"Disabled target '{t}' not found in YAML"

    print(f"PASS: {len(disabled)} disabled targets all exist in YAML")


def test_all_targets_count():
    """Total target count matches expectations."""
    all_targets = get_all_targets()
    assert len(all_targets) >= 100, f"Expected 100+ targets, got {len(all_targets)}"
    print(f"PASS: {len(all_targets)} total targets")


if __name__ == "__main__":
    test_single_target_includes_deps()
    test_single_target_deps_ordered()
    test_dep_components_covers_chain()
    test_multiple_targets_merge()
    test_component_selection_includes_all_targets()
    test_disabled_targets_in_policy()
    test_all_targets_count()
    print("\nAll selection tests passed.")
