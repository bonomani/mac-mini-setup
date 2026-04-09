#!/usr/bin/env python3
"""Test Khan topological ordering and dependency resolution."""

import os
import sys
import subprocess
import tempfile
import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QUERY_SCRIPT = os.path.join(REPO_ROOT, "tools", "validate_targets_manifest.py")
UCC_DIR = os.path.join(REPO_ROOT, "ucc")


def run_query(*args, env_extra=None):
    """Run the validator query and return stdout."""
    env = os.environ.copy()
    if env_extra:
        env.update(env_extra)
    result = subprocess.run(
        ["python3", QUERY_SCRIPT] + list(args) + [UCC_DIR],
        capture_output=True, text=True, env=env
    )
    return result.stdout.strip(), result.stderr.strip(), result.returncode


def test_khan_order_respects_depends_on():
    """Targets with depends_on must come AFTER their dependencies."""
    stdout, _, rc = run_query("--all-deps")
    assert rc == 0, f"Query failed: {stdout}"

    # Parse dep lines: target\tdep1,dep2,...
    deps = {}
    for line in stdout.splitlines():
        if "\t" not in line:
            continue
        if line.startswith("__section__"):
            continue
        parts = line.split("\t")
        target = parts[0]
        dep_list = parts[1].split(",") if len(parts) > 1 else []
        deps[target] = dep_list

    # Get ordered targets for each component
    for comp in ["software-bootstrap", "cli-tools", "node-stack", "vscode-stack",
                  "ai-python-stack", "docker", "ai-apps", "system", "build-tools"]:
        stdout, _, rc = run_query("--ordered-targets", comp)
        if rc != 0:
            continue
        ordered = [t for t in stdout.splitlines() if t.strip()]
        positions = {t: i for i, t in enumerate(ordered)}

        # Every dep must come before the target that depends on it
        for target in ordered:
            for dep in deps.get(target, []):
                if dep in positions:
                    assert positions[dep] < positions[target], \
                        f"[{comp}] {target} depends on {dep}, but {dep} (pos {positions[dep]}) " \
                        f"comes after {target} (pos {positions[target]})"
    print("PASS: Khan ordering respects all depends_on")


def test_no_cycles():
    """No dependency cycles exist."""
    stdout, stderr, rc = run_query()
    # The validator reports cycles as errors
    assert "cycle" not in stderr.lower(), f"Cycle detected: {stderr}"
    assert "cycle" not in stdout.lower(), f"Cycle detected: {stdout}"
    print("PASS: No dependency cycles")


def test_dep_targets_is_subset_of_ordered():
    """--dep-targets for any target returns a subset of the global ordered list."""
    env = {"HOST_PLATFORM": "macos", "HOST_PLATFORM_VARIANT": "macos",
           "HOST_PACKAGE_MANAGER": "brew", "HOST_OS_ID": "macos-15.4",
           "HOST_FINGERPRINT": "macos/15.4/arm64/brew"}

    # Get a few targets to test
    test_targets = ["homebrew", "ariaflow-server", "ollama", "pip-group-pytorch", "git-global-config"]
    for target in test_targets:
        stdout, stderr, rc = run_query("--dep-targets", target, env_extra=env)
        if rc != 0:
            continue
        dep_chain = [t for t in stdout.splitlines() if t.strip()]

        # The target itself must be last in its dep chain
        assert dep_chain[-1] == target, \
            f"dep-targets for {target}: target not last. Got: {dep_chain}"

        # Every dep must come before the target
        for i, t in enumerate(dep_chain[:-1]):
            assert t != target, f"dep-targets for {target}: target appears before end at pos {i}"

    print("PASS: dep-targets returns correct ordered subsets")


def test_cross_component_deps_resolved():
    """Targets depending on other components' targets are resolved."""
    env = {"HOST_PLATFORM": "macos", "HOST_PLATFORM_VARIANT": "macos",
           "HOST_PACKAGE_MANAGER": "brew", "HOST_OS_ID": "macos-15.4",
           "HOST_FINGERPRINT": "macos/15.4/arm64/brew"}

    # ariaflow-dashboard (network-services) depends on ariaflow-server (same component)
    stdout, _, _ = run_query("--dep-targets", "ariaflow-dashboard", env_extra=env)
    deps = stdout.splitlines()
    assert "ariaflow-server" in deps, f"ariaflow-dashboard should depend on ariaflow-server, got: {deps}"

    # git-global-config (cli-tools) depends on git (cli-tools) — same component
    stdout, _, _ = run_query("--dep-targets", "git-global-config", env_extra=env)
    deps = stdout.splitlines()
    assert "git" in deps, f"git-global-config should depend on git, got: {deps}"

    # pip-group-pytorch (ai-python-stack) depends on pip-latest → python → pyenv → homebrew
    stdout, _, _ = run_query("--dep-targets", "pip-group-pytorch", env_extra=env)
    deps = stdout.splitlines()
    assert "homebrew" in deps, f"pip-group-pytorch chain should include homebrew, got: {deps}"
    assert "python" in deps, f"pip-group-pytorch chain should include python, got: {deps}"
    assert "pyenv" in deps, f"pip-group-pytorch chain should include pyenv, got: {deps}"

    print("PASS: Cross-component deps resolved correctly")


def test_dep_components_derived_from_dep_targets():
    """--dep-components must include all components from --dep-targets."""
    env = {"HOST_PLATFORM": "macos", "HOST_PLATFORM_VARIANT": "macos",
           "HOST_PACKAGE_MANAGER": "brew", "HOST_OS_ID": "macos-15.4",
           "HOST_FINGERPRINT": "macos/15.4/arm64/brew"}

    targets_stdout, _, _ = run_query("--dep-targets", "ariaflow-server", env_extra=env)
    comps_stdout, _, _ = run_query("--dep-components", "ariaflow-server", env_extra=env)

    dep_targets = targets_stdout.splitlines()
    dep_components = comps_stdout.splitlines()

    # Load all targets to find their components
    all_targets = {}
    for root, _, files in os.walk(UCC_DIR):
        for f in files:
            if not f.endswith(".yaml"):
                continue
            with open(os.path.join(root, f)) as fh:
                data = yaml.safe_load(fh) or {}
            comp = data.get("component", "")
            for t in (data.get("targets") or {}):
                all_targets[t] = comp

    needed_comps = set()
    for t in dep_targets:
        if t in all_targets:
            needed_comps.add(all_targets[t])

    for comp in needed_comps:
        assert comp in dep_components, \
            f"Component {comp} needed by dep chain but not in --dep-components: {dep_components}"

    print("PASS: dep-components covers all dep-targets components")


if __name__ == "__main__":
    test_khan_order_respects_depends_on()
    test_no_cycles()
    test_dep_targets_is_subset_of_ordered()
    test_cross_component_deps_resolved()
    test_dep_components_derived_from_dep_targets()
    print("\nAll ordering tests passed.")
